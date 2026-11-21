import 'dart:async';
import 'dart:convert';

import 'package:bao_link/bao_link_io.dart';
import 'package:flutter/foundation.dart';

import 'link_providers.dart';
import 'link_store.dart';

/// Where a paired computer's link stands.
enum PhonePhase {
  /// No connection: never dialled, or it ended and the next try waits.
  offline,

  /// Dialling, or pairing.
  connecting,

  /// Pairing: the safety codes are up, waiting for the user to compare
  /// them (and, for a computer found nearby, for its user to allow it).
  pairing,

  /// Connected and answered `hello`.
  online,
}

/// A pairing under way, as the phone shows it.
class PhonePairing {
  const PhonePairing({required this.name, required this.codes, this.approval = false});

  /// The computer's name, from its offer or advert.
  final String name;

  /// What both screens show, to be compared.
  final List<String> codes;

  /// Its user has to allow it on the desktop too (found nearby: no
  /// secret proved who asked).
  final bool approval;
}

/// What a followed session holds, as the desktop last told it: its items
/// (as JSON, the chat codec's to read), and where it stands. Made whole
/// by the [LinkSessionMirror] of the [LinkPeer] before it gets here, so
/// [items] is always the phone's whole list, [start] counting into it.
class SessionFeed extends ChangeNotifier {
  SessionFeed(this.session);

  final String session;

  /// The items from the first the phone has, as JSON. An item the codec
  /// does not know stays as its JSON: [count] counts it, and the `edit`
  /// index is its place here.
  List<Object?> items = const [];
  int count = 0;
  bool earlier = false;
  bool live = false;
  Map<String, Object?>? interaction;
  List<LinkChoice> choices = const [];
  List<Map<String, Object?>> changes = const [];
  List<LinkTask> tasks = const [];
  Map<String, Object?>? goal;
  Map<String, Object?>? context;
  Map<String, Object?>? quota;

  /// Whether there are items before the first.
  bool get hasMore => earlier;

  /// A whole update ([LinkSessionUpdate]'s JSON, made whole).
  void apply(Map<String, Object?> update) {
    final start = update['start'];
    final incoming = update['items'];
    if (start is! int || incoming is! List) return;
    final next = [...items.take(start.clamp(0, items.length)), ...incoming];
    items = next;
    final total = update['count'];
    count = total is int ? total : next.length;
    live = update['live'] == true;
    interaction = switch (update['interaction']) {
      final Map<String, Object?> map => map,
      _ => null,
    };
    choices = [
      for (final choice in (update['choices'] as List?) ?? const [])
        if (choice is Map<String, Object?>) LinkChoice.fromJson(choice),
    ];
    changes = [
      for (final change in (update['changes'] as List?) ?? const [])
        if (change is Map<String, Object?>) change,
    ];
    tasks = [
      for (final task in (update['tasks'] as List?) ?? const [])
        if (task is Map<String, Object?>) LinkTask.fromJson(task),
    ];
    earlier = update['earlier'] == true;
    goal = switch (update['goal']) {
      final Map<String, Object?> map => map,
      _ => null,
    };
    context = switch (update['context']) {
      final Map<String, Object?> map => map,
      _ => null,
    };
    quota = switch (update['quota']) {
      final Map<String, Object?> map => map,
      _ => null,
    };
    notifyListeners();
  }

  /// The `earlier` answer's items, put before the first.
  void prepend(List<Object?> items) {
    this.items = [...items, ...this.items];
    notifyListeners();
  }
}

/// A group chat followed, its messages as they came.
class GroupFeed extends ChangeNotifier {
  GroupFeed(this.group);

  final String group;
  final List<LinkGroupMessage> messages = [];
  bool more = false;

  void add(List<LinkGroupMessage> incoming) {
    messages.addAll(incoming);
    notifyListeners();
  }

  void prepend(List<LinkGroupMessage> incoming) {
    messages.insertAll(0, incoming);
    notifyListeners();
  }
}

/// One paired computer's link: dials it by its key, pairs when asked,
/// keeps the connection (trying again with a growing wait when it drops),
/// and follows its sessions.
///
/// The phone's one [LinkNode] is the app's; this asks for it each time it
/// dials, so a node rebound for new relays is the one used.
class PhoneLink extends ChangeNotifier {
  PhoneLink({
    required this.store,
    required this.computer,
    required Future<LinkNode> Function() node,
    required this.phoneName,
    required this.phoneSystem,
    LinkSessionMirror? mirror,
  }) : _node = node,
       mirror = mirror ?? LinkSessionMirror();

  /// The computers paired, kept by the app.
  final LinkStore store;

  /// Which computer this link is to.
  PairedComputer computer;

  /// This phone's name and OS, as `hello` tells the computer.
  final String phoneName;
  final String phoneSystem;

  /// The sessions' whole updates are made of the slim ones by this.
  final LinkSessionMirror mirror;

  final Future<LinkNode> Function() _node;

  PhonePhase phase = PhonePhase.offline;

  /// Why the last try failed, in a word the screens show; null while
  /// nothing failed.
  String? error;

  /// The computer unpaired the phone: pair again.
  bool get needsRePair => error == 'unpaired';

  /// The pairing under way, while [phase] is [PhonePhase.pairing].
  PhonePairing? pairing;

  /// The computer as it last said it is.
  DeviceInfo? device;

  /// Its projects and agents, as its last `state` said.
  LinkState? state;

  /// The path the connection takes now.
  LinkPath path = LinkPath.none;

  /// The sessions followed, by id.
  final Map<String, SessionFeed> feeds = {};

  /// The sessions the app wants followed, by id: reopened when the
  /// connection comes back (a feed's items the mirror still has come
  /// with only what changed).
  final Set<String> wanted = {};

  /// The group chats wanted followed, by id.
  final Set<String> wantedGroups = {};

  /// The group chats followed, by id.
  final Map<String, GroupFeed> groups = {};

  /// What watched tasks wrote, by `session/task`: its text so far, and
  /// the offset it ends at.
  final Map<String, ({String text, int offset})> outputs = {};

  /// Told when a followed session comes to need the user: an interaction
  /// appears, or a turn ends. For a notification while the app is away.
  void Function(String session, SessionFeed feed)? onAttention;

  /// When each session was last opened here (ms): a state update saying
  /// it is unread again counts only when it is newer than this. Kept by
  /// the owner through [onReadMarks].
  final Map<String, int> readMarks = {};

  /// [readMarks] changed: persist it.
  void Function()? onReadMarks;

  /// Who the phone's user is, told to the computer's bots with `setMe`
  /// once online and when it changes ([updateMe]).
  String? meName;
  String? meGender;
  String? meSignature;

  LinkPeer? _peer;
  StreamSubscription<LinkEvent>? _events;
  StreamSubscription<LinkPath>? _paths;
  Timer? _retry;
  int _attempts = 0;
  bool _closed = false;
  bool _wantOnline = false;

  /// Asks the computer for its state again when it is connected.
  Future<void> refresh() async {
    final peer = _peer;
    if (peer == null || peer.isClosed) return;
    state = LinkState.fromJson(_map(await peer.call(LinkMethods.state)));
    _applyReadMarks();
    notifyListeners();
  }

  // --- Connecting -----------------------------------------------------------

  /// Dials the computer, or pairs with it when [offer] (a QR code's or a
  /// pasted link's) or [advert] (one found nearby) is given.
  Future<void> connect({
    PairingOffer? offer,
    LinkAdvert? advert,
  }) async {
    if (_closed ||
        phase == PhonePhase.connecting ||
        phase == PhonePhase.online ||
        phase == PhonePhase.pairing) {
      return;
    }
    _wantOnline = true;
    _retry?.cancel();
    phase = PhonePhase.connecting;
    error = null;
    notifyListeners();
    try {
      final address = switch ((offer, advert)) {
        (final PairingOffer offer, _) => offer.address,
        (_, final LinkAdvert advert) => LinkAddress(
          advert.id,
          addrs: advert.addrs,
          relays: store.nodeRelays,
        ),
        _ => LinkAddress(
          computer.id,
          relays: computer.relays,
          addrs: computer.addrs,
        ),
      };
      final node = await _node();
      final connection = await node.connect(address);
      _watchPath(connection);
      final peer = await LinkPeer.connect(connection, mirror: mirror);
      _peer = peer;
      _listen(peer);
      final hello = _map(
        await peer.call(
          LinkMethods.hello,
          _helloParams(offer: offer, advert: advert),
          const Duration(seconds: 30),
        ),
      );
      if (hello['pairing'] == true) {
        _beginPairing(offer ?? _offerOf(advert), hello);
        return;
      }
      _online(hello);
    } on Object catch (failure) {
      _failed(failure);
    }
  }

  Map<String, Object?> _helloParams({
    PairingOffer? offer,
    LinkAdvert? advert,
  }) => {
    'name': phoneName,
    'system': phoneSystem,
    if (offer != null) 'token': encodeKey(offer.token),
    if (offer == null && advert != null) 'request': true,
  };

  /// The offer a nearby advert stands for: its name and key, no token
  /// (the computer's user allows it instead).
  PairingOffer? _offerOf(LinkAdvert? advert) => advert == null
      ? null
      : PairingOffer(
          name: advert.name,
          key: advert.key,
          token: Uint8List(0),
          expires: DateTime.now().add(const Duration(minutes: 5)),
        );

  void _beginPairing(PairingOffer? offer, Map<String, Object?> hello) {
    final key = _peer?.remote ?? '';
    pairing = PhonePairing(
      name: offer?.name ?? device?.name ?? computer.name,
      codes: safetyCode(keyOfDeviceId(key) ?? Uint8List(0), store.identity.publicKey),
      approval: hello['approval'] == true,
    );
    phase = PhonePhase.pairing;
    notifyListeners();
  }

  /// The safety codes matched on both screens: the computer keeps the
  /// phone from then on. Answered once its user allowed it, for one found
  /// nearby.
  Future<void> confirm() async {
    final peer = _peer;
    final pending = pairing;
    if (peer == null || peer.isClosed || pending == null) return;
    try {
      final hello = _map(
        await peer.call(
          LinkMethods.confirm,
          const {},
          const Duration(minutes: 10),
        ),
      );
      pairing = null;
      _online(hello);
    } on LinkRemoteException catch (failure) {
      pairing = null;
      phase = PhonePhase.offline;
      error = failure.code == LinkErrors.rejected
          ? 'rejected'
          : failure.message;
      notifyListeners();
      await _teardown();
      _scheduleRetry();
    } on Object {
      // Still waiting on its user (a nearby pairing's approval), or the
      // call timed out: the pairing stays up for another try. A closed
      // peer ends it through `done`.
      if (peer.isClosed) {
        pairing = null;
        phase = PhonePhase.offline;
        notifyListeners();
      }
    }
  }

  /// Leaves the pairing without confirming.
  Future<void> cancelPairing() async {
    pairing = null;
    await _teardown();
    phase = PhonePhase.offline;
    _wantOnline = false;
    notifyListeners();
  }

  void _online(Map<String, Object?> hello) {
    _attempts = 0;
    _retry?.cancel();
    final info = DeviceInfo.fromJson(_map(hello['device']));
    device = info;
    final paired = PairedComputer(
      id: computer.id,
      name: info.name.isEmpty ? computer.name : info.name,
      kind: info.kind.isEmpty ? computer.kind : info.kind,
      system: info.system.isEmpty ? computer.system : info.system,
      laptop: info.laptop,
      relays: info.relays,
      addrs: info.addrs,
      direct: info.direct,
      pairedAt: computer.pairedAt,
      lastSeen: DateTime.now(),
    );
    computer = paired;
    unawaited(store.pair(paired));
    phase = PhonePhase.online;
    error = null;
    notifyListeners();
    _sendMe();
    // What was followed before the drop is followed again.
    for (final id in wanted) {
      unawaited(open(id));
    }
    for (final id in wantedGroups) {
      unawaited(openGroup(id));
    }
    unawaited(refresh());
  }

  /// Remembers the profile and tells it to the computer when online
  /// ([LinkMethods.setMe]).
  void updateMe({String? name, String? gender, String? signature}) {
    meName = name;
    meGender = gender;
    meSignature = signature;
    _sendMe();
  }

  void _sendMe() {
    if (phase != PhonePhase.online) return;
    final name = meName;
    if (name == null || name.isEmpty) return;
    unawaited(
      setMe(name: name, gender: meGender, signature: meSignature)
          .catchError((_) {}),
    );
  }

  void _failed(Object failure) {
    _teardown();
    phase = PhonePhase.offline;
    error = switch (failure) {
      LinkRemoteException(:final code) => code,
      LinkClosedException() => 'unreachable',
      TimeoutException() => 'timeout',
      _ => 'failed',
    };
    if (error == LinkErrors.unpaired) {
      // The computer forgot the phone: pair again, not retry.
      _wantOnline = false;
    }
    notifyListeners();
    if (_wantOnline) _scheduleRetry();
  }

  void _scheduleRetry() {
    _retry?.cancel();
    if (!_wantOnline || _closed) return;
    final seconds = _attempts < 5 ? 1 << _attempts : 30;
    _attempts++;
    _retry = Timer(Duration(seconds: seconds.clamp(1, 30)), () {
      // The peer is always closed here (a failure tore it down); the
      // retry is exactly what makes a fresh one.
      if (_wantOnline) unawaited(connect());
    });
  }

  bool get isClosedPeer => _peer?.isClosed ?? true;

  // --- The connection ---------------------------------------------------------

  void _listen(LinkPeer peer) {
    _events = peer.events.listen(_event);
    peer.done.whenComplete(() {
      if (identical(_peer, peer)) {
        _peer = null;
        if (phase == PhonePhase.pairing) {
          // The pairing's connection went: it cannot be confirmed now.
          pairing = null;
          phase = PhonePhase.offline;
          error = 'unreachable';
          notifyListeners();
          if (_wantOnline) _scheduleRetry();
        } else {
          _failed(const LinkClosedException('closed'));
        }
      }
    });
  }

  void _watchPath(LinkConnection connection) {
    _paths = connection.paths.listen((path) {
      this.path = path;
      notifyListeners();
    });
  }

  void _event(LinkEvent event) {
    final data = event.data;
    switch (event.name) {
      case LinkEvents.state:
        state = LinkState.fromJson(_map(data));
        _updateDevice(state?.device);
        _applyReadMarks();
        notifyListeners();
      case LinkEvents.session:
        if (data is Map<String, Object?>) _session(data);
      case LinkEvents.earlier:
        if (data is Map<String, Object?> && data['session'] is String) {
          feeds[data['session']]?.prepend([
            ...(data['items'] as List? ?? const []),
          ]);
        }
      case LinkEvents.resync:
        if (data is Map<String, Object?> && data['session'] is String) {
          final id = data['session']! as String;
          feeds.remove(id)?.dispose();
          unawaited(open(id));
        }
      case LinkEvents.group:
        if (data is Map<String, Object?> && data['group'] is String) {
          _group(data['group']! as String, data['messages']);
        }
      case LinkEvents.output:
        final output = LinkOutput.fromJson(data);
        if (output != null) {
          final key = '${output.session}/${output.task}';
          final kept = outputs[key];
          outputs[key] = (
            offset: output.offset,
            text: output.reset || kept == null
                ? output.text
                : kept.text + output.text,
          );
          notifyListeners();
        }
      case LinkEvents.unpaired:
        error = 'unpaired';
        _wantOnline = false;
        notifyListeners();
        unawaited(_teardown());
      default:
    }
  }

  void _updateDevice(DeviceInfo? info) {
    if (info == null) return;
    device = info;
    final next = computer.withDevice(info, lastSeen: DateTime.now());
    if (next.relays.toString() != computer.relays.toString() ||
        next.addrs.toString() != computer.addrs.toString() ||
        next.direct != computer.direct) {
      computer = next;
      unawaited(store.pair(next));
    }
  }

  void _session(Map<String, Object?> update) {
    final id = update['session'];
    if (id is! String || id.isEmpty) return;
    final feed = feeds.putIfAbsent(id, () => SessionFeed(id));
    final wasLive = feed.live;
    final hadInteraction = feed.interaction != null;
    feed.apply(update);
    // Keep the sidebar's copy of it fresh too.
    _updateSessionSummary(id, feed);
    if ((!hadInteraction && feed.interaction != null) ||
        (wasLive && !feed.live)) {
      onAttention?.call(id, feed);
    }
  }

  void _updateSessionSummary(String id, SessionFeed feed) {
    final sessions = state?.sessions;
    if (sessions == null) return;
    final index = sessions.indexWhere((session) => session.id == id);
    if (index < 0) return;
    final old = sessions[index];
    final status = feed.live
        ? LinkSessionStatus.running
        : feed.interaction != null
        ? LinkSessionStatus.needsInput
        : LinkSessionStatus.idle;
    final list = [...sessions];
    list[index] = SessionSummary(
      id: old.id,
      project: old.project,
      title: old.title,
      updatedAt: DateTime.now(),
      status: status,
      unread: old.unread,
      pinned: old.pinned,
      model: old.model,
      mode: old.mode,
      permission: old.permission,
    );
    state = LinkState(
      device: state!.device,
      projects: state!.projects,
      sessions: list,
      bots: state!.bots,
      groups: state!.groups,
    );
  }

  void _group(String id, Object? messages) {
    final feed = groups.putIfAbsent(id, () => GroupFeed(id));
    if (messages is List) {
      feed.add([
        for (final message in messages)
          if (message is Map<String, Object?>)
            LinkGroupMessage.fromJson(message),
      ]);
    }
  }

  // --- Sessions ---------------------------------------------------------------

  /// Follows [sessionId] (the last [window] items first, more with
  /// [earlier]); the feed fills in by events. Throws when the computer
  /// does not know it.
  Future<SessionFeed> open(String sessionId, {int window = 50}) async {
    final peer = _peer;
    if (peer == null || peer.isClosed) {
      throw const LinkClosedException('offline');
    }
    feeds.remove(sessionId)?.dispose();
    wanted.add(sessionId);
    final feed = feeds[sessionId] = SessionFeed(sessionId);
    try {
      await peer.call(LinkMethods.open, {
        'session': sessionId,
        'window': window,
      });
    } on Object {
      feeds.remove(sessionId)?.dispose();
      rethrow;
    }
    _markRead(sessionId);
    return feed;
  }

  /// Opened, it is read — now and after restarts: [readMarks] remembers
  /// when, and [_applyReadMarks] unmakes "unread" a server state may
  /// still claim for anything older.
  void _markRead(String sessionId) {
    readMarks[sessionId] = DateTime.now().millisecondsSinceEpoch;
    onReadMarks?.call();
    _applyReadMarks();
  }

  /// Clears `unread` on every summary whose last activity predates the
  /// session's read mark; leaves it for anything newer.
  void _applyReadMarks() {
    final current = state;
    if (current == null || readMarks.isEmpty) return;
    var changed = false;
    final sessions = [
      for (final session in current.sessions)
        if (session.unread &&
            session.updatedAt.millisecondsSinceEpoch <=
                (readMarks[session.id] ?? 0))
          () {
            changed = true;
            return SessionSummary(
              id: session.id,
              project: session.project,
              title: session.title,
              updatedAt: session.updatedAt,
              status: session.status,
              unread: false,
              pinned: session.pinned,
              model: session.model,
              mode: session.mode,
              permission: session.permission,
            );
          }()
        else
          session,
    ];
    if (!changed) return;
    state = LinkState(
      device: current.device,
      projects: current.projects,
      sessions: sessions,
      bots: current.bots,
      groups: current.groups,
    );
    notifyListeners();
  }

  /// No longer followed.
  Future<void> close(String sessionId) async {
    wanted.remove(sessionId);
    feeds.remove(sessionId)?.dispose();
    final peer = _peer;
    if (peer != null && !peer.isClosed) {
      await peer.call(LinkMethods.close, {'session': sessionId});
    }
  }

  /// Up to [count] items before the first the phone has.
  Future<bool> earlier(String sessionId, {int count = 50}) async {
    final peer = _peer;
    if (peer == null || peer.isClosed) return false;
    final result = _map(
      await peer.call(LinkMethods.earlier, {
        'session': sessionId,
        'count': count,
      }),
    );
    return result['earlier'] == true;
  }

  /// A message to [sessionId] (or a new one in [projectId], or to the
  /// bot [botId]'s conversation). [images] are `{"data", "type", "name"?}`.
  /// Answered with the session it went to.
  Future<String?> send({
    String? sessionId,
    String? projectId,
    String? botId,
    required String text,
    List<Map<String, Object?>> images = const [],
    List<String> mentions = const [],
    bool now = false,
    String? id,
  }) async {
    final result = _map(await _call(LinkMethods.send, {
      if (sessionId != null) 'session': sessionId,
      if (projectId != null) 'project': projectId,
      if (botId != null) 'bot': botId,
      'text': text,
      if (images.isNotEmpty) 'images': images,
      if (mentions.isNotEmpty) 'mentions': mentions,
      if (now) 'now': true,
      if (id != null) 'id': id,
    }));
    return result['session'] as String?;
  }

  /// The user's message at [index] sent again as [text]: everything
  /// after it is discarded and the turn runs again. [revertFiles] puts
  /// back what the agent did to the files first (see [rewindPlan]).
  Future<void> edit({
    required String sessionId,
    required int index,
    required String text,
    List<Map<String, Object?>> images = const [],
    List<String> mentions = const [],
    bool revertFiles = false,
  }) => _call(LinkMethods.edit, {
    'session': sessionId,
    'index': index,
    'text': text,
    if (images.isNotEmpty) 'images': images,
    if (mentions.isNotEmpty) 'mentions': mentions,
    if (revertFiles) 'revertFiles': true,
  });

  /// What [edit] with `revertFiles` would put back, asked before it.
  /// Null from a desktop before it (nothing is asked, files left).
  Future<Map<String, Object?>?> rewindPlan(String sessionId, int index) async {
    try {
      return _map(await _call(LinkMethods.rewindPlan, {
        'session': sessionId,
        'index': index,
      }));
    } on LinkRemoteException catch (failure) {
      if (failure.code == LinkErrors.unknown) return null;
      rethrow;
    }
  }

  Future<void> stop(String sessionId) =>
      _call(LinkMethods.stop, {'session': sessionId});

  /// Answers what the agent asked: [answer] as the app's interaction
  /// codec wrote it, to the request the feed's `interaction` names.
  Future<void> answer(String sessionId, Object? answer) => _call(
    LinkMethods.answer,
    {
      'session': sessionId,
      'request': feeds[sessionId]?.interaction?['id'],
      'answer': answer,
    },
  );

  Future<void> startPlan(String sessionId) =>
      _call(LinkMethods.startPlan, {'session': sessionId});

  /// Picks a model, a mode, a permission mode, an effort or a context
  /// size ([LinkChoice.kind]).
  Future<void> choose(
    String sessionId,
    String kind,
    String option,
  ) => _call(LinkMethods.choose, {
    'session': sessionId,
    'kind': kind,
    'option': option,
  });

  Future<void> quota(String sessionId) =>
      _call(LinkMethods.quota, {'session': sessionId});

  Future<void> rename(String sessionId, String title) =>
      _call(LinkMethods.rename, {'session': sessionId, 'title': title});

  Future<void> pin(String sessionId, bool pinned) =>
      _call(LinkMethods.pin, {'session': sessionId, 'pinned': pinned});

  Future<void> pinProject(String projectId, bool pinned) => _call(
    LinkMethods.pinProject,
    {'project': projectId, 'pinned': pinned},
  );

  Future<void> archive(String sessionId) =>
      _call(LinkMethods.archive, {'session': sessionId});

  Future<void> delete(String sessionId) =>
      _call(LinkMethods.delete, {'session': sessionId});

  Future<void> hideProject(String projectId) =>
      _call(LinkMethods.hideProject, {'project': projectId});

  /// Keeps the changes to [paths] (all of them, with none), as the
  /// desktop's Keep.
  Future<void> keep(String sessionId, [List<String>? paths]) => _call(
    LinkMethods.keep,
    {'session': sessionId, if (paths != null) 'paths': paths},
  );

  /// Undoes them, as the desktop's Undo.
  Future<void> undo(String sessionId, [List<String>? paths]) => _call(
    LinkMethods.undo,
    {'session': sessionId, if (paths != null) 'paths': paths},
  );

  /// Stops a task left running, or the subagent [agent] started.
  Future<void> stopTask(String sessionId, {String? task, String? agent}) =>
      _call(LinkMethods.stopTask, {
        'session': sessionId,
        if (task != null) 'task': task,
        if (agent != null) 'agent': agent,
      });

  /// A command task's output as it is now, the end of it (up to
  /// [LinkLimits.output] characters); null when there is none.
  Future<String?> output(String sessionId, String task) async {
    final result = _map(
      await _call(LinkMethods.output, {'session': sessionId, 'task': task}),
    );
    return result['text'] as String?;
  }

  /// A watched task's output as it grows; the end of it at once. Events
  /// land in [outputs].
  Future<String> watchOutput(String sessionId, String task) async {
    final result = _map(await _call(LinkMethods.watchOutput, {
      'session': sessionId,
      'task': task,
    }));
    outputs['$sessionId/$task'] = (
      offset: result['offset'] is int ? result['offset']! as int : 0,
      text: result['text'] as String? ?? '',
    );
    notifyListeners();
    return result['text'] as String? ?? '';
  }

  Future<void> unwatchOutput(String sessionId, String task) => _call(
    LinkMethods.unwatchOutput,
    {'session': sessionId, 'task': task},
  );

  /// A new agent the project's next conversation starts, as the
  /// desktop's New Chat has it ready.
  Future<String?> draft(String projectId) async {
    final result = _map(
      await _call(LinkMethods.draft, {'project': projectId}),
    );
    return result['session'] as String?;
  }

  // --- Files -------------------------------------------------------------------

  /// The project's files, `/`-separated from its root.
  Future<Map<String, Object?>> files(String projectId) =>
      _call(LinkMethods.files, {'project': projectId}).then(_map);

  /// What is in a folder of the project (`""` its root).
  Future<Map<String, Object?>> folder(String projectId, String path) =>
      _call(LinkMethods.folder, {'project': projectId, 'path': path})
          .then(_map);

  /// A file of the project: `{"text", "original"?}`, `{"binary": true}`,
  /// or `{"tooLarge": true, "size"}`.
  Future<Map<String, Object?>> read(String projectId, String path) =>
      _call(LinkMethods.read, {'project': projectId, 'path': path}).then(_map);

  /// A picture of the project, as a reply names it.
  Future<Map<String, Object?>> image(String projectId, String path) =>
      _call(LinkMethods.image, {'project': projectId, 'path': path})
          .then(_map);

  /// Any file of the machine, its bytes, for another app to open.
  Future<Map<String, Object?>> download(String projectId, String path) =>
      _call(LinkMethods.download, {'project': projectId, 'path': path})
          .then(_map);

  /// Claude Code's customizations on the desktop.
  Future<List<LinkExtension>> extensions() async {
    final items = _map(await _call(LinkMethods.extensions))['items'];
    return [
      for (final item in items is List ? items : const [])
        if (item is Map<String, Object?>) LinkExtension.fromJson(item),
    ];
  }

  /// A picture a project shows as its icon.
  Future<Map<String, Object?>> icon(String id) async =>
      _map(await _call(LinkMethods.icon, {'id': id}));

  /// A file of the phone's put where the project's agent reads it:
  /// `{"data"}` base64, at most [LinkLimits.upload]. Answered with
  /// `{"path"}` for a message to name.
  Future<Map<String, Object?>> upload({
    String? projectId,
    String? botId,
    required String name,
    required Uint8List data,
  }) => _call(LinkMethods.upload, {
    if (projectId != null) 'project': projectId,
    if (botId != null) 'bot': botId,
    'name': name,
    'data': base64Encode(data),
  }).then(_map);

  // --- Workspaces browsed ---------------------------------------------------------

  /// The folders under [path] on the desktop (its home, null): `{"path",
  /// "parent"?, "home", "dirs": [{"name", "path"}], "truncated"?}`.
  Future<Map<String, Object?>> browse([String? path]) =>
      _call(LinkMethods.browse, {if (path != null) 'path': path}).then(_map);

  /// [path] listed as a workspace; the project it made.
  Future<ProjectInfo> addProject(String path) async {
    final result = _map(
      await _call(LinkMethods.addProject, {'path': path}),
    );
    return ProjectInfo.fromJson(
      (result['project'] as Map?)?.cast<String, Object?>() ?? const {},
    );
  }

  // --- Model upstreams ------------------------------------------------------------

  /// The upstreams and the jobs' models: `{"providers", "defaults"}`.
  Future<({List<LinkProvider> providers, LinkModelDefaults defaults})>
  providers() async {
    final result = _map(await _call(LinkMethods.providers));
    final defaults = LinkModelDefaults.fromJson(
      (result['defaults'] as Map?)?.cast<String, Object?>() ?? const {},
    );
    return (
      providers: [
        for (final item in result['providers'] as List? ?? const [])
          if (item is Map<String, Object?>) LinkProvider.fromJson(item),
      ],
      defaults: defaults,
    );
  }

  /// [provider] saved — `{"id"?}` (none: a new one), `{"name",
  /// "protocol", "baseUrl", "modelsUrl"?, "endpointUrl"?, "auth"?,
  /// "enabled"?, "models"?, "key"?}` (the key kept on the desktop, an
  /// empty one removed); its id.
  Future<String> saveProvider(Map<String, Object?> provider) async =>
      _map(await _call(LinkMethods.saveProvider, provider))['id']
          as String? ??
      '';

  /// Upstream [id] removed, its key with it.
  Future<void> deleteProvider(String id) =>
      _call(LinkMethods.deleteProvider, {'id': id});

  /// The models an upstream lists — of a saved one's (`id`), or of the
  /// fields for one not saved yet (`baseUrl`, `protocol`, `modelsUrl`,
  /// `auth`, `key` — used once, not kept).
  Future<List<LinkProviderModel>> fetchModels({
    String? id,
    String? baseUrl,
    String? protocol,
    String? modelsUrl,
    String? auth,
    String? key,
  }) async {
    final result = _map(
      await _call(LinkMethods.fetchModels, {
        'id': ?id,
        'baseUrl': ?baseUrl,
        'protocol': ?protocol,
        'modelsUrl': ?modelsUrl,
        'auth': ?auth,
        'key': ?key,
      }),
    );
    return [
      for (final item in result['models'] as List? ?? const [])
        if (item is Map<String, Object?>) LinkProviderModel.fromJson(item),
    ];
  }

  /// The jobs' models set where [values] names one — `model`,
  /// `auxiliary`, `actions`, `image` (a ref, or null to unset; a key not
  /// given is not changed), `builtinHidden`; what they are then.
  Future<LinkModelDefaults> modelDefaults(
    Map<String, Object?> values,
  ) async {
    final result = _map(await _call(LinkMethods.modelDefaults, values));
    return LinkModelDefaults.fromJson(result);
  }

  // --- Groups -------------------------------------------------------------------

  /// Follows [groupId]'s messages ([LinkMethods.openGroup]).
  Future<GroupFeed> openGroup(String groupId, {int count = 50}) async {
    final peer = _requirePeer();
    wantedGroups.add(groupId);
    groups.remove(groupId)?.dispose();
    final feed = groups[groupId] = GroupFeed(groupId);
    final result = _map(await peer.call(LinkMethods.openGroup, {
      'group': groupId,
      'count': count,
    }));
    feed.more = result['more'] == true;
    feed.prepend([
      for (final message in (result['messages'] as List?) ?? const [])
        if (message is Map<String, Object?>)
          LinkGroupMessage.fromJson(message),
    ]);
    return feed;
  }

  Future<void> earlierGroup(String groupId, {int count = 50}) async {
    final peer = _requirePeer();
    final feed = groups[groupId];
    if (feed == null) return;
    final result = _map(await peer.call(LinkMethods.earlierGroup, {
      'group': groupId,
      'before': feed.messages.isEmpty ? 0 : feed.messages.first.seq,
      'count': count,
    }));
    feed.more = result['more'] == true;
    feed.prepend([
      for (final message in (result['messages'] as List?) ?? const [])
        if (message is Map<String, Object?>)
          LinkGroupMessage.fromJson(message),
    ]);
  }

  Future<void> closeGroup(String groupId) async {
    wantedGroups.remove(groupId);
    groups.remove(groupId)?.dispose();
    final peer = _peer;
    if (peer != null && !peer.isClosed) {
      await peer.call(LinkMethods.closeGroup, {'group': groupId});
    }
  }

  /// The user's message to the group; answered with its `seq`.
  Future<int?> sendGroup(
    String groupId, {
    required String text,
    List<Map<String, Object?>> images = const [],
    String? id,
    int? ref,
  }) async {
    final result = _map(await _call(LinkMethods.sendGroup, {
      'group': groupId,
      'text': text,
      if (images.isNotEmpty) 'images': images,
      if (id != null) 'id': id,
      if (ref != null) 'ref': ref,
    }));
    return result['seq'] as int?;
  }

  /// A picture of one of a group's messages.
  Future<Map<String, Object?>> groupImage(String groupId, int seq) => _call(
    LinkMethods.groupImage,
    {'group': groupId, 'image': seq},
  ).then(_map);

  // --- Bots ---------------------------------------------------------------------

  /// The bot changed, or a new one (no [botId]).
  Future<LinkBot?> saveBot(Map<String, Object?> bot, {String? botId}) async {
    final result = _map(await _call(LinkMethods.saveBot, {
      if (botId != null) 'bot': botId,
      ...bot,
    }));
    final saved = result['bot'];
    return saved is Map<String, Object?> ? LinkBot.fromJson(saved) : null;
  }

  /// The bot's picture: `{"type", "data"}`.
  Future<Map<String, Object?>> botAvatar(String botId) =>
      _call(LinkMethods.botAvatar, {'bot': botId}).then(_map);

  Future<void> deleteBot(String botId) =>
      _call(LinkMethods.deleteBot, {'bot': botId});

  /// The bot's conversation deleted, a new one started in its place.
  Future<void> clearBotChat(String botId) =>
      _call(LinkMethods.clearBotChat, {'bot': botId});

  /// What the bot remembers of the user: `{"text", "self"}`.
  Future<Map<String, Object?>> botMemory(String botId) =>
      _call(LinkMethods.botMemory, {'bot': botId}).then(_map);

  Future<void> setBotMemory(String botId, String text) =>
      _call(LinkMethods.setBotMemory, {'bot': botId, 'text': text});

  Future<void> setBotSelf(String botId, String text) =>
      _call(LinkMethods.setBotSelf, {'bot': botId, 'text': text});

  /// Who the user is, as their phone's profile says, for their bots.
  Future<void> setMe({
    String? name,
    String? gender,
    String? signature,
    Map<String, Object?>? picture,
  }) => _call(LinkMethods.setMe, {
    'name': ?name,
    'gender': ?gender,
    'signature': ?signature,
    if (picture != null) 'picture': picture,
  });

  /// What the desktop pushes the phone while it is away: its words for
  /// `needsInput` and `done`, the bots to tell of, `notices` by kind.
  /// Android keeps its own service instead; this is for iOS's APNs.
  Future<void> push(Map<String, Object?> config) =>
      _call(LinkMethods.push, config);

  /// The phone's app in the background (or in front again).
  void away(bool away) {
    _peer?.emit(LinkMethods.away, {'away': away});
  }

  // --- Groups' chats --------------------------------------------------------------

  /// The group chat changed, or a new one.
  Future<LinkGroup?> saveGroup(Map<String, Object?> group, {String? groupId}) async {
    final result = _map(await _call(LinkMethods.saveGroup, {
      if (groupId != null) 'group': groupId,
      ...group,
    }));
    final saved = result['group'];
    return saved is Map<String, Object?> ? LinkGroup.fromJson(saved) : null;
  }

  Future<void> deleteGroup(String groupId) =>
      _call(LinkMethods.deleteGroup, {'group': groupId});

  // --- Lifecycle ------------------------------------------------------------------

  Future<Object?> _call(String method, [Map<String, Object?> params = const {}]) {
    final peer = _requirePeer();
    return peer.call(method, params);
  }

  LinkPeer _requirePeer() {
    final peer = _peer;
    if (peer == null || peer.isClosed) {
      throw const LinkClosedException('offline');
    }
    return peer;
  }

  Future<void> _teardown() async {
    final peer = _peer;
    _peer = null;
    await _events?.cancel();
    _events = null;
    await _paths?.cancel();
    _paths = null;
    if (peer != null) await peer.close();
    for (final feed in feeds.values) {
      feed.dispose();
    }
    feeds.clear();
    for (final feed in groups.values) {
      feed.dispose();
    }
    groups.clear();
    outputs.clear();
  }

  /// Forgets the computer: unpaired here.
  Future<void> forget() async {
    _wantOnline = false;
    _retry?.cancel();
    await _teardown();
    phase = PhonePhase.offline;
    pairing = null;
    state = null;
    device = null;
    path = LinkPath.none;
    wanted.clear();
    wantedGroups.clear();
    notifyListeners();
  }

  /// The computer may be reachable now (its advert seen, the network
  /// changed): try at once rather than at the retry's wait.
  void retryNow() {
    if (phase == PhonePhase.online || phase == PhonePhase.pairing) return;
    _retry?.cancel();
    if (!_closed && _wantOnline) unawaited(connect());
  }

  /// The app is going away: connections kept by the node, not here.
  Future<void> suspend() async {
    await _teardown();
    if (phase != PhonePhase.pairing) phase = PhonePhase.offline;
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    _wantOnline = false;
    _retry?.cancel();
    unawaited(_teardown());
    super.dispose();
  }

  static Map<String, Object?> _map(Object? json) =>
      json is Map<String, Object?> ? json : const {};
}
