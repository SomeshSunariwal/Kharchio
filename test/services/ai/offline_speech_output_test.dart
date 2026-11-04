import 'package:flutter_test/flutter_test.dart';
import 'package:kharchio/services/ai/expense_extractor.dart';
import 'package:kharchio/services/ai/model_validator.dart';

void main() {
  test('offline card output retains the original English policy', () {
    final offlinePrompt = ExpenseExtractor().buildPrompt(
      text: 'दूध 100',
      categories: ['Groceries'],
      currency: 'INR',
    );
    expect(offlinePrompt, contains('Write titles and descriptions in English'));
  });
  test('local Whisper checks require the original English sample output', () {
    expect(
      ModelValidator.matchesSpeechSample(
        'I bought milk for 100 rupees and watched a movie for 150 rupees.',
      ),
      isTrue,
    );
    for (final transcript in [
      'मैंने दूध 100 रुपये का लिया और movie के लिए 150 रुपये दिए।',
      'मैंने दूध सौ रुपये का लिया और मूवी के लिए डेढ़ सौ रुपये दिए।',
      'दूध १०० रुपये और फिल्म १५० रुपये।',
    ]) {
      expect(
        ModelValidator.matchesSpeechSample(transcript),
        isFalse,
        reason: transcript,
      );
    }
    expect(ModelValidator.matchesSpeechSample('दूध १०० रुपये।'), isFalse);
    expect(
      ModelValidator.matchesSpeechSample('Milk and movie, no amounts.'),
      isFalse,
    );
  });

  test('online source-preserving card output keeps English and Hindi instead of forcing translation', () {
    final sourcePrompt = ExpenseExtractor().buildPrompt(
      text: 'दूध 100 और movie 150',
      categories: ['Groceries', 'Entertainment'],
      currency: 'INR',
      outputLanguage: 'source',
    );
    expect(sourcePrompt, contains('Keep English in English'));
    expect(sourcePrompt, contains('original spoken language and script'));
    expect(
      sourcePrompt,
      isNot(contains('Write titles and descriptions in English')),
    );
    expect(sourcePrompt, contains('Movie ticket का refund'));
    final englishPrompt = ExpenseExtractor().buildPrompt(
      text: 'दूध 100',
      categories: ['Groceries'],
      currency: 'INR',
      outputLanguage: 'en',
    );
    expect(englishPrompt, contains('Write titles and descriptions in English'));
  });
}
