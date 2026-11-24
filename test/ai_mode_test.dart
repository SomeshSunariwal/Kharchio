import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharchio/core/network_connectivity.dart';
import 'package:kharchio/core/preferences.dart';
import 'package:kharchio/database/app_database.dart';
import 'package:kharchio/database/local_store.dart';

void main() {
  late StreamController<bool> connection;

  setUp(() => connection = StreamController<bool>.broadcast(sync: true));
  tearDown(() => connection.close());

  ProviderContainer preferencesWith(Map<String, String> savedSettings) {
    final container = ProviderContainer.test(
      overrides: [
        initialPreferencesProvider.overrideWithValue(
          AppPreferences.fromMap(savedSettings),
        ),
        networkConnectivityProvider.overrideWith((ref) => connection.stream),
      ],
    );
    container.listen(showOfflineAiNoticeProvider, (_, _) {});
    return container;
  }

  test('automatically switches AI mode as the connection changes', () async {
    final container = preferencesWith({'onlineAiProvider': 'gemini'});

    expect(container.read(activeAiModeProvider), AiMode.onDevice);
    expect(container.read(showOfflineAiNoticeProvider), isFalse);

    connection.add(false);
    await container.pump();
    expect(container.read(activeAiModeProvider), AiMode.onDevice);
    expect(container.read(usesOnlineAiProvider), isFalse);
    expect(container.read(showOfflineAiNoticeProvider), isTrue);

    connection.add(true);
    await container.pump();
    expect(container.read(activeAiModeProvider), AiMode.online);
    expect(container.read(usesOnlineAiProvider), isTrue);
    expect(container.read(showOfflineAiNoticeProvider), isFalse);

    connection.add(false);
    await container.pump();
    expect(container.read(activeAiModeProvider), AiMode.onDevice);
    expect(container.read(showOfflineAiNoticeProvider), isTrue);
    expect(
      container.read(preferencesProvider).onlineAiProvider,
      OnlineAiProvider.gemini,
    );
  });

  test(
    'a saved On Device choice stays silent on either network state',
    () async {
      final container = preferencesWith({
        'aiMode': 'onDevice',
        'onlineAiProvider': 'gemini',
      });

      for (final connected in [false, true]) {
        connection.add(connected);
        await container.pump();
        expect(container.read(activeAiModeProvider), AiMode.onDevice);
        expect(container.read(usesOnlineAiProvider), isFalse);
        expect(container.read(showOfflineAiNoticeProvider), isFalse);
      }
    },
  );

  test('keeps local processing available without an online provider', () async {
    final container = preferencesWith({});

    connection.add(true);
    await container.pump();
    expect(container.read(activeAiModeProvider), AiMode.online);
    expect(container.read(usesOnlineAiProvider), isFalse);
  });

  test(
    'persists each mode choice without replacing either configuration',
    () async {
      final store = LocalStore(AppDatabase.forTesting(NativeDatabase.memory()));
      addTearDown(store.db.close);
      final container = ProviderContainer.test(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      final preferences = container.read(preferencesProvider.notifier);
      await preferences.setOnlineAiProvider(OnlineAiProvider.gemini);
      await preferences.setSpeechProcessing(ProcessingMode.cpu);
      await preferences.setExpenseProcessing(ProcessingMode.gpu);

      await preferences.setAiMode(AiMode.onDevice);
      expect(await store.setting('ai_mode'), 'onDevice');
      expect(await store.setting('online_ai_provider'), 'gemini');

      await preferences.setAiMode(AiMode.online);
      expect(await store.setting('ai_mode'), 'online');
      expect(await store.setting('online_ai_provider'), 'gemini');
      expect(await store.setting('speech_processing'), 'cpu');
      expect(await store.setting('expense_processing'), 'gpu');

      final restored = AppPreferences.fromMap({
        'aiMode': (await store.setting('ai_mode'))!,
        'onlineAiProvider': (await store.setting('online_ai_provider'))!,
        'speechProcessing': (await store.setting('speech_processing'))!,
        'expenseProcessing': (await store.setting('expense_processing'))!,
      });
      expect(restored.aiMode, AiMode.online);
      expect(restored.onlineAiProvider, OnlineAiProvider.gemini);
      expect(restored.speechProcessing, ProcessingMode.cpu);
      expect(restored.expenseProcessing, ProcessingMode.gpu);
    },
  );
}
