import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io';

import 'package:bao_link/bao_link.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat/chat_models.dart' show ImageAttachment;
import '../codicons.dart';
import '../link/phone_link.dart';
import '../phone_platform.dart';
import 'items/image_preview.dart';
import 'link_status.dart';
import 'md/md_theme.dart';
import 'widgets.dart';
import '../ui/markdown.dart';

/// A group chat of the user and bots: its messages, image attachments,
/// earlier-history pagination, live typing status, and the composer.
class GroupPage extends StatefulWidget {
  const GroupPage({super.key, required this.link, required this.group});

  final PhoneLink link;
  final LinkGroup group;

  @override
  State<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<GroupPage> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  GroupFeed? _feed;
  bool _busy = false;
  bool _opening = false;
  bool _loadingEarlier = false;
  List<Map<String, Object?>> _images = const [];
  LinkGroupMessage? _replyTo;

  LinkGroup get _currentGroup =>
      widget.link.state?.groups
          .where((g) => g.id == widget.group.id)
          .firstOrNull ??
      widget.group;

  @override
  void initState() {
    super.initState();
    widget.link.addListener(_onLinkChanged);
    _scroll.addListener(_onScroll);
    _feed = widget.link.groups[widget.group.id];
    unawaited(_open());
  }

  @override
  void dispose() {
    widget.link.removeListener(_onLinkChanged);
    _scroll.removeListener(_onScroll);
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final feed = _feed;
    if (feed == null || !feed.more || _loadingEarlier || !_scroll.hasClients) {
      return;
    }
    if (_scroll.position.pixels <= 80) {
      unawaited(_loadEarlier());
    }
  }

  Future<void> _loadEarlier() async {
    if (_loadingEarlier) return;
    setState(() => _loadingEarlier = true);
    try {
      await widget.link.earlierGroup(widget.group.id);
    } on Object {
      // Best-effort pagination.
    } finally {
      if (mounted) setState(() => _loadingEarlier = false);
    }
  }

  void _onLinkChanged() {
    if (!mounted) return;
    if (widget.link.phase == PhonePhase.online) {
      final liveFeed = widget.link.groups[widget.group.id];
      if (liveFeed != null && !identical(_feed, liveFeed)) {
        _feed = liveFeed;
      } else if (_feed == null && !_opening) {
        unawaited(_open());
      }
    }
    setState(() {});
  }

  Future<void> _open() async {
    if (_opening) return;
    _opening = true;
    try {
      final feed = await widget.link.openGroup(widget.group.id);
      if (mounted) {
        setState(() => _feed = feed);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
      }
    } on Object {
      // A feed that failed to open stays empty; retried when online again.
    } finally {
      _opening = false;
    }
  }

  Future<void> _attach() async {
    final kind = await showBActions<String>(
      context,
      actions: const [
        (Codicons.deviceCamera, '拍照', '拍摄照片发到群里', 'camera'),
        (Icons.photo_library_outlined, '图片', '从相册选择图片', 'image'),
      ],
    );
    if (kind == 'camera') {
      final path = await PhonePlatform.takePhoto();
      if (path == null || !mounted) return;
      final file = File(path);
      try {
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        if (bytes.length > 8 * 1024 * 1024) {
          showBToast(context, '照片超过 8 MB', isError: true);
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
      } finally {
        unawaited(file.delete().catchError((Object _) => file));
      }
    } else if (kind == 'image') {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'gif', 'webp'],
      );
      if (files.isEmpty || !mounted) return;
      final added = <Map<String, Object?>>[];
      for (final file in files) {
        final bytes = await file.readAsBytes();
        if (bytes.length > 8 * 1024 * 1024) continue;
        final ext = (file.extension ?? '').toLowerCase();
        final mime = switch (ext) {
          'png' => 'image/png',
          'gif' => 'image/gif',
          'webp' => 'image/webp',
          _ => 'image/jpeg',
        };
        added.add({
          'data': base64Encode(bytes),
          'type': mime,
          'name': file.name,
        });
      }
      if (added.isNotEmpty && mounted) {
        setState(() => _images = [..._images, ...added]);
      }
    }
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if ((text.isEmpty && _images.isEmpty) || _busy) return;
    final images = _images;
    final replyRef = _replyTo?.seq;
    _text.clear();
    setState(() {
      _images = const [];
      _replyTo = null;
      _busy = true;
    });
    try {
      await widget.link.sendGroup(
        widget.group.id,
        text: text,
        images: images,
        ref: replyRef,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        }
      });
    } on Object {
      if (mounted) {
        // Restore unsent draft on failure.
        if (_text.text.isEmpty && text.isNotEmpty) {
          _text.text = text;
          _text.selection = TextSelection.collapsed(offset: text.length);
        }
        if (_images.isEmpty && images.isNotEmpty) {
          _images = images;
        }
        showBToast(context, '发送失败', isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _nameOf(String id) {
    if (id == 'user' || id == 'me') return '我';
    for (final bot in widget.link.state?.bots ?? const []) {
      if (bot.id == id) return bot.name;
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    final feed = _feed;
    final group = _currentGroup;
    final typingNames = [for (final id in group.typing) _nameOf(id)];
    final subtitle = typingNames.isNotEmpty
        ? '${typingNames.join('、')} 正在输入…'
        : group.members.isNotEmpty
        ? '${group.members.length} 位成员'
        : null;
    final canSend = _text.text.trim().isNotEmpty || _images.isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.conversationSurface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(group.name, style: const TextStyle(fontSize: 17)),
            if (subtitle != null)
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: typingNames.isNotEmpty
                      ? AppColors.accent
                      : AppColors.textMuted,
                ),
              ),
          ],
        ),
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
          Expanded(
            child: feed == null
                ? widget.link.phase != PhonePhase.online
                    ? LinkUnavailableBody(
                        link: widget.link,
                        offlineTitle: '无法加载群聊',
                        offlineSubtitle: '连接恢复后会自动加载群消息。',
                        onRetry: () => widget.link.retryNow(force: true),
                      )
                    : const Align(
                        alignment: Alignment.topCenter,
                        child: BSkeletonLines(lines: 5),
                      )
                : ListenableBuilder(
                    listenable: feed,
                    builder: (context, _) => ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      itemCount: feed.messages.length + (_loadingEarlier ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (_loadingEarlier && index == 0) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.accent,
                                ),
                              ),
                            ),
                          );
                        }
                        final msgIndex = _loadingEarlier ? index - 1 : index;
                        final message = feed.messages[msgIndex];
                        return _message(context, message);
                      },
                    ),
                  ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.background,
              border: Border(
                top: BorderSide(color: AppColors.partBorder, width: 0.5),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_replyTo != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.bubbleFill,
                          borderRadius: BorderRadius.circular(10),
                          border: Border(
                            left: BorderSide(color: AppColors.accent, width: 3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '回复 ${_nameOf(_replyTo!.from)}：${_replyTo!.text.replaceAll(RegExp(r'\s+'), ' ').trim()}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => setState(() => _replyTo = null),
                              child: Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Icon(
                                  Codicons.close,
                                  size: 14,
                                  color: AppColors.textFaint,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_images.isNotEmpty)
                      SizedBox(
                        height: 62,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.only(bottom: 6),
                          itemCount: _images.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 6),
                          itemBuilder: (_, i) => Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  base64Decode(_images[i]['data']! as String),
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 0,
                                right: 0,
                                child: GestureDetector(
                                  onTap: () => setState(
                                    () => _images = [..._images]..removeAt(i),
                                  ),
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
                      ),
                    BComposer(
                      controller: _text,
                      hint: '向群里发消息…',
                      canSend: canSend,
                      onAttach: _attach,
                      onChanged: () => setState(() {}),
                      onSend: _send,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onMessageActions(LinkGroupMessage message) async {
    PhonePlatform.haptic('longPress');
    final action = await showBActions<String>(
      context,
      actions: const [
        (Icons.reply_rounded, '引用回复', null, 'reply'),
        (Icons.copy_outlined, '复制内容', null, 'copy'),
      ],
    );
    if (action == null || !mounted) return;
    if (action == 'reply') {
      setState(() => _replyTo = message);
    } else if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: message.text));
      if (mounted) showBToast(context, '已复制');
    }
  }

  LinkGroupMessage? _findRef(int? seq) {
    if (seq == null) return null;
    for (final m in _feed?.messages ?? const <LinkGroupMessage>[]) {
      if (m.seq == seq) return m;
    }
    return null;
  }

  Widget _message(BuildContext context, LinkGroupMessage message) {
    final mine = message.from == 'user' || message.from == 'me';
    final refMsg = _findRef(message.ref);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _onMessageActions(message),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.8,
          ),
          decoration: BoxDecoration(
            color: mine ? AppColors.userBubble : AppColors.surfaceRaised,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 5),
              bottomRight: Radius.circular(mine ? 5 : 16),
            ),
            border: Border.all(
              color: mine
                  ? AppColors.accent.withValues(alpha: MdTheme.dark ? 0.25 : 0.2)
                  : AppColors.partBorder,
              width: 0.75,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mine) ...[
                Text(
                  _nameOf(message.from),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
              ],
              if (refMsg != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(
                      alpha: MdTheme.dark ? 0.18 : 0.05,
                    ),
                    borderRadius: BorderRadius.circular(6),
                    border: Border(
                      left: BorderSide(color: AppColors.accent, width: 2),
                    ),
                  ),
                  child: Text(
                    '${_nameOf(refMsg.from)}: ${refMsg.text.replaceAll(RegExp(r'\s+'), ' ').trim()}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                  ),
                ),
              if (message.text.isNotEmpty)
                DefaultTextStyle.merge(
                  style: TextStyle(
                    color: mine ? AppColors.onUserBubble : AppColors.text,
                  ),
                  child: ChatMarkdown(text: message.text),
                ),
              if (message.images.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _GroupImageThumb(
                    link: widget.link,
                    groupId: widget.group.id,
                    seq: message.seq,
                    count: message.images.length,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupImageThumb extends StatefulWidget {
  const _GroupImageThumb({
    required this.link,
    required this.groupId,
    required this.seq,
    required this.count,
  });

  final PhoneLink link;
  final String groupId;
  final int seq;
  final int count;

  @override
  State<_GroupImageThumb> createState() => _GroupImageThumbState();
}

class _GroupImageThumbState extends State<_GroupImageThumb> {
  static final Map<String, ({Uint8List bytes, String type})> _cache = {};
  ({Uint8List bytes, String type})? _loaded;

  String get _key => '${widget.groupId}:${widget.seq}';

  @override
  void initState() {
    super.initState();
    _loaded = _cache[_key];
    if (_loaded == null) _fetch();
  }

  Future<void> _fetch() async {
    try {
      final result = await widget.link.groupImage(widget.groupId, widget.seq);
      final data = result['data'];
      if (data is! String || data.isEmpty) return;
      final entry = (
        bytes: base64Decode(data),
        type: result['type'] as String? ?? 'image/jpeg',
      );
      _cache[_key] = entry;
      if (mounted) setState(() => _loaded = entry);
    } on Object {
      // Leave fallback label on failure.
    }
  }

  @override
  Widget build(BuildContext context) {
    final loaded = _loaded;
    if (loaded == null) {
      return Text(
        '${widget.count} 张图片',
        style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
      );
    }
    return GestureDetector(
      onTap: () => showImagePreview(
        context,
        ImageAttachment(bytes: loaded.bytes, mediaType: loaded.type),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          loaded.bytes,
          width: 180,
          height: 140,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}
