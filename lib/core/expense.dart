class Expense {
  final String id, title, description, category;
  final double amount;
  final DateTime date;
  const Expense({
    required this.id,
    required this.title,
    this.description = '',
    required this.category,
    required this.amount,
    required this.date,
  });
}
