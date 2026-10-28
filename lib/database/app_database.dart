import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

@DataClassName('StoredCategory')
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name =>
      text().customConstraint('NOT NULL COLLATE NOCASE UNIQUE')();
  TextColumn get iconKey => text()();
  IntColumn get colorValue => integer()();
  IntColumn get sortOrder => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('StoredMonth')
class MonthlyBudgetsTable extends Table {
  @override
  String get tableName => 'monthly_budgets';
  TextColumn get id => text()();
  IntColumn get month =>
      integer().customConstraint('NOT NULL CHECK (month BETWEEN 1 AND 12)')();
  IntColumn get year => integer().customConstraint(
    'NOT NULL CHECK (year BETWEEN 1900 AND 9999)',
  )();
  RealColumn get budget => real()
      .withDefault(const Constant(-1.0))
      .check(const CustomExpression<bool>('budget = -1 OR budget > 0'))();
  TextColumn get currencyCode => text().customConstraint(
    "NOT NULL CHECK (currency_code IN ('INR', 'USD'))",
  )();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
    {month, year, currencyCode},
  ];
}

@TableIndex(name: 'expenses_month', columns: {#monthId})
@TableIndex(name: 'expenses_spent_at', columns: {#spentAt})
@TableIndex(name: 'expenses_category_date', columns: {#categoryId, #spentAt})
@TableIndex(name: 'expenses_currency_date', columns: {#currencyCode, #spentAt})
@DataClassName('StoredExpense')
class Expenses extends Table {
  TextColumn get id => text()();
  TextColumn get monthId => text().references(MonthlyBudgetsTable, #id)();
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get description => text().withDefault(const Constant(''))();
  IntColumn get minor =>
      integer().customConstraint('NOT NULL CHECK (minor > 0)')();
  TextColumn get currencyCode => text().customConstraint(
    "NOT NULL CHECK (currency_code IN ('INR', 'USD'))",
  )();
  IntColumn get spentAt => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('StoredSetting')
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  IntColumn get updatedAt => integer()();
  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Categories, Expenses, AppSettings, MonthlyBudgetsTable])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'kharchio'));
  AppDatabase.forTesting(super.executor);
  @override
  int get schemaVersion => 2;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(monthlyBudgetsTable);
        // Backfill every existing expense before adding its required foreign key.
        final expenses = await customSelect(
          'SELECT spent_at, currency_code FROM expenses',
        ).get();
        for (final row in expenses) {
          final date = DateTime.fromMillisecondsSinceEpoch(
            row.read<int>('spent_at'),
          );
          final currency = row.read<String>('currency_code');
          await into(monthlyBudgetsTable).insert(
            MonthlyBudgetsTableCompanion.insert(
              id: '$currency-${date.year}-${date.month}',
              month: date.month,
              year: date.year,
              currencyCode: currency,
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
        // The first Budget Planner version kept its budgets in settings JSON.
        final legacy = await customSelect(
          "SELECT value FROM app_settings WHERE key = 'monthly_budgets'",
        ).getSingleOrNull();
        if (legacy != null) {
          final rows = jsonDecode(legacy.read<String>('value')) as List;
          for (final item in rows) {
            final row = item as Map<String, dynamic>;
            final currency = row['currency'] as String;
            final year = row['year'] as int;
            final month = row['month'] as int;
            await into(monthlyBudgetsTable).insertOnConflictUpdate(
              MonthlyBudgetsTableCompanion.insert(
                id: '$currency-$year-$month',
                month: month,
                year: year,
                currencyCode: currency,
                budget: Value((row['amount'] as num).toDouble()),
              ),
            );
          }
          await customStatement(
            "DELETE FROM app_settings WHERE key = 'monthly_budgets'",
          );
        }
        await m.alterTable(
          TableMigration(
            this.expenses,
            newColumns: [this.expenses.monthId],
            columnTransformer: {
              this.expenses.monthId: const CustomExpression<String>(
                "currency_code || '-' || CAST(strftime('%Y', spent_at / 1000, 'unixepoch', 'localtime') AS INTEGER) || '-' || CAST(strftime('%m', spent_at / 1000, 'unixepoch', 'localtime') AS INTEGER)",
              ),
            },
          ),
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS expenses_month ON expenses(month_id)',
        );
      }
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA journal_mode = WAL');
    },
  );
}
