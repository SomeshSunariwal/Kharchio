import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/native_settings.dart';
import 'core/preferences.dart';
import 'core/theme_settings.dart';
import 'database/app_database.dart';
import 'database/local_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = LocalStore(AppDatabase());
  try {
    Map<String, String> legacy = {};
    try {
      legacy = await NativeSettings.readAll();
    } catch (_) {
      /* Fresh install. */
    }
    await store.initialize(legacy);
  } catch (error, stack) {
    await store.db.close();
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stack),
    );
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Could not open your local database.'),
                  const Text('Your saved data has not been reset.'),
                  TextButton(onPressed: main, child: const Text('Retry')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }
  final settings = store.initialSettings;
  runApp(
    ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        initialThemeModeProvider.overrideWithValue(
          themeModeFromName(settings['theme_mode']),
        ),
        initialPreferencesProvider.overrideWithValue(
          AppPreferences.fromMap({
            'currency': settings['default_currency'] ?? 'INR',
            'speechLanguage': settings['speech_language'] ?? 'auto',
            if (settings['processing'] case final String mode)
              'processing': mode,
            if (settings['speech_processing'] case final String mode)
              'speechProcessing': mode,
            if (settings['expense_processing'] case final String mode)
              'expenseProcessing': mode,
          }),
        ),
      ],
      child: const KharchioApp(),
    ),
  );
}
