import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/categories.dart';
import '../../database/app_database.dart';
import '../../database/local_store.dart';

class ImportResult {
  final int added, skipped;
  const ImportResult(this.added, this.skipped);
}

/// Shares ledger rows, never settings, budgets, models, or profile files.
/// Existing expense IDs and existing category metadata are never updated.
class ExpenseTransferRepository {
  final LocalStore store;
  ExpenseTransferRepository(this.store);

  Future<List<Map<String, Object>>> exportExpenses() =>
      store.db.transaction(() async {
        final db = store.db;
        final categories = {
          for (final row in await db.select(db.categories).get()) row.id: row,
        };
        final months = {
          for (final row in await db.select(db.monthlyBudgetsTable).get())
            row.id: row,
        };
        final rows = await db.select(db.expenses).get();
        return [
          for (final row in rows)
            {
              'id': row.id,
              'title': row.title,
              'description': row.description,
              'minor': row.minor,
              'currency': row.currencyCode,
              'spentAt': row.spentAt,
              'createdAt': row.createdAt,
              'updatedAt': row.updatedAt,
              'year': months[row.monthId]!.year,
              'month': months[row.monthId]!.month,
              'category': {
                'name': categories[row.categoryId]!.name,
                'icon': categories[row.categoryId]!.iconKey,
                'color': categories[row.categoryId]!.colorValue,
              },
            },
        ];
      });

  Future<ImportResult> importBatch(String payload) async {
    final decoded = jsonDecode(payload);
    if (decoded is! Map ||
        decoded['version'] != 1 ||
        decoded['expenses'] is! List ||
        (decoded['expenses'] as List).length > 100) {
      throw const FormatException('Unsupported expense transfer.');
    }
    final rows = [
      for (final value in decoded['expenses'] as List)
        _TransferExpense.parse(value),
    ];
    return store.db.transaction(() async {
      final db = store.db;
      final ids =
          (await (db.selectOnly(db.expenses)
                    ..addColumns([db.expenses.id])
                    ..where(db.expenses.id.isIn(rows.map((row) => row.id))))
                  .get())
              .map((row) => row.read(db.expenses.id)!)
              .toSet();
      final categories = {
        for (final c in await store.readCategories()) c.name.toLowerCase(): c,
      };
      var added = 0;
      var skipped = 0;
      for (final row in rows) {
        if (!ids.add(row.id)) {
          skipped++;
          continue;
        }
        var category = categories[row.categoryName.toLowerCase()];
        if (category == null) {
          category = ExpenseCategory(
            row.categoryName,
            row.color,
            row.icon,
            id: const Uuid().v4(),
          );
          await db
              .into(db.categories)
              .insert(
                CategoriesCompanion.insert(
                  id: category.id,
                  name: category.name,
                  iconKey: category.iconKey,
                  colorValue: category.colorValue,
                  sortOrder: categories.length,
                  createdAt: row.createdAt,
                  updatedAt: row.updatedAt,
                ),
              );
          categories[row.categoryName.toLowerCase()] = category;
        }
        final monthId = '${row.currency}-${row.year}-${row.month}';
        await db
            .into(db.monthlyBudgetsTable)
            .insert(
              MonthlyBudgetsTableCompanion.insert(
                id: monthId,
                year: row.year,
                month: row.month,
                currencyCode: row.currency,
              ),
              mode: InsertMode.insertOrIgnore,
            );
        await db
            .into(db.expenses)
            .insert(
              ExpensesCompanion.insert(
                id: row.id,
                monthId: monthId,
                categoryId: category.id,
                title: row.title,
                description: Value(row.description),
                minor: row.minor,
                currencyCode: row.currency,
                spentAt: row.spentAt,
                createdAt: row.createdAt,
                updatedAt: row.updatedAt,
              ),
              mode: InsertMode.insertOrIgnore,
            );
        added++;
      }
      return ImportResult(added, skipped);
    });
  }
}

class _TransferExpense {
  final String id, title, description, currency, categoryName, icon;
  final int minor, spentAt, createdAt, updatedAt, year, month, color;
  const _TransferExpense(
    this.id,
    this.title,
    this.description,
    this.currency,
    this.categoryName,
    this.icon,
    this.minor,
    this.spentAt,
    this.createdAt,
    this.updatedAt,
    this.year,
    this.month,
    this.color,
  );

  factory _TransferExpense.parse(Object? value) {
    if (value is! Map || value['category'] is! Map) {
      throw const FormatException('Invalid expense data.');
    }
    String text(Map map, String key, int max, {bool empty = false}) {
      final v = map[key];
      if (v is! String || (!empty && v.trim().isEmpty) || v.length > max) {
        throw const FormatException('Invalid expense text.');
      }
      return v;
    }

    int integer(String key, int min, int max) {
      final v = value[key];
      if (v is! int || v < min || v > max) {
        throw const FormatException('Invalid expense number.');
      }
      return v;
    }

    final category = value['category'] as Map;
    final currency = text(value, 'currency', 3);
    if (!const ['INR', 'USD'].contains(currency)) {
      throw const FormatException('Unsupported currency.');
    }
    final color = category['color'];
    if (color is! int || color < 0 || color > 0xFFFFFFFF) {
      throw const FormatException('Invalid category colour.');
    }
    final icon = text(category, 'icon', 80);
    return _TransferExpense(
      text(value, 'id', 200),
      text(value, 'title', 200),
      text(value, 'description', 20000, empty: true),
      currency,
      text(category, 'name', 30).trim(),
      categoryIconOptions.containsKey(icon) ? icon : 'others',
      integer('minor', 1, 9007199254740991),
      integer('spentAt', -2208988800000, 253402300799999),
      integer('createdAt', 0, 253402300799999),
      integer('updatedAt', 0, 253402300799999),
      integer('year', 1900, 9999),
      integer('month', 1, 12),
      color,
    );
  }
}
