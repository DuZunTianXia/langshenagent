import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bao_link/bao_link.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../link/phone_link.dart';
import '../phone_platform.dart';
import 'md/md_theme.dart';
import 'widgets.dart';

/// A bot's settings (the official's bot profile editor): name, signature,
/// who it is, its abilities and the model it talks on — the model through
/// its conversation's `choices`, the rest through `saveBot`.
class BotEditPage extends StatefulWidget {
  const BotEditPage({super.key, required this.link, this.bot});

  final PhoneLink link;
  final LinkBot? bot;

  @override
  State<BotEditPage> createState() => _BotEditPageState();
}

class _BotEditPageState extends State<BotEditPage> {
  late final _name = TextEditingController(text: widget.bot?.name ?? '');
  late final _signature = TextEditingController(
    text: widget.bot?.signature ?? '',
  );
  late final _identity = TextEditingController(
    text: widget.bot?.identity ?? '',
  );
  late final _style = TextEditingController(text: widget.bot?.style ?? '');
  late final Set<BotAbility> _abilities = Set.of(
    widget.bot?.abilities ?? const <BotAbility>[],
  );
  late bool _chatOnly = widget.bot?.chatOnly ?? false;
  late bool _writesFirst = widget.bot?.writesFirst ?? true;
  final _memory = TextEditingController();
  final _self = TextEditingController();
  Uint8List? _avatarBytes;
  String? _avatarType;
  bool _avatarChanged = false;
  bool _clearAvatar = false;
  bool _saving = false;

  bool get _isNew => widget.bot == null;

  /// The model choices of the bot's conversation — it is picked by
  /// `choose`, not `saveBot`. A feed we opened ourselves is closed again.
  SessionFeed? _feed;
  bool _openedFeed = false;
  Timer? _feedWait;

  @override
  void initState() {
    super.initState();
    final bot = widget.bot;
    if (bot == null) return;
    final session = bot.session;
    if (session != null) {
      final feed = widget.link.feeds[session];
      if (feed != null) {
        _feed = feed;
      } else {
        _openedFeed = true;
        widget.link
            .open(session, window: 1)
            .then((feed) {
              if (!mounted) return;
              setState(() => _feed = feed);
            })
            .catchError((_) {});
      }
      // The choices arrive by events; give the feed a moment to fill.
      _feedWait = Timer(const Duration(seconds: 5), () {});
    }
    if (bot.hasAvatarImage) {
      widget.link
          .botAvatar(bot.id)
          .then((result) {
            final data = result['data'];
            if (!mounted || data is! String || _avatarChanged) return;
            setState(() {
              _avatarBytes = base64Decode(data);
              _avatarType = result['type'] as String?;
            });
          })
          .catchError((_) {});
    }
    widget.link
        .botMemory(bot.id)
        .then((memory) {
          if (!mounted) return;
          _memory.text = memory['text'] as String? ?? '';
          _self.text = memory['self'] as String? ?? '';
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    _feedWait?.cancel();
    final session = widget.bot?.session;
    if (_openedFeed && session != null) {
      widget.link.close(session).catchError((_) {});
    }
    _name.dispose();
    _signature.dispose();
    _identity.dispose();
    _style.dispose();
    _memory.dispose();
    _self.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final action = await showBActions<String>(
      context,
      title: '设置 Bot 头像',
      danger: const {'clear'},
      actions: [
        (Icons.photo_library_outlined, '从相册选择', '支持 PNG / JPG / WebP', 'gallery'),
        (Icons.photo_camera_outlined, '拍照', null, 'camera'),
        if (_avatarBytes != null || (widget.bot?.hasAvatarImage ?? false))
          (Icons.restore_outlined, '恢复默认头像', null, 'clear'),
      ],
    );
    if (action == null || !mounted) return;
    if (action == 'clear') {
      setState(() {
        _avatarBytes = null;
        _avatarType = null;
        _avatarChanged = true;
        _clearAvatar = true;
      });
      return;
    }
    if (action == 'camera') {
      final path = await PhonePlatform.takePhoto();
      if (path == null || !mounted) return;
      final file = File(path);
      try {
        final bytes = await file.readAsBytes();
        _applyAvatar(bytes, 'image/jpeg');
      } finally {
        unawaited(file.delete().catchError((Object _) => file));
      }
      return;
    }
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
    );
    if (files.isEmpty || !mounted) return;
    final picked = files.first;
    final bytes = await picked.readAsBytes();
    final ext = (picked.extension ?? '').toLowerCase();
    final mime = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    _applyAvatar(bytes, mime);
  }

  void _applyAvatar(Uint8List bytes, String mime) {
    if (!mounted) return;
    if (bytes.isEmpty || bytes.length > LinkLimits.avatar) {
      showBToast(context, '头像图片过大，请选择更小的图片', isError: true);
      return;
    }
    setState(() {
      _avatarBytes = bytes;
      _avatarType = mime;
      _avatarChanged = true;
      _clearAvatar = false;
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showBToast(context, '请填写 Bot 名字', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final bot = widget.bot;
      final saved = await widget.link.saveBot(
        {
          'name': name,
          'signature': _signature.text.trim(),
          'identity': _identity.text.trim(),
          'style': _style.text.trim(),
          'abilities': [
            for (final ability in _abilities) ability.name,
          ],
          if (_avatarChanged && _avatarBytes != null && _avatarType != null)
            'avatarImage': {
              'data': base64Encode(_avatarBytes!),
              'type': _avatarType!,
            }
          else if (_clearAvatar)
            'avatar': ''
          else if (bot?.avatar != null)
            'avatar': bot!.avatar,
          if (bot != null) 'proactive': bot.proactive.toJson(),
          if (_chatOnly) 'chatOnly': true,
          if (!_writesFirst) 'writesFirst': false,
        },
        botId: bot?.id,
      );
      if (saved != null && _avatarChanged) {
        BotAvatar.cachePut(saved.id, saved.avatar, _avatarBytes);
      }
      if (bot != null) {
        await widget.link.setBotMemory(bot.id, _memory.text.trim());
        await widget.link.setBotSelf(bot.id, _self.text.trim());
      }
      if (mounted) Navigator.of(context).pop();
    } on Object catch (failure) {
      if (mounted) {
        setState(() => _saving = false);
        showBToast(context, '保存失败：$failure', isError: true);
      }
    }
  }

  Future<void> _pickModel(LinkChoice choice) async {
    final session = widget.bot?.session;
    if (session == null) return;
    final picked = await showBChoicePicker(
      context,
      title: '选择模型',
      options: choice.options,
      selected: choice.selected,
    );
    if (picked != null && mounted) {
      try {
        await widget.link.choose(session, 'model', picked.id);
      } on Object catch (failure) {
        if (mounted) {
          showBToast(context, '$failure', isError: true);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bot = widget.bot;
    final modelChoice = _feed?.choices
        .where((c) => c.kind == 'model')
        .firstOrNull;
    final model = modelChoice == null
        ? (bot?.model ?? '默认')
        : modelChoice.options
              .where((o) => o.id == modelChoice.selected)
              .firstOrNull
              ?.label ??
          modelChoice.selected ??
          '默认';
    final danger = Theme.of(context).colorScheme.error;
    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? '添加 Bot' : '编辑 ${bot!.name}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          BCard(
            child: Column(
              children: [
                GestureDetector(
                  onTap: _pickAvatar,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ValueListenableBuilder(
                        valueListenable: _name,
                        builder: (context, _, _) => BotAvatar.preview(
                          name: _name.text.trim(),
                          bytes: _avatarBytes,
                          size: 72,
                        ),
                      ),
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.surfaceRaised,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '点击头像上传图片 · 它在聊天和列表里的样子',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          BSection(
            title: '基本',
            children: [
              _pad(BTextField(controller: _name, label: '名字', hint: 'Bot 显示的名字')),
              _pad(BTextField(controller: _signature, label: '签名', hint: '列表里名字下的一行')),
            ],
          ),
          BSection(
            title: '人设',
            children: [
              _pad(BTextField(controller: _identity, label: '身份', hint: '它是谁、要做什么', lines: 3)),
              _pad(BTextField(controller: _style, label: '风格', hint: '它怎么说话', lines: 2)),
            ],
          ),
          BSection(
            title: '对话',
            children: [
              BCell(
                icon: Icons.auto_awesome,
                title: '模型',
                subtitle: model,
                showChevron: modelChoice != null,
                onTap: modelChoice == null
                    ? null
                    : () => _pickModel(modelChoice),
              ),
              const BDivider(),
              BCell(
                icon: Icons.chat_bubble_outline_rounded,
                title: '只聊天',
                subtitle: '不使用文件、命令等智能体工具',
                showChevron: false,
                trailing: Switch.adaptive(
                  value: _chatOnly,
                  onChanged: (v) => setState(() => _chatOnly = v),
                ),
                onTap: () => setState(() => _chatOnly = !_chatOnly),
              ),
              const BDivider(),
              BCell(
                icon: Icons.notifications_none_rounded,
                title: '主动发消息',
                subtitle: '有情况时它先开口',
                showChevron: false,
                trailing: Switch.adaptive(
                  value: _writesFirst,
                  onChanged: (v) => setState(() => _writesFirst = v),
                ),
                onTap: () => setState(() => _writesFirst = !_writesFirst),
              ),
            ],
          ),
          BSection(
            title: '能力',
            children: [
              for (final (i, (ability, icon, label, hint)) in [
                (
                  BotAbility.agents,
                  Icons.smart_toy_outlined,
                  '照看智能体',
                  '查看、停止、重试、发消息',
                ),
                (
                  BotAbility.browser,
                  Icons.language_rounded,
                  '使用浏览器',
                  '替你打开网页、操作页面',
                ),
                (
                  BotAbility.proactive,
                  Icons.campaign_outlined,
                  '主动汇报',
                  '智能体等待或失败时告知你',
                ),
              ].indexed) ...[
                if (i > 0) const BDivider(),
                BCell(
                  icon: icon,
                  title: label,
                  subtitle: hint,
                  showChevron: false,
                  trailing: Checkbox(
                    value: _abilities.contains(ability),
                    onChanged: (v) => setState(
                      () => v == true
                          ? _abilities.add(ability)
                          : _abilities.remove(ability),
                    ),
                  ),
                  onTap: () => setState(
                    () => _abilities.contains(ability)
                        ? _abilities.remove(ability)
                        : _abilities.add(ability),
                  ),
                ),
              ],
            ],
          ),
          if (!_isNew) ...[
            BSection(
              title: '记忆',
              children: [
                _pad(BTextField(controller: _memory, label: '关于你的事', hint: '它记住的你的情况', lines: 3)),
                _pad(BTextField(controller: _self, label: '自我笔记', hint: '它记下的自己', lines: 3)),
              ],
            ),
            BSection(
              title: '操作',
              children: [
                BCell(
                  icon: Icons.cleaning_services_outlined,
                  iconColor: danger,
                  title: '清空对话',
                  titleColor: danger,
                  subtitle: '重开它的对话，记忆和设定保留',
                  onTap: _saving ? null : _clearChat,
                ),
                if (!bot!.assistant) ...[
                  const BDivider(),
                  BCell(
                    icon: Icons.delete_outline,
                    iconColor: danger,
                    title: '删除 Bot',
                    titleColor: danger,
                    onTap: _saving ? null : _delete,
                  ),
                ],
              ],
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: BButton(
              label: _isNew ? '创建 Bot' : '保存',
              primary: true,
              expand: true,
              busy: _saving,
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }

  /// A field inside a [BSection]'s card: the card's own edges padded off.
  Widget _pad(Widget field) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    child: field,
  );

  Future<void> _clearChat() async {
    final bot = widget.bot;
    if (bot == null) return;
    final ok = await showBConfirm(
      context,
      title: '清空对话？',
      body: '它的对话将重开，记忆和设定保留。',
      confirm: '清空',
    );
    if (!ok) return;
    try {
      await widget.link.clearBotChat(bot.id);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (failure) {
      if (mounted) showBToast(context, '$failure', isError: true);
    }
  }

  Future<void> _delete() async {
    final bot = widget.bot;
    if (bot == null) return;
    final ok = await showBConfirm(
      context,
      title: '删除 ${bot.name}？',
      body: 'Bot 和它的对话、记忆一并删除，不可恢复。',
      confirm: '删除',
      danger: true,
    );
    if (!ok) return;
    try {
      await widget.link.deleteBot(bot.id);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (failure) {
      if (mounted) showBToast(context, '$failure', isError: true);
    }
  }
}

/// A Bot's avatar: fetches and caches its uploaded image via
/// [PhoneLink.botAvatar] when [LinkBot.hasAvatarImage], else renders its
/// emoji or a refined gradient monogram squircle.
class BotAvatar extends StatefulWidget {
  const BotAvatar({
    super.key,
    required this.link,
    required this.bot,
    this.size = 44,
  });

  final PhoneLink link;
  final LinkBot bot;
  final double size;

  static final Map<String, Uint8List?> _cache = {};

  static void cachePut(String botId, String? avatar, Uint8List? bytes) {
    if (avatar != null) {
      _cache['$botId:$avatar'] = bytes;
    }
  }

  static Widget preview({
    required String name,
    Uint8List? bytes,
    String? emoji,
    double size = 44,
  }) {
    final radius = BorderRadius.circular(size * 0.28);
    if (bytes != null && bytes.isNotEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    }
    const palettes = [
      (Color(0xFF8B5CF6), Color(0xFF6D28D9)),
      (Color(0xFF3B82F6), Color(0xFF2563EB)),
      (Color(0xFF10B981), Color(0xFF059669)),
      (Color(0xFFEC4899), Color(0xFFDB2777)),
      (Color(0xFF06B6D4), Color(0xFF0891B2)),
      (Color(0xFF6366F1), Color(0xFF4F46E5)),
    ];
    final (top, bottom) = palettes[name.hashCode.abs() % palettes.length];
    final label = (emoji != null && emoji.isNotEmpty)
        ? emoji
        : (name.trim().isEmpty ? 'B' : name.trim().characters.first.toUpperCase());
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [top, bottom],
        ),
        borderRadius: radius,
        border: Border.all(
          color: Colors.white.withValues(alpha: MdTheme.dark ? 0.14 : 0.28),
          width: 0.75,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  State<BotAvatar> createState() => _BotAvatarState();
}

class _BotAvatarState extends State<BotAvatar> {
  Uint8List? _bytes;
  String? _loadedKey;

  String get _cacheKey => '${widget.bot.id}:${widget.bot.avatar ?? ''}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(BotAvatar old) {
    super.didUpdateWidget(old);
    if (old.bot.id != widget.bot.id || old.bot.avatar != widget.bot.avatar) {
      _load();
    }
  }

  Future<void> _load() async {
    if (!widget.bot.hasAvatarImage) {
      if (_bytes != null) setState(() => _bytes = null);
      return;
    }
    final key = _cacheKey;
    if (BotAvatar._cache.containsKey(key)) {
      _bytes = BotAvatar._cache[key];
      _loadedKey = key;
      return;
    }
    _loadedKey = key;
    try {
      final result = await widget.link.botAvatar(widget.bot.id);
      final data = result['data'];
      final decoded = data is String ? base64Decode(data) : null;
      BotAvatar._cache[key] = decoded;
      if (mounted && _loadedKey == key) {
        setState(() => _bytes = decoded);
      }
    } on Object {
      // Fall back to gradient monogram.
    }
  }

  @override
  Widget build(BuildContext context) {
    final emoji =
        widget.bot.avatar != null && !widget.bot.hasAvatarImage
        ? widget.bot.avatar
        : null;
    return BotAvatar.preview(
      name: widget.bot.name,
      bytes: _bytes ?? BotAvatar._cache[_cacheKey],
      emoji: emoji,
      size: widget.size,
    );
  }
}
