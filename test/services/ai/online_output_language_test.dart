import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kharchio/core/preferences.dart';
import 'package:kharchio/services/ai/online_ai_client.dart';

void main() {
  for (final provider in [
    OnlineAiProvider.gemini,
    OnlineAiProvider.openai,
    OnlineAiProvider.claude,
    OnlineAiProvider.openrouter,
  ]) {
    for (final language in ['en', 'auto', 'hinglish']) {
      test(
        '${provider.label}: final transcript and cards follow $language using the locked context model',
        () async {
          const models = OnlineAiModels(
            speech: 'locked-speech',
            expense: 'locked-context',
            jsonSchemaModels: ['locked-context'],
          );
          var calls = 0;
          const source = 'मैंने दूध के लिए सौ रुपये दिए।';
          final transcript = language == 'en'
              ? 'I paid 100 rupees for milk.'
              : source;
          final client = OnlineAiClient(
            provider,
            'fake',
            client: MockClient((request) async {
              calls++;
              expect(request.method, 'POST');
              final body = jsonDecode(request.body) as Map;
              expect(
                provider == OnlineAiProvider.gemini
                    ? request.url.path
                    : body['model'],
                contains('locked-context'),
              );
              final instructions = switch (provider) {
                OnlineAiProvider.gemini =>
                  body['systemInstruction']['parts'][0]['text'],
                OnlineAiProvider.openai => body['instructions'],
                OnlineAiProvider.claude => body['system'],
                _ => body['messages'][0]['content'],
              } as String;
              if (language != 'en') {
                expect(
                  instructions,
                  contains('original spoken language and script'),
                );
                expect(instructions, contains('Keep English in English'));
                expect(
                  instructions,
                  isNot(contains('Write titles and descriptions in English')),
                );
              } else {
                expect(instructions, contains('English'));
              }
              final result = jsonEncode({
                if (language == 'en') 'transcript': transcript,
                'transactions': [
                  {
                    'title': language != 'en' ? 'दूध' : 'Milk',
                    'description': language != 'en'
                        ? 'Sharma Dairy से लिया।'
                        : 'Bought from Sharma Dairy.',
                    'amount': 100,
                    'category': 'Groceries',
                    'type': 'expense',
                  },
                ],
              });
              final response = switch (provider) {
                OnlineAiProvider.gemini => {
                  'candidates': [
                    {
                      'finishReason': 'STOP',
                      'content': {
                        'parts': [
                          {'text': result},
                        ],
                      },
                    },
                  ],
                },
                OnlineAiProvider.openai => {
                  'status': 'completed',
                  'output': [
                    {
                      'content': [
                        {'type': 'output_text', 'text': result},
                      ],
                    },
                  ],
                },
                OnlineAiProvider.claude => {
                  'stop_reason': 'end_turn',
                  'content': [
                    {'type': 'text', 'text': result},
                  ],
                },
                _ => {
                  'choices': [
                    {
                      'finish_reason': 'stop',
                      'message': {'content': result},
                    },
                  ],
                },
              };
              return http.Response(
                jsonEncode(response),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }),
          );
          final result = await client.extractRecording(
            text: source,
            categories: ['Groceries'],
            currency: 'INR',
            models: models,
            language: language,
            translateTranscript: true,
          );
          expect(result.transcript, transcript);
          expect(
            result.expenses.single.title,
            language != 'en' ? 'दूध' : 'Milk',
          );
          expect(result.expenses.single.amount, 100);
          expect(calls, 1);
          client.close();
        },
      );
    }
  }

  test('English formatting rejects untranslated Hindi instead of silently displaying the wrong script', () async {
    final client = OnlineAiClient(
      OnlineAiProvider.openrouter,
      'fake',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'choices': [
              {
                'finish_reason': 'stop',
                'message': {
                  'content': jsonEncode({
                    'transcript': 'मैंने दूध खरीदा।',
                    'transactions': [],
                  }),
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    await expectLater(
      client.extractRecording(
        text: 'Milk 100',
        language: 'en',
        translateTranscript: true,
        categories: ['Groceries'],
        currency: 'INR',
        models: const OnlineAiModels(speech: 'speech', expense: 'context'),
      ),
      throwsA(isA<OnlineAiConnectionException>()),
    );
    client.close();
  });
}
