import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/expense.dart';
import '../core/subscriptions.dart';
import 'app_database.dart';
import 'local_store.dart';

final subscriptionStoreProvider = Provider(
  (ref) => SubscriptionStore(ref.watch(localStoreProvider)),
);
final subscriptionsProvider = StreamProvider(
  (ref) => ref.watch(subscriptionStoreProvider).watch(),
);

class SubscriptionStore {
  final LocalStore store;
  SubscriptionStore(this.store);

  AppDatabase get _db => store.db;

  Stream<SubscriptionState> watch() => _db
      .select(_db.subscriptionPlans)
      .join([
        leftOuterJoin(
          _db.subscriptionRenewals,
          _db.subscriptionRenewals.planId.equalsExp(_db.subscriptionPlans.id),
        ),
      ])
      .watch()
      .map((rows) {
        final plans = <String, SubscriptionPlan>{};
        final renewals = <SubscriptionRenewal>[];
        for (final row in rows) {
          final id = row.read(_db.subscriptionPlans.id)!;
          plans.putIfAbsent(id, () => row.readTable(_db.subscriptionPlans));
          if (row.readTableOrNull(_db.subscriptionRenewals)
              case final SubscriptionRenewal renewal) {
            renewals.add(renewal);
          }
        }
        return SubscriptionState(plans.values.toList(), renewals);
      });

  Future<void> save(SubscriptionPlan plan) async {
    if (plan.name.trim().isEmpty || plan.minor <= 0) {
      throw ArgumentError('Enter a name and amount.');
    }
    await _db.transaction(() async {
      final existing = await (_db.select(
        _db.subscriptionPlans,
      )..where((row) => row.id.equals(plan.id))).getSingleOrNull();
      await _db
          .into(_db.subscriptionPlans)
          .insertOnConflictUpdate(
            plan.copyWith(
              merchantAliases:
                  existing?.merchantAliases ?? plan.merchantAliases,
            ),
          );
    });
  }

  Future<void> unlink(String id, int day, String expenseId) async {
    await (_db.update(_db.subscriptionRenewals)..where(
          (row) =>
              row.planId.equals(id) &
              row.dueDay.equals(day) &
              row.expenseId.equals(expenseId),
        ))
        .write(const SubscriptionRenewalsCompanion(expenseId: Value(null)));
  }

  Future<void> skip(String id, int day) => _db.transaction(() async {
    final entry = await _renewal(id, day);
    if (entry?.expenseId != null) {
      throw StateError('This renewal is already paid.');
    }
    await _db
        .into(_db.subscriptionRenewals)
        .insertOnConflictUpdate(
          SubscriptionRenewalsCompanion.insert(
            planId: id,
            dueDay: day,
            skipped: const Value(true),
          ),
        );
  });

  Future<void> link(String planId, Map<int, String> expenses) =>
      _db.transaction(() => _link(planId, expenses));

  Future<void> saveAndLink(Expense expense, String planId, int day) =>
      _db.transaction(() async {
        await store.saveExpenses([expense]);
        await _link(planId, {day: expense.id});
      });

  Future<void> _link(String planId, Map<int, String> expenses) async {
    if (expenses.isEmpty) return;
    final plan = await (_db.select(
      _db.subscriptionPlans,
    )..where((row) => row.id.equals(planId))).getSingle();
    final current = {
      for (final renewal
          in await (_db.select(_db.subscriptionRenewals)..where(
                (row) =>
                    row.planId.equals(planId) & row.dueDay.isIn(expenses.keys),
              ))
              .get())
        renewal.dueDay: renewal,
    };
    final payments = {
      for (final expense in await (_db.select(
        _db.expenses,
      )..where((row) => row.id.isIn(expenses.values.toSet()))).get())
        expense.id: expense,
    };
    final aliases = {...subscriptionAliases(plan)};
    final updates = <SubscriptionRenewalsCompanion>[];
    for (final link in expenses.entries) {
      final renewal = current[link.key];
      if (renewal?.expenseId == link.value) continue;
      if (renewal?.expenseId != null) {
        throw StateError('This renewal is already paid.');
      }
      final expense = payments[link.value];
      if (expense == null ||
          expense.transactionType != 'expense' ||
          expense.currencyCode != plan.currencyCode) {
        throw StateError('Choose an expense in the subscription currency.');
      }
      updates.add(
        SubscriptionRenewalsCompanion.insert(
          planId: planId,
          dueDay: link.key,
          expenseId: Value(link.value),
        ),
      );
      final alias = normalizeSubscriptionMerchant(expense.title);
      if (hasSubscriptionMerchant(alias) && alias.length <= 200) {
        aliases.add(alias);
      }
    }
    if (updates.isEmpty) return;
    await _db.batch(
      (batch) =>
          batch.insertAllOnConflictUpdate(_db.subscriptionRenewals, updates),
    );
    final encoded = jsonEncode(
      aliases.skip((aliases.length - 25).clamp(0, aliases.length)).toList(),
    );
    if (encoded != plan.merchantAliases) {
      await (_db.update(_db.subscriptionPlans)
            ..where((row) => row.id.equals(planId)))
          .write(SubscriptionPlansCompanion(merchantAliases: Value(encoded)));
    }
  }

  Future<SubscriptionRenewal?> _renewal(String id, int day) =>
      (_db.select(_db.subscriptionRenewals)
            ..where((row) => row.planId.equals(id) & row.dueDay.equals(day)))
          .getSingleOrNull();
}
