import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../database/local_store.dart';
import '../data_share/expense_transfer_repository.dart';

/// A portable ledger backup. No settings, credentials or profile metadata.
class ExpenseBackup {
  static const maxFileBytes = 16 * 1024 * 1024;
  static const maxExpandedBytes = 64 * 1024 * 1024;
  final List<Map<String, dynamic>> expenses;
  final List<Map<String, dynamic>> limits;

  ExpenseBackup._(this.expenses, this.limits);

  static Future<ExpenseBackup> read(Stream<List<int>> stream) async {
    final sink = _BoundedBytes(maxFileBytes);
    await for (final bytes in stream) {
      sink.add(bytes);
    }
    final bytes = sink.bytes.takeBytes();
    return Isolate.run(() => decode(bytes));
  }

  static ExpenseBackup decode(Uint8List bytes) {
    try {
      if (bytes.length > maxFileBytes ||
          bytes.length < 2 ||
          bytes[0] != 0x1f ||
          bytes[1] != 0x8b) {
        throw const FormatException();
      }
      final output = _BoundedBytes(maxExpandedBytes);
      final decoder = gzip.decoder.startChunkedConversion(output);
      for (var i = 0; i < bytes.length; i += 65536) {
        decoder.add(
          Uint8List.sublistView(bytes, i, min(i + 65536, bytes.length)),
        );
      }
      decoder.close();
      final value = jsonDecode(utf8.decode(output.bytes.takeBytes()));
      if (value is! Map ||
          value['format'] != 'kharchio-expenses' ||
          value['version'] != 1 ||
          value['expenses'] is! List ||
          value['monthlyLimits'] is! List) {
        throw const FormatException();
      }
      final rows = value['expenses'] as List;
      final limits = value['monthlyLimits'] as List;
      if (rows.length > 200000 || limits.length > 200000) {
        throw const FormatException();
      }
      final expenses = <Map<String, dynamic>>[];
      final ids = <String>{};
      for (final row in rows) {
        if (row is! Map<String, dynamic> ||
            row['id'] is! String ||
            row['category'] is! String ||
            !ids.add(row['id'] as String)) {
          throw const FormatException();
        }
        expenses.add(Map.of(row));
      }
      ExpenseTransferRepository.validateExpenses(expenses.map(_transferRow));
      final budgets = <Map<String, dynamic>>[];
      final months = <String>{};
      for (final limit in limits) {
        if (limit is! Map<String, dynamic>) throw const FormatException();
        final year = limit['year'], month = limit['month'];
        final currency = limit['currency'], amount = limit['amount'];
        if (year is! int ||
            year < 1900 ||
            year > 9999 ||
            month is! int ||
            month < 1 ||
            month > 12 ||
            !const ['INR', 'USD'].contains(currency) ||
            amount is! num ||
            !amount.isFinite ||
            amount <= 0 ||
            !months.add('$currency-$year-$month')) {
          throw const FormatException();
        }
        budgets.add(Map.of(limit));
      }
      return ExpenseBackup._(expenses, budgets);
    } on FormatException {
      throw const FormatException(
        'Invalid, damaged or unsupported Kharchio backup.',
      );
    }
  }

  static Future<Uint8List> encode(Map<String, Object?> data) => Isolate.run(() {
    final json = utf8.encode(jsonEncode(data));
    if (json.length > ExpenseBackup.maxExpandedBytes) {
      throw const FormatException('There is too much data for one backup.');
    }
    final bytes = Uint8List.fromList(gzip.encode(json));
    if (bytes.length > ExpenseBackup.maxFileBytes) {
      throw const FormatException('There is too much data for one backup.');
    }
    return bytes;
  });

  /// Supply default display metadata only when restoring missing categories.
  /// It is not present in the file; existing category icons remain unchanged.
  static Map<String, dynamic> _transferRow(Map<String, dynamic> row) => {
    ...row,
    'category': {
      'name': row['category'],
      'icon': 'others',
      'color': 0xFF9BA7B7,
    },
  };
}

class ExpenseBackupRepository {
  final LocalStore store;
  ExpenseBackupRepository(this.store);

  Future<Uint8List> export() async {
    final data = await store.db.transaction(() async {
      final rows = await ExpenseTransferRepository(store).exportExpenses();
      final months = await (store.db.select(
        store.db.monthlyBudgetsTable,
      )..where((row) => row.budget.isBiggerThanValue(0))).get();
      return {
        'format': 'kharchio-expenses',
        'version': 1,
        'expenses': [
          for (final row in rows)
            {...row, 'category': (row['category'] as Map)['name']},
        ],
        'monthlyLimits': [
          for (final month in months)
            {
              'year': month.year,
              'month': month.month,
              'currency': month.currencyCode,
              'amount': month.budget,
            },
        ],
      };
    });
    return ExpenseBackup.encode(data);
  }

  /// Advisory only: independently created purchases can share these details.
  Future<int> possibleDuplicates(ExpenseBackup backup) async {
    final rows = await store.db.select(store.db.expenses).get();
    final ids = {for (final row in rows) row.id};
    final fingerprints = {
      for (final row in rows)
        _fingerprint(
          row.title,
          row.minor,
          row.currencyCode,
          row.transactionType,
          row.spentAt,
        ),
    };
    var count = 0;
    for (final row in backup.expenses) {
      if (ids.contains(row['id'])) continue;
      if (!fingerprints.add(
        _fingerprint(
          row['title'] as String,
          row['minor'] as int,
          row['currency'] as String,
          (row['type'] ?? 'expense') as String,
          row['spentAt'] as int,
        ),
      )) {
        count++;
      }
    }
    return count;
  }

  static String _fingerprint(
    String title,
    int minor,
    String currency,
    String type,
    int spentAt,
  ) {
    final date = DateTime.fromMillisecondsSinceEpoch(spentAt);
    return jsonEncode([
      title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' '),
      minor,
      currency,
      type,
      date.year,
      date.month,
      date.day,
    ]);
  }

  /// One transaction protects existing data if any row cannot be restored.
  Future<ImportResult> merge(
    ExpenseBackup backup, {
    void Function(double fraction)? onProgress,
  }) async {
    final total = backup.expenses.length + backup.limits.length;
    var completed = 0;
    void report(int count) {
      completed += count;
      // Reserve 100% for the successful outer transaction commit.
      onProgress?.call(total == 0 ? 0 : min(completed / total, .99));
    }

    onProgress?.call(0);
    final result = await store.db.transaction(() async {
      var added = 0, skipped = 0;
      final transfer = ExpenseTransferRepository(store);
      for (var i = 0; i < backup.expenses.length; i += 100) {
        final rows = backup.expenses.sublist(
          i,
          min(i + 100, backup.expenses.length),
        );
        final batch = await transfer.importBatch(
          jsonEncode({
            'version': 2,
            'expenses': rows.map(ExpenseBackup._transferRow).toList(),
          }),
        );
        added += batch.added;
        skipped += batch.skipped;
        report(rows.length);
      }
      for (var i = 0; i < backup.limits.length; i += 100) {
        final rows = backup.limits.sublist(
          i,
          min(i + 100, backup.limits.length),
        );
        await store.db.batch((batch) {
          batch.insertAllOnConflictUpdate(store.db.monthlyBudgetsTable, [
            for (final row in rows)
              MonthlyBudgetsTableCompanion.insert(
                id: '${row['currency']}-${row['year']}-${row['month']}',
                year: row['year'] as int,
                month: row['month'] as int,
                currencyCode: row['currency'] as String,
                budget: Value((row['amount'] as num).toDouble()),
              ),
          ]);
        });
        report(rows.length);
      }
      return ImportResult(added, skipped);
    });
    onProgress?.call(1);
    return result;
  }
}

class _BoundedBytes implements Sink<List<int>> {
  final int limit;
  final bytes = BytesBuilder(copy: false);
  _BoundedBytes(this.limit);
  @override
  void add(List<int> data) {
    if (bytes.length + data.length > limit) {
      throw const FormatException('The backup exceeds the supported size.');
    }
    bytes.add(data);
  }

  @override
  void close() {}
}
