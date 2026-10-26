import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/theme_settings.dart';
import 'core/native_settings.dart';
import 'core/preferences.dart';
import 'core/categories.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var mode = ThemeMode.system;
  var preferences = const AppPreferences();
  List<ExpenseCategory> categories = defaultCategories;
  try {
    final stored = await NativeSettings.readAll();
    mode = themeModeFromName(stored['themeMode']);
    preferences = AppPreferences.fromMap(stored);
    categories = categoriesFromJson(stored['categories']);
  } catch (_) {
    // A temporarily unavailable preferences store must not prevent startup.
  }
  runApp(
    ProviderScope(
      overrides: [
        initialThemeModeProvider.overrideWithValue(mode),
        initialPreferencesProvider.overrideWithValue(preferences),
        initialCategoriesProvider.overrideWithValue(categories),
      ],
      child: const KharchioApp(),
    ),
  );
}
