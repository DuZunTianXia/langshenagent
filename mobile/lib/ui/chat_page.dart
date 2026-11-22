import 'dart:convert';
import 'dart:math' as math;

import 'package:bao_link/bao_link.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../codicons.dart';

import '../chat/chat_models.dart'
    show
        AgentItem,
        AssistantTextItem,
        ChatItem,
        DiffLineType,
        ImageAttachment,
        LiveStatusItem,
        PlanItem,
        PlanStatus,
        TurnUsage,
        UserMessageItem;
import 'agent_page.dart';
import 'bot_edit_page.dart';
import 'file_viewer.dart';
import 'items/image_preview.dart';
import 'md/md_theme.dart';
import 'widgets.dart';
import '../chat/interaction.dart';
import '../chat/step_folds.dart';
import '../chat/user_message_style.dart';
import '../link/chat_codec.dart';
import '../link/interaction_codec.dart';
import '../link/phone_link.dart';
import 'chat_items.dart';
import 'items/fold_line.dart';
import 'markdown.dart';

/// One conversation: a session's items as they come, the composer, and
/// what the agent asks of the user.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.link, this.sessionId, this.bot});

  final PhoneLink link;

  /// The session followed; with [bot], its conversation's once it has
  /// one (a bot with none yet is written to by [bot]'s id).
  final String? sessionId;
  final LinkBot? bot;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  SessionFeed? _feed;
  String? _sessionId;
  String? _error;
  bool _opening = false;
  List<Map<String, Object?>> _images = const [];

  String? get _botId => widget.bot?.id;

  @override
  void initState() {
    super.initState();
    _sessionId = widget.sessionId ?? widget.bot?.session;
    if (_sessionId != null) _open(_sessionId!);
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _open(String id) async {
    if (_opening) return;
    _opening = true;
    try {
      final feed = await widget.link.open(id);
      if (!mounted) return;
      setState(() {
        _feed = feed;
        _sessionId = id;
        _error = null;
        _keys.clear();
        _offsets.clear();
        _stickyText = null;
        _stickyIndex = -1;
        _firstOpen = true;
        _atBottom = true;
        _lastCount = 0;
      });
      _toBottom();
    } on Object catch (failure) {
      if (mounted) setState(() => _error = '$failure');
    } finally {
      _opening = false;
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty && _images.isEmpty) return;
    _text.clear();
    final images = _images;
    setState(() => _images = const []);
    try {
      final session = await widget.link.send(
        sessionId: _sessionId,
        botId: _sessionId == null ? _botId : null,
        text: text,
        images: images,
      );
      if (session != null && session != _sessionId && mounted) {
        await _open(session);
      } else {
        _toBottom();
      }
    } on Object catch (failure) {
      if (mounted) {
        showBToast(context, '发送失败：$failure');
      }
    }
  }

  Future<void> _stop() async {
    final id = _sessionId;
    if (id == null) return;
    try {
      await widget.link.stop(id);
    } on Object {}
  }

  /// The + menu: a picture joins the message's images; another file goes
  /// to the desktop with `upload` and its path is mentioned in the text.
  Future<void> _attach() async {
    final kind = await showBActions<String>(
      context,
      actions: const [
        (Codicons.deviceCamera, '图片', null, 'image'),
        (Codicons.file, '文件', '上传到电脑，路径以 @ 引用发给会话', 'file'),
      ],
    );
    if (kind == 'image') return _attachImage();
    if (kind == 'file') return _attachFile();
  }

  Future<void> _attachFile() async {
    final files = await FilePicker.pickFiles();
    if (!mounted) return;
    final session = _sessionId;
    final summary = session == null
        ? null
        : widget.link.state?.sessions
            .where((s) => s.id == session)
            .firstOrNull;
    var done = 0;
    for (final file in files) {
      try {
        final bytes = await file.readAsBytes();
        if (bytes.length > 64 * 1024 * 1024) {
          throw Exception('${file.name} 超过 64 MB');
        }
        final reply = await widget.link.upload(
          projectId: summary?.project,
          botId: _sessionId == null ? _botId : null,
          name: file.name,
          data: bytes,
        );
        final path = reply?['path'] as String?;
        if (path != null) {
          final text = _text.text;
          final mention = '@$path ';
          _text.value = TextEditingValue(
            text: text.isEmpty ? mention : '$text $mention',
            selection: TextSelection.collapsed(
              offset: (text.isEmpty ? mention : '$text $mention').length,
            ),
          );
        }
        done++;
      } on Object catch (failure) {
        if (mounted) {
          showBToast(context, '上传失败：$failure');
        }
      }
    }
    if (done > 0 && mounted) {
      showBToast(context, '已上传 $done 个文件');
    }
  }

  Future<void> _attachImage() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'png', 'jpg', 'jpeg', 'gif', 'webp', 'heic', 'bmp',
      ],
    );
    var skipped = 0;
    final added = <Map<String, Object?>>[];
    for (final file in files) {
      final bytes = await file.readAsBytes();
      if (bytes.length > 8 * 1024 * 1024) {
        skipped++;
        continue;
      }
      added.add({
        'data': base64Encode(bytes),
        'type': _mime(file.extension),
        'name': file.name,
      });
    }
    if (!mounted || added.isEmpty && skipped == 0) return;
    if (added.isNotEmpty) setState(() => _images = [..._images, ...added]);
    if (skipped > 0) {
      showBToast(context, '$skipped 张图片超过 8 MB，已跳过。');
    }
  }

  String _mime(String? extension) => switch (extension?.toLowerCase()) {
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'bmp' => 'image/bmp',
    _ => 'image/jpeg',
  };

  /// A plan card tapped: the plan's file in this session's project.
  void _openPlan(String path) {
    final session = _sessionId;
    if (session == null) return;
    final summary = widget.link.state?.sessions
        .where((s) => s.id == session)
        .firstOrNull;
    final project = widget.link.state?.projects
        .where((p) => p.id == summary?.project)
        .firstOrNull;
    if (project == null) {
      showBToast(context, '找不到会话的项目', isError: true);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            FileViewer(link: widget.link, project: project, path: path),
      ),
    );
  }

  Future<void> _earlier() async {
    final id = _sessionId;
    if (id == null) return;
    try {
      await widget.link.earlier(id);
    } on Object {}
  }

  @override
  Widget build(BuildContext context) {
    final feed = _feed;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.bot?.name ?? _title() ?? '聊天',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17),
            ),
            Text(
              widget.link.computer.name,
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
        actions: [
          if (widget.bot != null)
            IconButton(
              tooltip: '机器人设置',
              icon: const Icon(Icons.tune_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BotEditPage(
                    link: widget.link,
                    bot: widget.bot!,
                  ),
                ),
              ),
            )
          else if (_sessionId != null)
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () async {
                final action = await showBActions<String>(
                  context,
                  danger: const {'delete'},
                  actions: const [
                    (Icons.edit_outlined, '重命名', null, 'rename'),
                    (Icons.push_pin_outlined, '置顶', null, 'pin'),
                    (Icons.archive_outlined, '归档', null, 'archive'),
                    (Icons.delete_outline, '删除', null, 'delete'),
                  ],
                );
                if (action == null || !context.mounted) return;
                final id = _sessionId!;
                switch (action) {
                  case 'rename':
                    final title = await _rename();
                    if (title != null) {
                      await widget.link.rename(id, title);
                    }
                  case 'pin':
                    await widget.link.pin(id, true);
                  case 'archive':
                    await widget.link.archive(id);
                    if (context.mounted) Navigator.of(context).pop();
                  case 'delete':
                    final yes = await _confirm('删除这个会话？');
                    if (yes) {
                      await widget.link.delete(id);
                      if (context.mounted) Navigator.of(context).pop();
                    }
                }
              },
            ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(child: _body(feed)),
          if (feed != null) _SessionBar(link: widget.link, feed: feed),
          if (feed?.interaction != null)
            _InteractionCard(
              interaction: feed!.interaction!,
              onAnswer: (answer) => widget.link.answer(
                _sessionId!,
                InteractionCodec.encodeAnswer(answer),
              ),
            ),
          if (feed != null && _text.text.isEmpty)
            _Suggestions(
              feed: feed,
              bot: widget.bot != null,
              onPick: (text) {
                _text.text = text;
                _text.selection = TextSelection.collapsed(offset: text.length);
                setState(() {});
              },
              onSend: (text) {
                _text.text = text;
                _send();
              },
            ),
          _Composer(
            controller: _text,
            live: feed?.live ?? false,
            images: _images,
            onChanged: () => setState(() {}),
            onAttach: _attach,
            onRemoveImage: (index) =>
                setState(() => _images = [..._images]..removeAt(index)),
            onSend: _send,
            onStop: _stop,
          ),
          if (feed != null) _StatusLine(link: widget.link, feed: feed),
        ],
      ),
    );
  }

  String? _title() {
    final id = _sessionId;
    if (id == null) return widget.bot?.name ?? '新对话';
    for (final session in widget.link.state?.sessions ?? const []) {
      if (session.id == id) return session.title;
    }
    return null;
  }

  Widget _body(SessionFeed? feed) {
    if (feed == null) {
      return Center(
        child: _opening
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_sessionId == null && widget.bot != null)
                    const Text('说点什么开始聊天吧。'),
                  if (_error != null)
                    TextButton(
                      onPressed: () {
                        final id = _sessionId ?? widget.sessionId;
                        if (id != null) _open(id);
                      },
                      child: const Text('重试'),
                    ),
                ],
              ),
      );
    }
    return ListenableBuilder(
      listenable: feed,
      builder: (context, _) {
        final items = [
          for (final json in feed.items) ChatCodec.decode(json),
        ];
        // As the desktop's history folds: each run of quick steps into a
        // tally line, each finished turn's work into "已处理 …" before its
        // answer, the turn's figures under its last row.
        final folds = StepFolds.of(
          items.length,
          (i) => items[i] ?? const AssistantTextItem(''),
          live: feed.live,
        );
        // Opens on the newest message, and stays pinned to the bottom
        // while it is the bottom the user is at.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scroll.hasClients) return;
          if (_firstOpen) {
            _firstOpen = false;
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          } else if (_atBottom && items.length != _lastCount) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
          _lastCount = items.length;
          _sticky(items);
        });
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollUpdateNotification &&
                notification.metrics.pixels <= 80 &&
                feed.hasMore) {
              _earlier();
            }
            if (notification is ScrollUpdateNotification) {
              _sticky(items);
            }
            return false;
          },
          child: Stack(
            children: [
              ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              if (item == null) return const SizedBox.shrink();
              final row = folds.rowAt(index, item, _isFoldOpen);
              return KeyedSubtree(
                key: _keys.putIfAbsent(index, GlobalKey.new),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (row.work case final fold?)
                      WorkFoldLine(
                        worked: fold.worked ?? Duration.zero,
                        stopped: fold.stopped,
                        edits: turnEdits(_itemsIn(fold, items)),
                        expanded: _isFoldOpen(fold),
                        onToggle: () => _toggleFold(fold),
                        images: foldImages(_itemsIn(fold, items)),
                      ),
                    if (row.steps case final fold?)
                      StepsFoldLine(
                        tally: StepTally(_itemsIn(fold, items)),
                        expanded: _isFoldOpen(fold),
                        onToggle: () => _toggleFold(fold),
                        images: foldImages(_itemsIn(fold, items)),
                      ),
                    if (row.item)
                      if (widget.bot != null && item is AssistantTextItem)
                        _BotReply(item: item, bot: widget.bot!)
                      else
                        ChatItemView(
                          item: folds.shownAt(index, item),
                          onAgent: item is AgentItem
                    ? (agent) => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AgentPage(agent: agent),
                        ),
                      )
                    : null,
                onEditResend: item is UserMessageItem
                    ? (text, revert) async {
                        try {
                          await widget.link.edit(
                            sessionId: feed.session,
                            index: index,
                            text: text,
                            revertFiles: revert,
                          );
                        } catch (e) {
                          if (context.mounted) {
                            showBToast(context, '重发失败：$e');
                          }
                        }
                      }
                    : null,
                onOpenPlan: item is PlanItem
                    ? () => _openPlan(item.path)
                    : null,
                onRewind: item is PlanItem
                    ? () async {
                        try {
                          final reply = await widget.link.rewindPlan(
                            feed.session,
                            index,
                          );
                          if (context.mounted && reply == null) {
                            showBToast(context, '回退失败');
                          }
                        } catch (e) {
                          if (context.mounted) {
                            showBToast(context, '回退失败：$e');
                          }
                        }
                      }
                    : null,
                        ),
                    if (folds.turnEndingAt(index) case final prompt?)
                      if (items[prompt]
                          case UserMessageItem(
                            :final worked?,
                            :final usage
                          ))
                        _TurnStats(worked: worked, usage: usage),
                  ],
                ),
              );
            },
          ),
              if (_stickyText != null)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _StickyUserBar(
                    text: _stickyText!,
                    onTap: _jumpToSticky,
                  ),
                ),
              Positioned(
                right: 12,
                bottom: 12,
                child: AnimatedOpacity(
                  opacity: _showJump ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: IgnorePointer(
                    ignoring: !_showJump,
                    child: Material(
                      color: AppColors.surfaceRaised,
                      shape: CircleBorder(
                        side: BorderSide(color: AppColors.bubbleBorder()),
                      ),
                      elevation: 3,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _jumpToBottom,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Icon(
                            Icons.keyboard_arrow_down,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  final Map<int, GlobalKey> _keys = {};
  final Map<int, double> _offsets = {};
  // The folds the history makes ([StepFolds]): which ones a click opened,
  // and which turns stay open once they were (see [_toggleFold]).
  final Map<(StepFoldKind, int), bool> _foldOpen = {};
  final Set<int> _unfoldedTurns = {};
  String? _stickyText;
  int _stickyIndex = -1;
  bool _showJump = false;
  bool _firstOpen = true;
  bool _atBottom = true;
  int _lastCount = 0;

  /// The message of the turn at the top pins itself while its answers
  /// scroll under it — the desktop's `sticky` user-message style.
  /// The message of the turn at the top pins itself while its answers
  /// scroll under it — decided from each message's real position in the
  /// viewport, not from estimated heights.
  void _sticky(List<ChatItem?> items) {
    if (UserMessageStyle.current.value != UserMessageStyle.sticky ||
        !_scroll.hasClients) {
      if (_stickyText != null) setState(() => _stickyText = null);
      if (!_scroll.hasClients && _showJump) {
        setState(() => _showJump = false);
      }
      return;
    }
    final offset = _scroll.offset;
    // The desktop's algorithm (chat_history_view._topTurnMessage): the
    // last user message fully scrolled past the top sticks. When it is
    // not even laid out, the nearest user message before the first
    // laid-out item is the one.
    String? pinnedText;
    var pinnedIndex = -1;
    var firstLaid = -1;
    var passed = -1;
    var blocked = false;
    for (var i = 0; i < items.length; i++) {
      final ro = _keys[i]?.currentContext?.findRenderObject();
      if (ro == null || !ro.attached) continue;
      if (firstLaid < 0) firstLaid = i;
      final item = items[i];
      if (item is! UserMessageItem) continue;
      final viewport = RenderAbstractViewport.of(ro);
      final topOffset = viewport.getOffsetToReveal(ro, 0).offset;
      _offsets[i] = topOffset; // remembered for the jump when unbuilt
      // Its bottom edge in viewport coordinates; above the top edge
      // means fully scrolled away (a still-visible one breaks the scan).
      final height = (ro as RenderBox).size.height;
      if (topOffset + height > offset - 2) {
        // On screen, even by a line: it and the bar would overlap — the
        // bar only shows while what it pins is fully out of view.
        blocked = true;
        break;
      }
      passed = i;
    }
    var index = blocked ? -1 : passed;
    if (index < 0 && !blocked && firstLaid > 0) {
      for (var i = firstLaid - 1; i >= 0; i--) {
        if (items[i] is UserMessageItem) {
          index = i;
          break;
        }
      }
    }
    if (index >= 0) {
      pinnedText = (items[index] as UserMessageItem).text;
      pinnedIndex = index;
    }
    _atBottom =
        offset >= _scroll.position.maxScrollExtent - 40;
    final showJump = !_atBottom &&
        offset < _scroll.position.maxScrollExtent - 240;
    if (pinnedText != _stickyText ||
        pinnedIndex != _stickyIndex ||
        showJump != _showJump) {
      setState(() {
        _stickyText = pinnedText;
        _stickyIndex = pinnedIndex;
        _showJump = showJump;
      });
    }
  }

  /// Whether [fold] is open: as clicked, or a work fold of a turn the
  /// user opened once (it stays open until clicked shut).
  bool _isFoldOpen(StepFold fold) =>
      _foldOpen[fold.key] ??
      (fold.kind == StepFoldKind.work && _unfoldedTurns.contains(fold.start));

  void _toggleFold(StepFold fold) => setState(() {
    final open = !_isFoldOpen(fold);
    _foldOpen[fold.key] = open;
    if (fold.kind == StepFoldKind.work) {
      if (open) {
        _unfoldedTurns.add(fold.start);
      } else {
        _unfoldedTurns.remove(fold.start);
      }
    }
  });

  /// The items [fold] holds (decode misses left out).
  static List<ChatItem> _itemsIn(StepFold fold, List<ChatItem?> items) => [
    for (var i = fold.start; i < fold.end; i++) ?items[i],
  ];

  void _jumpToSticky() {
    if (_stickyIndex < 0) return;
    final ctx = _keys[_stickyIndex]?.currentContext;
    if (ctx != null) {
      // Lands the message flush at the top of the viewport.
      Scrollable.ensureVisible(
        ctx,
        alignment: 0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } else if (_scroll.hasClients) {
      // Unbuilt (long ago): its last measured top is still good.
      final top = _offsets[_stickyIndex];
      if (top != null) {
        _scroll.animateTo(
          top.clamp(
            _scroll.position.minScrollExtent,
            _scroll.position.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  void _jumpToBottom() {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<String?> _rename() =>
      showBPrompt(context, title: '重命名', initial: _title() ?? '');

  Future<bool> _confirm(String text) =>
      showBConfirm(context, title: text, confirm: '删除', danger: true);
}

/// The composer's circular buttons: plus, stop, send — a tinted circle,
/// not the framework's filled IconButton.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.live,
    required this.images,
    required this.onChanged,
    required this.onAttach,
    required this.onRemoveImage,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final bool live;
  final List<Map<String, Object?>> images;
  final VoidCallback onChanged;
  final VoidCallback onAttach;
  final void Function(int index) onRemoveImage;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final canSend = controller.text.trim().isNotEmpty || images.isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (images.isNotEmpty)
              SizedBox(
                height: 64,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var i = 0; i < images.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Stack(
                          children: [
                            GestureDetector(
                              onTap: () => showImagePreview(
                                context,
                                ImageAttachment(
                                  bytes: base64Decode(
                                    images[i]['data']! as String,
                                  ),
                                  mediaType:
                                      images[i]['type'] as String? ??
                                      'image/jpeg',
                                  name: images[i]['name'] as String?,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  base64Decode(images[i]['data']! as String),
                                  width: 64,
                                  height: 64,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: () => onRemoveImage(i),
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Codicons.close,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            BComposer(
              controller: controller,
              live: live,
              canSend: canSend,
              onAttach: onAttach,
              onChanged: onChanged,
              onSend: onSend,
              onStop: onStop,
            ),
          ],
        ),
      ),
    );
  }
}

/// What the agent waits on the user for: a question's options, or an
/// approval's decision.
class _InteractionCard extends StatefulWidget {
  const _InteractionCard({required this.interaction, required this.onAnswer});

  final Map<String, Object?> interaction;
  final Future<void> Function(InteractionAnswer answer) onAnswer;

  @override
  State<_InteractionCard> createState() => _InteractionCardState();
}

class _InteractionCardState extends State<_InteractionCard> {
  final Map<int, Set<String>> _picks = {};
  final Map<int, TextEditingController> _others = {};
  bool _busy = false;
  int _step = 0;

  InteractionRequest? get _request => InteractionCodec.decode(
    widget.interaction,
  );

  @override
  void dispose() {
    for (final controller in _others.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final request = _request;
    if (request == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: BCard(
        padding: const EdgeInsets.all(14),
        child: switch (request) {
          QuestionRequest() => _question(context, request),
          ApprovalRequest() => _approval(context, request),
        },
      ),
    );
  }

  /// One question at a time: [上一步/下一步] steps through them, the last
  /// step's button submits all the answers picked so far.
  Widget _question(BuildContext context, QuestionRequest request) {
    final total = request.questions.length;
    final step = _step.clamp(0, total - 1);
    final q = request.questions[step];
    final last = step == total - 1;
    final answered = _stepAnswered(step, q);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                request.title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (total > 1)
              Text(
                '${step + 1}/$total',
                style: TextStyle(fontSize: 12, color: AppColors.textFaint),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (q.header.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              q.header,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.accent,
              ),
            ),
          ),
        Text(
          q.prompt,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 10),
        for (final option in q.options)
          _optionCard(context, step, q, option.label, option.description),
        if (q.allowOther) _otherCard(context, step, q),
        const SizedBox(height: 12),
        Row(
          children: [
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _answer(QuestionAnswer(const [], skipped: true)),
              child: Text('跳过', style: TextStyle(color: AppColors.textMuted)),
            ),
            const Spacer(),
            if (step > 0)
              BButton(
                label: '上一步',
                onPressed: () => setState(() => _step = step - 1),
              )
            else
              const SizedBox.shrink(),
            const SizedBox(width: 8),
            BButton(
              label: last ? '提交回答' : '下一步',
              primary: true,
              busy: _busy,
              onPressed: last
                  ? () => _answer(_questionAnswer())
                  : answered
                  ? () => setState(() => _step = step + 1)
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  /// Whether question [step] already has a pick or words of its own.
  bool _stepAnswered(int step, Question q) =>
      (_picks[step]?.isNotEmpty ?? false) ||
      (_others[step]?.text.trim().isNotEmpty ?? false);

  Widget _optionCard(
    BuildContext context,
    int q,
    Question question,
    String label,
    String description,
  ) {
    final selected = _picks[q]?.contains(label) ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? AppColors.accent.withValues(alpha: 0.08)
            : AppColors.bubbleFill,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _busy ? null : () => _pick(q, question, label),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppColors.accent : Colors.transparent,
                width: 1.4,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    selected
                        ? (question.allowMultiple
                              ? Icons.check_box
                              : Icons.radio_button_checked)
                        : (question.allowMultiple
                              ? Icons.check_box_outline_blank
                              : Icons.radio_button_off),
                    size: 20,
                    color: selected ? AppColors.accent : AppColors.textFaint,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _pick(int q, Question question, String label) {
    setState(() {
      final picks = _picks.putIfAbsent(q, () => {});
      if (picks.contains(label)) {
        picks.remove(label);
      } else {
        if (!question.allowMultiple) picks.clear();
        picks.add(label);
        // Picking an option clears the question's own words.
        if (!question.allowMultiple) _others[q]?.clear();
      }
    });
  }

  /// The "其他" answer: a card that opens a text field when its words
  /// count as the answer.
  Widget _otherCard(BuildContext context, int q, Question question) {
    final controller = _others.putIfAbsent(q, TextEditingController.new);
    final written = controller.text.trim().isNotEmpty;
    final label = question.otherLabel?.isNotEmpty == true
        ? question.otherLabel!
        : '其他';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 6, 12, 6),
        decoration: BoxDecoration(
          color: written
              ? AppColors.accent.withValues(alpha: 0.08)
              : AppColors.bubbleFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: written ? AppColors.accent : Colors.transparent,
            width: 1.4,
          ),
        ),
        child: TextField(
          controller: controller,
          enabled: !_busy,
          style: const TextStyle(fontSize: 13.5),
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            hintText: label,
            hintStyle: TextStyle(color: AppColors.textFaint),
          ),
          onChanged: (_) => setState(() {
            if (controller.text.trim().isNotEmpty &&
                !question.allowMultiple) {
              _picks[q]?.clear();
            }
          }),
        ),
      ),
    );
  }

  QuestionAnswer _questionAnswer() {
    final request = _request! as QuestionRequest;
    return QuestionAnswer([
      for (var q = 0; q < request.questions.length; q++) [
        ...?_picks[q],
        if (_others[q]?.text.trim().isNotEmpty == true)
          _others[q]!.text.trim(),
      ],
    ]);
  }

  Widget _approval(BuildContext context, ApprovalRequest request) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(request.title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          [
            request.toolName,
            if (request.reason != null) request.reason!,
          ].join(' — '),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (request.preview != null) ...[
          const SizedBox(height: 8),
          _preview(context, request.preview!),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            BButton(
              label: '拒绝',
              danger: true,
              onPressed: _busy
                  ? null
                  : () => _answer(
                      const ApprovalAnswer(ApprovalDecision.deny),
                    ),
            ),
            if (request.alwaysAllowLabel != null) ...[
              const SizedBox(width: 8),
              BButton(
                label: request.alwaysAllowLabel!,
                onPressed: _busy
                    ? null
                    : () => _answer(
                        const ApprovalAnswer(ApprovalDecision.allowAlways),
                      ),
              ),
            ],
            const Spacer(),
            BButton(
              label: '允许',
              primary: true,
              busy: _busy,
              onPressed: _busy
                  ? null
                  : () => _answer(
                      const ApprovalAnswer(ApprovalDecision.allowOnce),
                    ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _preview(BuildContext context, ApprovalPreview preview) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: switch (preview) {
        CommandPreview(:final command, :final description) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (description != null)
              Text(description, style: theme.textTheme.bodySmall),
            SelectableText(
              command,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        DiffPreview(:final path, :final lines) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(path, style: theme.textTheme.labelSmall),
            for (final line in lines.take(30))
              Text(
                '${line.type == DiffLineType.added ? '+' : line.type == DiffLineType.removed ? '−' : ' '} ${line.text}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: switch (line.type) {
                    DiffLineType.added => Colors.green.shade700,
                    DiffLineType.removed => theme.colorScheme.error,
                    DiffLineType.context => null,
                  },
                ),
              ),
          ],
        ),
        TextPreview(:final text) => SelectableText(
          text,
          style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
        ),
      },
    );
  }

  Future<void> _answer(InteractionAnswer answer) async {
    setState(() => _busy = true);
    try {
      await widget.onAnswer(answer);
    } on Object {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// What the session's state asks of the phone beyond the messages: a
/// plan put to the user, the files it changed, the model and mode to
/// pick, and the tasks still running or keeping their output.
class _SessionBar extends StatelessWidget {
  const _SessionBar({required this.link, required this.feed});

  final PhoneLink link;
  final SessionFeed feed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The plan awaiting, if the newest one is.
    PlanItem? plan;
    for (final json in feed.items.reversed) {
      final item = ChatCodec.decode(json);
      if (item is PlanItem) {
        plan = item;
        break;
      }
    }
    final awaitingPlan = plan?.status == PlanStatus.awaiting;
    final changes = feed.changes;
    final tasks = feed.tasks;
    if (!awaitingPlan && changes.isEmpty && tasks.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (awaitingPlan)
            ListTile(
              dense: true,
              leading: const Icon(Icons.fact_check_outlined, size: 20),
              title: Text(
                '计划已就绪：${plan!.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: FilledButton.tonal(
                onPressed: () => _run(
                  context,
                  () => link.startPlan(feed.session),
                ),
                child: const Text('开始'),
              ),
            ),
          if (changes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _changesLabel(changes),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        _run(context, () => link.undo(feed.session)),
                    child: const Text('撤回'),
                  ),
                  FilledButton(
                    onPressed: () =>
                        _run(context, () => link.keep(feed.session)),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: const Text('保留'),
                  ),
                ],
              ),
            ),
          for (final task in tasks)
            if (task.status == 'running' || task.output)
              _TaskTile(link: link, session: feed.session, task: task),
        ],
      ),
    );
  }

  /// `83 个文件 +10540 -1173`, the adds and drops summed over the maps the
  /// desktop sends (`path`/`added`/`removed`).
  static String _changesLabel(List<Map<String, Object?>> changes) {
    var added = 0, removed = 0;
    for (final change in changes) {
      added += (change['added'] as num?)?.toInt() ?? 0;
      removed += (change['removed'] as num?)?.toInt() ?? 0;
    }
    return '${changes.length} 个文件'
        '${added > 0 ? ' +$added' : ''}'
        '${removed > 0 ? ' -$removed' : ''}';
  }

  Future<void> _run(BuildContext context, Future<void> Function() call) async {
    try {
      await call();
    } on Object catch (failure) {
      if (context.mounted) {
        showBToast(context, '$failure');
      }
    }
  }
}

/// A task the session runs or ran, its output watched as it grows and
/// it stopped when asked.
class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.link,
    required this.session,
    required this.task,
  });

  final PhoneLink link;
  final String session;
  final LinkTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = task.status == 'running';
    final title = task.description.isNotEmpty
        ? task.description
        : task.command ?? task.kind;
    return ListTile(
      dense: true,
      leading: Icon(
        running ? Icons.sync : Icons.terminal,
        size: 18,
        color: running ? Colors.blue : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: task.summary == null
          ? null
          : Text(task.summary!, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (task.output)
            IconButton(
              tooltip: '输出',
              icon: const Icon(Icons.output_outlined, size: 18),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => OutputPage(
                    link: link,
                    session: session,
                    task: task,
                  ),
                ),
              ),
            ),
          if (running)
            IconButton(
              tooltip: '停止',
              icon: const Icon(Icons.stop_circle_outlined, size: 18),
              onPressed: () async {
                try {
                  await link.stopTask(session, task: task.id);
                } on Object catch (failure) {
                  if (context.mounted) {
                    showBToast(context, '$failure');
                  }
                }
              },
            ),
        ],
      ),
    );
  }
}

/// A task's output as the desktop streams it: the tail it had when
/// watched, then what it adds, until the page closes.
class OutputPage extends StatefulWidget {
  const OutputPage({
    super.key,
    required this.link,
    required this.session,
    required this.task,
  });

  final PhoneLink link;
  final String session;
  final LinkTask task;

  @override
  State<OutputPage> createState() => _OutputPageState();
}

class _OutputPageState extends State<OutputPage> {
  bool _loading = true;
  Object? _error;

  String get _key => '${widget.session}/${widget.task.id}';

  @override
  void initState() {
    super.initState();
    _watch();
  }

  @override
  void dispose() {
    widget.link.unwatchOutput(widget.session, widget.task.id);
    super.dispose();
  }

  Future<void> _watch() async {
    try {
      await widget.link.watchOutput(widget.session, widget.task.id);
      if (mounted) setState(() => _loading = false);
    } on Object catch (failure) {
      if (mounted) {
        setState(() {
          _error = failure;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.task.description.isNotEmpty
        ? widget.task.description
        : widget.task.command ?? widget.task.id;
    return Scaffold(
      appBar: AppBar(title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('$_error'))
          : ListenableBuilder(
              listenable: widget.link,
              builder: (context, _) {
                final output = widget.link.outputs[_key]?.text ?? '';
                return output.isEmpty
                    ? const Center(child: Text('暂无输出'))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          output,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                        ),
                      );
              },
            ),
    );
  }
}

/// What the latest reply suggests sending next, as tappable chips: a tap
/// fills the composer with it.
/// What the agent suggests the user send next, as the desktop's
/// `ReplySuggestionBar` has them: pills piled on the composer (onto the
/// line above when a row fills), a click putting one in the composer to
/// be edited and sent, sent as it is at a second click soon after. Shown
/// for the first time, they rise in one after another, as a bot's
/// message does on the phone.
class _Suggestions extends StatefulWidget {
  const _Suggestions({
    required this.feed,
    required this.bot,
    required this.onPick,
    required this.onSend,
  });

  final SessionFeed feed;

  /// A bot's chat: its reply's `<bot_suggest>`s, not a reply's markup's.
  final bool bot;
  final ValueChanged<String> onPick;
  final ValueChanged<String> onSend;

  /// Before the first comes: the reply's last words read, the room open.
  static const delay = Duration(milliseconds: 100);

  /// Between one and the next: each comes on its own.
  static const stagger = Duration(milliseconds: 110);

  /// How long each takes to come.
  static const each = Duration(milliseconds: 480);

  @override
  State<_Suggestions> createState() => _SuggestionsState();
}

class _SuggestionsState extends State<_Suggestions>
    with SingleTickerProviderStateMixin {
  /// Those played in, the latest last (a conversation's suggestions play
  /// once each).
  static final _played = <String>{};

  late final AnimationController _entry;

  @override
  void initState() {
    super.initState();
    final count = _suggestions().length;
    _entry = AnimationController(
      vsync: this,
      duration:
          _Suggestions.delay +
          _Suggestions.stagger * (count > 0 ? count - 1 : 0) +
          _Suggestions.each,
    );
    final play = _played.add('${widget.feed.session}\n${_suggestions().join('\n')}');
    if (_played.length > 200) _played.remove(_played.first);
    if (play) {
      _entry.forward();
    } else {
      _entry.value = 1;
    }
  }

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  /// The newest reply's suggestions: none while a turn is under way, and
  /// none once anything came after it (a message sent again, or more of
  /// the agent's work) — they are what to send after *this* answer.
  List<String> _suggestions() {
    if (widget.feed.live) return const [];
    for (final json in widget.feed.items.reversed) {
      final item = ChatCodec.decode(json);
      // The status row under a live turn stands after it for a moment.
      if (item == null || item is LiveStatusItem) continue;
      if (item is! AssistantTextItem) return const [];
      return widget.bot
          ? ChatCodec.botSuggestions(item.raw)
          : item.suggestions;
    }
    return const [];
  }

  /// The [i]th's part of the whole.
  Animation<double> _of(int i) {
    final total = _entry.duration!.inMicroseconds;
    final start = (_Suggestions.delay + _Suggestions.stagger * i)
        .inMicroseconds;
    final end = start + _Suggestions.each.inMicroseconds;
    return CurvedAnimation(
      parent: _entry,
      curve: Interval(start / total, end / total),
    );
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _suggestions();
    if (suggestions.isEmpty) return const SizedBox.shrink();
    // Less motion asked for: they only fade in.
    final still = MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: [
          for (final (i, said) in suggestions.indexed)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Center(
                child: _Entering(
                  animation: _of(i),
                  still: still,
                  child: _Pill(
                    text: said,
                    onTap: () => widget.onPick(said),
                    onDoubleTap: () => widget.onSend(said),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One coming in by [animation]: rising and growing from its lower
/// corner first, fading in just after; with [still], only fading.
class _Entering extends AnimatedWidget {
  const _Entering({
    required Animation<double> animation,
    required this.still,
    required this.child,
  }) : super(listenable: animation);

  final bool still;
  final Widget child;

  static const _fade = Interval(0.2, 1, curve: Curves.easeOut);
  static const _rise = Interval(0.1, 1, curve: Curves.easeOutCubic);

  @override
  Widget build(BuildContext context) {
    final t = (listenable as Animation<double>).value;
    if (t >= 1) return child;
    final faded = Opacity(opacity: _fade.transform(t), child: child);
    if (still) return faded;
    final rise = _rise.transform(t);
    return Transform.translate(
      offset: Offset(0, (1 - rise) * 10),
      child: Transform.scale(
        scale: 0.94 + 0.06 * rise,
        alignment: Alignment.bottomLeft,
        child: faded,
      ),
    );
  }
}

/// One suggestion pill: clicked it goes in the composer, clicked again
/// within a double click's time it is sent.
class _Pill extends StatefulWidget {
  const _Pill({
    required this.text,
    required this.onTap,
    required this.onDoubleTap,
  });

  final String text;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  @override
  State<_Pill> createState() => _PillState();
}

class _PillState extends State<_Pill> {
  /// When it was last clicked: clicked again within a double click's
  /// time, it is sent. A click is taken at once, not once no second one
  /// came.
  Duration? _clickedAt;

  void _click() {
    final at = _clock.elapsed;
    final before = _clickedAt;
    if (before != null && at - before <= kDoubleTapTimeout) {
      _clickedAt = null;
      widget.onDoubleTap();
    } else {
      _clickedAt = at;
      widget.onTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _click,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.bubbleFill,
          // A pill on one line; on more, its corners as round.
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: AppColors.bubbleBorder()),
        ),
        child: Text(
          line,
          style: TextStyle(color: AppColors.text, fontSize: 12.5),
        ),
      ),
    );
  }
}

/// The time, for clicks.
final _clock = Stopwatch()..start();

/// A choice's kind as a word, for its label and its sheet's title.
String _kindLabel(String kind) => switch (kind) {
  'model' => '模型',
  'mode' => '模式',
  'permission' => '权限',
  'effort' => '投入',
  'context' => '上下文',
  _ => kind,
};

/// The bar under the composer the official app shows: the agent's mode,
/// permission and model (a tap on one picks another), and how much of
/// the context window the turn has used.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.link, required this.feed});

  final PhoneLink link;
  final SessionFeed feed;

  String? _selectedLabel(LinkChoice choice) {
    for (final option in choice.options) {
      if (option.id == choice.selected) {
        return _localize(choice, option.label);
      }
    }
    return choice.selected;
  }

  /// The server labels choices in English; the phone shows Chinese.
  static String _localize(LinkChoice choice, String label) {
    return switch ((choice.kind, label)) {
      ('mode', 'Agent' || 'Task') => '智能体',
      ('mode', 'Ask' || 'Chat') => '问答',
      ('mode', 'Plan') => '规划',
      ('permission', 'Ask for approval' || 'Default') => '逐项批准',
      ('permission', 'Accept edits') => '接受编辑',
      ('permission', 'Approve for me' || 'Auto') => '替我批准',
      ('permission', "Don't ask") => '仅限已允许',
      ('permission', 'Full access') => '完全访问',
      ('permission', 'Plan') => '仅规划',
      ('permission', 'Read only') => '只读',
      ('effort', 'Disable') => '关闭',
      ('effort', 'Low') => '低',
      ('effort', 'Medium') => '中',
      ('effort', 'High') => '高',
      ('effort', 'X-High') => '极高',
      ('effort', 'Max') => '最高',
      _ => label,
    };
  }

  /// The option's description as the sheet shows it, Chinese too.
  static String _localizeDescription(String description) {
    return switch (description) {
      'Plan, edit and run code' => '规划、改代码、跑命令',
      'Talk it through, suggest changes' => '讨论并给出建议，不动文件',
      'Research and plan, then build' => '先调研和规划，再动手',
      'Ask before edits and commands' => '改文件、跑命令前先问你',
      'Edit files freely, ask before commands' => '自由改文件，跑命令前问',
      'Run what is safe, block what looks risky' => '安全的直接执行，危险的拦下',
      'Deny whatever is not pre-approved' => '未预先允许的一律拒绝',
      'No checks: edits and commands run without asking' =>
        '不做检查：编辑和命令直接执行',
      _ => description,
    };
  }

  /// The effort/context choices folded into the model chip's dropdown.
  List<LinkChoice> get _modelSubChoices => [
    for (final choice in feed.choices)
      if (choice.kind == 'effort' || choice.kind == 'context') choice,
  ];

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final choice in feed.choices) {
      final label = _selectedLabel(choice);
      if (label == null || label.isEmpty) continue;
      if (choice.kind == 'effort' || choice.kind == 'context') continue;
      if (children.isNotEmpty) children.add(const SizedBox(width: 8));
      children.add(
        _StatusChip(
          icon: switch (choice.kind) {
            'mode' => Codicons.symbolConstant,
            'permission' => Codicons.shield,
            'model' => Codicons.hubot,
            _ => Codicons.settings,
          },
          label: choice.kind == 'mode' ? '∞ $label' : label,
          accent: choice.kind == 'permission',
          onTap: () => _pick(context, choice),
          onMenuTap: choice.kind == 'model' && _modelSubChoices.isNotEmpty
              ? () => _modelSettings(context)
              : null,
        ),
      );
    }
    final used = feed.context?['used'];
    final window = feed.context?['window'];
    if (used is num && window is num && window > 0) {
      if (children.isNotEmpty) children.add(const SizedBox(width: 8));
      children.add(
        _StatusChip(
          icon: Codicons.pieChart,
          label: '${_tokens(used)} / ${_tokens(window)}',
        ),
      );
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: children),
        ),
      ),
    );
  }

  static String _tokens(num tokens) {
    if (tokens >= 1000) {
      final k = tokens / 1000;
      return '${k.toStringAsFixed(k >= 100 ? 0 : 1)}K';
    }
    return '$tokens';
  }

  /// A provider brand icon for a model/option id, from the official app's
  /// extracted `assets/model_icons`, when one matches a known name.
  static Widget? _modelIcon(String id) {
    final lower = id.toLowerCase();
    const names = [
      'claudecode', 'claude', 'anthropic', 'openai', 'gemini', 'deepseek',
      'kimi', 'moonshot', 'qwen', 'doubao', 'zhipu', 'xai', 'ollama',
      'minimax', 'mistral', 'meta', 'perplexity', 'hunyuan', 'wenxin',
      'baichuan', 'yi', 'siliconflow', 'openrouter', 'together',
      'fireworks', 'vertexai', 'bedrock', 'azure', 'google', 'bytedance',
      'nvidia', 'volcengine', 'stepfun', 'lmstudio', 'huggingface',
      'githubcopilot', 'cloudflare', 'microsoft', 'vercel',
    ];
    for (final name in names) {
      if (lower.contains(name)) {
        return SvgPicture.asset(
          'assets/model_icons/$name.svg',
          width: 20,
          height: 20,
        );
      }
    }
    return null;
  }

  /// The model chip's dropdown: the effort/context choices that used to
  /// sit beside it, each leading into its own picker.
  Future<void> _modelSettings(BuildContext context) async {
    final picked = await showBActions<LinkChoice>(
      context,
      actions: [
        for (final choice in _modelSubChoices)
          (
            choice.kind == 'effort' ? Codicons.zap : Codicons.pieChart,
            _kindLabel(choice.kind),
            _selectedLabel(choice),
            choice,
          ),
      ],
    );
    if (picked != null && context.mounted) {
      _pick(context, picked);
    }
  }

  Future<void> _pick(BuildContext context, LinkChoice choice) async {
    String? initialGroup;
    if (choice.kind == 'model') {
      for (final option in choice.options) {
        if (option.id == choice.selected) {
          initialGroup = option.group;
          break;
        }
      }
    }
    final picked = await showBChoicePicker(
      context,
      title: _kindLabel(choice.kind),
      initialGroup: initialGroup,
      options: [
        for (final option in choice.options)
          LinkOption(
            id: option.id,
            label: option.label,
            description: _localizeDescription(option.description),
            group: option.group,
            groupLabel: option.groupLabel,
            caution: option.caution,
          ),
      ],
      selected: choice.selected,
      iconOf: choice.kind == 'model' ? (id) => _modelIcon(id) : null,
      labelOf: (label) => _localize(choice, label),
    );
    if (picked != null && context.mounted) {
      try {
        await link.choose(feed.session, choice.kind, picked.id);
      } on Object catch (failure) {
        if (context.mounted) {
          showBToast(context, '$failure');
        }
      }
    }
  }
}

/// A status pill under the composer: icon + label on a soft fill; the
/// permission kind in the caution tone. [onTap] null means display only.
class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    this.accent = false,
    this.onTap,
    this.onMenuTap,
  });

  final IconData icon;
  final String label;
  final bool accent;
  final VoidCallback? onTap;

  /// A second tap zone at the pill's right edge: a divider plus a
  /// dropdown arrow — the model chip's effort/context settings.
  final VoidCallback? onMenuTap;

  @override
  Widget build(BuildContext context) {
    final color = accent ? AppColors.caution : AppColors.textMuted;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: accent
              ? AppColors.caution.withValues(alpha: 0.10)
              : AppColors.bubbleFill,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: accent ? AppColors.caution : AppColors.text,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 2),
              Icon(Icons.unfold_more, size: 13, color: color),
            ],
            if (onMenuTap != null) ...[
              Container(
                width: 0.5,
                height: 14,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: AppColors.partBorder,
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onMenuTap,
                child: Icon(
                  Icons.arrow_drop_down,
                  size: 18,
                  color: color,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// How a finished turn went, under its last item: how long it worked,
/// how fast and how much it wrote, what it cost — as the official app
/// shows them.
class _TurnStats extends StatelessWidget {
  const _TurnStats({required this.worked, required this.usage});

  final Duration? worked;
  final TurnUsage? usage;

  static String _duration(Duration d) {
    final s = d.inSeconds;
    if (s < 60) return '$s秒';
    final h = d.inHours, m = d.inMinutes % 60;
    return h > 0 ? '$h小时$m分' : '${d.inMinutes}分${s % 60}秒';
  }

  /// "$0.42", "$0.0031": two figures past the first that is not 0, at
  /// least two decimals (the desktop's `TurnFooter.formatCost`).
  static String _cost(double usd) {
    if (usd >= 1 || usd == 0) return '\$${usd.toStringAsFixed(2)}';
    var digits = 2;
    while (digits < 6 && usd < math.pow(10, 1 - digits)) {
      digits++;
    }
    return '\$${usd.toStringAsFixed(digits)}';
  }

  /// `8.69M`, `222.03k`: the official's two-decimal thousands/millions.
  static String _human(int tokens) {
    if (tokens >= 1000000) return '${(tokens / 1000000).toStringAsFixed(2)}M';
    if (tokens >= 1000) return '${(tokens / 1000).toStringAsFixed(2)}k';
    return '$tokens';
  }

  @override
  Widget build(BuildContext context) {
    final usage = this.usage;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 5, 0, 10),
      child: Wrap(
        spacing: 12,
        runSpacing: 2,
        children: [
          if (worked case final worked?)
            _stat(Icons.schedule_rounded, _duration(worked)),
          if (usage?.tokensPerSecond case final speed?)
            _stat(
              Icons.bolt_rounded,
              '${speed.toStringAsFixed(2)} tok/s',
            ),
          if (usage?.costUsd case final cost?)
            _stat(Icons.attach_money_rounded, _cost(cost)),
          if (usage?.totalTokens case final tokens?)
            _stat(Icons.data_usage_rounded, '${_human(tokens)} tokens'),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: AppColors.textFaint),
      const SizedBox(width: 3),
      Text(
        text,
        style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
      ),
    ],
  );
}

/// A bot's reply as one bubble by its avatar: its `<bot_say>`s the
/// bubble's paragraphs, its narrations faint lines among them (its
/// `<bot_suggest>`s are the chips over the composer,
/// [ChatCodec.botSuggestions]).
class _BotReply extends StatelessWidget {
  const _BotReply({required this.item, required this.bot});

  final AssistantTextItem item;
  final LinkBot bot;

  @override
  Widget build(BuildContext context) {
    final parts = ChatCodec.botParts(item.raw);
    if (parts.isEmpty) {
      // Nothing closed yet (still writing), or a reply without tags:
      // what it has so far, without the tags themselves.
      final said = ChatCodec.withoutVoiceCues(
        item.raw.replaceAll(RegExp(r'</?bot_\w+[^>]*>'), ''),
      );
      if (said.isEmpty) return const SizedBox.shrink();
      return _bubble(context, ChatMarkdown(text: said));
    }
    final children = <Widget>[
      for (final (tag, text) in parts)
        switch (tag) {
          ChatCodec.botSayTag => ChatMarkdown(
            text: ChatCodec.withoutVoiceCues(text),
          ),
          ChatCodec.botNarrateTag => Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 2),
            child: Text(
              ChatCodec.withoutVoiceCues(text),
              style: TextStyle(
                fontSize: 11.5,
                fontStyle: FontStyle.italic,
                color: AppColors.textFaint,
              ),
            ),
          ),
          _ => const SizedBox.shrink(),
        },
    ];
    if (children.isEmpty) return const SizedBox.shrink();
    return _bubble(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: children,
      ),
    );
  }

  Widget _bubble(BuildContext context, Widget child) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 48, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF9270CA),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              bot.name.isEmpty ? 'B' : bot.name[0],
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.conversationSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.partBorder),
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// The user message of the turn at the top, pinned there while the
/// answers below it scroll.
class _StickyUserBar extends StatelessWidget {
  const _StickyUserBar({required this.text, this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceRaised,
      elevation: 2,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: AppColors.accent, width: 3),
              bottom: BorderSide(color: AppColors.bubbleBorder()),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.person_outline, size: 15, color: AppColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.text,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '跳转到此消息',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
              Icon(
                Icons.keyboard_arrow_up,
                size: 16,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
