import 'dart:convert';

import 'package:flutter/widgets.dart';

/// What a command printed, as the phone shows it: the desktop runs it
/// through a headless terminal for its colors and rewrites (see
/// `lib/chat/widgets/terminal_output.dart`); the phone keeps the text
/// only, the escape sequences out and `\r`/`\b` resolved by hand, one
/// style throughout.
///
/// Results are cached by output, which never changes for an item: a new
/// output comes as a new string.
TerminalOutput terminalOutput(String output) {
  if (!output.contains('\x1b') &&
      !output.contains('\r') &&
      !output.contains('\b')) {
    return TerminalOutput._plain(output.trimRight());
  }
  final result = _cache.remove(output) ?? _clean(output);
  _cache[output] = result;
  if (_cache.length > _cacheSize) _cache.remove(_cache.keys.first);
  return result;
}

/// The last outputs cleaned, least recently used first.
final _cache = <String, TerminalOutput>{};
const _cacheSize = 64;

/// A CSI/OSC escape sequence, or a lone escape's letter command.
final _escape = RegExp(
  // CSI: ESC [ params intermediates final. OSC: ESC ] up to BEL or ST.
  '\x1b\\[[0-?]*[ -/]*[@-~]'
  '|\x1b\\][^\x07\x1b]*(?:\x07|\x1b\\\\)?'
  '|\x1b[()#][0-9A-Za-z]?'
  '|\x1b[@-Z\\\\-_]',
);

/// [output] as plain text: escapes out, each line what its last `\r` left,
/// backspaces applied.
TerminalOutput _clean(String output) {
  var text = output.replaceAll(_escape, '');
  if (text.contains('\r')) {
    text = [
      for (final line in text.split('\n')) line.split('\r').last,
    ].join('\n');
  }
  if (text.contains('\b')) {
    final chars = text.characters.toList();
    final kept = <String>[];
    for (final char in chars) {
      if (char == '\b') {
        if (kept.isNotEmpty) kept.removeLast();
      } else {
        kept.add(char);
      }
    }
    text = kept.join();
  }
  return TerminalOutput._plain(text.trimRight());
}

/// What a command printed, as shown: [terminalOutput].
class TerminalOutput {
  TerminalOutput._plain(this.text)
    : runs = [if (text.isNotEmpty) TerminalRun(text)],
      styled = false;

  /// The text shown, its lines joined with `\n`: what copying it gives.
  final String text;

  /// [text] in runs of one style each (the phone has one: [runs] is
  /// [text] alone).
  final List<TerminalRun> runs;

  /// Whether any run has a style of its own; else [text] shows plain.
  final bool styled;

  /// [runs] as spans, over the step's style.
  late final TextSpan span = TextSpan(
    children: [
      for (final run in runs) TextSpan(text: run.text, style: run.style),
    ],
  );
}

/// A run of output in one style. A null color is the step's own: its text's,
/// or no background.
class TerminalRun {
  const TerminalRun(
    this.text, {
    this.foreground,
    this.background,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
  });

  final String text;
  final Color? foreground;
  final Color? background;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;

  /// Its style over the step's, null when it has none.
  TextStyle? get style {
    if (foreground == null &&
        background == null &&
        !bold &&
        !italic &&
        !underline &&
        !strikethrough) {
      return null;
    }
    return TextStyle(
      color: foreground,
      backgroundColor: background,
      fontWeight: bold ? FontWeight.bold : null,
      fontStyle: italic ? FontStyle.italic : null,
      decoration: underline || strikethrough
          ? TextDecoration.combine([
              if (underline) TextDecoration.underline,
              if (strikethrough) TextDecoration.lineThrough,
            ])
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TerminalRun &&
      other.text == text &&
      other.foreground == foreground &&
      other.background == background &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.strikethrough == strikethrough;

  @override
  int get hashCode => Object.hash(
    text,
    foreground,
    background,
    bold,
    italic,
    underline,
    strikethrough,
  );

  @override
  String toString() {
    final attributes = [
      if (foreground case final color?) 'foreground: $color',
      if (background case final color?) 'background: $color',
      if (bold) 'bold',
      if (italic) 'italic',
      if (underline) 'underline',
      if (strikethrough) 'strikethrough',
    ];
    return 'TerminalRun(${[jsonEncode(text), ...attributes].join(', ')})';
  }
}
