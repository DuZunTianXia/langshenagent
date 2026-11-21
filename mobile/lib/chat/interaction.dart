// What the agent waits on the user for, as the phone's interaction
// models: the desktop's kernel types' shape, as interaction_codec.dart
// encodes and decodes them (its copy of the desktop's file).

import '../chat/chat_models.dart';

/// Something the agent waits on the user for.
sealed class InteractionRequest {
  const InteractionRequest({required this.id, required this.title});

  final String id;
  final String title;
}

class QuestionOption {
  const QuestionOption(this.label, {this.description = ''});

  final String label;
  final String description;
}

class Question {
  const Question({
    required this.prompt,
    required this.options,
    this.header = '',
    this.allowMultiple = false,
    this.allowOther = true,
    this.otherLabel,
  });

  final String prompt;

  /// A short tag for the question, e.g. "Library".
  final String header;
  final List<QuestionOption> options;
  final bool allowMultiple;

  /// Whether the user may answer in their own words.
  final bool allowOther;

  /// The option to answer in their own words, as it shows ("Other" when
  /// null); left empty, the answer is this label.
  final String? otherLabel;
}

/// The agent asks the user to choose.
class QuestionRequest extends InteractionRequest {
  const QuestionRequest({
    required super.id,
    required super.title,
    required this.questions,
  });

  final List<Question> questions;
}

/// A line of a diff an approval shows.
class DiffLine {
  const DiffLine(this.type, this.lineNumber, this.text);

  final DiffLineType type;
  final int lineNumber;
  final String text;
}

/// What an approval is for, as the user should see it.
sealed class ApprovalPreview {
  const ApprovalPreview();
}

class CommandPreview extends ApprovalPreview {
  const CommandPreview(this.command, {this.description});

  final String command;
  final String? description;
}

class DiffPreview extends ApprovalPreview {
  const DiffPreview(this.path, this.lines);

  final String path;
  final List<DiffLine> lines;
}

class TextPreview extends ApprovalPreview {
  const TextPreview(this.text);

  final String text;
}

/// The agent asks leave to use a tool.
class ApprovalRequest extends InteractionRequest {
  const ApprovalRequest({
    required super.id,
    required super.title,
    required this.toolName,
    this.reason,
    this.preview,
    this.alwaysAllowLabel,
  });

  final String toolName;

  /// Why it asks, when the kernel says.
  final String? reason;
  final ApprovalPreview? preview;

  /// What "always allow" would allow, when the kernel offers it; null for
  /// no such option.
  final String? alwaysAllowLabel;
}

sealed class InteractionAnswer {
  const InteractionAnswer();
}

/// For each question, the labels picked (an answer of their own included).
class QuestionAnswer extends InteractionAnswer {
  const QuestionAnswer(this.picks, {this.skipped = false});

  final List<List<String>> picks;

  /// Dismissed without answering.
  final bool skipped;
}

enum ApprovalDecision { allowOnce, allowAlways, deny }

class ApprovalAnswer extends InteractionAnswer {
  const ApprovalAnswer(this.decision, {this.message});

  final ApprovalDecision decision;

  /// With a denial: what to do instead.
  final String? message;
}
