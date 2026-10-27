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

@TableIndex(name: 'expenses_spent_at', columns: {#spentAt})
@TableIndex(name: 'expenses_category_date', columns: {#categoryId, #spentAt})
@TableIndex(name: 'expenses_currency_date', columns: {#currencyCode, #spentAt})
@DataClassName('StoredExpense')
class Expenses extends Table {
  TextColumn get id => text()();
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

@DriftDatabase(tables: [Categories, Expenses, AppSettings])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'kharchio'));
  AppDatabase.forTesting(super.executor);
  @override
  int get schemaVersion => 1;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA journal_mode = WAL');
    },
  );
}
