import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharchio/core/expense.dart';
import 'package:kharchio/core/subscriptions.dart';
import 'package:kharchio/database/app_database.dart';
import 'package:kharchio/database/local_store.dart';
import 'package:kharchio/database/subscription_store.dart';
import 'package:kharchio/services/notifications/subscription_reminders.dart';
import 'package:kharchio/services/subscription_demo.dart';

const plan = SubscriptionPlan(
  id: 'spotify',
  name: 'Spotify',
  minor: 11900,
  currencyCode: 'INR',
  intervalMonths: 1,
  anchorDay: 20261115,
  reminderDays: 7,
  reminderMinutes: 9 * 60 + 30,
  active: true,
  merchantAliases: '[]',
);

Expense payment(
  String id,
  DateTime date, {
  String title = 'SPOTIFY INDIA',
  double amount = 119,
  String currency = 'INR',
}) => Expense(
  id: id,
  title: title,
  category: 'Others',
  amount: amount,
  date: date,
  currencyCode: currency,
);

void main() {
  test(
    'renewals enter the list at the reminder window and past dues remain',
    () {
      final monthly = plan.copyWith(
        anchorDay: 20261015,
        reminderDays: const Value(3),
      );
      final state = SubscriptionState([monthly], []);
      List<int> visible(DateTime today) => state
          .upcomingRenewals(
            DateTime(2026),
            DateTime(2026, 12, 31),
            'INR',
            asOf: today,
          )
          .map((r) => r.dueDay)
          .toList();
      expect(visible(DateTime(2026, 11, 11)), [20261015]);
      expect(visible(DateTime(2026, 11, 12)), [20261015, 20261115]);
      expect(visible(DateTime(2026, 12, 1)), [20261015, 20261115]);
      final done = SubscriptionState(
        [monthly],
        [
          const SubscriptionRenewal(
            planId: 'spotify',
            dueDay: 20261015,
            skipped: true,
          ),
          const SubscriptionRenewal(
            planId: 'spotify',
            dueDay: 20261115,
            skipped: false,
            expenseId: 'paid',
          ),
        ],
      );
      expect(
        done.upcomingRenewals(
          DateTime(2026),
          DateTime(2026, 12, 31),
          'INR',
          asOf: DateTime(2026, 12, 1),
        ),
        isEmpty,
      );
    },
  );
  test('sample subscriptions seed paid and unpaid cycles once', () async {
    final store = LocalStore(AppDatabase.forTesting(NativeDatabase.memory()));
    addTearDown(store.db.close);
    await store.initialize({});
    await seedSubscriptionDemo(store, DateTime(2026, 11, 24));
    await seedSubscriptionDemo(store, DateTime(2026, 11, 24));
    final state = await SubscriptionStore(store).watch().first;
    expect(state.plans.length, 2);
    expect((await store.readExpenses()).length, 9);
    expect(state.byExpense.length, 9);
    expect(state.plans.every((plan) => plan.reminderDays == null), isTrue);
    expect(
      state
          .upcomingRenewals(
            DateTime(2026, 11, 24),
            DateTime(2026, 11, 30),
            'INR',
            asOf: DateTime(2026, 11, 28),
          )
          .single
          .plan
          .name,
      'Sample Netflix',
    );
  });
  test('matches a late payment by merchant, amount, currency and due date', () {
    final state = SubscriptionState([plan], []);
    expect(
      state.match(payment('late', DateTime(2026, 11, 19)))?.dueDay,
      20261115,
    );
    expect(state.match(payment('too-late', DateTime(2026, 11, 23))), isNull);
    expect(
      state.match(
        payment('generic', DateTime(2026, 11, 15), title: 'Card/UPI payment'),
      ),
      isNull,
    );
    expect(
      state.match(payment('other-price', DateTime(2026, 11, 15), amount: 149)),
      isNull,
    );
    expect(
      state.match(
        payment('other-currency', DateTime(2026, 11, 15), currency: 'USD'),
      ),
      isNull,
    );
    expect(
      state.match(
        payment('different', DateTime(2026, 11, 15), title: 'Spotifyland'),
      ),
      isNull,
    );
    final ambiguous = SubscriptionState([
      plan,
      plan.copyWith(id: 'second'),
    ], []);
    expect(
      ambiguous.match(payment('ambiguous', DateTime(2026, 11, 15))),
      isNull,
    );
  });

  test(
    'finds older payments and leaves duplicate candidates for manual review',
    () {
      final state = SubscriptionState([plan], []);
      final expenses = [
        for (var month = 7; month <= 11; month++)
          payment('$month', DateTime(2026, month, 16)),
      ];
      expect(
        state.historicalMatches(plan, expenses, DateTime(2026, 11, 20)).length,
        5,
      );
      final ambiguous = state.historicalMatches(plan, [
        ...expenses,
        payment('duplicate', DateTime(2026, 11, 15)),
      ], DateTime(2026, 11, 20));
      expect(ambiguous.length, 4);
      expect(ambiguous.containsKey(20261115), isFalse);
    },
  );

  test('keeps the billing day across shorter months', () {
    final monthly = plan.copyWith(anchorDay: 20260131);
    expect(
      subscriptionDueOnOrAfter(monthly, DateTime(2026, 2, 1)),
      DateTime(2026, 2, 28),
    );
    expect(
      subscriptionDueOnOrAfter(monthly, DateTime(2026, 3, 1)),
      DateTime(2026, 3, 31),
    );
  });

  test(
    'schedules two alerts at the chosen local time and excludes settled cycles',
    () {
      final start = DateTime(2026, 11, 1);
      final expected = subscriptionReminders(
        SubscriptionState([plan], []),
        start,
        limit: 10,
      );
      final first = expected
          .where((reminder) => reminder.dueDay == 20261115)
          .toList();
      expect(first.map((r) => r.at), [
        DateTime(2026, 11, 8, 9, 30),
        DateTime(2026, 11, 17, 9, 30),
      ]);
      expect(first.map((r) => r.followUp), [false, true]);
      for (final settled in [
        const SubscriptionRenewal(
          planId: 'spotify',
          dueDay: 20261115,
          skipped: true,
        ),
        const SubscriptionRenewal(
          planId: 'spotify',
          dueDay: 20261115,
          skipped: false,
          expenseId: 'paid',
        ),
      ]) {
        final state = SubscriptionState([plan], [settled]);
        expect(
          subscriptionReminders(state, start, limit: 4).first.dueDay,
          20261215,
        );
      }
      expect(
        subscriptionReminders(
          SubscriptionState([plan.copyWith(active: false)], []),
          start,
          limit: 4,
        ),
        isEmpty,
      );
      expect(
        subscriptionReminders(
          SubscriptionState([
            plan.copyWith(reminderDays: const Value(null)),
          ], []),
          start,
          limit: 4,
        ),
        isEmpty,
      );
    },
  );

  test(
    'links the original expense once and reopens the renewal if it is deleted',
    () async {
      final local = LocalStore(AppDatabase.forTesting(NativeDatabase.memory()));
      addTearDown(local.db.close);
      await local.initialize({});
      final subscriptions = SubscriptionStore(local);
      await subscriptions.save(plan);
      final expense = payment(
        'original',
        DateTime(2026, 11, 19),
        title: 'SPOTIFY INDIA',
      );
      await subscriptions.saveAndLink(expense, plan.id, 20261115);
      await subscriptions.link(plan.id, {20261115: expense.id});
      await expectLater(
        subscriptions.link(plan.id, {20261215: expense.id}),
        throwsA(anything),
      );
      final settled = await subscriptions.watch().first;
      expect(settled.byExpense[expense.id]?.dueDay, 20261115);
      expect(subscriptionAliases(settled.plans.single), ['spotify india']);
      expect(settled.nextDue(plan, expense.date), DateTime(2026, 12, 15));
      expect((await local.readExpenses()).single.date, expense.date);
      await local.deleteExpense(expense.id);
      final reopened = await subscriptions.watch().first;
      expect(reopened.settled(plan.id, 20261115), isFalse);
    },
  );

  test(
    'bulk linking is atomic, idempotent and keeps the original expenses',
    () async {
      final local = LocalStore(AppDatabase.forTesting(NativeDatabase.memory()));
      addTearDown(local.db.close);
      await local.initialize({});
      final subscriptions = SubscriptionStore(local);
      await subscriptions.save(plan);
      await local.saveExpenses([
        payment('first', DateTime(2026, 11, 16)),
        payment('second', DateTime(2026, 12, 16)),
      ]);
      for (final invalid in [
        {20261115: 'first', 20261215: 'missing'},
        {20261115: 'first', 20261215: 'first'},
      ]) {
        await expectLater(
          subscriptions.link(plan.id, invalid),
          throwsA(anything),
        );
        final unchanged = await subscriptions.watch().first;
        expect(unchanged.renewals, isEmpty);
        expect(subscriptionAliases(unchanged.plans.single), isEmpty);
      }
      final links = {20261115: 'first', 20261215: 'second'};
      await subscriptions.link(plan.id, links);
      await subscriptions.link(plan.id, links);
      final state = await subscriptions.watch().first;
      expect(state.renewals.length, 2);
      expect(state.planForExpense('first')?.id, plan.id);
      expect(state.byExpense['second']?.dueDay, 20261215);
      expect((await local.readExpenses()).length, 2);
    },
  );

  test(
    'migrates a version 3 database without losing existing expenses',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'kharchio-subscriptions-',
      );
      addTearDown(() => folder.delete(recursive: true));
      final file = File('${folder.path}${Platform.pathSeparator}ledger.sqlite');
      final old = LocalStore(AppDatabase.forTesting(NativeDatabase(file)));
      await old.initialize({});
      await old.saveExpenses([payment('existing', DateTime(2026, 11, 19))]);
      await old.db.customStatement('DROP TABLE subscription_renewals');
      await old.db.customStatement('DROP TABLE subscription_plans');
      await old.db.customStatement('PRAGMA user_version = 3');
      await old.db.close();

      final current = LocalStore(AppDatabase.forTesting(NativeDatabase(file)));
      addTearDown(current.db.close);
      await current.initialize({});
      expect(current.initialExpenses.single.id, 'existing');
      final subscriptions = SubscriptionStore(current);
      await subscriptions.save(plan);
      await subscriptions.link(plan.id, {20261115: 'existing'});
      expect(
        (await subscriptions.watch().first).byExpense['existing']?.planId,
        plan.id,
      );
    },
  );
}
