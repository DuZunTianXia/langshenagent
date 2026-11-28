import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bao_link/bao_link.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../codicons.dart';
import '../main.dart';
import '../phone_platform.dart';

import '../chat/chat_models.dart'
    show
        AgentItem,
        AssistantTextItem,
        ChatItem,
        CommandStatus,
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
import 'items/agent_step.dart';
import 'items/image_preview.dart';
import 'items/shimmer_text.dart';
import 'md/md_theme.dart';
import 'widgets.dart';
import '../chat/interaction.dart';
import '../chat/step_folds.dart';
import '../chat/user_message_style.dart';
import '../link/chat_codec.dart';
import '../link/interaction_codec.dart';
import '../link/phone_link.dart';
import 'link_status.dart';
import 'chat_items.dart';
import 'edit_resend_sheet.dart';
import 'items/fold_line.dart';
import 'items/pixel_loader.dart';
import 'items/step_header.dart' show ExpandReveal;
import 'markdown.dart';

/// One conversation: a session's items as they come, the composer, and
/// what the agent asks of the user.
class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.link,
    this.sessionId,
    this.bot,
    this.initialText,
  });

  final PhoneLink link;

  /// The session followed; with [bot], its conversation's once it has
  /// one (a bot with none yet is written to by [bot]'s id).
  final String? sessionId;
  final LinkBot? bot;

  /// Optional prefilled text (e.g. `@path ` from FileViewer).
  final String? initialText;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _text = TextEditingController();
  final _scroll = BottomAnchoredScrollController();
  SessionFeed? _feed;
  String? _sessionId;
  String? _error;
  bool _opening = false;
  bool _stopping = false;
  bool _pickingMention = false;
  String _prevComposerText = '';
  final Set<String> _stoppingTasks = {};
  List<Map<String, Object?>> _images = const [];

  String? get _botId => widget.bot?.id;

  ProjectInfo? get _project {
    final session = _sessionId;
    if (session == null) return null;
    final summary = widget.link.state?.sessions
        .where((s) => s.id == session)
        .firstOrNull;
    if (summary == null) return null;
    return widget.link.state?.projects
        .where((p) => p.id == summary.project)
        .firstOrNull;
  }

  void _bindFeed(SessionFeed? next) {
    if (identical(_feed, next)) return;
    _feed?.removeListener(_onFeedChanged);
    _feed = next;
    _feed?.addListener(_onFeedChanged);
  }

  void _onFeedChanged() {
    if (!mounted) return;
    final feed = _feed;
    if (feed == null) return;
    var changed = false;
    if (_stopping && !feed.live) {
      _stopping = false;
      changed = true;
    }
    if (_stoppingTasks.isNotEmpty) {
      final activeIds = <String>{
        for (final t in feed.tasks)
          if (t.status == 'running') ...[t.id, ?t.toolUseId],
      };
      for (final json in feed.items) {
        final item = ChatCodec.decode(json);
        if (item is AgentItem &&
            item.status == CommandStatus.running &&
            item.id != null) {
          activeIds.add(item.id!);
        }
      }
      final before = _stoppingTasks.length;
      _stoppingTasks.removeWhere((id) => !activeIds.contains(id));
      if (_stoppingTasks.length != before) changed = true;
    }
    if (changed) setState(() {});
  }

  String? get _draftKey =>
      _sessionId ?? widget.sessionId ?? (widget.bot == null ? null : 'bot:${widget.bot!.id}');

  @override
  void initState() {
    super.initState();
    widget.link.addListener(_onLinkChanged);
    // Every move of the offset re-decides the pin — scroll notifications
    // miss the layout corrections of the anchored controller, which is
    // most of what streaming moves.
    _scroll.addListener(_onScrolled);
    _sessionId = widget.sessionId ?? widget.bot?.session;
    if (widget.initialText != null && widget.initialText!.isNotEmpty) {
      _text.text = widget.initialText!;
      _text.selection = TextSelection.collapsed(
        offset: widget.initialText!.length,
      );
      _prevComposerText = widget.initialText!;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _text.text.isNotEmpty) return;
        final key = _draftKey;
        if (key == null) return;
        final saved = AppScope.of(context).draftOf(key);
        if (saved.isNotEmpty) {
          _text.text = saved;
          _text.selection = TextSelection.collapsed(offset: saved.length);
          _prevComposerText = saved;
          setState(() {});
        }
      });
    }
    if (_sessionId != null) _open(_sessionId!);
  }

  @override
  void dispose() {
    _feed?.removeListener(_onFeedChanged);
    widget.link.removeListener(_onLinkChanged);
    _scroll.removeListener(_onScrolled);
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScrolled() {
    if (!mounted || _feed == null) return;
    final items = _decodedItems ?? const <ChatItem?>[];
    _sticky(items);
    // Rows coming into view are laid out only after this frame: scan
    // again once they are, or a fast fling would leave the pin unset
    // until the offset next moves.
    if (_stickyFrameScheduled) return;
    _stickyFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _stickyFrameScheduled = false;
      if (mounted && _feed != null) _sticky(_decodedItems ?? const []);
    });
  }

  bool _stickyFrameScheduled = false;

  /// The last items the feed was decoded into, for the scroll listener.
  List<ChatItem?>? _decodedItems;

  /// Decode results by their JSON object (see the history's builder); a
  /// decode miss (undecodable JSON) is cached as [_decodeMiss].
  final Expando<Object> _decodeCache = Expando<Object>();

  /// What an undecodable item is cached as: it decodes once, not per frame.
  static final Object _decodeMiss = Object();

  /// Re-opens or re-binds the session once the computer is online again.
  void _onLinkChanged() {
    if (!mounted) return;
    final id = _sessionId ?? widget.sessionId ?? widget.bot?.session;
    if (widget.link.phase == PhonePhase.online) {
      if (_error != null) _error = null;
      if (id != null) {
        final liveFeed = widget.link.feeds[id];
        if (liveFeed != null && !identical(_feed, liveFeed)) {
          _bindFeed(liveFeed);
          _sessionId = id;
        } else if (_feed == null && !_opening) {
          unawaited(_open(id));
        }
      }
    }
    setState(() {});
  }

  Future<void> _open(String id) async {
    if (_opening) return;
    _opening = true;
    try {
      final feed = await widget.link.open(id);
      if (!mounted) return;
      setState(() {
        _bindFeed(feed);
        _sessionId = id;
        _error = null;
        _stopping = false;
        _keys.clear();
        _positions.clear();
        _stickyText = null;
        _stickyIndex = -1;
        _firstOpen = true;
        _scroll.anchored = true;
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
    final sendNow =
        (_feed?.live ?? false) && AppScope.of(context).sendNowWhileLive;
    final images = _images;
    _text.clear();
    _prevComposerText = '';
    final draftKey = _draftKey;
    if (draftKey != null) {
      AppScope.of(context).setDraft(draftKey, '');
    }
    setState(() {
      _images = const [];
      _stopping = false;
    });
    try {
      final session = await widget.link.send(
        sessionId: _sessionId,
        botId: _sessionId == null ? _botId : null,
        text: text,
        images: images,
        now: sendNow,
      );
      if (session != null && session != _sessionId && mounted) {
        await _open(session);
      } else {
        _toBottom();
      }
    } on Object catch (failure) {
      if (mounted) {
        // Restore unsent draft so user input is never lost on network errors.
        setState(() {
          if (_text.text.isEmpty && text.isNotEmpty) {
            _text.text = text;
            _text.selection = TextSelection.collapsed(offset: text.length);
            _prevComposerText = text;
          }
          if (_images.isEmpty && images.isNotEmpty) {
            _images = images;
          }
        });
        showBToast(context, '发送失败：$failure', isError: true);
      }
    }
  }

  void _onComposerChanged() {
    final current = _text.text;
    final prev = _prevComposerText;
    _prevComposerText = current;
    final draftKey = _draftKey;
    if (draftKey != null) {
      AppScope.of(context).setDraft(draftKey, current);
    }
    setState(() {});
    final project = _project;
    if (project == null || _pickingMention) return;
    final sel = _text.selection;
    if (!sel.isCollapsed || sel.baseOffset <= 0) return;
    final cursor = sel.baseOffset;
    if (current.length == prev.length + 1 && current[cursor - 1] == '@') {
      final before = cursor == 1 ? ' ' : current[cursor - 2];
      if (before == ' ' || before == '\n' || before == '\t') {
        unawaited(_mentionWorkspaceFile(project, triggerAtOffset: cursor - 1));
      }
    }
  }

  Future<void> _stop() async {
    final id = _sessionId;
    if (id == null || _stopping) return;
    PhonePlatform.haptic('selection');
    setState(() => _stopping = true);
    try {
      await widget.link.stop(id);
    } on Object {
      // Stopping is best-effort: the session may be gone already.
      if (mounted) setState(() => _stopping = false);
    }
  }

  Future<void> _stopTaskItem(LinkTask task) async {
    final id = _sessionId;
    if (id == null) return;
    final key = task.toolUseId ?? task.id;
    if (_stoppingTasks.contains(key)) return;
    PhonePlatform.haptic('selection');
    setState(() => _stoppingTasks.add(key));
    try {
      final inTasks = _feed?.tasks.any((t) => t.id == task.id) ?? false;
      await widget.link.stopTask(
        id,
        task: inTasks ? task.id : null,
        agent: inTasks ? null : task.toolUseId,
      );
    } on Object catch (failure) {
      if (mounted) {
        setState(() => _stoppingTasks.remove(key));
        showBToast(context, '$failure');
      }
    }
  }

  /// A message waiting its turn: `remove`/`sendNow`/`edit`/`move`, as the
  /// desktop's queue panel does. Failures are toasted, not thrown.
  Future<void> _queue(
    String id,
    String action, {
    int? index,
  }) async {
    final session = _sessionId;
    if (session == null) return;
    try {
      await widget.link.queue(
        session,
        id: id,
        action: action,
        index: index,
      );
    } on Object catch (failure) {
      if (mounted) showBToast(context, '$failure');
    }
  }

  /// The + menu: camera photo, gallery image, file upload, or @workspace file.
  Future<void> _attach() async {
    final project = _project;
    final kind = await showBActions<String>(
      context,
      actions: [
        (Codicons.deviceCamera, '拍照', '拍摄照片直接发送', 'camera'),
        (Icons.photo_library_outlined, '图片', '从相册选择图片', 'image'),
        (Codicons.file, '文件', '上传到电脑，路径以 @ 引用发给会话', 'file'),
        if (project != null)
          (Codicons.mention, '@工作区文件', '引用 ${project.name} 中的文件', 'mention'),
      ],
    );
    if (kind == 'camera') return _takePhoto();
    if (kind == 'image') return _attachImage();
    if (kind == 'file') return _attachFile();
    if (kind == 'mention' && project != null) {
      return _mentionWorkspaceFile(project);
    }
  }

  Future<void> _takePhoto() async {
    final path = await PhonePlatform.takePhoto();
    if (path == null || !mounted) return;
    final file = File(path);
    try {
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.length > 8 * 1024 * 1024) {
        showBToast(context, '照片超过 8 MB，请调低分辨率后重试。', isError: true);
        return;
      }
      setState(() {
        _images = [
          ..._images,
          {
            'data': base64Encode(bytes),
            'type': 'image/jpeg',
            'name': file.uri.pathSegments.last,
          },
        ];
      });
    } on Object catch (failure) {
      if (mounted) showBToast(context, '读取照片失败：$failure', isError: true);
    } finally {
      unawaited(file.delete().catchError((Object _) => file));
    }
  }

  Future<void> _mentionWorkspaceFile(
    ProjectInfo project, {
    int? triggerAtOffset,
  }) async {
    if (_pickingMention) return;
    _pickingMention = true;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _WorkspaceFilePickerSheet(
        link: widget.link,
        project: project,
      ),
    );
    _pickingMention = false;
    if (picked == null || picked.isEmpty || !mounted) return;
    final text = _text.text;
    final mention = '@$picked ';
    final String next;
    final int nextCursor;
    if (triggerAtOffset != null &&
        triggerAtOffset >= 0 &&
        triggerAtOffset < text.length &&
        text[triggerAtOffset] == '@') {
      next =
          '${text.substring(0, triggerAtOffset)}$mention${text.substring(triggerAtOffset + 1)}';
      nextCursor = triggerAtOffset + mention.length;
    } else {
      next = text.isEmpty || text.endsWith(' ') || text.endsWith('\n')
          ? '$text$mention'
          : '$text $mention';
      nextCursor = next.length;
    }
    _prevComposerText = next;
    _text.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: nextCursor),
    );
    setState(() {});
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
        final path = reply['path'] as String?;
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
    } on Object {
      // Best-effort too: nothing else asks for the page now.
    }
  }

  @override
  Widget build(BuildContext context) {
    final feed = _feed;
    return Scaffold(
      backgroundColor: AppColors.conversationSurface,
      appBar: AppBar(
        backgroundColor: AppColors.background,
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
            _Subtitle(link: widget.link, feed: feed, stopping: _stopping),
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Divider(height: 0.5, color: AppColors.partBorder),
        ),
      ),
      body: Column(
        children: [
          BConnectionBanner(
            link: widget.link,
            onRetry: () => widget.link.retryNow(force: true),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: BCard(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, size: 18, color: AppColors.removed),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _friendlyError(_error!),
                        style: TextStyle(fontSize: 13, color: AppColors.removed),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        final id = _sessionId ?? widget.sessionId;
                        if (id != null) {
                          unawaited(_open(id));
                        } else {
                          widget.link.retryNow();
                        }
                      },
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(child: _body(feed)),
          if (feed != null)
            ListenableBuilder(
              listenable: feed,
              builder: (context, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SessionBar(
                    link: widget.link,
                    feed: feed,
                    project: _project,
                    stoppingTasks: _stoppingTasks,
                    onStopTask: _stopTaskItem,
                  ),
                  if (feed.interaction != null)
                    _InteractionCard(
                      interaction: feed.interaction!,
                      onAnswer: (answer) => widget.link.answer(
                        _sessionId!,
                        InteractionCodec.encodeAnswer(answer),
                      ),
                    ),
                  if (_text.text.isEmpty)
                    _Suggestions(
                      feed: feed,
                      bot: widget.bot != null,
                      onPick: (text) {
                        _text.text = text;
                        _text.selection = TextSelection.collapsed(
                          offset: text.length,
                        );
                        setState(() {});
                      },
                      onSend: (text) {
                        _text.text = text;
                        _send();
                      },
                    ),
                  if (feed.queued.isNotEmpty)
                    _QueuePanel(
                      queued: feed.queued,
                      onQueue: (id, action, {index}) =>
                          _queue(id, action, index: index),
                      onEditQueued: (entry) {
                        // 撤回这一条，文字填进输入框（手机没有 draft：撤回后由
                        // 用户确认再发）。
                        final item = ChatCodec.decode(entry['item']);
                        final text = item is UserMessageItem ? item.text : '';
                        if (text.isNotEmpty) {
                          _text.text = text;
                          _text.selection = TextSelection.collapsed(
                            offset: text.length,
                          );
                        }
                        setState(() {});
                        _queue(entry['id']! as String, 'edit');
                      },
                    ),
                  _Composer(
                    controller: _text,
                    live: feed.live,
                    stopping: _stopping,
                    images: _images,
                    onChanged: _onComposerChanged,
                    onAttach: _attach,
                    onRemoveImage: (index) => setState(
                      () => _images = [..._images]..removeAt(index),
                    ),
                    onSend: _send,
                    onStop: _stop,
                  ),
                  _StatusLine(link: widget.link, feed: feed),
                ],
              ),
            )
          else
            _Composer(
              controller: _text,
              live: false,
              images: _images,
              onChanged: () => setState(() {}),
              onAttach: _attach,
              onRemoveImage: (index) =>
                  setState(() => _images = [..._images]..removeAt(index)),
              onSend: _send,
              onStop: _stop,
            ),
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

  String _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('offline') || lower.contains('closed')) {
      return describeLinkErrorCode('unreachable');
    }
    return raw;
  }

  /// A centered time divider above the item at [index], when more than
  /// five minutes passed since the last message with a time — a chat
  /// app's stamps between messages, not on them.
  Widget? _timeHeader(List<ChatItem?> items, int index) {
    DateTime? atOf(ChatItem? item) =>
        item is UserMessageItem ? item.sentAt : null;
    final at = atOf(items[index]);
    if (at == null) return null;
    for (var i = index - 1; i >= 0; i--) {
      final before = atOf(items[i]);
      if (before == null) continue;
      if (at.difference(before).abs() < const Duration(minutes: 5)) {
        return null;
      }
      break;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Center(
        child: Text(
          _formatStamp(at),
          style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
        ),
      ),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// HH:mm today, "昨天 HH:mm" yesterday, the date further back.
  static String _formatStamp(DateTime at) {
    final now = DateTime.now();
    final hm = '${_two(at.hour)}:${_two(at.minute)}';
    final day = DateTime(at.year, at.month, at.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return hm;
    if (diff == 1) return '昨天 $hm';
    if (at.year == now.year) return '${at.month}月${at.day}日';
    return '${at.year}/${at.month}/${at.day}';
  }

  Widget _body(SessionFeed? feed) {
    if (feed == null) {
      final wantsSession =
          _sessionId ?? widget.sessionId ?? widget.bot?.session;
      if (_opening || (wantsSession != null && linkWaitsForState(widget.link))) {
        return const Align(
          alignment: Alignment.topCenter,
          child: BSkeletonLines(lines: 5),
        );
      }
      if (wantsSession != null &&
          widget.link.phase != PhonePhase.online) {
        return LinkUnavailableBody(
          link: widget.link,
          offlineTitle: '会话未打开',
          offlineSubtitle: '连接恢复后会自动加载；也可以点「立即重连」。',
          onRetry: () {
            widget.link.retryNow();
            unawaited(_open(wantsSession));
          },
        );
      }
      if (wantsSession == null && widget.bot != null) {
        if (widget.link.phase != PhonePhase.online) {
          return LinkUnavailableBody(
            link: widget.link,
            offlineTitle: '电脑未连接',
            offlineSubtitle: '连接后即可开始与 Bot 聊天。',
            onRetry: widget.link.retryNow,
          );
        }
        return const BEmptyState(
          icon: Icons.forum_outlined,
          title: '说点什么开始聊天吧',
          subtitle: '发送第一条消息后，会话会在电脑上创建。',
        );
      }
      return BEmptyState(
        icon: Icons.forum_outlined,
        title: '会话未打开',
        subtitle: _error != null
            ? _friendlyError(_error!)
            : '与电脑连接后即可收发消息。',
        actionLabel: _error != null ? '重试' : '立即重连',
        onAction: () {
          final id = wantsSession;
          if (id != null) {
            unawaited(_open(id));
          } else {
            widget.link.retryNow();
          }
        },
      );
    }
    return ListenableBuilder(
      listenable: feed,
      builder: (context, _) {
        // Decoded once per JSON object, not per update: streaming
        // replaces the list but reuses the objects of items unchanged,
        // so decoding anew what was decoded is most of the work a frame
        // would do. (An Expando: the lists hold the keys, nothing keeps
        // them past the items themselves.)
        ChatItem? decode(Object json) =>
            switch (_decodeCache[json] ??=
                ChatCodec.decode(json) ?? _decodeMiss) {
              final ChatItem item => item,
              _ => null,
            };
        final items = [
          for (final json in feed.items) json == null ? null : decode(json),
        ];
        _decodedItems = items;
        // As the desktop's history folds: each run of quick steps into a
        // tally line, each finished turn's work into "已处理 …" before its
        // answer, the turn's figures under its last row.
        final folds = StepFolds.of(
          items.length,
          (i) => items[i] ?? const AssistantTextItem(''),
          live: feed.live,
        );
        // Opens on the newest message, and stays pinned to the bottom
        // while it is the bottom the user is at — the controller itself
        // holds the pin through layout as streaming grows the list.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scroll.hasClients) return;
          if (_firstOpen) {
            _firstOpen = false;
            _scroll.anchored = true;
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
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
              // As the desktop's: it re-anchors only at the very end, any
              // tolerance snapping a small scroll up straight back down.
              final position = _scroll.position;
              if (position.hasContentDimensions && !_animatingToBottom) {
                _scroll.anchored =
                    position.pixels >= position.maxScrollExtent - 1;
              }
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
              final stamp = _timeHeader(items, index);
              return KeyedSubtree(
                key: _keys.putIfAbsent(index, GlobalKey.new),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ?stamp,
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
                    // Hidden in a fold or shown out of it, the row stays in
                    // the tree: its coming and going glides (ExpandReveal)
                    // rather than popping the rows under it.
                    ExpandReveal(
                      show: row.item,
                      child: Padding(
                        // Breath between a message and what answers it:
                        // bubbles and prose are flush without it.
                        padding: item is UserMessageItem ||
                                item is AssistantTextItem
                            ? const EdgeInsets.symmetric(vertical: 5)
                            : EdgeInsets.zero,
                        child:
                            widget.bot != null && item is AssistantTextItem
                            ? _BotReply(
                                link: widget.link,
                                item: item,
                                bot: widget.bot!,
                              )
                            : ChatItemView(
                          item: folds.shownAt(index, item),
                          // As the desktop's: it opens to its own
                          // conversation, when it has one (its tool call's id).
                          onAgent: item is AgentItem && item.id != null
                              ? (agent) => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => AgentPage(
                                      feed: feed,
                                      agentId: agent.id!,
                                    ),
                                  ),
                                )
                              : null,
                          onStop: item is AgentItem &&
                                  _agentTask(item, feed) != null
                              ? () async {
                                  try {
                                    await widget.link.stopTask(
                                      feed.session,
                                      agent: item.id,
                                    );
                                  } on Object catch (failure) {
                                    if (context.mounted) {
                                      showBToast(context, '$failure');
                                    }
                                  }
                                }
                              : null,
                          onEditResend:
                    item is UserMessageItem && item.fromAgent == null
                    ? (text) => showEditResendSheet(
                        context: context,
                        link: widget.link,
                        feed: feed,
                        index: index,
                        initialText: text,
                      )
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
                      ),
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
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                // In and out with a slide as a header would, rather than
                // popping over the text under it.
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, -1),
                      end: Offset.zero,
                    ).animate(animation),
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: _stickyText != null
                      ? _StickyUserBar(
                          key: ValueKey(_stickyIndex),
                          text: _stickyText!,
                          onTap: _jumpToSticky,
                        )
                      : const SizedBox.shrink(),
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

  /// Where each user message's row stands in the list: its top in scroll
  /// offsets, and its height. Rows report it as they are laid out
  /// ([_MeasureRow]); relaid out — a fold opened, text scaled — they
  /// report it again, the entries of rows above one changed invalid then:
  /// they are dropped, and re-reported as the rows come up again.
  final Map<int, (double, double)> _positions = {};
  // The folds the history makes ([StepFolds]): which ones a click opened,
  // and which turns stay open once they were (see [_toggleFold]).
  final Map<(StepFoldKind, int), bool> _foldOpen = {};
  final Set<int> _unfoldedTurns = {};
  String? _stickyText;
  int _stickyIndex = -1;
  bool _showJump = false;
  bool _firstOpen = true;
  bool _atBottom = true;

  /// The user message of the turn at the top pins itself while its answers
  /// scroll under it. The rule is plain: the last user message whose
  /// bottom edge is above the viewport's top. Positions come from the
  /// rows themselves, reported as they are laid out ([_MeasureRow]), kept
  /// after the row leaves the tree — scrolling anywhere near them means
  /// they were laid out, so the map is complete where it matters.
  void _sticky(List<ChatItem?> items) {
    if (UserMessageStyle.current.value != UserMessageStyle.sticky ||
        !_scroll.hasClients ||
        !_scroll.position.hasContentDimensions) {
      if (_stickyText != null) setState(() => _stickyText = null);
      return;
    }
    final offset = _scroll.offset;
    // Rows in the tree re-report where they stand: a fold opened or
    // closed, the list reflowed — what the map has of them is refreshed.
    // Rows out of it keep what they last said: their position stands
    // until they are laid out again (nothing of them changes meanwhile:
    // a row's height is its content's, unchanged while away).
    for (var i = 0; i < items.length; i++) {
      if (items[i] is! UserMessageItem) continue;
      final ro = _keys[i]?.currentContext?.findRenderObject();
      if (ro is! RenderBox || !ro.attached || !ro.hasSize) continue;
      final viewport = RenderAbstractViewport.of(ro);
      _positions[i] = (viewport.getOffsetToReveal(ro, 0).offset, ro.size.height);
    }
    var index = -1;
    double? top;
    for (final entry in _positions.entries) {
      final i = entry.key;
      if (i >= items.length || items[i] is! UserMessageItem) continue;
      final (rowTop, height) = entry.value;
      if (rowTop + height <= offset + 1 && (index < 0 || rowTop > top!)) {
        index = i;
        top = rowTop;
      }
    }
    final pinnedText =
        index >= 0 ? (items[index] as UserMessageItem).text : null;
    final pinnedIndex = pinnedText == null ? -1 : index;
    _atBottom = _scroll.anchored;
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
    // Heights under it changed: the tops remembered no longer say where
    // rows are. They re-report as they are laid out again.
    _positions.clear();
  });

  /// The items [fold] holds (decode misses left out).
  static List<ChatItem> _itemsIn(StepFold fold, List<ChatItem?> items) => [
    for (var i = fold.start; i < fold.end; i++) ?items[i],
  ];

  /// The task [agent] runs as, if the session's tasks list one still
  /// running for it — the desktop's `stopOf`: the tool call that started
  /// it is its [AgentItem.id].
  static LinkTask? _agentTask(AgentItem agent, SessionFeed feed) {
    final id = agent.id;
    if (id == null) return null;
    for (final task in feed.tasks) {
      if (task.toolUseId == id && task.status == 'running') return task;
    }
    return null;
  }

  void _jumpToSticky() {
    if (_stickyIndex < 0 || !_scroll.hasClients) return;
    // Follow it again no longer: the user is headed up the list.
    _scroll.anchored = false;
    _animatingToBottom = true; // midway positions must not re-anchor
    _jumpToIndex(_stickyIndex).whenComplete(() {
      _animatingToBottom = false;
    });
  }

  /// Scrolls the row at [index] to the top of the viewport, whether or not
  /// it is built yet: built rows [Scrollable.ensureVisible] animates to;
  /// unbuilt ones are jumped near first — the estimate of their top, or
  /// as many rows up as they are — which builds them, then ensured.
  Future<void> _jumpToIndex(int index, [int hops = 0]) async {
    if (!mounted || !_scroll.hasClients || hops > 12) return;
    final ctx = _keys[index]?.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(
        ctx,
        alignment: 0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    final position = _scroll.position;
    final top = _positions[index]?.$1;
    if (top != null) {
      // Its last measured top: layouts of the same content repeat close
      // enough that the row is in view afterwards.
      _scroll.jumpTo(
        top.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    } else {
      // Never measured (the session opened at the bottom, this far above
      // never shown): a viewport up per hop, converging on it.
      final up = position.pixels - position.viewportDimension;
      _scroll.jumpTo(up.clamp(position.minScrollExtent, position.maxScrollExtent));
    }
    await WidgetsBinding.instance.endOfFrame;
    return _jumpToIndex(index, hops + 1);
  }

  void _jumpToBottom() {
    if (_scroll.hasClients) {
      // Headed for the end, however it lands: what is written is followed
      // again — midway positions of the animation itself must not drop it.
      _animatingToBottom = true;
      _scroll
          .animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      )
          .then((_) {
        _animatingToBottom = false;
        if (_scroll.hasClients &&
            _scroll.position.pixels >= _scroll.position.maxScrollExtent - 1) {
          _scroll.anchored = true;
        }
      });
    }
  }

  bool _animatingToBottom = false;

  Future<String?> _rename() =>
      showBPrompt(context, title: '重命名', initial: _title() ?? '');

  Future<bool> _confirm(String text) =>
      showBConfirm(context, title: text, confirm: '删除', danger: true);
}

/// The AppBar's second line: what the session is doing now, or where it
/// stands reaching the computer — the computer's name when nothing is
/// the more interesting answer.
class _Subtitle extends StatelessWidget {
  const _Subtitle({required this.link, this.feed, this.stopping = false});

  final PhoneLink link;
  final SessionFeed? feed;
  final bool stopping;

  @override
  Widget build(BuildContext context) {
    final listenables = <Listenable>[link, ?feed];
    return ListenableBuilder(
      listenable: Listenable.merge(listenables),
      builder: (context, _) {
        final String text;
        final Color color;
        if (link.phase != PhonePhase.online) {
          text = link.phase == PhonePhase.connecting ||
                  link.phase == PhonePhase.pairing
              ? '连接中…'
              : '离线，等待重连';
          color = AppColors.caution;
        } else if (stopping && (feed?.live ?? false)) {
          text = '正在停止…';
          color = AppColors.textMuted;
        } else if (feed?.live ?? false) {
          text = '正在输入…';
          color = AppColors.accent;
        } else {
          text = link.computer.name;
          color = AppColors.textMuted;
        }
        return Text(text, style: TextStyle(fontSize: 11, color: color));
      },
    );
  }
}

/// The composer's circular buttons: plus, stop, send — a tinted circle,
/// not the framework's filled IconButton.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.live,
    this.stopping = false,
    required this.images,
    required this.onChanged,
    required this.onAttach,
    required this.onRemoveImage,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final bool live;
  final bool stopping;
  final List<Map<String, Object?>> images;
  final VoidCallback onChanged;
  final VoidCallback onAttach;
  final void Function(int index) onRemoveImage;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final canSend = controller.text.trim().isNotEmpty || images.isNotEmpty;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.partBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
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
              stopping: stopping,
              canSend: canSend,
              onAttach: onAttach,
              onChanged: onChanged,
              onSend: onSend,
              onStop: onStop,
            ),
          ],
        ),
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
  const _SessionBar({
    required this.link,
    required this.feed,
    required this.project,
    required this.stoppingTasks,
    required this.onStopTask,
  });

  final PhoneLink link;
  final SessionFeed feed;
  final ProjectInfo? project;
  final Set<String> stoppingTasks;
  final Future<void> Function(LinkTask task) onStopTask;

  @override
  Widget build(BuildContext context) {
    // The plan awaiting, if the newest one is, plus any running foreground
    // subagents not already listed in `feed.tasks`.
    PlanItem? plan;
    final runningTasks = <LinkTask>[
      for (final task in feed.tasks)
        if (task.status == 'running') task,
    ];
    final taskAgentIds = <String>{
      for (final task in runningTasks)
        if (task.kind == 'agent') ...[task.id, ?task.toolUseId],
    };
    final agentItemsById = <String, AgentItem>{};
    final runningAgents = <LinkTask>[];
    for (final json in feed.items.reversed) {
      final item = ChatCodec.decode(json);
      if (plan == null && item is PlanItem) {
        plan = item;
      }
      if (item is AgentItem) {
        final agentId = item.id;
        if (agentId != null) {
          agentItemsById.putIfAbsent(agentId, () => item);
        }
        if (item.status == CommandStatus.running) {
          if (agentId != null && taskAgentIds.contains(agentId)) continue;
          if (agentId != null) taskAgentIds.add(agentId);
          runningAgents.add(
            LinkTask(
              id: agentId ?? item.description,
              kind: 'agent',
              description: item.description.isNotEmpty
                  ? item.description
                  : (item.agentType ?? '子代理'),
              status: 'running',
              startedAt: item.startedAt ?? DateTime.now(),
              toolUseId: agentId,
              summary: item.activity ?? item.lastTool,
            ),
          );
        }
      }
    }
    final activeTasks = <LinkTask>[
      ...runningTasks,
      ...runningAgents.reversed,
    ];
    final awaitingPlan = plan?.status == PlanStatus.awaiting;
    final changes = feed.changes;
    final goal = feed.goal;
    if (!awaitingPlan &&
        changes.isEmpty &&
        activeTasks.isEmpty &&
        goal == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (goal != null)
            Padding(
              padding: EdgeInsets.only(
                bottom:
                    (awaitingPlan ||
                        changes.isNotEmpty ||
                        activeTasks.isNotEmpty)
                    ? 6
                    : 2,
              ),
              child: _GoalCard(goal: goal),
            ),
          if (awaitingPlan || changes.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: activeTasks.isNotEmpty ? 6 : 2),
              child: BCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (awaitingPlan)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.fact_check_outlined,
                              size: 20,
                              color: AppColors.accent,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '计划已就绪：${plan!.name}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            BButton(
                              label: '开始',
                              primary: true,
                              onPressed: () => _run(
                                context,
                                () => link.startPlan(feed.session),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (changes.isNotEmpty)
                      InkWell(
                        onTap: () => _showChanges(context, changes),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
                          child: Row(
                            children: [
                              Icon(
                                Icons.difference_outlined,
                                size: 17,
                                color: AppColors.accent,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        _changesLabel(changes),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      size: 16,
                                      color: AppColors.textFaint,
                                    ),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: () => _run(
                                  context,
                                  () => link.undo(feed.session),
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.textMuted,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  minimumSize: const Size(0, 32),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  '撤回',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),
                              TextButton(
                                onPressed: () => _run(
                                  context,
                                  () => link.keep(feed.session),
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.accent,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  minimumSize: const Size(0, 32),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  '保留',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          // 正在运行的子代理/命令直接复用聊天界面的中性卡片样式，无多余外框与绿底。
          for (final task in activeTasks)
            _buildActiveTask(context, task, agentItemsById),
        ],
      ),
    );
  }

  Widget _buildActiveTask(
    BuildContext context,
    LinkTask task,
    Map<String, AgentItem> agentItemsById,
  ) {
    final key = task.toolUseId ?? task.id;
    final stopping = stoppingTasks.contains(key);
    if (task.kind == 'agent') {
      final agentItem =
          agentItemsById[task.toolUseId] ?? agentItemsById[task.id];
      if (agentItem != null) {
        return AgentStep(
          item: agentItem,
          onOpen: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AgentPage(
                feed: feed,
                agentId: task.toolUseId ?? task.id,
              ),
            ),
          ),
          onStop: stopping ? null : () => onStopTask(task),
        );
      }
    }
    return _TaskTile(
      link: link,
      feed: feed,
      task: task,
      stopping: stopping,
      onStop: () => onStopTask(task),
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

  void _showChanges(
    BuildContext context,
    List<Map<String, Object?>> changes,
  ) {
    PhonePlatform.haptic('selection');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _ChangesSheet(
        link: link,
        session: feed.session,
        project: project,
        changes: changes,
      ),
    );
  }
}

/// Compact `/goal` progress card docked above the composer.
class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal});

  final Map<String, Object?> goal;

  @override
  Widget build(BuildContext context) {
    final condition = (goal['condition'] as String? ?? '').trim();
    if (condition.isEmpty) return const SizedBox.shrink();
    final state = (goal['state'] as String? ?? '').toLowerCase();
    final checks = (goal['checks'] as num?)?.toInt();
    final durationMs = (goal['duration'] as num?)?.toInt();
    final (label, color) = switch (state) {
      'met' || 'done' || 'succeeded' => ('已达成', AppColors.accent),
      'stopped' || 'cancelled' || 'failed' => ('已停止', AppColors.textMuted),
      _ => ('目标进行中', AppColors.caution),
    };
    final meta = <String>[
      if (checks != null && checks > 0) '已检查 $checks 次',
      if (durationMs != null && durationMs > 0)
        _formatDuration(Duration(milliseconds: durationMs)),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.partBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.flag_rounded, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  condition,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (meta.isNotEmpty)
                  Text(
                    meta.join(' · '),
                    style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: MdTheme.dark ? 0.2 : 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDuration(Duration d) {
    final s = d.inSeconds;
    if (s < 60) return '$s秒';
    final m = d.inMinutes;
    if (m < 60) return '$m分${s % 60}秒';
    return '${d.inHours}小时${m % 60}分';
  }
}

/// Bottom sheet listing all changed files in the session with per-file Keep /
/// Undo and tap-to-view Diff via [FileViewer].
class _ChangesSheet extends StatelessWidget {
  const _ChangesSheet({
    required this.link,
    required this.session,
    required this.project,
    required this.changes,
  });

  final PhoneLink link;
  final String session;
  final ProjectInfo? project;
  final List<Map<String, Object?>> changes;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 12, 10),
              child: Row(
                children: [
                  Text(
                    '文件变更 (${changes.length})',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      try {
                        await link.undo(session);
                      } on Object catch (e) {
                        if (context.mounted) showBToast(context, '$e', isError: true);
                      }
                    },
                    child: Text(
                      '全部撤回',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                  BButton(
                    label: '全部保留',
                    primary: true,
                    onPressed: () async {
                      Navigator.of(context).pop();
                      try {
                        await link.keep(session);
                      } on Object catch (e) {
                        if (context.mounted) showBToast(context, '$e', isError: true);
                      }
                    },
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                itemCount: changes.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 0.5, indent: 44, color: AppColors.partBorder),
                itemBuilder: (context, index) {
                  final change = changes[index];
                  final path = change['path'] as String? ?? '';
                  final added = (change['added'] as num?)?.toInt() ?? 0;
                  final removed = (change['removed'] as num?)?.toInt() ?? 0;
                  final slash = path.lastIndexOf('/');
                  final name = slash < 0 ? path : path.substring(slash + 1);
                  final dir = slash < 0 ? '' : path.substring(0, slash);
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: project == null || path.isEmpty
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => FileViewer(
                                  link: link,
                                  project: project!,
                                  path: path,
                                ),
                              ),
                            );
                          },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 9,
                      ),
                      child: Row(
                        children: [
                          BFileIcon(name: name, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                if (dir.isNotEmpty)
                                  Text(
                                    dir,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (added > 0)
                            Text(
                              '+$added',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.added,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          if (removed > 0) ...[
                            const SizedBox(width: 5),
                            Text(
                              '-$removed',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.removed,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                          if (project != null) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: AppColors.textFaint,
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A task the session runs or ran, styled to match [AgentStep]'s neutral card.
class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.link,
    required this.feed,
    required this.task,
    this.stopping = false,
    this.onStop,
  });

  final PhoneLink link;
  final SessionFeed feed;
  final LinkTask task;
  final bool stopping;
  final VoidCallback? onStop;

  String get session => feed.session;

  @override
  Widget build(BuildContext context) {
    final running = task.status == 'running';
    final title = task.description.isNotEmpty
        ? task.description
        : task.command ?? task.kind;
    final isAgent = task.kind == 'agent';
    final opens = isAgent || task.output;
    final showSummary =
        task.summary != null &&
        task.summary != title &&
        !title.startsWith(task.summary!) &&
        !task.summary!.startsWith(title);
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: !opens
            ? null
            : () {
                if (isAgent) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AgentPage(
                        feed: feed,
                        agentId: task.toolUseId ?? task.id,
                      ),
                    ),
                  );
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => OutputPage(
                        link: link,
                        session: session,
                        task: task,
                      ),
                    ),
                  );
                }
              },
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.partBorder),
          ),
          child: Row(
            children: [
              if (running)
                (isAgent
                    ? const PixelLoader.subagent(size: 14)
                    : const PixelLoader.agent(size: 14))
              else
                Icon(
                  isAgent ? Codicons.hubot : Icons.terminal,
                  size: 14,
                  color: AppColors.textMuted,
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: running
                          ? ShimmerText(
                              title,
                              ellipsis: false,
                              padding: EdgeInsets.zero,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            )
                          : Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary,
                              ),
                            ),
                    ),
                    if (showSummary)
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text(
                            '· ${task.summary!}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textFaint,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (running &&
                  (!isAgent ||
                      task.toolUseId != null ||
                      feed.tasks.any((t) => t.id == task.id)))
                stopping
                    ? Padding(
                        padding: const EdgeInsets.all(6),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            color: AppColors.textMuted,
                          ),
                        ),
                      )
                    : _tileAction(
                        context,
                        tooltip: '停止',
                        icon: Icons.stop_circle_outlined,
                        color: AppColors.textMuted,
                        onTap: onStop ?? () {},
                      ),
              if (opens)
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// A small round action button at a task tile's right edge.
  Widget _tileAction(
    BuildContext context, {
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
    Color? color,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: color ?? AppColors.textMuted),
        ),
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
      backgroundColor: AppColors.conversationSurface,
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.accent))
          : _error != null
          ? BEmptyState(
              icon: Icons.error_outline,
              title: '无法加载输出',
              subtitle: '$_error',
            )
          : ListenableBuilder(
              listenable: widget.link,
              builder: (context, _) {
                final output = widget.link.outputs[_key]?.text ?? '';
                return output.isEmpty
                    ? const BEmptyState(
                        icon: Icons.terminal_outlined,
                        title: '暂无输出',
                        subtitle: '任务运行后会在这里显示终端输出。',
                      )
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
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
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
    final contextInfo = feed.context;
    final used = contextInfo?['used'];
    final window = contextInfo?['window'];
    if (contextInfo != null && used is num && window is num && window > 0) {
      if (children.isNotEmpty) children.add(const SizedBox(width: 8));
      children.add(
        _StatusChip(
          icon: Codicons.pieChart,
          label: '${_tokens(used)} / ${_tokens(window)}',
          onTap: () => _showContextUsage(context, contextInfo),
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

  void _showContextUsage(BuildContext context, Map<String, Object?> info) {
    PhonePlatform.haptic('selection');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _ContextUsageSheet(info: info),
    );
  }

  /// A provider brand icon for a model/option id, from the official app's
  /// extracted `assets/model_icons`. The matching is the desktop's
  /// `ModelBrand.ofModel` ported: a word of the id (after its start or a
  /// separator), the family before the vendor.
  static Widget? _modelIcon(String id) {
    final brand = _modelBrand(id);
    if (brand == null) return null;
    return SvgPicture.asset(
      'assets/model_icons/$brand.svg',
      width: 20,
      height: 20,
      // In the text's color, as the desktop draws them in one color.
      colorFilter: ColorFilter.mode(AppColors.text, BlendMode.srcIn),
    );
  }

  static String? _modelBrand(String id) {
    final name = id.toLowerCase();
    for (final (pattern, brand) in _brandPatterns) {
      if (pattern.hasMatch(name)) return brand;
    }
    return null;
  }

  /// A word of a model's name, after its start or a separator — as the
  /// desktop's `_word`.
  static RegExp _word(String pattern) =>
      RegExp('(^|[/_.: -])(?:$pattern)', caseSensitive: false);

  static final _brandPatterns = [
    (_word('claude|anthropic'), 'claude'),
    (_word(r'gemini'), 'gemini'),
    (_word(r'gemma'), 'google'),
    (_word(r'deepseek'), 'deepseek'),
    (_word(r'qwen|qwq|qvq'), 'qwen'),
    (_word(r'glm|chatglm|codegeex|cogview|zhipu'), 'zhipu'),
    (_word(r'kimi|moonshot'), 'kimi'),
    (_word(r'minimax|abab'), 'minimax'),
    (_word(r'doubao'), 'doubao'),
    (_word(r'seed'), 'bytedance'),
    (_word(r'hunyuan'), 'hunyuan'),
    (_word(r'ernie|wenxin'), 'wenxin'),
    (_word(r'step-'), 'stepfun'),
    (_word(r'baichuan'), 'baichuan'),
    (_word(r'yi-'), 'yi'),
    (_word(r'grok|xai'), 'xai'),
    (
      _word(r'mistral|mixtral|codestral|devstral|magistral|ministral|pixtral'),
      'mistral',
    ),
    (_word(r'llama'), 'meta'),
    (_word(r'phi-'), 'microsoft'),
    (_word(r'nemotron|nvidia'), 'nvidia'),
    (_word(r'sonar|perplexity'), 'perplexity'),
    // Last, as the most general: `o3` alone, or `o3-mini`.
    (_word(r'gpt|chatgpt|codex|openai|o\d+(?:$|[-_.: ])'), 'openai'),
  ];

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
              ? AppColors.caution.withValues(alpha: MdTheme.dark ? 0.14 : 0.10)
              : AppColors.bubbleFill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: accent
                ? AppColors.caution.withValues(alpha: 0.3)
                : AppColors.partBorder,
            width: 0.75,
          ),
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

/// Bottom sheet displaying the session's context window usage breakdown
/// (`used`, `window`, `compactAt`, and `parts`).
class _ContextUsageSheet extends StatelessWidget {
  const _ContextUsageSheet({required this.info});

  final Map<String, Object?> info;

  static const _partColors = <String, Color>{
    'system': Color(0xFF6366F1),
    'tools': Color(0xFF3B82F6),
    'mcp': Color(0xFF8B5CF6),
    'memory': Color(0xFF14B8A6),
    'skills': Color(0xFFF59E0B),
    'messages': Color(0xFF10B981),
  };

  static const _fallbackColors = [
    Color(0xFF06B6D4),
    Color(0xFFEC4899),
    Color(0xFF84CC16),
    Color(0xFFF97316),
  ];

  static String _partLabel(String key) => switch (key.toLowerCase()) {
    'system' => '系统提示词',
    'tools' => '内置工具',
    'mcp' => 'MCP 工具',
    'memory' => '记忆',
    'skills' => '技能',
    'messages' => '对话消息',
    _ => key,
  };

  static Color _colorOf(String key, int index) =>
      _partColors[key.toLowerCase()] ??
      _fallbackColors[index % _fallbackColors.length];

  static String _pct(num value, num total) {
    if (total <= 0) return '0%';
    final p = (value / total * 100).clamp(0, 100);
    return p >= 10 ? '${p.toStringAsFixed(0)}%' : '${p.toStringAsFixed(1)}%';
  }

  @override
  Widget build(BuildContext context) {
    final used = (info['used'] as num?) ?? 0;
    final window = (info['window'] as num?) ?? 1;
    final compactAt = info['compactAt'] as num?;
    final remaining = math.max(0, window - used);
    final ratio = (used / window).clamp(0.0, 1.0);
    final statusColor = ratio >= 0.85
        ? AppColors.removed
        : ratio >= 0.65
        ? AppColors.caution
        : AppColors.accent;
    final rawParts = info['parts'];
    final parts = <(String key, num tokens)>[
      if (rawParts is List)
        for (final entry in rawParts)
          if (entry is Map &&
              entry['part'] is String &&
              entry['tokens'] is num &&
              (entry['tokens'] as num) > 0)
            (entry['part'] as String, entry['tokens'] as num),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  '上下文用量',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(
                      alpha: MdTheme.dark ? 0.2 : 0.12,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _pct(used, window),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            BCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        _StatusLine._tokens(used),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        ' / ${_StatusLine._tokens(window)} tokens',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '剩余 ${_StatusLine._tokens(remaining)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final compactLeft =
                          compactAt != null && compactAt > 0 && compactAt < window
                          ? (compactAt / window).clamp(0.0, 1.0) * width
                          : null;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              height: 10,
                              color: AppColors.bubbleFill,
                              child: Row(
                                children: [
                                  if (parts.isNotEmpty)
                                    for (final (i, (key, tokens))
                                        in parts.indexed)
                                      Container(
                                        width: (tokens / window).clamp(0.0, 1.0) *
                                            width,
                                        color: _colorOf(key, i),
                                      )
                                  else
                                    Container(
                                      width: ratio * width,
                                      color: statusColor,
                                    ),
                                ],
                              ),
                            ),
                          ),
                          if (compactLeft != null)
                            Positioned(
                              left: compactLeft.clamp(0, width - 2),
                              top: -2,
                              bottom: -2,
                              child: Container(
                                width: 2,
                                decoration: BoxDecoration(
                                  color: AppColors.caution,
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  if (compactAt != null && compactAt > 0) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: AppColors.caution,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '自动压缩阈值：${_StatusLine._tokens(compactAt)} (${_pct(compactAt, window)})',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            BCard(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              child: Column(
                children: [
                  if (parts.isNotEmpty)
                    for (final (i, (key, tokens)) in parts.indexed) ...[
                      _usageRow(
                        color: _colorOf(key, i),
                        label: _partLabel(key),
                        tokens: tokens,
                        window: window,
                      ),
                      Divider(height: 0.5, color: AppColors.partBorder),
                    ]
                  else ...[
                    _usageRow(
                      color: statusColor,
                      label: '已占用',
                      tokens: used,
                      window: window,
                    ),
                    Divider(height: 0.5, color: AppColors.partBorder),
                  ],
                  _usageRow(
                    color: AppColors.borderStrong,
                    label: '剩余可用',
                    tokens: remaining,
                    window: window,
                    muted: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _usageRow({
    required Color color,
    required String label,
    required num tokens,
    required num window,
    bool muted = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              color: muted ? AppColors.textMuted : AppColors.textPrimary,
            ),
          ),
        ),
        Text(
          _StatusLine._tokens(tokens),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: muted ? AppColors.textMuted : AppColors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 44,
          child: Text(
            _pct(tokens, window),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textMuted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    ),
  );
}

/// The messages sent while the agent works, waiting their turn, docked
/// above the composer: each can be taken back to edit, sent at once (the
/// turn running stopped for it), or taken back — the desktop's
/// QueuePanel, without its drag ordering.
class _QueuePanel extends StatelessWidget {
  const _QueuePanel({
    required this.queued,
    required this.onQueue,
    required this.onEditQueued,
  });

  /// `{"id", "item"}` each, the next first.
  final List<Map<String, Object?>> queued;

  /// `(id, action)` — `remove`/`sendNow`/`edit`/`move`.
  final void Function(String id, String action, {int? index}) onQueue;

  /// The entry to take back into the composer.
  final void Function(Map<String, Object?> entry) onEditQueued;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: BCard(
        padding: const EdgeInsets.fromLTRB(12, 8, 10, 6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 196),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 14,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '排队等待中 · ${queued.length} 条',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: queued.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 0.5, color: AppColors.partBorder),
                  itemBuilder: (_, index) {
                    final entry = queued[index];
                    return _QueuedRow(
                      order: index + 1,
                      entry: entry,
                      onEdit: () => onEditQueued(entry),
                      onSendNow: () =>
                          onQueue(entry['id']! as String, 'sendNow'),
                      onRemove: () =>
                          onQueue(entry['id']! as String, 'remove'),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QueuedRow extends StatelessWidget {
  const _QueuedRow({
    required this.order,
    required this.entry,
    required this.onEdit,
    required this.onSendNow,
    required this.onRemove,
  });

  final int order;
  final Map<String, Object?> entry;
  final VoidCallback onEdit;
  final VoidCallback onSendNow;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final item = ChatCodec.decode(entry['item']);
    final text = item is UserMessageItem
        ? item.text.replaceAll(RegExp(r'\s+'), ' ').trim()
        : '';
    final images = item is UserMessageItem ? item.images.length : 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.bubbleFill,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$order',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onEdit,
              child: Text(
                [
                  if (text.isNotEmpty) text,
                  if (images > 0) '$images 张图片',
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.3,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onSendNow,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(
                  alpha: MdTheme.dark ? 0.18 : 0.12,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '立即发',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          _QueueAction(
            icon: Icons.edit_outlined,
            tooltip: '编辑',
            onTap: onEdit,
          ),
          _QueueAction(
            icon: Icons.close_rounded,
            tooltip: '移除',
            onTap: onRemove,
          ),
        ],
      ),
    );
  }
}

class _QueueAction extends StatelessWidget {
  const _QueueAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 17, color: AppColors.textMuted),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: onTap,
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
  const _BotReply({
    required this.link,
    required this.item,
    required this.bot,
  });

  final PhoneLink link;
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
          BotAvatar(link: link, bot: bot, size: 34),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                border: Border.all(color: AppColors.partBorder, width: 0.75),
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
/// answers below it scroll — a small echo of the bubble itself rather
/// than a bar: the user's green, rounded, a tap scrolling back to it.
class _StickyUserBar extends StatelessWidget {
  const _StickyUserBar({super.key, required this.text, this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      // What is under it shows through the ends of the fade: the list's own
      // background, not a bar across it.
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.conversationSurface,
            AppColors.conversationSurface.withValues(alpha: 0.0),
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.userBubble,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.userBubble.withValues(alpha: 0.6),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.onUserBubble,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.keyboard_arrow_up_rounded,
                size: 16,
                color: AppColors.onUserBubble.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Searchable bottom sheet for picking a file from the current workspace to
/// insert as `@path` into the chat composer.
class _WorkspaceFilePickerSheet extends StatefulWidget {
  const _WorkspaceFilePickerSheet({
    required this.link,
    required this.project,
  });

  final PhoneLink link;
  final ProjectInfo project;

  @override
  State<_WorkspaceFilePickerSheet> createState() =>
      _WorkspaceFilePickerSheetState();
}

class _WorkspaceFilePickerSheetState extends State<_WorkspaceFilePickerSheet> {
  final _query = TextEditingController();
  List<String> _paths = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.link.files(widget.project.id);
      final raw = result['paths'];
      final paths = <String>[
        for (final p in raw is List ? raw : const [])
          if (p is String && p.isNotEmpty) p,
      ];
      if (mounted) {
        setState(() {
          _paths = paths;
          _loading = false;
        });
      }
    } on Object catch (failure) {
      if (mounted) {
        setState(() {
          _error = '$failure';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final needle = _query.text.trim().toLowerCase();
    final filtered = needle.isEmpty
        ? _paths.take(200).toList()
        : _paths
              .where((p) => p.toLowerCase().contains(needle))
              .take(200)
              .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '@ ${widget.project.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (!_loading && _error == null)
                    Text(
                      '${_paths.length} 个文件',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textFaint,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                controller: _query,
                autofocus: true,
                style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                decoration: BTextField.decoration(hint: '搜索文件名或路径…'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(color: AppColors.accent),
                    )
                  : _error != null
                  ? BEmptyState(
                      icon: Icons.cloud_off_outlined,
                      title: '无法加载文件列表',
                      subtitle: _error,
                      actionLabel: '重试',
                      onAction: _load,
                    )
                  : filtered.isEmpty
                  ? const BEmptyState(
                      icon: Codicons.search,
                      title: '没有匹配的文件',
                      subtitle: '换个关键词试试。',
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const BDivider(),
                      itemBuilder: (context, index) {
                        final path = filtered[index];
                        final slash = path.lastIndexOf('/');
                        final name = slash < 0 ? path : path.substring(slash + 1);
                        final dir = slash < 0 ? '' : path.substring(0, slash);
                        return InkWell(
                          onTap: () => Navigator.of(context).pop(path),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                BFileIcon(name: name, size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      if (dir.isNotEmpty)
                                        Text(
                                          dir,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: AppColors.textMuted,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
