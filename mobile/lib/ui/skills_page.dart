import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';

import '../codicons.dart';
import '../link/phone_link.dart';
import '../phone_platform.dart';
import 'link_status.dart';
import 'md/md_theme.dart';
import 'widgets.dart';

/// Mobile counterpart to desktop's Customize / Skills view: view, toggle,
/// create, edit, and delete Skills, MCP servers, Subagents, and Plugins.
class SkillsPage extends StatefulWidget {
  const SkillsPage({super.key, required this.link});

  final PhoneLink link;

  @override
  State<SkillsPage> createState() => _SkillsPageState();
}

class _SkillsPageState extends State<SkillsPage> {
  static const _tabs = [
    ('skill', '技能', Codicons.zap),
    ('mcp', 'MCP', Codicons.server),
    ('agent', '子代理', Codicons.hubot),
    ('rule', '规则', Codicons.law),
    ('command', '命令', Codicons.terminal),
    ('plugin', '插件', Codicons.package),
  ];

  String _kind = 'skill';
  final _query = TextEditingController();
  List<LinkExtension> _items = const [];
  bool _loading = true;
  Object? _error;
  final Set<String> _toggling = {};

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
      final items = await widget.link.extensions();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on Object catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure;
        _loading = false;
      });
    }
  }

  Future<void> _toggle(LinkExtension item, bool enabled) async {
    final key = '${item.kind}:${item.name}';
    if (_toggling.contains(key)) return;
    PhonePlatform.haptic('selection');
    setState(() {
      _toggling.add(key);
      _items = [
        for (final x in _items)
          if (x.kind == item.kind && x.name == item.name)
            LinkExtension(
              kind: x.kind,
              scope: x.scope,
              name: x.name,
              description: x.description,
              project: x.project,
              enabled: enabled,
            )
          else
            x,
      ];
    });
    try {
      await widget.link.toggleExtension(
        kind: item.kind,
        name: item.name,
        enabled: enabled,
      );
    } on LinkRemoteException catch (failure) {
      if (!mounted) return;
      final message = failure.code == LinkErrors.unknown
          ? '请先更新电脑端以支持在手机上开关配置'
          : failure.message;
      showBToast(context, message, isError: true);
      await _load();
    } on Object catch (failure) {
      if (!mounted) return;
      showBToast(context, '$failure', isError: true);
      await _load();
    } finally {
      if (mounted) setState(() => _toggling.remove(key));
    }
  }

  Future<void> _create() async {
    final kind = _kind;
    final label = switch (kind) {
      'agent' => '子代理',
      'rule' => '规则',
      'command' => '命令',
      _ => '技能',
    };
    final example = switch (kind) {
      'agent' => 'my-agent',
      'rule' => 'my-rule',
      'command' => 'my-command',
      _ => 'my-skill',
    };
    final name = await showBPrompt(
      context,
      title: '新建$label',
      hint: '输入英文名称，例如 $example',
      confirm: '创建',
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await widget.link.saveExtension(
        kind: kind,
        scope: 'user',
        name: name,
      );
      if (!mounted) return;
      showBToast(context, '已创建 $name');
      await _load();
      final created = _items
          .where((x) => x.kind == kind && x.name == name)
          .firstOrNull;
      if (created != null && mounted) {
        await _openEditor(created);
      }
    } on LinkRemoteException catch (failure) {
      if (!mounted) return;
      final message = failure.code == LinkErrors.unknown
          ? '请先更新电脑端以支持在手机上新建$label'
          : failure.message;
      showBToast(context, message, isError: true);
    } on Object catch (failure) {
      if (mounted) showBToast(context, '创建失败：$failure', isError: true);
    }
  }

  Future<void> _openEditor(LinkExtension item) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _ExtensionDetailPage(link: widget.link, item: item),
      ),
    );
    if (changed == true && mounted) {
      await _load();
    }
  }

  String _scopeLabel(String scope) => switch (scope) {
    'user' => '用户',
    'project' => '项目',
    'local' => '本地',
    'plugin' => '插件',
    'synced' => '云端',
    _ => scope,
  };

  @override
  Widget build(BuildContext context) {
    final needle = _query.text.trim().toLowerCase();
    final filtered = [
      for (final item in _items)
        if (item.kind == _kind &&
            (needle.isEmpty ||
                item.name.toLowerCase().contains(needle) ||
                item.description.toLowerCase().contains(needle)))
          item,
    ];
    final canCreate =
        _kind == 'skill' ||
        _kind == 'agent' ||
        _kind == 'rule' ||
        _kind == 'command';
    final currentLabel = _tabs.firstWhere((t) => t.$1 == _kind).$2;
    return Scaffold(
      appBar: AppBar(
        title: const Text('技能与 MCP'),
        actions: [
          if (canCreate)
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: '新建$currentLabel',
              onPressed: _create,
            ),
        ],
      ),
      body: Column(
        children: [
          BConnectionBanner(
            link: widget.link,
            onRetry: () => widget.link.retryNow(force: true),
          ),
          // Category selector pills matching desktop CustomizeView.
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
              children: [
                for (final (kind, label, icon) in _tabs)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _CategoryPill(
                      icon: icon,
                      label: label,
                      count: _items.where((x) => x.kind == kind).length,
                      selected: _kind == kind,
                      onTap: () {
                        PhonePlatform.haptic('selection');
                        setState(() => _kind = kind);
                      },
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
            child: TextField(
              controller: _query,
              style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
              decoration: BTextField.decoration(hint: '搜索名称或描述…'),
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
                    title: '无法加载技能与扩展',
                    subtitle: '$_error',
                    actionLabel: '重试',
                    onAction: _load,
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    color: AppColors.accent,
                    child: filtered.isEmpty
                        ? ListView(
                            children: [
                              const SizedBox(height: 64),
                              BEmptyState(
                                icon: _tabs
                                    .firstWhere((t) => t.$1 == _kind)
                                    .$3,
                                title: needle.isNotEmpty
                                    ? '没有匹配的配置'
                                    : '暂无${_tabs.firstWhere((t) => t.$1 == _kind).$2}',
                                subtitle: canCreate && needle.isEmpty
                                    ? '点右上角 + 可快速创建，或在电脑端添加配置。'
                                    : '在电脑端配置后会同步显示在这里。',
                                actionLabel: canCreate && needle.isEmpty
                                    ? '新建$currentLabel'
                                    : null,
                                onAction: canCreate && needle.isEmpty
                                    ? _create
                                    : null,
                              ),
                            ],
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                            children: [
                              BCard(
                                padding: EdgeInsets.zero,
                                child: Column(
                                  children: [
                                    for (var i = 0; i < filtered.length; i++) ...[
                                      _extensionRow(filtered[i]),
                                      if (i < filtered.length - 1)
                                        const BDivider(),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _extensionRow(LinkExtension item) {
    final switchable =
        (item.kind == 'skill' && item.scope != 'plugin') || item.kind == 'mcp';
    final editable =
        item.kind == 'skill' ||
        item.kind == 'agent' ||
        item.kind == 'rule' ||
        item.kind == 'command' ||
        item.kind == 'mcp';
    final enabled = item.enabled ?? true;
    final key = '${item.kind}:${item.name}';
    final icon = switch (item.kind) {
      'skill' => Codicons.zap,
      'mcp' => Codicons.server,
      'agent' => Codicons.hubot,
      'rule' => Codicons.law,
      'command' => Codicons.terminal,
      _ => Codicons.package,
    };
    final subtitleParts = <String>[
      _scopeLabel(item.scope),
      if (item.description.isNotEmpty) item.description,
    ];
    return BCell(
      icon: icon,
      iconColor: enabled ? AppColors.accent : AppColors.textFaint,
      title: item.name,
      titleColor: enabled ? AppColors.textPrimary : AppColors.textMuted,
      subtitle: subtitleParts.join(' · '),
      showChevron: editable && !switchable,
      trailing: switchable
          ? Switch.adaptive(
              value: enabled,
              activeTrackColor: AppColors.accent,
              onChanged: _toggling.contains(key)
                  ? null
                  : (v) => _toggle(item, v),
            )
          : null,
      onTap: editable ? () => _openEditor(item) : null,
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.accent.withValues(alpha: MdTheme.dark ? 0.2 : 0.13)
            : AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? AppColors.accent : AppColors.partBorder,
          width: selected ? 1.2 : 0.75,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: selected ? AppColors.accent : AppColors.textMuted,
          ),
          const SizedBox(width: 6),
          Text(
            count > 0 ? '$label $count' : label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? AppColors.accent : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Viewer / editor for a Skill or Subagent Markdown file on the desktop.
class _ExtensionDetailPage extends StatefulWidget {
  const _ExtensionDetailPage({required this.link, required this.item});

  final PhoneLink link;
  final LinkExtension item;

  @override
  State<_ExtensionDetailPage> createState() => _ExtensionDetailPageState();
}

class _ExtensionDetailPageState extends State<_ExtensionDetailPage> {
  final _text = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _error;

  bool get _canModify =>
      widget.item.scope != 'plugin' && widget.item.scope != 'synced';

  bool get _canDelete => _canModify && widget.item.kind != 'mcp';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final text = await widget.link.readExtension(
        kind: widget.item.kind,
        scope: widget.item.scope,
        name: widget.item.name,
        project: widget.item.project,
      );
      if (!mounted) return;
      _text.text = text;
      setState(() {
        _loading = false;
        _dirty = false;
      });
    } on LinkRemoteException catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure.code == LinkErrors.unknown
            ? '请先更新电脑端以支持在手机上查看和编辑内容。'
            : failure.message;
        _loading = false;
      });
    } on Object catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = '$failure';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.link.saveExtension(
        kind: widget.item.kind,
        scope: widget.item.scope,
        name: widget.item.name,
        project: widget.item.project,
        text: _text.text,
      );
      if (!mounted) return;
      showBToast(context, '已保存');
      Navigator.of(context).pop(true);
    } on Object catch (failure) {
      if (!mounted) return;
      setState(() => _saving = false);
      showBToast(context, '保存失败：$failure', isError: true);
    }
  }

  Future<void> _delete() async {
    final ok = await showBConfirm(
      context,
      title: '删除 ${widget.item.name}？',
      body: '将从电脑端删除此配置文件，操作不可恢复。',
      confirm: '删除',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.link.deleteExtension(
        kind: widget.item.kind,
        scope: widget.item.scope,
        name: widget.item.name,
        project: widget.item.project,
      );
      if (!mounted) return;
      showBToast(context, '已删除');
      Navigator.of(context).pop(true);
    } on Object catch (failure) {
      if (!mounted) return;
      setState(() => _saving = false);
      showBToast(context, '删除失败：$failure', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item.name),
        actions: [
          if (_canModify && !_loading && _error == null) ...[
            if (_canDelete)
              IconButton(
                icon: Icon(Icons.delete_outline, color: AppColors.removed),
                tooltip: '删除',
                onPressed: _saving ? null : _delete,
              ),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Center(
                child: BButton(
                  label: '保存',
                  primary: true,
                  busy: _saving,
                  onPressed: _dirty ? _save : null,
                ),
              ),
            ),
          ],
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.accent))
          : _error != null
          ? BEmptyState(
              icon: Icons.description_outlined,
              title: widget.item.name,
              subtitle: _error,
              actionLabel: '重试',
              onAction: _load,
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.item.kind == 'mcp')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '正在编辑 MCP 配置文件（JSON），保存后将同步写回电脑端。',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  Expanded(
                    child: BCard(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        controller: _text,
                        readOnly: !_canModify,
                        expands: true,
                        maxLines: null,
                        textAlignVertical: TextAlignVertical.top,
                        style: TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 13,
                          height: 1.5,
                          color: AppColors.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (_) {
                          if (!_dirty) setState(() => _dirty = true);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
