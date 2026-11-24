import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../codicons.dart';
import '../link/phone_link.dart';
import 'md/md_theme.dart';
import 'widgets.dart';

/// Opens the edit-and-resend sheet: message text, model/mode/permission for
/// this turn, and whether to rewind file changes after the message.
Future<void> showEditResendSheet({
  required BuildContext context,
  required PhoneLink link,
  required SessionFeed feed,
  required int index,
  required String initialText,
}) async {
  final plan = await link.rewindPlan(feed.session, index);
  final files = <_RewindFile>[
    for (final raw in (plan?['files'] as List?) ?? const [])
      if (raw is Map<String, Object?>)
        _RewindFile(
          name: raw['name'] as String? ?? '',
          outcome: raw['outcome'] as String? ?? '',
        ),
  ];
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceRaised,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (context, scroll) => _EditResendSheet(
        link: link,
        feed: feed,
        index: index,
        initialText: initialText,
        rewindFiles: files,
        scrollController: scroll,
      ),
    ),
  );
}

class _RewindFile {
  const _RewindFile({required this.name, required this.outcome});

  final String name;
  final String outcome;

  bool get conflict => outcome == 'conflict';
}

class _EditResendSheet extends StatefulWidget {
  const _EditResendSheet({
    required this.link,
    required this.feed,
    required this.index,
    required this.initialText,
    required this.rewindFiles,
    required this.scrollController,
  });

  final PhoneLink link;
  final SessionFeed feed;
  final int index;
  final String initialText;
  final List<_RewindFile> rewindFiles;
  final ScrollController scrollController;

  @override
  State<_EditResendSheet> createState() => _EditResendSheetState();
}

class _EditResendSheetState extends State<_EditResendSheet> {
  late final TextEditingController _text;
  late Map<String, String> _picked;
  var _revert = false;
  var _sending = false;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.initialText);
    _picked = {
      for (final choice in widget.feed.choices)
        if (choice.selected != null && choice.selected!.isNotEmpty)
          choice.kind: choice.selected!,
    };
    if (widget.rewindFiles.isNotEmpty) {
      final revertible = widget.rewindFiles.where((f) => !f.conflict).length;
      if (revertible > 0) _revert = true;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  List<LinkChoice> get _sessionChoices => [
    for (final choice in widget.feed.choices)
      if (choice.kind == 'model' ||
          choice.kind == 'mode' ||
          choice.kind == 'permission')
        choice,
  ];

  List<LinkChoice> get _modelSubChoices => [
    for (final choice in widget.feed.choices)
      if (choice.kind == 'effort' || choice.kind == 'context') choice,
  ];

  String? _label(LinkChoice choice) {
    final id = _picked[choice.kind] ?? choice.selected;
    if (id == null) return null;
    for (final option in choice.options) {
      if (option.id == id) return _localize(choice, option.label);
    }
    return id;
  }

  Future<void> _pick(LinkChoice choice) async {
    String? initialGroup;
    if (choice.kind == 'model') {
      final id = _picked[choice.kind] ?? choice.selected;
      for (final option in choice.options) {
        if (option.id == id) {
          initialGroup = option.group;
          break;
        }
      }
    }
    final selected = _picked[choice.kind] ?? choice.selected;
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
      selected: selected,
      iconOf: choice.kind == 'model' ? _modelIcon : null,
      labelOf: (label) => _localize(choice, label),
    );
    if (picked != null && mounted) {
      setState(() => _picked[choice.kind] = picked.id);
    }
  }

  Future<void> _modelSettings() async {
    final picked = await showBActions<LinkChoice>(
      context,
      actions: [
        for (final choice in _modelSubChoices)
          (
            choice.kind == 'effort' ? Codicons.zap : Codicons.pieChart,
            _kindLabel(choice.kind),
            _label(choice),
            choice,
          ),
      ],
    );
    if (picked != null && mounted) _pick(picked);
  }

  Future<void> _submit() async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      for (final choice in widget.feed.choices) {
        final next = _picked[choice.kind];
        final was = choice.selected;
        if (next == null || next == was) continue;
        await widget.link.choose(widget.feed.session, choice.kind, next);
      }
      await widget.link.edit(
        sessionId: widget.feed.session,
        index: widget.index,
        text: text,
        revertFiles: _revert,
      );
      if (mounted) Navigator.of(context).pop();
    } on Object catch (failure) {
      if (mounted) {
        showBToast(context, '重发失败：$failure', isError: true);
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final revertible = widget.rewindFiles.where((f) => !f.conflict).toList();
    final conflicts = widget.rewindFiles.where((f) => f.conflict).toList();

    return ListView(
      controller: widget.scrollController,
      padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + bottom),
      children: [
        const Text(
          '编辑并重发',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _text,
          autofocus: true,
          minLines: 3,
          maxLines: 10,
          decoration: BTextField.decoration(hint: '修改消息后重新发送'),
        ),
        if (_sessionChoices.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            '发送选项',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final choice in _sessionChoices)
                if (_label(choice) case final label?)
                  _ChoiceChip(
                    icon: switch (choice.kind) {
                      'mode' => Codicons.symbolConstant,
                      'permission' => Codicons.shield,
                      'model' => Codicons.hubot,
                      _ => Codicons.settings,
                    },
                    label: choice.kind == 'mode' ? '∞ $label' : label,
                    accent: choice.kind == 'permission',
                    onTap: () => _pick(choice),
                    onMenuTap: choice.kind == 'model' &&
                            _modelSubChoices.isNotEmpty
                        ? _modelSettings
                        : null,
                  ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        Text(
          '文件改动',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        if (widget.rewindFiles.isEmpty)
          Text(
            '此消息之后没有可回滚的文件改动',
            style: TextStyle(fontSize: 13, color: AppColors.textFaint),
          )
        else ...[
          _RevertRow(
            value: _revert,
            enabled: revertible.isNotEmpty,
            onChanged: revertible.isEmpty
                ? null
                : (v) => setState(() => _revert = v),
          ),
          if (_revert && revertible.isNotEmpty) ...[
            const SizedBox(height: 8),
            _FilePreview(
              title: '将还原 ${revertible.length} 个文件',
              names: [for (final f in revertible.take(8)) f.name],
              more: revertible.length > 8 ? revertible.length - 8 : 0,
            ),
          ],
          if (conflicts.isNotEmpty) ...[
            const SizedBox(height: 8),
            _FilePreview(
              title: '${conflicts.length} 个文件无法自动还原',
              names: [for (final f in conflicts.take(4)) f.name],
              more: conflicts.length > 4 ? conflicts.length - 4 : 0,
              caution: true,
            ),
          ],
        ],
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            BButton(
              label: '取消',
              onPressed: _sending ? null : () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 10),
            BButton(
              label: '重发',
              icon: Icons.send,
              primary: true,
              busy: _sending,
              onPressed: _sending ? null : _submit,
            ),
          ],
        ),
      ],
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.icon,
    required this.label,
    this.accent = false,
    required this.onTap,
    this.onMenuTap,
  });

  final IconData icon;
  final String label;
  final bool accent;
  final VoidCallback onTap;
  final VoidCallback? onMenuTap;

  @override
  Widget build(BuildContext context) {
    final color = accent ? AppColors.caution : AppColors.textMuted;
    return GestureDetector(
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
            const SizedBox(width: 2),
            Icon(Icons.unfold_more, size: 13, color: color),
            if (onMenuTap != null) ...[
              Container(
                width: 0.5,
                height: 14,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: AppColors.partBorder,
              ),
              GestureDetector(
                onTap: onMenuTap,
                child: Icon(Icons.arrow_drop_down, size: 18, color: color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RevertRow extends StatelessWidget {
  const _RevertRow({
    required this.value,
    required this.enabled,
    this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: enabled && onChanged != null ? () => onChanged!(!value) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: value && enabled ? AppColors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: value && enabled
                      ? AppColors.accent
                      : AppColors.textFaint,
                  width: 1.5,
                ),
              ),
              child: value && enabled
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '回滚之后的文件改动',
                style: TextStyle(
                  fontSize: 13,
                  color: enabled ? AppColors.text : AppColors.textFaint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilePreview extends StatelessWidget {
  const _FilePreview({
    required this.title,
    required this.names,
    this.more = 0,
    this.caution = false,
  });

  final String title;
  final List<String> names;
  final int more;
  final bool caution;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bubbleFill,
        borderRadius: BorderRadius.circular(10),
        border: caution
            ? Border.all(color: AppColors.caution.withValues(alpha: 0.35))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: caution ? AppColors.caution : AppColors.text,
            ),
          ),
          for (final name in names)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                name,
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ),
          if (more > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '还有 $more 个…',
                style: TextStyle(fontSize: 12, color: AppColors.textFaint),
              ),
            ),
        ],
      ),
    );
  }
}

String _kindLabel(String kind) => switch (kind) {
  'model' => '模型',
  'mode' => '模式',
  'permission' => '权限',
  'effort' => '投入',
  'context' => '上下文',
  _ => kind,
};

String _localize(LinkChoice choice, String label) {
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

String _localizeDescription(String description) {
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

Widget? _modelIcon(String id) {
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
