import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';

import '../link/phone_link.dart';
import 'widgets.dart';

/// A group's edit page: its name, the bots in it, its rules, how many
/// passes a conversation may take and the seconds between answers.
/// A null [group] makes a new one.
class GroupEditPage extends StatefulWidget {
  const GroupEditPage({super.key, required this.link, this.group});

  final PhoneLink link;
  final LinkGroup? group;

  @override
  State<GroupEditPage> createState() => _GroupEditPageState();
}

class _GroupEditPageState extends State<GroupEditPage> {
  late final _name = TextEditingController(text: widget.group?.name ?? '');
  late final _rules = TextEditingController(text: widget.group?.rules ?? '');
  late final _passes = TextEditingController(
    text: '${widget.group?.passes ?? linkGroupPasses}',
  );
  late final _gap = TextEditingController(
    text: '${widget.group?.gap ?? 0}',
  );
  late final Set<String> _members = Set.of(widget.group?.members ?? const []);
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _rules.dispose();
    _passes.dispose();
    _gap.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showBToast(context, '群名不能为空', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.link.saveGroup({
        'name': name,
        'members': _members.toList(),
        'rules': _rules.text.trim(),
        'passes': int.tryParse(_passes.text.trim()) ?? linkGroupPasses,
        'gap': int.tryParse(_gap.text.trim()) ?? 0,
      }, groupId: widget.group?.id);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (failure) {
      if (mounted) {
        setState(() => _saving = false);
        showBToast(context, '保存失败：$failure', isError: true);
      }
    }
  }

  Future<void> _delete() async {
    final group = widget.group;
    if (group == null) return;
    final ok = await showBConfirm(
      context,
      title: '删除 ${group.name}？',
      body: '群和它的消息一并删除，不可恢复。',
      confirm: '删除',
      danger: true,
    );
    if (!ok) return;
    try {
      await widget.link.deleteGroup(group.id);
      if (mounted) {
        Navigator.of(context).pop(); // edit page
        Navigator.of(context).maybePop(); // its chat page
      }
    } on Object catch (failure) {
      if (mounted) showBToast(context, '$failure', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bots = widget.link.state?.bots ?? const <LinkBot>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.group == null ? '新建群聊' : '编辑 ${widget.group!.name}'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _field('群名', _name, '群聊显示的名字'),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              '成员',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (bots.isEmpty)
            const ListTile(title: Text('还没有 Bot 可以加入')),
          for (final bot in bots)
            CheckboxListTile(
              dense: true,
              title: Text(bot.name),
              subtitle: bot.signature.isEmpty ? null : Text(bot.signature),
              value: _members.contains(bot.id),
              onChanged: (v) => setState(
                () => v == true
                    ? _members.add(bot.id)
                    : _members.remove(bot.id),
              ),
            ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              '规则',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          _field('群规则', _rules, '成员们要遵守的规矩', lines: 3),
          _field('接力次数', _passes, '一轮对话最多传几次', number: true),
          _field('间隔秒数', _gap, '相邻两个 Bot 发言间隔', number: true),
          if (widget.group != null) ...[
            const Divider(),
            BCell(
              icon: Icons.delete_outline,
              iconColor: Theme.of(context).colorScheme.error,
              title: '删除群聊',
              titleColor: Theme.of(context).colorScheme.error,
              onTap: _saving ? null : _delete,
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller,
    String hint, {
    int lines = 1,
    bool number = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: BTextField(
      controller: controller,
      label: label,
      hint: hint,
      lines: lines,
      number: number,
    ),
  );
}
