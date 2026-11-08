import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharchio/core/preferences.dart';
import 'package:kharchio/core/theme.dart';
import 'package:kharchio/features/profile/profile_screen.dart';
import 'package:kharchio/services/ai/model_download_manager.dart';
import 'package:kharchio/services/ai/model_download_store.dart';
import 'package:kharchio/services/ai/online_ai_settings.dart';
import 'package:kharchio/services/notifications/pending_payment_reviews.dart';
import 'package:kharchio/services/profile_store.dart';

class _TestProfile extends UserProfileStore {
  @override
  Future<UserProfile> build() async => const UserProfile();
}

class _TestDownloads extends ModelDownloads {
  @override
  Future<ModelDownloadState> build() async =>
      ModelDownloadState(inventory: ModelInventory([]));
}

void main() {
  testWidgets('profile settings use the same height across sections', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      paymentNotificationChannel,
      (_) async => true,
    );
    addTearDown(
      () =>
          messenger.setMockMethodCallHandler(paymentNotificationChannel, null),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProfileProvider.overrideWith(_TestProfile.new),
          modelDownloadsProvider.overrideWith(_TestDownloads.new),
          initialPreferencesProvider.overrideWithValue(
            const AppPreferences(onlineAiProvider: OnlineAiProvider.gemini),
          ),
          onlineAiReadyProvider.overrideWith((_, _) async => true),
          onlineAiHasKeyProvider.overrideWith((_, _) async => true),
          onlineAiModelsProvider.overrideWith(
            (_, _) async => const OnlineAiModels(
              speech: 'gemini-speech',
              expense: 'gemini-expense',
              liveSpeech: true,
            ),
          ),
        ],
        child: MaterialApp(
          theme: appTheme(),
          home: const Scaffold(body: ProfileScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final label in [
      'Currency',
      'Budget Planner',
      'Review detected expenses',
      'Speech Model for GPU',
      'Speech Processing',
      'Qwen',
      'API Key',
      'Speech Model',
      'Share App Data with Others',
      'Export Data',
      'Reset Data',
      'About',
    ]) {
      final title = find.text(label);
      await tester.scrollUntilVisible(title, 120);
      await tester.pumpAndSettle();
      final row = find
          .ancestor(
            of: title,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is ListTile ||
                  widget is ConstrainedBox &&
                      widget.constraints.minHeight == settingsRowMinHeight,
            ),
          )
          .first;
      expect(tester.getSize(row).height, settingsRowMinHeight, reason: label);
    }
  });
}
