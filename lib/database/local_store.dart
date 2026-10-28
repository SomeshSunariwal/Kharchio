import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/categories.dart';
import '../core/expense.dart';
import 'app_database.dart';

final localStoreProvider = Provider<LocalStore>(
  (ref) => throw StateError('Database not initialized'),
);

class LocalStore {
  final AppDatabase db;
  List<Expense> initialExpenses = [];
  List<ExpenseCategory> initialCategories = [];
  Map<String, String> initialSettings = {};
  LocalStore(this.db);

  Future<void> initialize(Map<String, String> legacy) async {
    await db.transaction(() async {
      if (await setting('initialized') != '1') {
        final categories = categoriesFromJson(legacy['categories']);
        final now = DateTime.now().millisecondsSinceEpoch;
        for (var i = 0; i < categories.length; i++) {
          final c = categories[i];
          await db
              .into(db.categories)
              .insert(
                CategoriesCompanion.insert(
                  id: const Uuid().v4(),
                  name: c.name,
                  iconKey: c.iconKey,
                  colorValue: c.colorValue,
                  sortOrder: i,
                  createdAt: now,
                  updatedAt: now,
                ),
              );
        }
        await writeSetting('theme_mode', legacy['themeMode'] ?? 'system');
        await writeSetting('default_currency', legacy['currency'] ?? 'INR');
        await writeSetting(
          'speech_language',
          legacy['speechLanguage'] ?? 'auto',
        );
        await writeSetting('initialized', '1');
      }
      // Remove fixtures from older installs without touching user-created UUIDs.
      if (await setting('demo_expenses_removed') != '1') {
        await (db.delete(db.expenses)..where((e) => e.id.like('demo-%'))).go();
        await writeSetting('demo_expenses_removed', '1');
      }
      if (await setting('speech_language') == 'hi') {
        await writeSetting('speech_language', 'hinglish');
      }
    });
    initialCategories = await readCategories();
    initialExpenses = await readExpenses();
    initialSettings = {
      for (final row in await db.select(db.appSettings).get())
        row.key: row.value,
    };
  }

  Future<String?> setting(String key) async => (await (db.select(
    db.appSettings,
  )..where((r) => r.key.equals(key))).getSingleOrNull())?.value;

  Future<void> writeSetting(String key, String value) => db
      .into(db.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: key,
          value: value,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );

  Future<List<ExpenseCategory>> readCategories() async =>
      (await (db.select(
            db.categories,
          )..orderBy([(r) => OrderingTerm.asc(r.sortOrder)])).get())
          .map(_category)
          .toList();
  Stream<List<ExpenseCategory>> watchCategories() =>
      (db.select(db.categories)
            ..orderBy([(r) => OrderingTerm.asc(r.sortOrder)]))
          .watch()
          .map((rows) => rows.map(_category).toList());
  ExpenseCategory _category(StoredCategory row) =>
      ExpenseCategory(row.name, row.colorValue, row.iconKey, id: row.id);

  Future<void> addCategory(ExpenseCategory category) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await readCategories();
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            id: const Uuid().v4(),
            name: category.name.trim(),
            iconKey: category.iconKey,
            colorValue: category.colorValue,
            sortOrder: rows.length,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<String> removeCategory(String name) => db.transaction(() async {
    final categories = await readCategories();
    if (categories.length <= 1) throw StateError('Keep at least one category.');
    final removed = categories.firstWhere((c) => c.name == name);
    final remaining = categories.where((c) => c.id != removed.id).toList();
    final fallback =
        remaining.where((c) => c.name == 'Others').firstOrNull ??
        remaining.first;
    await (db.update(
      db.expenses,
    )..where((e) => e.categoryId.equals(removed.id))).write(
      ExpensesCompanion(
        categoryId: Value(fallback.id),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
    await (db.delete(
      db.categories,
    )..where((c) => c.id.equals(removed.id))).go();
    return fallback.name;
  });

  JoinedSelectStatement<HasResultSet, dynamic> _expenseQuery() =>
      db.select(db.expenses).join([
        innerJoin(
          db.monthlyBudgetsTable,
          db.monthlyBudgetsTable.id.equalsExp(db.expenses.monthId),
        ),
        innerJoin(
          db.categories,
          db.categories.id.equalsExp(db.expenses.categoryId),
        ),
      ])..orderBy([
        OrderingTerm.desc(db.expenses.spentAt),
        OrderingTerm.desc(db.expenses.id),
      ]);

  Expense _expense(TypedResult row) {
    final e = row.readTable(db.expenses);
    return Expense(
      id: e.id,
      monthId: e.monthId,
      accountingYear: row.readTable(db.monthlyBudgetsTable).year,
      accountingMonth: row.readTable(db.monthlyBudgetsTable).month,
      title: e.title,
      description: e.description,
      category: row.readTable(db.categories).name,
      amount: e.minor / 100,
      currencyCode: e.currencyCode,
      date: DateTime.fromMillisecondsSinceEpoch(e.spentAt),
    );
  }

  Future<List<Expense>> readExpenses() async =>
      (await _expenseQuery().get()).map(_expense).toList();
  Stream<List<Expense>> watchExpenses() =>
      _expenseQuery().watch().map((rows) => rows.map(_expense).toList());

  Future<void> saveExpenses(List<Expense> values) => db.transaction(() async {
    final categories = await readCategories();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final expense in values) {
      final minor = (expense.amount * 100).round();
      if (!expense.amount.isFinite ||
          minor <= 0 ||
          expense.title.trim().isEmpty) {
        throw ArgumentError('An expense needs a title and a positive amount.');
      }
      final category = categories.firstWhere(
        (c) => c.name == expense.category,
        orElse: () => throw StateError('Category no longer exists.'),
      );
      final old = await (db.select(
        db.expenses,
      )..where((e) => e.id.equals(expense.id))).getSingleOrNull();
      final monthId =
          '${expense.currencyCode}-${expense.date.year}-${expense.date.month}';
      await db
          .into(db.monthlyBudgetsTable)
          .insert(
            MonthlyBudgetsTableCompanion.insert(
              id: monthId,
              month: expense.date.month,
              year: expense.date.year,
              currencyCode: expense.currencyCode,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      await db
          .into(db.expenses)
          .insertOnConflictUpdate(
            ExpensesCompanion.insert(
              id: expense.id,
              monthId: monthId,
              categoryId: category.id,
              title: expense.title.trim(),
              description: Value(expense.description.trim()),
              minor: minor,
              currencyCode: expense.currencyCode,
              spentAt: expense.date.millisecondsSinceEpoch,
              createdAt: old?.createdAt ?? now,
              updatedAt: now,
            ),
          );
    }
  });

  Future<void> deleteExpense(String id) async {
    await (db.delete(db.expenses)..where((e) => e.id.equals(id))).go();
  }

  Future<void> clearExpenses() async {
    await db.delete(db.expenses).go();
    initialExpenses = [];
  }
}
