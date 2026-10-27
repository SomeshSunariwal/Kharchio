import 'package:flutter/material.dart';

import '../../../core/theme.dart';

class RecordingTranscript extends StatelessWidget {
  const RecordingTranscript({
    super.key,
    required this.text,
    required this.scroll,
    required this.preparing,
  });
  final TextEditingController text;
  final ScrollController scroll;
  final bool preparing;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SizedBox(
      height: 150,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.field,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.line),
        ),
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: text,
          builder: (context, value, _) => Semantics(
            label: 'Read-only live transcript',
            readOnly: true,
            child: Scrollbar(
              controller: scroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: scroll,
                padding: const EdgeInsets.all(12),
                child: Text(
                  value.text.isEmpty
                      ? preparing
                            ? 'Preparing the speech model… Audio is being captured.'
                            : 'Your live transcript will appear here…'
                      : value.text,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: colors.muted,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
