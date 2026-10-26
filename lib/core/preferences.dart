import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'native_settings.dart';

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

class AppPreferences {
  final AppCurrency currency;
  final String speechLanguage;
  const AppPreferences({
    this.currency = AppCurrency.inr,
    this.speechLanguage = 'auto',
  });

  factory AppPreferences.fromMap(Map<String, String> values) => AppPreferences(
    currency: values['currency'] == 'USD' ? AppCurrency.usd : AppCurrency.inr,
    speechLanguage:
        const {
          'auto',
          'hi',
          'en',
          'hinglish',
        }.contains(values['speechLanguage'])
        ? values['speechLanguage']!
        : 'auto',
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

  Future<void> setCurrency(AppCurrency currency) async {
    await NativeSettings.writePreference('currency', currency.code);
    state = AppPreferences(
      currency: currency,
      speechLanguage: state.speechLanguage,
    );
  }

  Future<void> setSpeechLanguage(String language) async {
    await NativeSettings.writePreference('speechLanguage', language);
    state = AppPreferences(currency: state.currency, speechLanguage: language);
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
