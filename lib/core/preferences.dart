import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../database/local_store.dart';

enum AppCurrency {
  inr('INR', '₹', 'en_IN'),
  usd('USD', r'$', 'en_US');

  final String code, symbol, locale;
  const AppCurrency(this.code, this.symbol, this.locale);

  static final _formatters = <String, NumberFormat>{};

  String _number(num amount, String decimals) {
    final pattern =
        '${this == AppCurrency.inr ? '#,##,##0' : '#,##0'}$decimals';
    final formatter = _formatters.putIfAbsent(
      '$locale:$pattern',
      () => NumberFormat(pattern, locale),
    );
    return formatter.format(amount);
  }

  String? _compactNumber(num amount) {
    final magnitude = amount.abs();
    final (divisor, suffix) = switch (this) {
      AppCurrency.inr when magnitude >= 10000000 => (10000000, 'Cr'),
      AppCurrency.inr when magnitude >= 100000 => (100000, 'L'),
      AppCurrency.usd when magnitude >= 100000 => (1000000, 'M'),
      _ => (0, ''),
    };
    return divisor == 0 ? null : '${_number(amount / divisor, '.##')}$suffix';
  }

  String format(num amount) => '$symbol ${_number(amount, '.00')}';
  String formatWhole(num amount) => '$symbol ${_number(amount, '')}';
  String formatChart(num amount) => '$symbol ${_number(amount, '.##')}';
  String formatChartNumber(num amount) =>
      _compactNumber(amount) ?? _number(amount, '.##');
  String formatCalendar(num amount) =>
      '$symbol ${_compactNumber(amount) ?? _number(amount, '')}';
}

enum ProcessingMode {
  gpu(1),
  cpu(0),
  npu(2),
  s23Ultra(3);

  final int nativeValue;
  const ProcessingMode(this.nativeValue);
}

enum AiMode { onDevice, online }

enum OnlineAiProvider {
  none('None'),
  gemini('Gemini'),
  openai('OpenAI'),
  claude('Claude'),
  openrouter('OpenRouter');

  final String label;
  const OnlineAiProvider(this.label);
}

class AppPreferences {
  final AiMode aiMode;
  final OnlineAiProvider onlineAiProvider;
  final AppCurrency currency;
  final String speechLanguage;
  final ProcessingMode speechProcessing, expenseProcessing;
  const AppPreferences({
    this.aiMode = AiMode.onDevice,
    this.onlineAiProvider = OnlineAiProvider.none,
    this.currency = AppCurrency.inr,
    this.speechLanguage = 'auto',
    this.speechProcessing = ProcessingMode.npu,
    this.expenseProcessing = ProcessingMode.npu,
  });

  factory AppPreferences.fromMap(Map<String, String> values) => AppPreferences(
    aiMode: AiMode.values.firstWhere(
      (mode) => mode.name == values['aiMode'],
      orElse: () => AiMode.onDevice,
    ),
    onlineAiProvider: OnlineAiProvider.values.firstWhere(
      (provider) => provider.name == values['onlineAiProvider'],
      orElse: () => OnlineAiProvider.none,
    ),
    currency: values['currency'] == 'USD' ? AppCurrency.usd : AppCurrency.inr,
    speechProcessing: ProcessingMode.values.firstWhere(
      (mode) =>
          mode.name == (values['speechProcessing'] ?? values['processing']),
      orElse: () => ProcessingMode.npu,
    ),
    expenseProcessing: ProcessingMode.values.firstWhere(
      (mode) =>
          mode != ProcessingMode.s23Ultra &&
          mode.name == (values['expenseProcessing'] ?? values['processing']),
      orElse: () => ProcessingMode.npu,
    ),
    speechLanguage:
        const {'auto', 'en', 'hinglish'}.contains(values['speechLanguage'])
        ? values['speechLanguage']!
        : values['speechLanguage'] == 'hi'
        ? 'hinglish'
        : 'auto',
  );

  AppPreferences copyWith({
    AiMode? aiMode,
    OnlineAiProvider? onlineAiProvider,
    AppCurrency? currency,
    String? speechLanguage,
    ProcessingMode? speechProcessing,
    ProcessingMode? expenseProcessing,
  }) => AppPreferences(
    aiMode: aiMode ?? this.aiMode,
    onlineAiProvider: onlineAiProvider ?? this.onlineAiProvider,
    currency: currency ?? this.currency,
    speechLanguage: speechLanguage ?? this.speechLanguage,
    speechProcessing: speechProcessing ?? this.speechProcessing,
    expenseProcessing: expenseProcessing ?? this.expenseProcessing,
  );
}

final initialPreferencesProvider = Provider<AppPreferences>(
  (ref) => const AppPreferences(),
);
final preferencesProvider = NotifierProvider<PreferencesStore, AppPreferences>(
  PreferencesStore.new,
);

class PreferencesStore extends Notifier<AppPreferences> {
  @override
  AppPreferences build() => ref.read(initialPreferencesProvider);

  Future<void> setAiMode(AiMode mode) async {
    final store = ref.read(localStoreProvider);
    await store.db.transaction(() async {
      await store.writeSetting('ai_mode', mode.name);
      if (mode == AiMode.onDevice) {
        await store.writeSetting('online_ai_provider', OnlineAiProvider.none.name);
      }
    });
    state = state.copyWith(
      aiMode: mode,
      onlineAiProvider: mode == AiMode.onDevice ? OnlineAiProvider.none : null,
    );
  }

  Future<void> setOnlineAiProvider(OnlineAiProvider provider) async {
    await ref
        .read(localStoreProvider)
        .writeSetting('online_ai_provider', provider.name);
    state = state.copyWith(onlineAiProvider: provider);
  }

  Future<void> setCurrency(AppCurrency currency) async {
    await ref
        .read(localStoreProvider)
        .writeSetting('default_currency', currency.code);
    state = state.copyWith(currency: currency);
  }

  Future<void> setSpeechLanguage(String language) async {
    await ref
        .read(localStoreProvider)
        .writeSetting('speech_language', language);
    state = state.copyWith(speechLanguage: language);
  }

  Future<void> setSpeechProcessing(ProcessingMode mode) async {
    await ref
        .read(localStoreProvider)
        .writeSetting('speech_processing', mode.name);
    state = state.copyWith(speechProcessing: mode);
  }

  Future<void> setExpenseProcessing(ProcessingMode mode) async {
    await ref
        .read(localStoreProvider)
        .writeSetting('expense_processing', mode.name);
    state = state.copyWith(expenseProcessing: mode);
  }
}

class CurrencyScope extends InheritedWidget {
  final AppCurrency currency;
  const CurrencyScope({
    super.key,
    required this.currency,
    required super.child,
  });

  @override
  bool updateShouldNotify(CurrencyScope oldWidget) =>
      oldWidget.currency != currency;
}

extension CurrencyFormatting on BuildContext {
  AppCurrency get currency =>
      dependOnInheritedWidgetOfExactType<CurrencyScope>()?.currency ??
      AppCurrency.inr;
  String money(num amount) => currency.format(amount);
}
