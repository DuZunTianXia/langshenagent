import '../chat/chat_models.dart' show DiffLineType;
import '../chat/interaction.dart';

/// What the agent waits on the user for, as JSON for a paired phone, and
/// the phone's answer back.
abstract final class InteractionCodec {
  /// The request [encode] wrote, back; null for JSON that is not one.
  static InteractionRequest? decode(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final id = json['id'] as String? ?? '';
    final title = json['title'] as String? ?? '';
    return switch (json['t']) {
      'question' => QuestionRequest(
        id: id,
        title: title,
        questions: [
          for (final question in (json['questions'] as List?) ?? const [])
            if (question is Map<String, Object?>)
              Question(
                prompt: question['prompt'] as String? ?? '',
                header: question['header'] as String? ?? '',
                allowMultiple: question['multiple'] == true,
                allowOther: question.containsKey('other'),
                otherLabel: question['other'] as String?,
                options: [
                  for (final option in (question['options'] as List?) ?? const [])
                    if (option is Map<String, Object?>)
                      QuestionOption(
                        option['label'] as String? ?? '',
                        description: option['description'] as String? ?? '',
                      ),
                ],
              ),
        ],
      ),
      'approval' => ApprovalRequest(
        id: id,
        title: title,
        toolName: json['tool'] as String? ?? '',
        reason: json['reason'] as String?,
        alwaysAllowLabel: json['always'] as String?,
        preview: switch (json['preview']) {
          final Map<String, Object?> preview => _decodePreview(preview),
          _ => null,
        },
      ),
      _ => null,
    };
  }

  static ApprovalPreview _decodePreview(Map<String, Object?> json) =>
      switch (json['t']) {
        'command' => CommandPreview(
          json['command'] as String? ?? '',
          description: json['description'] as String?,
        ),
        'diff' => DiffPreview(
          json['path'] as String? ?? '',
          [
            for (final line in (json['lines'] as List?) ?? const [])
              if (line is List && line.length >= 3)
                DiffLine(
                  DiffLineType.values[(line[0] as num?)?.toInt() ?? 0],
                  (line[1] as num?)?.toInt() ?? 0,
                  line[2] as String? ?? '',
                ),
          ],
        ),
        'text' => TextPreview(json['text'] as String? ?? ''),
        _ => const TextPreview(''),
      };

  /// The phone's answer, as [encodeAnswer] would have it; null when it
  /// does not say one.
  static Map<String, Object?>? encodeAnswer(InteractionAnswer answer) =>
      switch (answer) {
        QuestionAnswer(:final picks, :final skipped) => skipped
            ? {'t': 'question', 'skipped': true}
            : {
                't': 'question',
                'picks': [
                  for (final pick in picks) pick,
                ],
              },
        ApprovalAnswer(:final decision, :final message) => {
          't': 'approval',
          'decision': decision.name,
          if (message != null) 'message': message,
        },
      };

  static Map<String, Object?> encode(InteractionRequest request) =>
      switch (request) {
        QuestionRequest(:final questions) => {
          't': 'question',
          'id': request.id,
          'title': request.title,
          'questions': [
            for (final question in questions)
              {
                'prompt': question.prompt,
                if (question.header.isNotEmpty) 'header': question.header,
                'options': [
                  for (final option in question.options)
                    {
                      'label': option.label,
                      if (option.description.isNotEmpty)
                        'description': option.description,
                    },
                ],
                if (question.allowMultiple) 'multiple': true,
                if (question.allowOther) 'other': question.otherLabel ?? '',
              },
          ],
        },
        ApprovalRequest() => {
          't': 'approval',
          'id': request.id,
          'title': request.title,
          'tool': request.toolName,
          'reason': ?request.reason,
          'always': ?request.alwaysAllowLabel,
          if (request.preview case final preview?)
            'preview': switch (preview) {
              CommandPreview(:final command, :final description) => {
                't': 'command',
                'command': command,
                'description': ?description,
              },
              DiffPreview(:final path, :final lines) => {
                't': 'diff',
                'path': path,
                'lines': [
                  for (final line in lines)
                    [line.type.index, line.lineNumber, line.text],
                ],
              },
              TextPreview(:final text) => {'t': 'text', 'text': text},
            },
        },
      };

  /// The phone's answer; null when it does not say one.
  static InteractionAnswer? decodeAnswer(Object? json) => switch (json) {
    {'t': 'question', 'skipped': true} => const QuestionAnswer(
      [],
      skipped: true,
    ),
    {'t': 'question', 'picks': final List picks} => QuestionAnswer([
      for (final pick in picks) [if (pick is List) ...pick.whereType<String>()],
    ]),
    {'t': 'approval', 'decision': final String decision} =>
      switch (ApprovalDecision.values.asNameMap()[decision]) {
        final decision? => ApprovalAnswer(
          decision,
          message: json['message'] as String?,
        ),
        null => null,
      },
    _ => null,
  };
}
