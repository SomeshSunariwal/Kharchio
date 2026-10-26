import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'native_settings.dart';

const categoryIconOptions = <String, IconData>{
  'groceries': Icons.local_drink_outlined,
  'food': Icons.restaurant_rounded,
  'transport': Icons.directions_bus_outlined,
  'shopping': Icons.shopping_bag_outlined,
  'utilities': Icons.lightbulb_outline_rounded,
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
  final String name, iconKey;
  final int colorValue;
  const ExpenseCategory(this.name, this.colorValue, this.iconKey);
  Color get color => Color(colorValue);
  IconData get icon => categoryIconOptions[iconKey] ?? Icons.more_horiz;
  Map<String, Object> toJson() => {
    'name': name,
    'color': colorValue,
    'icon': iconKey,
  };
}

const defaultCategories = [
  ExpenseCategory('Groceries', 0xFF00AE87, 'groceries'),
  ExpenseCategory('Food & Dining', 0xFF365CFF, 'food'),
  ExpenseCategory('Transport', 0xFFFFAB00, 'transport'),
  ExpenseCategory('Shopping', 0xFFFF3891, 'shopping'),
  ExpenseCategory('Utilities', 0xFF8D51FF, 'utilities'),
  ExpenseCategory('Others', 0xFF9BA7B7, 'others'),
  ExpenseCategory('Health', 0xFF009DC4, 'health'),
  ExpenseCategory('Education', 0xFFDB6D38, 'education'),
  ExpenseCategory('Entertainment', 0xFF9A60B4, 'entertainment'),
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
  return result.isEmpty ? [...defaultCategories] : result;
}

final initialCategoriesProvider = Provider<List<ExpenseCategory>>(
  (ref) => defaultCategories,
);
final categoriesProvider =
    NotifierProvider<CategoriesStore, List<ExpenseCategory>>(
      CategoriesStore.new,
    );

class CategoriesStore extends Notifier<List<ExpenseCategory>> {
  @override
  List<ExpenseCategory> build() => ref.read(initialCategoriesProvider);

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
    final next = [
      ...state,
      ExpenseCategory(name, category.colorValue, category.iconKey),
    ];
    await _save(next);
    state = next;
  }

  Future<void> _save(List<ExpenseCategory> categories) =>
      NativeSettings.writePreference(
        'categories',
        jsonEncode({
          'version': 1,
          'items': categories.map((c) => c.toJson()).toList(),
        }),
      );

  Future<String> remove(String name) async {
    if (state.length <= 1) {
      throw StateError('Keep at least one expense category.');
    }
    final next = state.where((c) => c.name != name).toList();
    final replacement =
        next.where((c) => c.name == 'Others').firstOrNull ?? next.first;
    await _save(next);
    state = next;
    return replacement.name;
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
