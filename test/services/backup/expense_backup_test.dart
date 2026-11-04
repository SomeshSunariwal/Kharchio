import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharchio/core/expense.dart';
import 'package:kharchio/database/app_database.dart';
import 'package:kharchio/database/local_store.dart';
import 'package:kharchio/services/backup/expense_backup.dart';

void main() {
  // Every source and target owns a different in-memory executor.
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);
  Future<LocalStore> store() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final result = LocalStore(db);
    await result.initialize({});
    return result;
  }

  Expense expense(String id, {String title = 'Milk', bool refund = false}) =>
      Expense(
        id: id,
        title: title,
        description: 'दूध',
        category: 'Groceries',
        amount: 100,
        date: DateTime(2026, 11, 4, 12),
        type: refund ? TransactionType.refund : TransactionType.expense,
        originalExpenseId: refund ? 'purchase' : null,
      );

  Future<void> limit(LocalStore store, int month, double amount) => store.db
      .into(store.db.monthlyBudgetsTable)
      .insertOnConflictUpdate(
        MonthlyBudgetsTableCompanion.insert(
          id: 'INR-2026-$month',
          month: month,
          year: 2026,
          currencyCode: 'INR',
          budget: Value(amount),
        ),
      );

  test(
    'compressed round trip merges IDs, refunds and budgets without settings',
    () async {
      final source = await store(), target = await store();
      await source.saveExpenses([
        expense('purchase'),
        expense('refund', refund: true),
      ]);
      await limit(source, 11, 500);
      await limit(
        source,
        12,
        700,
      ); // A budget without expenses must also survive.
      await source.writeSetting('profile_name', 'Private Name');
      await source.writeSetting('online_api_key', 'dummy-secret');
      final bytes = await ExpenseBackupRepository(source).export();
      expect(bytes.take(2), [0x1f, 0x8b]);
      final json = jsonDecode(utf8.decode(gzip.decode(bytes))) as Map;
      expect(json.keys.toSet(), {
        'format',
        'version',
        'expenses',
        'monthlyLimits',
      });
      final serialized = jsonEncode(json);
      expect(serialized, isNot(contains('dummy-secret')));
      expect(serialized, isNot(contains('Private Name')));
      expect(serialized, isNot(contains('icon')));
      expect(serialized, isNot(contains('color')));
      expect(json['expenses'][0]['category'], 'Groceries');
      final backup = await ExpenseBackup.read(Stream.value(bytes));
      await target.saveExpenses([
        expense('purchase', title: 'Keep my edited title'),
      ]);
      await limit(target, 11, 200);
      await limit(target, 10, 900);
      await target.writeSetting('theme_mode', 'dark');
      final repo = ExpenseBackupRepository(target);
      final progress = <double>[];
      final result = await repo.merge(backup, onProgress: progress.add);
      expect(progress.first, 0);
      expect(progress.last, 1);
      expect(
        progress.sublist(0, progress.length - 1),
        everyElement(lessThan(1)),
      );
      expect(progress, orderedEquals([...progress]..sort()));
      expect(result.added, 1);
      expect(result.skipped, 1);
      final rows = await target.readExpenses();
      expect(rows.length, 2);
      expect(
        rows.firstWhere((r) => r.id == 'purchase').title,
        'Keep my edited title',
      );
      expect(
        rows.firstWhere((r) => r.id == 'refund').originalExpenseId,
        'purchase',
      );
      final budgets = await target.db
          .select(target.db.monthlyBudgetsTable)
          .get();
      expect(
        {for (final b in budgets) b.month: b.budget},
        {10: 900.0, 11: 500.0, 12: 700.0},
      );
      expect(await target.setting('theme_mode'), 'dark');
      final again = await repo.merge(backup);
      expect(again.added, 0);
      expect(again.skipped, 2);
    },
  );

  test('similar purchases with different IDs are flagged and kept', () async {
    final source = await store(), target = await store();
    await source.saveExpenses([expense('source')]);
    await target.saveExpenses([expense('independent')]);
    final backup = ExpenseBackup.decode(
      await ExpenseBackupRepository(source).export(),
    );
    final repo = ExpenseBackupRepository(target);
    expect(await repo.possibleDuplicates(backup), 1);
    expect((await repo.merge(backup)).added, 1);
    expect((await target.readExpenses()).length, 2);
  });

  test('invalid format, duplicate IDs and bad limits are rejected', () async {
    final source = await store();
    await source.saveExpenses([expense('purchase')]);
    final bytes = await ExpenseBackupRepository(source).export();
    Uint8List encode(Map value) =>
        Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(value))));
    Map value() => jsonDecode(utf8.decode(gzip.decode(bytes))) as Map;
    final damaged = Uint8List.fromList(bytes);
    damaged[damaged.length - 1] ^= 0xff;
    expect(() => ExpenseBackup.decode(damaged), throwsFormatException);
    expect(
      () => ExpenseBackup.decode(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
    expect(
      () => ExpenseBackup.decode(encode(value()..['version'] = 99)),
      throwsFormatException,
    );
    final duplicate = value();
    (duplicate['expenses'] as List).add(duplicate['expenses'][0]);
    expect(
      () => ExpenseBackup.decode(encode(duplicate)),
      throwsFormatException,
    );
    final invalid = value()
      ..['monthlyLimits'] = [
        {'year': 2026, 'month': 13, 'currency': 'INR', 'amount': 500},
      ];
    expect(() => ExpenseBackup.decode(encode(invalid)), throwsFormatException);
  });

  test(
    'budget-only and empty backups merge without deleting expenses',
    () async {
      final source = await store(), target = await store();
      await target.saveExpenses([expense('keep')]);
      final repo = ExpenseBackupRepository(target);
      final empty = ExpenseBackup.decode(
        await ExpenseBackupRepository(source).export(),
      );
      expect((await repo.merge(empty)).added, 0);
      await limit(source, 12, 600);
      final backup = ExpenseBackup.decode(
        await ExpenseBackupRepository(source).export(),
      );
      expect(backup.expenses, isEmpty);
      await repo.merge(backup);
      expect((await target.readExpenses()).single.id, 'keep');
      final restored = await (target.db.select(
        target.db.monthlyBudgetsTable,
      )..where((row) => row.id.equals('INR-2026-12'))).getSingle();
      expect(restored.budget, 600);
    },
  );

  test('a later batch failure rolls back the entire import', () async {
    final source = await store(), target = await store();
    await source.saveExpenses([
      for (var i = 0; i <= 100; i++)
        expense('row-$i', title: i == 100 ? 'Blocked' : 'Item $i'),
    ]);
    await target.db.customStatement(
      "CREATE TRIGGER reject_import BEFORE INSERT ON expenses WHEN NEW.title = 'Blocked' BEGIN SELECT RAISE(ABORT, 'rejected'); END",
    );
    final backup = ExpenseBackup.decode(
      await ExpenseBackupRepository(source).export(),
    );
    final progress = <double>[];
    await expectLater(
      ExpenseBackupRepository(target).merge(backup, onProgress: progress.add),
      throwsA(isA<Exception>()),
    );
    expect(progress, everyElement(lessThan(1)));
    expect(progress.any((value) => value > 0), isTrue);
    expect(await target.readExpenses(), isEmpty);
    expect(
      await target.db.select(target.db.monthlyBudgetsTable).get(),
      isEmpty,
    );
  });
}
