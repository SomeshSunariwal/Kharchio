import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../core/preferences.dart';
import 'online_ai_client.dart';
export 'online_ai_client.dart' show OnlineAiModels, OnlineAiConnectionException;

final onlineAiKeysProvider = Provider((ref) => OnlineAiKeys());
final onlineAiHasKeyProvider = FutureProvider.family<bool, OnlineAiProvider>(
  (ref, provider) async =>
      (await ref.watch(onlineAiKeysProvider).read(provider))?.isNotEmpty ==
      true,
);
final onlineAiReadyProvider = FutureProvider.family<bool, OnlineAiProvider>(
  (ref, provider) => ref.watch(onlineAiKeysProvider).isReady(provider),
);
final onlineAiModelsProvider =
    FutureProvider.family<OnlineAiModels?, OnlineAiProvider>((
      ref,
      provider,
    ) async {
      await ref.watch(onlineAiReadyProvider(provider).future);
      return ref.read(onlineAiKeysProvider).models(provider);
    });

/// Credentials never enter SQLite, preferences, or expense sharing payloads.
class OnlineAiKeys {
  final FlutterSecureStorage storage;
  OnlineAiKeys({this.storage = const FlutterSecureStorage()});

  String _name(OnlineAiProvider provider) {
    if (provider == OnlineAiProvider.none) {
      throw ArgumentError('Select an online AI provider first.');
    }
    return 'online_ai_key_${provider.name}';
  }

  Future<String?> read(OnlineAiProvider provider) =>
      storage.read(key: _name(provider));
  String _fingerprint(String key) =>
      sha256.convert(utf8.encode(key.trim())).toString();

  Future<bool> isReady(OnlineAiProvider provider) async =>
      await models(provider) != null;

  Future<OnlineAiModels?> models(OnlineAiProvider provider) async {
    final key = await read(provider);
    if (key == null || key.isEmpty) return null;
    final value = await storage.read(key: '${_name(provider)}_validated');
    if (value == null) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map ||
          decoded['version'] != 2 ||
          decoded['fingerprint'] != _fingerprint(key)) {
        return null;
      }
      final models = OnlineAiModels.fromJson(decoded['models']);
      if ((provider == OnlineAiProvider.gemini ||
              provider == OnlineAiProvider.openai) &&
          models?.liveSpeech != true) {
        return null;
      }
      if (const bool.fromEnvironment('GEMINI_FREE_TIER_ONLY') &&
          provider == OnlineAiProvider.gemini &&
          models != null &&
          (!OnlineAiClient.freeTierGeminiLiveModels.contains(models.speech) ||
              !OnlineAiClient.freeTierGeminiModels.contains(models.expense))) {
        return null;
      }
      return models;
    } on FormatException {
      // Older authentication-only checks must pass the full processing test.
      return null;
    }
  }

  Future<void> clearValidation(OnlineAiProvider provider) =>
      storage.delete(key: '${_name(provider)}_validated');

  Future<void> save(
    OnlineAiProvider provider,
    String key, {
    bool validated = false,
    OnlineAiModels? models,
  }) async {
    await clearValidation(provider);
    await storage.write(key: _name(provider), value: key.trim());
    if (validated && models != null && key.trim().isNotEmpty) {
      await storage.write(
        key: '${_name(provider)}_validated',
        value: jsonEncode({
          'version': 2,
          'fingerprint': _fingerprint(key),
          'models': models.toJson(),
        }),
      );
    }
  }

  Future<void> remove(OnlineAiProvider provider) async {
    await clearValidation(provider);
    await storage.delete(key: _name(provider));
  }
}

/// Tests the same automatically selected speech and expense models used to record.
Future<OnlineAiModels> testOnlineAiConnection(
  OnlineAiProvider provider,
  String key, {
  http.Client? client,
}) async {
  final connection = OnlineAiClient(provider, key, client: client);
  try {
    return await connection.checkConnection();
  } finally {
    connection.close();
  }
}
