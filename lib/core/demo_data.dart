import 'expense.dart';

// Set false to start with an empty ledger. Default categories are independent.
const demoDataEnabled = true;
const demoYear = 2026;

List<Expense> createDemoExpenses() {
  if (!demoDataEnabled) return [];
  final values = <Expense>[];
  for (var month = 1; month <= 12; month++) {
    void add(
      int day,
      String title,
      String category,
      double amount, [
      String note = '',
    ]) {
      values.add(
        Expense(
          id: 'demo-$month-${values.length}',
          title: title,
          description: note,
          category: category,
          amount: amount,
          date: DateTime(demoYear, month, day, 9 + day % 10, day % 6 * 10),
        ),
      );
    }

    add(2, 'Weekly Groceries', 'Groceries', 900 + month * 35, 'सब्जी और राशन');
    add(5, 'Lunch with Friends', 'Food & Dining', 320 + month * 12);
    add(9, 'Metro & Bus', 'Transport', 160 + month * 5);
    add(12, 'Electricity Bill', 'Utilities', 850 + month * 22, 'बिजली बिल');
    add(16, 'Household Shopping', 'Shopping', 600 + month * 20);
    add(20, 'Medicine & Wellness', 'Health', 180 + month * 8);
    add(22, 'Books & Learning', 'Education', 250 + month * 10);
    add(24, 'Movie Night', 'Entertainment', 300 + month * 10);
    add(26, 'Coffee & Snacks', 'Food & Dining', 140 + month * 4);
    add(28, 'Milk & Dairy', 'Groceries', 120, 'दूध और दूध से जुड़ी चीजें');
    if (month == 11) {
      add(28, 'Bus Ticket', 'Transport', 30, 'बस का किराया');
      add(28, 'Dinner at Restaurant', 'Food & Dining', 450, 'रात का खाना');
      add(27, 'Grocery Shopping', 'Groceries', 680);
      add(25, 'Mobile Recharge', 'Utilities', 299);
    }
  }
  // Extra current-month fixtures keep the scrolling/collapsed chart reviewable.
  // They share demoDataEnabled, so disabling fixtures removes these too.
  final now = DateTime.now();
  const samples = [
    ('Fresh vegetables', 'Groceries', 285.50),
    ('Lunch break', 'Food & Dining', 175.00),
    ('Metro commute', 'Transport', 60.00),
    ('Household essentials', 'Shopping', 460.75),
    ('Internet recharge', 'Utilities', 299.00),
    ('Pharmacy', 'Health', 210.50),
    ('Learning materials', 'Education', 350.00),
    ('Weekend entertainment', 'Entertainment', 240.00),
    ('Daily essentials', 'Others', 95.00),
  ];
  for (var day = 1; day <= now.day; day++) {
    for (var item = 0; item < 4; item++) {
      final sample = samples[((day - 1) * 4 + item) % samples.length];
      values.add(
        Expense(
          id: 'demo-scroll-${now.year}-${now.month}-$day-$item',
          title: sample.$1,
          category: sample.$2,
          amount: sample.$3 + day % 5 * 10,
          description: 'Temporary demo transaction',
          date: DateTime(now.year, now.month, day, 8 + item * 3, item * 10),
        ),
      );
    }
  }
  for (var i = 0; i < 54; i++) {
    final sample = samples[i % samples.length];
    values.add(
      Expense(
        id: 'demo-analysis-2026-10-26-$i',
        title: '${sample.$1} ${i + 1}',
        category: sample.$2,
        amount: sample.$3 + i % 7 * 15,
        description: 'Temporary Analysis scrolling fixture',
        date: DateTime(2026, 10, 26, 7 + i ~/ 4, i % 4 * 15),
      ),
    );
  }
  return values..sort((a, b) => b.date.compareTo(a.date));
}
