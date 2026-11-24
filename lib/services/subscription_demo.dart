import '../core/expense.dart';
import '../core/subscriptions.dart';
import '../database/local_store.dart';
import '../database/subscription_store.dart';

/// Enabled only in explicitly requested debug validation builds.
Future<void> seedSubscriptionDemo(LocalStore store, DateTime now) async {
  const marker = 'subscription_demo_v1';
  await store.db.transaction(() async {
    if (await store.setting(marker) == '1') return;
    final subscriptions = SubscriptionStore(store);
    final category = store.initialCategories.first.name;
    for (final service in ['Spotify', 'Netflix']) {
      final spotify = service == 'Spotify';
      final id = 'subscription-sample-${service.toLowerCase()}';
      final anchor = DateTime(now.year, now.month - 4, spotify ? 2 : 28);
      final plan = SubscriptionPlan(
        id: id,
        name: 'Sample $service',
        minor: spotify ? 19900 : 49900,
        currencyCode: 'INR',
        intervalMonths: 1,
        anchorDay: subscriptionDay(anchor),
        reminderMinutes: 9 * 60,
        active: true,
        merchantAliases: '[]',
      );
      await subscriptions.save(plan);
      final count = spotify ? 5 : 4;
      for (var cycle = 0; cycle < count; cycle++) {
        final due = subscriptionCycle(plan, anchor, cycle);
        final paid = shiftSubscriptionDate(due, spotify ? 1 : 2);
        if (paid.isAfter(now)) continue;
        await subscriptions.saveAndLink(
          Expense(
            id: '$id-${subscriptionDay(due)}',
            title: 'Sample $service payment',
            description: 'Dummy subscription payment for validation',
            category: category,
            amount: spotify ? 189 : 499,
            date: paid,
          ),
          id,
          subscriptionDay(due),
        );
      }
    }
    await store.writeSetting(marker, '1');
  });
  store.initialExpenses = await store.readExpenses();
}
