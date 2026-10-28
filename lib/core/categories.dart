import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/local_store.dart';

const categoryIconOptions = <String, IconData>{
  'groceries': Icons.local_drink_outlined,
  'food': Icons.restaurant_rounded,
  'transport': Icons.directions_bus_outlined,
  'shopping': Icons.shopping_bag_outlined,
  'utilities': Icons.lightbulb_outline_rounded,
  'technology': Icons.devices_outlined,
  'health': Icons.favorite_outline,
  'home': Icons.home_outlined,
  'work': Icons.work_outline,
  'education': Icons.school_outlined,
  'travel': Icons.flight_outlined,
  'entertainment': Icons.movie_outlined,
  'coffee': Icons.local_cafe_outlined,
  'fitness': Icons.fitness_center,
  'pets': Icons.pets_outlined,
  'gifts': Icons.card_giftcard_outlined,
  'subscriptions': Icons.subscriptions_outlined,
  'fuel': Icons.local_gas_station_outlined,
  'phone': Icons.smartphone_outlined,
  'internet': Icons.wifi,
  'insurance': Icons.shield_outlined,
  'beauty': Icons.spa_outlined,
  'savings': Icons.savings_outlined,
  'bank': Icons.account_balance_outlined,
  'clothing': Icons.checkroom_outlined,
  'water': Icons.water_drop_outlined,
  'games': Icons.sports_esports_outlined,
  'music': Icons.music_note_outlined,
  'parking': Icons.local_parking_rounded,
  'repair': Icons.build_outlined,
  'others': Icons.more_horiz,
};

class ExpenseCategory {
  final String name, iconKey, id;
  final int colorValue;
  const ExpenseCategory(
    this.name,
    this.colorValue,
    this.iconKey, {
    this.id = '',
  });
  Color get color => Color(colorValue);
  IconData get icon => categoryIconOptions[iconKey] ?? Icons.more_horiz;
}

/// Category ordering shared by every database-backed selection and chart.
int compareExpenseCategories(ExpenseCategory a, ExpenseCategory b) {
  final left = a.name.trim().toLowerCase();
  final right = b.name.trim().toLowerCase();
  bool isOther(String name) => name == 'other' || name == 'others';
  if (isOther(left) != isOther(right)) return isOther(left) ? 1 : -1;
  return left.compareTo(right);
}

const defaultCategories = [
  ExpenseCategory('Education', 0xFFDB6D38, 'education'),
  ExpenseCategory('Entertainment', 0xFF9A60B4, 'entertainment'),
  ExpenseCategory('Food & Dining', 0xFF365CFF, 'food'),
  ExpenseCategory('Groceries', 0xFF00AE87, 'groceries'),
  ExpenseCategory('Health', 0xFF009DC4, 'health'),
  ExpenseCategory('Shopping', 0xFFFF3891, 'shopping'),
  ExpenseCategory('Technology', 0xFF587BFF, 'technology'),
  ExpenseCategory('Transport', 0xFFFFAB00, 'transport'),
  ExpenseCategory('Utilities', 0xFF8D51FF, 'utilities'),
  ExpenseCategory('Others', 0xFF9BA7B7, 'others'),
];

List<ExpenseCategory> categoriesFromJson(String? text) {
  var result = <ExpenseCategory>[...defaultCategories];
  try {
    final decoded = jsonDecode(text ?? '[]');
    final values = decoded is Map ? decoded['items'] : decoded;
    if (decoded is Map) result = [];
    if (values is! List) return [...defaultCategories];
    for (final value in values) {
      if (value is! Map) continue;
      final name = value['name'];
      final color = value['color'];
      final icon = value['icon'];
      if (name is! String ||
          name.trim().isEmpty ||
          name.trim().length > 30 ||
          color is! int ||
          color < 0 ||
          color > 0xFFFFFFFF ||
          icon is! String ||
          !categoryIconOptions.containsKey(icon) ||
          result.any(
            (c) => c.name.toLowerCase() == name.trim().toLowerCase(),
          )) {
        continue;
      }
      result.add(ExpenseCategory(name.trim(), color, icon));
    }
  } catch (_) {
    // Retain the built-in categories if saved metadata is invalid.
  }
  return (result.isEmpty ? [...defaultCategories] : result)
    ..sort(compareExpenseCategories);
}

final categoriesProvider =
    NotifierProvider<CategoriesStore, List<ExpenseCategory>>(
      CategoriesStore.new,
    );

class CategoriesStore extends Notifier<List<ExpenseCategory>> {
  @override
  List<ExpenseCategory> build() {
    final store = ref.read(localStoreProvider);
    final subscription = store.watchCategories().listen(
      (values) => state = values,
    );
    ref.onDispose(subscription.cancel);
    return store.initialCategories;
  }

  Future<void> add(ExpenseCategory category) async {
    final name = category.name.trim();
    if (name.isEmpty ||
        name.length > 30 ||
        state.any((c) => c.name.toLowerCase() == name.toLowerCase())) {
      throw ArgumentError(
        'Enter a unique category name (up to 30 characters).',
      );
    }
    if (!categoryIconOptions.containsKey(category.iconKey)) {
      throw ArgumentError('Choose a category icon.');
    }
    await ref.read(localStoreProvider).addCategory(category);
  }

  Future<String> remove(String name) async {
    if (state.length <= 1) {
      throw StateError('Keep at least one expense category.');
    }
    return ref.read(localStoreProvider).removeCategory(name);
  }
}

class CategoriesScope extends InheritedWidget {
  final List<ExpenseCategory> categories;
  const CategoriesScope({
    super.key,
    required this.categories,
    required super.child,
  });
  @override
  bool updateShouldNotify(CategoriesScope oldWidget) =>
      oldWidget.categories != categories;
}

extension CategoryAccess on BuildContext {
  List<ExpenseCategory> get expenseCategories =>
      dependOnInheritedWidgetOfExactType<CategoriesScope>()?.categories ??
      defaultCategories;
  List<String> get categoryNames =>
      expenseCategories.map((c) => c.name).toList();
  List<Color> get categoryColors =>
      expenseCategories.map((c) => c.color).toList();
  List<IconData> get categoryIcons =>
      expenseCategories.map((c) => c.icon).toList();
  int categoryIndex(String name) {
    final index = expenseCategories.indexWhere((c) => c.name == name);
    if (index >= 0) return index;
    final others = expenseCategories.indexWhere((c) => c.name == 'Others');
    return others < 0 ? 0 : others;
  }
}
