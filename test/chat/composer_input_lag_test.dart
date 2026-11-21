import 'dart:io';

import 'package:bao_markdown/bao_markdown.dart';
import 'package:langshenagent/chat/chat_session.dart';
import 'package:langshenagent/chat/composer/composer.dart';
import 'package:langshenagent/chat/composer/composer_controller.dart';
import 'package:langshenagent/diagnostics/input_lag.dart';
import 'package:langshenagent/platform/event_log.dart';
import 'package:langshenagent/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory folder;
  setUp(() {
    folder = Directory.systemTemp.createTempSync('composer_input_lag');
    EventLog.current = EventLog(folder.path);
    InputLag.debugReset();
  });
  tearDown(() {
    EventLog.current = null;
    folder.deleteSync(recursive: true);
  });

  List<String> lines() {
    final file = File(EventLog.current!.path);
    if (!file.existsSync()) return const [];
    return [
      for (final line in file.readAsLinesSync())
        if (line.contains(' [input] ')) line,
    ];
  }

  testWidgets('an edit slow to show is written, the draft kept its part; '
      'a quick one is not', (tester) async {
    final session = ChatSession(historyCount: 0);
    addTearDown(session.dispose);
    var slow = false;
    session.draft.onSaved = () {
      if (slow) sleep(const Duration(milliseconds: 120));
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ChatComposer(session: session, draft: session.draft),
        ),
      ),
    );
    await tester.pump();
    final controller =
        tester.widget<MarkdownEditor>(find.byType(MarkdownEditor)).controller
            as ComposerController;

    controller.replace(0, 0, 'a');
    await tester.pump();
    expect(lines(), isEmpty);

    slow = true;
    controller.replace(1, 1, 'b');
    await tester.pump();
    expect(
      lines().single,
      matches(
        RegExp(
          r'\[input\] chat input: a change shown after \d+ ms; '
          r'before the frame \d+ ms \(draft 1\d\d, edit 1\d\d\), '
          r'the frame \d+ ms; text 2 chars, 1 lines; ',
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  });
}
