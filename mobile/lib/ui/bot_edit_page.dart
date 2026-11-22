import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';

import '../link/phone_link.dart';
import 'md/md_theme.dart';
import 'widgets.dart';

/// A bot's settings (the official's bot profile editor): name, signature,
/// who it is, its abilities and the model it talks on — the model through
/// its conversation's `choices`, the rest through `saveBot`.
class BotEditPage extends StatefulWidget {
  const BotEditPage({super.key, required this.link, required this.bot});

  final PhoneLink link;
  final LinkBot bot;

  @override
  State<BotEditPage> createState() => _BotEditPageState();
}

class _BotEditPageState extends State<BotEditPage> {
  late final _name = TextEditingController(text: widget.bot.name);
  late final _signature = TextEditingController(
    text: widget.bot.signature,
  );
  late final _identity = TextEditingController(text: widget.bot.identity);
  late final _style = TextEditingController(text: widget.bot.style);
  late final Set<BotAbility> _abilities = Set.of(widget.bot.abilities);
  late bool _chatOnly = widget.bot.chatOnly;
  late bool _writesFirst = widget.bot.writesFirst;
  final _memory = TextEditingController();
  final _self = TextEditingController();
  bool _saving = false;

  /// The model choices of the bot's conversation — it is picked by
  /// `choose`, not `saveBot`. A feed we opened ourselves is closed again.
  SessionFeed? _feed;
  bool _openedFeed = false;
  Timer? _feedWait;

  @override
  void initState() {
    super.initState();
    final session = widget.bot.session;
    if (session == null) return;
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
    widget.link
        .botMemory(widget.bot.id)
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
    final session = widget.bot.session;
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

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.link.saveBot(
        {
          'name': _name.text.trim(),
          'signature': _signature.text.trim(),
          'identity': _identity.text.trim(),
          'style': _style.text.trim(),
          'abilities': [
            for (final ability in _abilities) ability.name,
          ],
          'proactive': widget.bot.proactive.toJson(),
          if (_chatOnly) 'chatOnly': true,
          if (!_writesFirst) 'writesFirst': false,
        },
        botId: widget.bot.id,
      );
      await widget.link.setBotMemory(widget.bot.id, _memory.text.trim());
      await widget.link.setBotSelf(widget.bot.id, _self.text.trim());
      if (mounted) Navigator.of(context).pop();
    } on Object catch (failure) {
      if (mounted) {
        setState(() => _saving = false);
        showBToast(context, '保存失败：$failure', isError: true);
      }
    }
  }

  Future<void> _pickModel(LinkChoice choice) async {
    final session = widget.bot.session;
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
    final modelChoice = _feed?.choices
        .where((c) => c.kind == 'model')
        .firstOrNull;
    final model = modelChoice == null
        ? (widget.bot.model ?? '默认')
        : modelChoice.options
              .where((o) => o.id == modelChoice.selected)
              .firstOrNull
              ?.label ??
          modelChoice.selected ??
          '默认';
    final danger = Theme.of(context).colorScheme.error;
    return Scaffold(
      appBar: AppBar(title: Text('编辑 ${widget.bot.name}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          BCard(
            child: Column(
              children: [
                ValueListenableBuilder(
                  valueListenable: _name,
                  builder: (context, _, _) => Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF9270CA),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _name.text.isEmpty ? 'B' : _name.text.characters.first,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '它在聊天和列表里的样子。',
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
              if (!widget.bot.assistant) ...[
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
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: BButton(
              label: '保存',
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
    final ok = await showBConfirm(
      context,
      title: '清空对话？',
      body: '它的对话将重开，记忆和设定保留。',
      confirm: '清空',
    );
    if (!ok) return;
    try {
      await widget.link.clearBotChat(widget.bot.id);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (failure) {
      if (mounted) showBToast(context, '$failure', isError: true);
    }
  }

  Future<void> _delete() async {
    final ok = await showBConfirm(
      context,
      title: '删除 ${widget.bot.name}？',
      body: 'Bot 和它的对话、记忆一并删除，不可恢复。',
      confirm: '删除',
      danger: true,
    );
    if (!ok) return;
    try {
      await widget.link.deleteBot(widget.bot.id);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (failure) {
      if (mounted) showBToast(context, '$failure', isError: true);
    }
  }

}
