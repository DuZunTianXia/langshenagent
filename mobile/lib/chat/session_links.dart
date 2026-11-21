// The `session_*` steps' conversations, by their ids, as the desktop's
// chat codec names them (see lib/link/chat_codec.dart there). On the
// phone there is no workspace host: the ids are only carried through,
// and the widgets asking [SessionLinks.of] for one get null.

import 'package:flutter/widgets.dart';

import 'chat_models.dart';

/// How a conversation another handed work to stands.
enum HandedStatus { running, waiting, done, failed }

/// A conversation another handed work to, as it stands.
@immutable
class HandedConversation {
  const HandedConversation({
    required this.id,
    required this.title,
    required this.status,
    this.model,
  });

  final String id;
  final String title;
  final HandedStatus status;

  /// The model it is on, by its name; null where not known.
  final String? model;

  @override
  bool operator ==(Object other) =>
      other is HandedConversation &&
      other.id == id &&
      other.title == title &&
      other.status == status &&
      other.model == model;

  @override
  int get hashCode => Object.hash(id, title, status, model);
}

/// The user's conversations, by their ids as the `session_*` tools give
/// them. The phone has no workspace to answer; a [SessionLinks] would
/// have to come from above.
abstract interface class SessionLinkHost {
  /// Its title; null for none there is.
  String? titleOf(String id);

  /// How it stands; null for none there is.
  HandedStatus? statusOf(String id);

  /// The model it is on, by its name as the user sees it; null where not
  /// known.
  String? modelOf(String id);

  /// Told as how they stand changes.
  Listenable get statuses;

  /// Shows it.
  void open(String id);
}

/// The [SessionLinkHost] for what is under it.
class SessionLinks extends InheritedWidget {
  const SessionLinks({super.key, required this.host, required super.child});

  final SessionLinkHost host;

  static SessionLinkHost? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SessionLinks>()?.host;

  @override
  bool updateShouldNotify(SessionLinks oldWidget) =>
      !identical(oldWidget.host, host);
}

/// Whether [tool] (a step's) is one of the `session_*` tools.
bool isSessionTool(String? tool) => tool != null && tool.startsWith('session_');

/// The conversations a `session_*` step is about, by their ids: the one it
/// started, else those it names.
List<String> sessionIdsOf(ToolCallItem item) => [
  if (item.tool == 'session_new') ?_started.firstMatch(item.output ?? '')?[1],
  if (item.input['session'] case final String id when id.isNotEmpty) id,
  if (item.input['sessions'] case final List<Object?> ids)
    ...ids.whereType<String>(),
];

final _started = RegExp(r'^Started: (\S+)');
