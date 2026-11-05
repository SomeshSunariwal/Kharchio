import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kharchio/core/preferences.dart';
import 'package:kharchio/core/theme.dart';
import 'package:kharchio/features/expenses/record_expense_modal.dart';
import 'package:kharchio/features/profile/online_ai_section.dart';
import 'package:kharchio/services/ai/live_transcriber.dart';
import 'package:kharchio/services/ai/online_ai_client.dart';
import 'package:kharchio/services/ai/online_ai_settings.dart';
import 'package:kharchio/services/ai/openrouter_transcriber.dart';
import 'package:kharchio/services/ai/model_manager.dart';
import 'package:kharchio/services/audio/voice_capture.dart';
import 'package:kharchio/shared/preference_dropdown_row.dart';

class _MissingWhisper extends ModelManager {
  @override
  Future<OfflineModels> build() async => const OfflineModels('', '');
  @override
  Future<OfflineModels> requireAvailable({
    int? speechMode,
    bool expense = false,
  }) async {
    expect(expense, isFalse);
    throw StateError('Download Whisper for speech.');
  }
}

class _Capture extends VoiceCapture {
  final audio = BytesBuilder();
  bool paused = false;
  @override
  int get length => audio.length;
  @override
  Uint8List snapshot() => audio.toBytes();
  void push() {
    final pcm = Uint8List(48000); // One shared 1.5-second speech chunk.
    final data = ByteData.sublistView(pcm);
    for (var i = 0; i < pcm.length; i += 2) {
      data.setInt16(i, i % 4 == 0 ? 2000 : -2000, Endian.little);
    }
    audio.add(pcm);
    onPcm?.call(pcm);
    onAudio?.call();
  }

  @override
  Future<void> start() async {}
  @override
  Future<void> pause() async {
    paused = true;
  }

  @override
  Future<void> resume() async {
    paused = false;
  }

  @override
  Future<Uint8List> stop() async => snapshot();
  @override
  void clearAudio() => audio.clear();
  @override
  Future<void> dispose() async {
    level.dispose();
  }
}

http.Response _json(Object value, [int code = 200]) => http.Response(
  jsonEncode(value),
  code,
  headers: {'content-type': 'application/json'},
);
Map<String, Object?> _model(
  String id,
  List<String> input, {
  bool free = true,
}) => {
  'id': id,
  'architecture': {
    'input_modalities': input,
    'output_modalities': ['text'],
  },
  'pricing': {'prompt': free ? '0' : '0.01', 'completion': free ? '0' : '0.01'},
  'supported_parameters': ['response_format', 'structured_outputs'],
};
final _catalog = {
  'data': [
    _model('vendor/paid-audio', ['audio', 'text'], free: false),
    _model('vendor/free-text', ['text']),
    _model('vendor/free-audio', ['audio']),
    _model('openrouter/auto', ['audio', 'text']),
    {
      'id': 'image-only',
      'architecture': {
        'input_modalities': ['text'],
        'output_modalities': ['image'],
      },
    },
  ],
};
http.Response _chat(String text) => _json({
  'choices': [
    {
      'finish_reason': 'stop',
      'message': {'content': text},
    },
  ],
});
final _expenses = {
  'transactions': [
    {
      'title': 'Milk',
      'description': '',
      'amount': 100,
      'category': 'Groceries',
      'type': 'expense',
    },
    {
      'title': 'Refund',
      'description': '',
      'amount': 50,
      'category': 'Groceries',
      'type': 'refund',
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('OpenRouter pause returns while a delayed chunk is still pending and Stop retains its result', () async {
    final reply = Completer<http.Response>();
    var calls = 0;
    final speech = OpenRouterTranscriber(
      'fake',
      'audio',
      pauseTimeout: const Duration(milliseconds: 20),
      client: MockClient((_) async {
        calls++;
        return calls == 1 ? reply.future : _chat('Bus 40.');
      }),
    );
    await speech.start(language: 'en');
    speech.addAudio(Uint8List(3200));
    expect(await speech.pause(), '');
    speech.addAudio(Uint8List(3200));
    reply.complete(_chat('Milk 100.'));
    expect(await speech.finish(), 'Milk 100. Bus 40.');
    expect(calls, 2);
  });

  for (final provider in [
    OnlineAiProvider.openrouter,
    OnlineAiProvider.claude,
  ]) {
    testWidgets(
      '${provider.label} hybrid disables speech, shows red Whisper message, and keeps expenses enabled',
      (tester) async {
        tester.view.physicalSize = const Size(430, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final models = const OnlineAiModels(
          speech: 'unused',
          expense: 'vendor/text',
          available: ['vendor/text'],
        ).withOnDeviceSpeech();
        await OnlineAiKeys().save(
          provider,
          'fake',
          validated: true,
          models: models,
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              initialPreferencesProvider.overrideWithValue(
                AppPreferences(
                  aiMode: AiMode.online,
                  onlineAiProvider: provider,
                ),
              ),
              onlineAiClientFactoryProvider.overrideWithValue(
                (_, _) => throw StateError(
                  'Viewing settings must not call a provider.',
                ),
              ),
            ],
            child: MaterialApp(
              theme: appTheme(),
              home: const Scaffold(body: OnlineAiSection()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final rows = tester.widgetList<PreferenceDropdownRow<String>>(
          find.byType(PreferenceDropdownRow<String>),
        );
        final speech = rows.singleWhere((row) => row.label == 'Speech Model');
        final expense = rows.singleWhere(
          (row) => row.label == 'Available Model',
        );
        expect(speech.enabled, isFalse);
        expect(speech.value, OnlineAiModels.onDeviceSpeech);
        expect(speech.descriptionError, isTrue);
        expect(expense.enabled, isTrue);
        expect(
          tester
              .widget<Text>(find.text('Using on-device Whisper'))
              .style
              ?.color,
          red,
        );
        expect(find.text('Ready'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'OpenRouter hybrid requires local Whisper and does not open online speech',
    (tester) async {
      final models = const OnlineAiModels(
        speech: 'unused',
        expense: 'vendor/text',
        available: ['vendor/text'],
      ).withOnDeviceSpeech();
      await OnlineAiKeys().save(
        OnlineAiProvider.openrouter,
        'fake',
        validated: true,
        models: models,
      );
      const recordChannel = MethodChannel('com.llfbandit.record/messages');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        recordChannel,
        (_) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          recordChannel,
          null,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialPreferencesProvider.overrideWithValue(
              const AppPreferences(
                aiMode: AiMode.online,
                onlineAiProvider: OnlineAiProvider.openrouter,
              ),
            ),
            voiceCaptureFactoryProvider.overrideWithValue(_Capture.new),
            offlineModelsProvider.overrideWith(_MissingWhisper.new),
            onlineLiveFactoryProvider.overrideWithValue(
              (_, _, _) =>
                  throw StateError('Hybrid must not open online speech.'),
            ),
            onlineAiClientFactoryProvider.overrideWithValue(
              (provider, key) => OnlineAiClient(
                provider,
                key,
                client: MockClient(
                  (_) async =>
                      throw StateError('No expense request before speech.'),
                ),
              ),
            ),
          ],
          child: MaterialApp(
            theme: appTheme(),
            home: const Scaffold(
              body: SingleChildScrollView(child: RecordExpenseModal()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Download Whisper for speech.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'rejected audio does not block a validated OpenRouter expense model',
    () async {
      var audioCalls = 0, expenseCalls = 0;
      final client = OnlineAiClient(
        OnlineAiProvider.openrouter,
        'fake',
        diagnosticFrameInterval: Duration.zero,
        client: MockClient((request) async {
          if (request.method == 'GET') return _json(_catalog);
          expenseCalls++;
          return _chat(jsonEncode(_expenses));
        }),
        liveFactory: (_, key, model) => OpenRouterTranscriber(
          key,
          model,
          client: MockClient((_) async {
            audioCalls++;
            return _json({'error': 'credits required'}, 402);
          }),
        ),
      );
      final models = await client.checkConnection(
        sampleWav: await File('assets/diagnostics/model_check.wav')
            .readAsBytes(),
      );
      expect(audioCalls, 2);
      expect(expenseCalls, 1);
      expect(models.usesOnDeviceSpeech, isTrue);
      expect(models.availableSpeech, isEmpty);
      expect(models.expense, 'vendor/free-text');
      await OnlineAiKeys().save(
        OnlineAiProvider.openrouter,
        'fake',
        validated: true,
        models: models,
      );
      expect(await OnlineAiKeys().isReady(OnlineAiProvider.openrouter), isTrue);
      expect(
        (await OnlineAiKeys().models(OnlineAiProvider.openrouter))!
            .usesOnDeviceSpeech,
        isTrue,
      );
      await client.checkSelectedModels(models, previous: models);
      expect(audioCalls, 2);
      expect(expenseCalls, 1);
      client.close();
    },
  );

  for (final outputLanguage in ['auto', 'hinglish', 'en']) {
    testWidgets(
      'OpenRouter recording keeps live text fast, resumes, and writes final $outputLanguage output with pinned models',
      (tester) async {
        tester.view.physicalSize = const Size(430, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const recordChannel = MethodChannel('com.llfbandit.record/messages');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          recordChannel,
          (_) async => null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            recordChannel,
            null,
          ),
        );
        const models = OnlineAiModels(
          speech: 'vendor/audio',
          expense: 'vendor/text',
          liveSpeech: true,
          availableSpeech: ['vendor/audio'],
          available: ['vendor/text'],
        );
        await OnlineAiKeys().save(
          OnlineAiProvider.openrouter,
          'fake',
          validated: true,
          models: models,
        );
        final capture = _Capture();
        var speechCalls = 0, expenseCalls = 0, formattingCalls = 0;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              initialPreferencesProvider.overrideWithValue(
                AppPreferences(
                  aiMode: AiMode.online,
                  onlineAiProvider: OnlineAiProvider.openrouter,
                  speechLanguage: outputLanguage,
                ),
              ),
              voiceCaptureFactoryProvider.overrideWithValue(() => capture),
              offlineModelsProvider.overrideWith(
                () =>
                    throw StateError('OpenRouter must not load local models.'),
              ),
              onlineLiveFactoryProvider.overrideWithValue((
                provider,
                key,
                model,
              ) {
                expect(model, models.speech);
                return OpenRouterTranscriber(
                  key,
                  model,
                  client: MockClient((request) async {
                    speechCalls++;
                    expect(jsonDecode(request.body)['model'], models.speech);
                    return _chat(speechCalls == 1 ? 'Milk 100.' : 'Refund 50.');
                  }),
                );
              }),
              onlineAiClientFactoryProvider.overrideWithValue(
                (provider, key) => OnlineAiClient(
                  provider,
                  key,
                  client: MockClient((request) async {
                    expect(request.method, 'POST');
                    expect(jsonDecode(request.body)['model'], models.expense);
                    final system =
                        jsonDecode(request.body)['messages'][0]['content']
                            as String;
                    if (system.contains('Rewrite only')) {
                      formattingCalls++;
                      expect(outputLanguage, 'en');
                    }
                    expenseCalls++;
                    return _chat(
                      jsonEncode({
                        ..._expenses,
                        if (outputLanguage == 'en') 'transcript': 'I paid 100 rupees for milk and received a 50 rupee refund.',
                      }),
                    );
                  }),
                ),
              ),
            ],
            child: MaterialApp(
              theme: appTheme(),
              home: const Scaffold(
                body: SingleChildScrollView(child: RecordExpenseModal()),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(() async {
          capture.push();
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await tester.pump();
        expect(
          speechCalls,
          1,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((text) => text.data)
              .join(';'),
        );
        expect(find.textContaining('Milk 100.'), findsOneWidget);
        expect(expenseCalls, 0);
        expect(formattingCalls, 0);
        await tester.tap(find.byTooltip('Pause recording'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(capture.paused, isTrue);
        await tester.tap(find.byTooltip('Resume recording'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(capture.paused, isFalse);
        await tester.runAsync(() async {
          capture.push();
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await tester.pump();
        await tester.tap(find.byTooltip('Stop and process recording'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Transaction summary (2)'), findsOneWidget);
        expect(speechCalls, 2);
        expect(expenseCalls, 1);
        expect(formattingCalls, outputLanguage == 'en' ? 1 : 0);
        if (outputLanguage == 'en') {
          expect(
            find.textContaining('I paid 100 rupees for milk'),
            findsOneWidget,
          );
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('OpenRouter separates capabilities, prefers free models and preserves metadata', () async {
    final client = OnlineAiClient(
      OnlineAiProvider.openrouter,
      'fake',
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/models');
        expect(request.headers['Authorization'], 'Bearer fake');
        return _json(_catalog);
      }),
    );
    final models = await client.selectModels();
    expect(models.speech, 'vendor/free-audio');
    expect(models.expense, 'vendor/free-text');
    expect(models.availableSpeech, ['vendor/free-audio', 'vendor/paid-audio']);
    expect(models.available, ['vendor/free-text', 'vendor/paid-audio']);
    expect(
      models.freeModels,
      containsAll(['vendor/free-text', 'vendor/free-audio']),
    );
    final manual = models
        .selectSpeech('vendor/paid-audio')
        .selectExpense('vendor/paid-audio');
    final restored = OnlineAiModels.fromJson(
      jsonDecode(jsonEncode(manual.toJson())),
    )!;
    expect(restored.selectSpeech('auto').speech, 'vendor/free-audio');
    expect(restored.selectExpense('auto').expense, 'vendor/free-text');
    expect(restored.jsonSchemaModels, contains('vendor/free-text'));
    FlutterSecureStorage.setMockInitialValues({});
    final keys = OnlineAiKeys();
    await keys.save(
      OnlineAiProvider.openrouter,
      'fake',
      validated: true,
      models: restored,
    );
    expect(await keys.isReady(OnlineAiProvider.openrouter), isTrue);
    expect(
      (await keys.models(OnlineAiProvider.openrouter))!.freeModels,
      restored.freeModels,
    );
    client.close();
  });

  test('audio chunks update before Stop, serialize requests, and preserve odd sample boundaries', () async {
    final firstReply = Completer<http.Response>();
    final sent = BytesBuilder();
    final updates = <String>[];
    var calls = 0;
    final speech = OpenRouterTranscriber(
      'fake',
      'vendor/audio',
      client: MockClient((request) async {
        calls++;
        expect(request.url.path, '/api/v1/chat/completions');
        final body = jsonDecode(request.body);
        expect(body['model'], 'vendor/audio');
        final audio = body['messages'][0]['content'][1]['input_audio'];
        expect(audio['format'], 'wav');
        final pcm = wavToPcm(base64Decode(audio['data'] as String));
        expect(pcm.length, lessThanOrEqualTo(64000));
        sent.add(pcm);
        if (calls == 1) return firstReply.future;
        return _chat('Bus 40.');
      }),
    )..onTranscript = updates.add;
    await speech.start(language: 'hinglish');
    final pcm = Uint8List.fromList(List.generate(70000, (i) => i % 256));
    speech.addAudio(Uint8List.sublistView(pcm, 0, 3001));
    speech.addAudio(Uint8List.sublistView(pcm, 3001));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(calls, 1);
    firstReply.complete(_chat('Milk 100.'));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(updates, ['Milk 100.']);
    expect(await speech.pause(), 'Milk 100. Bus 40.');
    speech.addAudio(Uint8List(3200));
    expect(await speech.finish(), 'Milk 100. Bus 40. Bus 40.');
    expect(sent.toBytes(), [...pcm, ...Uint8List(3200)]);
    expect(calls, 3);
  });

  test('connection testing falls back from unavailable free audio, then locks the working pair', () async {
    final speechModels = <String>[];
    var discovery = 0, expenseCalls = 0;
    final client = OnlineAiClient(
      OnlineAiProvider.openrouter,
      'fake',
      diagnosticFrameInterval: Duration.zero,
      client: MockClient((request) async {
        if (request.method == 'GET') {
          discovery++;
          return _json(_catalog);
        }
        expenseCalls++;
        final body = jsonDecode(request.body);
        expect(body['model'], 'vendor/free-text');
        expect(body['response_format']['type'], 'json_schema');
        return _chat(jsonEncode(_expenses));
      }),
      liveFactory: (provider, key, model) => OpenRouterTranscriber(
        key,
        model,
        client: MockClient((request) async {
          speechModels.add(model);
          if (model == 'vendor/free-audio') {
            return _json({'error': 'access denied'}, 403);
          }
          return _chat('Milk 100 and refund 50.');
        }),
      ),
    );
    final models = await client.checkConnection(
      sampleWav: await File('assets/diagnostics/model_check.wav').readAsBytes(),
    );
    expect(discovery, 1);
    expect(expenseCalls, 1);
    expect(speechModels.first, 'vendor/free-audio');
    expect(models.speech, 'vendor/paid-audio');
    expect(models.automaticSpeech, models.speech);
    expect(models.expense, 'vendor/free-text');
    expect(models.freeModels, contains('vendor/free-text'));
    final result = await client.extract(
      text: 'Milk 100 and refund 50',
      categories: ['Groceries'],
      currency: 'INR',
      models: models,
    );
    expect(result, hasLength(2));
    expect(discovery, 1);
    client.close();
  });

  test('audio failures are safe and stop pending chunks', () async {
    var calls = 0;
    final speech = OpenRouterTranscriber(
      'private-key',
      'vendor/audio',
      client: MockClient((_) async {
        calls++;
        return _json({'error': 'private-key in provider detail'}, 401);
      }),
    );
    await speech.start(language: 'auto');
    speech.addAudio(Uint8List(128000));
    await expectLater(
      speech.finish(),
      throwsA(
        isA<LiveTranscriptionException>()
            .having((error) => error.statusCode, 'status', 401)
            .having(
              (error) => error.message,
              'message',
              isNot(contains('private-key')),
            ),
      ),
    );
    expect(calls, 1);
  });

  test('text-only catalogs explicitly use local Whisper and keep expense validation available', () async {
    final client = OnlineAiClient(
      OnlineAiProvider.openrouter,
      'fake',
      client: MockClient(
        (request) async => request.method == 'GET'
            ? _json({
                'data': [
                  _model('text-only', ['text']),
                ],
              })
            : _chat(jsonEncode(_expenses)),
      ),
      liveFactory: (_, _, _) =>
          throw StateError('No online speech model to test.'),
    );
    final models = await client.checkConnection();
    expect(models.usesOnDeviceSpeech, isTrue);
    expect(models.availableSpeech, isEmpty);
    expect(models.expense, 'text-only');
    client.close();
  });
}
