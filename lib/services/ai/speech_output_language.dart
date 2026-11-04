String speechOutputInstruction(String language) => switch (language) {
  'en' =>
    'Write in English. Translate Hindi or Hinglish speech into natural English. '
        'Preserve all names, amounts, refunds and factual details.',
  'hinglish' =>
    'Preserve the original spoken language and script. Keep English in English. '
        'Keep Hindi and Hindi-English speech as spoken, including Devanagari. '
        'Do not translate English into Hindi or Hindi into English. Preserve all names and amounts.',
  _ =>
    'Preserve the spoken language and all names, amounts and factual details.',
};
