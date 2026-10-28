class Expense {
  final String id, title, description, category, currencyCode;
  final String? monthId;
  final int? accountingYear, accountingMonth;
  int get year => accountingYear ?? date.year;
  int get month => accountingMonth ?? date.month;
  final double amount;
  final DateTime date;
  const Expense({
    required this.id,
    this.monthId,
    this.accountingYear,
    this.accountingMonth,
    required this.title,
    this.description = '',
    required this.category,
    required this.amount,
    required this.date,
    this.currencyCode = 'INR',
  });
}
