import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/local_store.dart';

final initialThemeModeProvider = Provider<ThemeMode>((ref) => ThemeMode.system);
final themeModeProvider = NotifierProvider<ThemeModeStore, ThemeMode>(
  ThemeModeStore.new,
);

ThemeMode themeModeFromName(String? name) => switch (name) {
  'dark' => ThemeMode.dark,
  'light' => ThemeMode.light,
  _ => ThemeMode.system,
};

class ThemeModeStore extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.read(initialThemeModeProvider);

  Future<void> select(ThemeMode mode) async {
    await ref.read(localStoreProvider).writeSetting('theme_mode', mode.name);
    state = mode;
  }
}
