import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/chat/reply_suggestions.dart';

void main() {
  test('reply suggestions come off the end of a reply', () {
    final text = ReplySuggestions.write('Done.', ['Go ahead', 'Try again']);
    expect(ReplySuggestions.strip(text), 'Done.');
    expect(ReplySuggestions.of(text), ['Go ahead', 'Try again']);
  });

  test('suggestions spoken of mid-text stay', () {
    const text =
        'I will use <reply_suggestion>hi</reply_suggestion> tags later.\nDone.';
    expect(ReplySuggestions.strip(text), text);
    expect(ReplySuggestions.of(text), isEmpty);
  });
}
