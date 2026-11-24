import 'dart:convert';

import '../database/app_database.dart';
import 'expense.dart';

export '../database/app_database.dart'
    show SubscriptionPlan, SubscriptionRenewal;

int subscriptionDay(DateTime value) =>
    value.year * 10000 + value.month * 100 + value.day;

DateTime subscriptionDate(int day) =>
    DateTime(day ~/ 10000, day ~/ 100 % 100, day % 100);

DateTime shiftSubscriptionDate(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

DateTime subscriptionCycle(SubscriptionPlan plan, DateTime date, int cycles) {
  final month = DateTime(date.year, date.month + cycles * plan.intervalMonths);
  final lastDay = DateTime(month.year, month.month + 1, 0).day;
  return DateTime(
    month.year,
    month.month,
    (plan.anchorDay % 100).clamp(1, lastDay),
  );
}

DateTime subscriptionDueOnOrAfter(SubscriptionPlan plan, DateTime date) {
  final anchor = subscriptionDate(plan.anchorDay);
  final months = (date.year - anchor.year) * 12 + date.month - anchor.month;
  final cycle = subscriptionCycle(
    plan,
    anchor,
    (months / plan.intervalMonths).floor(),
  );
  return subscriptionDay(cycle) < subscriptionDay(date)
      ? subscriptionCycle(plan, cycle, 1)
      : cycle;
}

final _merchantSeparators = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

String normalizeSubscriptionMerchant(String value) =>
    value.toLowerCase().replaceAll(_merchantSeparators, ' ').trim();

List<String> subscriptionAliases(SubscriptionPlan plan) =>
    (jsonDecode(plan.merchantAliases) as List).cast<String>();

bool hasSubscriptionMerchant(String merchant) =>
    merchant.isNotEmpty && merchant != 'card upi payment';

bool subscriptionMerchantMatches(SubscriptionPlan plan, String title) =>
    _MerchantMatcher(plan).matches(normalizeSubscriptionMerchant(title));

class _MerchantMatcher {
  final String name;
  final Set<String> aliases;
  _MerchantMatcher(SubscriptionPlan plan)
    : name = normalizeSubscriptionMerchant(plan.name),
      aliases = subscriptionAliases(plan).toSet();

  bool matches(String merchant) =>
      hasSubscriptionMerchant(merchant) &&
      (aliases.contains(merchant) ||
          merchant == name ||
          (name.length >= 3 && ' $merchant '.contains(' $name ')));
}

typedef SubscriptionDue = ({String planId, int dueDay});
typedef SubscriptionMatch = ({SubscriptionPlan plan, int dueDay});

class SubscriptionState {
  final List<SubscriptionPlan> plans;
  final Map<SubscriptionDue, SubscriptionRenewal> renewals;
  final Map<String, SubscriptionRenewal> byExpense;
  late final plansById = {for (final plan in plans) plan.id: plan};
  final _matchers = <SubscriptionPlan, _MerchantMatcher>{};

  SubscriptionPlan? planForExpense(String id) =>
      plansById[byExpense[id]?.planId];

  SubscriptionState(this.plans, Iterable<SubscriptionRenewal> renewals)
    : renewals = {
        for (final r in renewals) (planId: r.planId, dueDay: r.dueDay): r,
      },
      byExpense = {
        for (final r in renewals)
          if (r.expenseId case final String id) id: r,
      };

  SubscriptionRenewal? renewal(String planId, int day) =>
      renewals[(planId: planId, dueDay: day)];

  bool settled(String planId, int day) {
    final entry = renewal(planId, day);
    return entry?.expenseId != null || entry?.skipped == true;
  }

  DateTime nextDue(SubscriptionPlan plan, DateTime today) {
    var due = subscriptionDueOnOrAfter(plan, today);
    if (subscriptionDay(due) < plan.anchorDay) {
      due = subscriptionDate(plan.anchorDay);
    }
    while (settled(plan.id, subscriptionDay(due))) {
      due = subscriptionCycle(plan, due, 1);
    }
    return due;
  }

  DateTime dueToReview(SubscriptionPlan plan, DateTime today) {
    final upcoming = nextDue(plan, today);
    final lastDue = subscriptionCycle(
      plan,
      subscriptionDueOnOrAfter(plan, today),
      -1,
    );
    final key = subscriptionDay(lastDue);
    return key >= plan.anchorDay && !settled(plan.id, key) ? lastDue : upcoming;
  }

  Iterable<SubscriptionMatch> upcomingRenewals(
    DateTime first,
    DateTime last,
    String currencyCode, {
    required DateTime asOf,
  }) sync* {
    if (first.isAfter(last)) return;
    final asOfDay = subscriptionDay(asOf);
    for (final plan in plans) {
      if (!plan.active || plan.currencyCode != currencyCode) continue;
      for (
        var due = nextDue(plan, first);
        !due.isAfter(last);
        due = subscriptionCycle(plan, due, 1)
      ) {
        // Later cycles cannot enter the reminder window before this one.
        if (subscriptionDay(
              shiftSubscriptionDate(due, -(plan.reminderDays ?? 0)),
            ) >
            asOfDay) {
          break;
        }
        final day = subscriptionDay(due);
        if (!settled(plan.id, day)) yield (plan: plan, dueDay: day);
      }
    }
  }

  SubscriptionMatch? match(Expense expense, {SubscriptionPlan? onlyPlan}) {
    if (expense.isRefund || byExpense.containsKey(expense.id)) return null;
    final merchant = normalizeSubscriptionMerchant(expense.title);
    if (!hasSubscriptionMerchant(merchant)) return null;
    final minor = (expense.amount * 100).round();
    final earliest = shiftSubscriptionDate(expense.date, -7);
    final latest = subscriptionDay(shiftSubscriptionDate(expense.date, 3));
    SubscriptionMatch? result;
    for (final plan in onlyPlan == null ? plans : [onlyPlan]) {
      if ((onlyPlan == null && !plan.active) ||
          plan.currencyCode != expense.currencyCode ||
          plan.minor != minor ||
          !_matchers
              .putIfAbsent(plan, () => _MerchantMatcher(plan))
              .matches(merchant)) {
        continue;
      }
      final due = subscriptionDay(subscriptionDueOnOrAfter(plan, earliest));
      if (due <= latest &&
          (onlyPlan != null || due >= plan.anchorDay) &&
          !settled(plan.id, due)) {
        if (result != null) return null;
        result = (plan: plan, dueDay: due);
      }
    }
    return result;
  }

  Map<int, Expense> historicalMatches(
    SubscriptionPlan plan,
    Iterable<Expense> expenses,
    DateTime today,
  ) {
    final results = <int, Expense>{};
    final ambiguous = <int>{};
    for (final expense in expenses) {
      final suggestion = match(expense, onlyPlan: plan);
      if (suggestion == null || suggestion.dueDay > subscriptionDay(today)) {
        continue;
      }
      if (results.containsKey(suggestion.dueDay)) {
        ambiguous.add(suggestion.dueDay);
      }
      results[suggestion.dueDay] = expense;
    }
    results.removeWhere((day, _) => ambiguous.contains(day));
    return results;
  }
}
