import 'dart:io';

import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';
import '../codicons.dart';
import 'bot_edit_page.dart';
import 'browse_page.dart';
import 'group_edit_page.dart';
import 'group_page.dart';

import '../app_state.dart';
import '../link/link_store.dart';
import '../link/phone_link.dart';
import '../main.dart';
import '../phone_platform.dart';
import 'chat_page.dart';
import 'files_page.dart';
import 'md/md_theme.dart';
import 'widgets.dart';
import 'pair_page.dart';
import 'settings_page.dart';
import 'update_dialog.dart';
import 'link_status.dart';

/// The app's home: the official phone app's shell — a computer picked at
/// the top, its conversations, bots, files and settings in the bottom
/// bar's four tabs.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

enum _WorkspaceScope { all, local, remote }

enum _WorkspaceSort { recent, name }

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int _tab = 0;
  _WorkspaceScope _scope = _WorkspaceScope.all;
  _WorkspaceSort _sort = _WorkspaceSort.recent;
  final Set<String> _onlyProjects = {};
  DateTime _checkedUpdateAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _hasActiveFilter =>
      _scope != _WorkspaceScope.all ||
      _sort != _WorkspaceSort.recent ||
      _onlyProjects.isNotEmpty;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Quietly checks for a newer build — on open and each time the app
  /// comes back, at most once every six hours.
  void _checkUpdate() {
    if (DateTime.now().difference(_checkedUpdateAt).inHours < 6) return;
    _checkedUpdateAt = DateTime.now();
    if (mounted) checkForUpdate(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate());
    }
  }

  AppState get _state => AppScope.of(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The download service says quietly when a newer build is up.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate());
  }

  /// The computer the tabs show: the persisted picked one, else any online,
  /// else the first paired.
  PhoneLink? get _link {
    final links = _state.links;
    final picked = _state.selectedComputerId;
    if (picked != null && links.containsKey(picked)) {
      return links[picked];
    }
    for (final link in links.values) {
      if (link.phase == PhonePhase.online) return link;
    }
    return links.values.firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final systemDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    MdTheme.dark = switch (state.themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => systemDark,
    };
    if (state.store?.computers.isNotEmpty != true) {
      return _NoComputers(state: state);
    }
    final pendingNotification = state.takePendingNotification();
    if (pendingNotification != null) {
      final targetLink = state.links[pendingNotification.computerId];
      if (targetLink != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChatPage(
                link: targetLink,
                sessionId: pendingNotification.sessionId,
              ),
            ),
          );
        });
      }
    }
    final link = _link;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        leading: _tab == 0
            ? _FilterButton(
                active: _hasActiveFilter,
                onTap: () => _openFilter(link),
              )
            : null,
        title: _ComputerTitle(
          state: state,
          selected: link,
          onPick: (id) {
            state.selectComputer(id);
            setState(() => _onlyProjects.clear());
          },
        ),
        actions: [
          _PlusMenu(
            link: link,
            onPair: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const PairPage())),
            onNewChat: link == null ? null : () => _newChat(link),
            onNewGroup: link == null
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => GroupEditPage(link: link),
                    ),
                  ),
            onAddBot: link == null
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => BotEditPage(link: link)),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (link != null)
            BConnectionBanner(
              link: link,
              onRetry: () => link.retryNow(force: true),
            ),
          if (state.shared.isNotEmpty && link != null)
            _SharedIncomingBanner(
              count: state.shared.length,
              onSend: () => _sendShared(link, state),
              onDismiss: () {
                state.takeShared();
                setState(() {});
              },
            ),
          Expanded(
            child: switch (_tab) {
              0 => _ChatsTab(
                  link: link,
                  scope: _scope,
                  sort: _sort,
                  onlyProjects: _onlyProjects,
                  onResetFilter: () => setState(() {
                    _scope = _WorkspaceScope.all;
                    _sort = _WorkspaceSort.recent;
                    _onlyProjects.clear();
                  }),
                  onOpenSearch: link == null
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => _SearchPage(link: link),
                          ),
                        ),
                ),
              1 => _BotsTab(link: link),
              2 => _FilesTab(link: link),
              _ => SettingsPage(link: link),
            },
          ),
        ],
      ),
      bottomNavigationBar: _BottomBar(
        tab: _tab,
        unread: link == null ? 0 : _unread(link),
        onSelect: (tab) => setState(() => _tab = tab),
      ),
    );
  }

  Future<void> _openFilter(PhoneLink? link) async {
    PhonePlatform.haptic('selection');
    final projects = link?.state?.projects ?? const <ProjectInfo>[];
    final sessions = link?.state?.sessions ?? const <SessionSummary>[];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _FilterSheet(
        scope: _scope,
        sort: _sort,
        onlyProjects: Set.of(_onlyProjects),
        projects: projects,
        sessions: sessions,
        onChanged: (scope, sort, onlyProjects) {
          if (!mounted) return;
          setState(() {
            _scope = scope;
            _sort = sort;
            _onlyProjects
              ..clear()
              ..addAll(onlyProjects);
          });
        },
      ),
    );
  }

  int _unread(PhoneLink link) {
    var count = 0;
    for (final session in link.state?.sessions ?? const <SessionSummary>[]) {
      if (session.unread) count++;
    }
    return count;
  }

  /// Picks a project to send files shared from other apps into.
  Future<void> _sendShared(PhoneLink link, AppState state) async {
    final projects = link.state?.projects ?? const <ProjectInfo>[];
    if (projects.isEmpty) {
      showBToast(context, '电脑上还没有可用的工作区。', isError: true);
      return;
    }
    final project = await showBActions<ProjectInfo>(
      context,
      title: '选择接收文件的工作区',
      leadingOf: (p) => _Tile(name: p.name),
      actions: [
        for (final p in projects) (null, p.name, p.path, p),
      ],
    );
    if (project == null || !mounted) return;
    final items = state.takeShared();
    if (items.isEmpty) return;
    setState(() {});
    final mentions = <String>[];
    var uploaded = 0;
    for (final item in items) {
      final path = item['path'] as String?;
      final name = item['name'] as String? ?? 'file';
      if (path == null) continue;
      try {
        final bytes = await File(path).readAsBytes();
        final reply = await link.upload(
          projectId: project.id,
          name: name,
          data: bytes,
        );
        final remotePath = reply['path'] as String?;
        if (remotePath != null) {
          mentions.add('@$remotePath');
          uploaded++;
        }
      } on Object catch (failure) {
        if (mounted) showBToast(context, '上传 $name 失败：$failure', isError: true);
      }
    }
    if (mentions.isEmpty || !mounted) return;
    try {
      final session = await link.draft(project.id);
      if (session != null && mounted) {
        await link.send(sessionId: session, text: mentions.join(' '));
        if (mounted) {
          showBToast(context, '已发送 $uploaded 个文件');
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChatPage(link: link, sessionId: session),
            ),
          );
        }
      }
    } on Object catch (failure) {
      if (mounted) showBToast(context, '发送失败：$failure', isError: true);
    }
  }

  /// Picks a project and starts its next conversation (the desktop's New
  /// Chat), then opens it.
  Future<void> _newChat(PhoneLink link) async {
    final projects = link.state?.projects ?? const <ProjectInfo>[];
    if (projects.isEmpty) {
      showBToast(context, '电脑上还没有项目。');
      return;
    }
    final project = await showBActions<ProjectInfo>(
      context,
      title: '选择项目',
      leadingOf: (p) => _Tile(name: p.name),
      actions: [
        for (final p in projects) (null, p.name, p.path, p),
      ],
    );
    if (project == null || !mounted) return;
    try {
      final session = await link.draft(project.id);
      if (session != null && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatPage(link: link, sessionId: session),
          ),
        );
      }
    } on Object catch (failure) {
      if (mounted) {
        showBToast(context, '$failure');
      }
    }
  }
}

/// Before any computer is paired.
class _NoComputers extends StatelessWidget {
  const _NoComputers({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.accent.withValues(alpha: 0.25),
                      AppColors.accent.withValues(alpha: 0.05),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(
                        alpha: MdTheme.dark ? 0.18 : 0.12,
                      ),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Image.asset(
                    'assets/branding/app_icon.png',
                    width: 84,
                    height: 84,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '欢迎使用宝码',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '与电脑上的 LangshenAgent 配对后，\n随时随地查看进度、审批操作并与智能体对话。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.55,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 30),
              BButton(
                label: '扫码配对电脑',
                icon: Icons.qr_code_scanner_rounded,
                primary: true,
                expand: true,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PairPage()),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The picked computer's name and state at the top, a tap picking another
/// (or pairing one).
class _ComputerTitle extends StatelessWidget {
  const _ComputerTitle({
    required this.state,
    required this.selected,
    required this.onPick,
  });

  final AppState state;
  final PhoneLink? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final link = selected;
    return Material(
      color: AppColors.surfaceRaised,
      shape: StadiumBorder(
        side: BorderSide(color: AppColors.partBorder, width: 0.75),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () async {
          PhonePlatform.haptic('selection');
          final id = await showBActions<String>(
            context,
            title: '切换电脑',
            selected: selected?.computer.id,
            actions: [
              for (final computer
                  in state.store?.computers.values ?? const <PairedComputer>[])
                () {
                  final l = state.links[computer.id];
                  final phase = l?.phase ?? PhonePhase.offline;
                  final phaseText = linkPhaseLabel(phase, error: l?.error);
                  final pathText = phase == PhonePhase.online && l != null
                      ? describeLinkPath(l.path)
                      : null;
                  return (
                    Icons.computer_outlined,
                    computer.name,
                    [phaseText, ?pathText].join(' · '),
                    computer.id,
                  );
                }(),
              (Icons.add_link, '配对新电脑', null, ''),
            ],
          );
          if (id == null || !context.mounted) return;
          if (id.isEmpty) {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const PairPage()));
            return;
          }
          onPick(id);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 6, 9, 6),
          child: ListenableBuilder(
            listenable: link ?? state,
            builder: (context, _) {
              final phase = link?.phase ?? PhonePhase.offline;
              final online = phase == PhonePhase.online;
              final connecting =
                  phase == PhonePhase.connecting || phase == PhonePhase.pairing;
              final dotColor = online
                  ? AppColors.accent
                  : connecting
                  ? AppColors.caution
                  : link?.needsRePair == true
                  ? AppColors.removed
                  : AppColors.textFaint;
              final running = online
                  ? (link?.state?.sessions
                            .where(
                              (s) => s.status == LinkSessionStatus.running,
                            )
                            .length ??
                        0)
                  : 0;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (connecting)
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: dotColor,
                      ),
                    )
                  else
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dotColor,
                        boxShadow: online
                            ? [
                                BoxShadow(
                                  color: dotColor.withValues(alpha: 0.5),
                                  blurRadius: 6,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      link?.computer.name ?? '未连接',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (running > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const BPulseDot(size: 6),
                          const SizedBox(width: 4),
                          Text(
                            '$running',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(width: 2),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The `+` at the top right: new chat, new group, add bot, pair computer.
class _PlusMenu extends StatelessWidget {
  const _PlusMenu({
    this.link,
    this.onPair,
    this.onNewChat,
    this.onNewGroup,
    this.onAddBot,
  });

  final PhoneLink? link;
  final VoidCallback? onPair;
  final VoidCallback? onNewChat;
  final VoidCallback? onNewGroup;
  final VoidCallback? onAddBot;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: const Icon(Icons.add_circle_outline),
    tooltip: '更多操作',
    onPressed: () async {
      final action = await showBActions<String>(
        context,
        actions: [
          if (onNewChat != null)
            (Icons.chat_bubble_outline, '新建对话', '选择项目开始新对话', 'chat'),
          if (onNewGroup != null)
            (Icons.groups_outlined, '发起群聊', '创建多 Bot 协作群聊', 'group'),
          if (onAddBot != null)
            (Icons.smart_toy_outlined, '添加 Bot', '新建自定义智能体', 'bot'),
          (Icons.add_link, '配对新电脑', '扫码或粘贴链接配对', 'pair'),
        ],
      );
      if (action == 'chat') {
        onNewChat?.call();
      } else if (action == 'group') {
        onNewGroup?.call();
      } else if (action == 'bot') {
        onAddBot?.call();
      } else if (action == 'pair') {
        onPair?.call();
      }
    },
  );
}

/// Filter icon button on the left of the home AppBar, with a small emerald
/// dot whenever a non-default filter is active.
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: '筛选',
    onPressed: onTap,
    icon: Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(
          Icons.tune_rounded,
          color: active ? AppColors.accent : AppColors.textPrimary,
        ),
        if (active)
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.background, width: 1.2),
              ),
            ),
          ),
      ],
    ),
  );
}

/// The bottom bar: four tabs, the picked one's icon in a green pill,
/// the chat tab's unread count in a red capsule.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.tab,
    required this.unread,
    required this.onSelect,
  });

  final int tab;
  final int unread;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    // (unselected outlined, selected filled) as the official app's tabs:
    // the filled one reads at a glance, the outlined ones stay quiet.
    final items = [
      (
        Icons.chat_bubble_outline_rounded,
        Icons.chat_bubble_rounded,
        '对话',
        unread,
      ),
      (
        Icons.smart_toy_outlined,
        Icons.smart_toy_rounded,
        'Bot',
        0,
      ),
      (
        Icons.folder_outlined,
        Icons.folder_rounded,
        '文件',
        0,
      ),
      (
        Icons.settings_outlined,
        Icons.settings_rounded,
        '设置',
        0,
      ),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        border: Border(
          top: BorderSide(color: AppColors.partBorder, width: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: MdTheme.dark
                ? Colors.black.withValues(alpha: 0.4)
                : const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 7, 8, 6),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _TabItem(
                    icon: items[i].$1,
                    selectedIcon: items[i].$2,
                    label: items[i].$3,
                    badge: items[i].$4,
                    selected: tab == i,
                    onTap: () {
                      if (tab != i) PhonePlatform.haptic('selection');
                      onSelect(i);
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

/// One tab in [_BottomBar]: icon (with its badge) over its label, the
/// icon in a soft emerald pill while selected.
class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.badge,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.textMuted;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                width: selected ? 54 : 38,
                height: 30,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.accent.withValues(
                          alpha: MdTheme.dark ? 0.16 : 0.12,
                        )
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    selected ? selectedIcon : icon,
                    key: ValueKey(selected),
                    size: 21,
                    color: color,
                  ),
                ),
              ),
              if (badge > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: BUnreadBadge(count: badge),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              color: color,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// A refined gradient squircle avatar tile keyed by name hash.
class _Tile extends StatelessWidget {
  const _Tile({required this.name, this.icon});

  final String name;
  final IconData? icon;
  static const size = 44.0;

  static const _palettes = [
    (Color(0xFF3B82F6), Color(0xFF2563EB)),
    (Color(0xFF10B981), Color(0xFF059669)),
    (Color(0xFF8B5CF6), Color(0xFF7C3AED)),
    (Color(0xFFF59E0B), Color(0xFFD97706)),
    (Color(0xFFEC4899), Color(0xFFDB2777)),
    (Color(0xFF06B6D4), Color(0xFF0891B2)),
    (Color(0xFF6366F1), Color(0xFF4F46E5)),
    (Color(0xFF14B8A6), Color(0xFF0D9488)),
  ];

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final label = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    final (top, bottom) = _palettes[name.hashCode.abs() % _palettes.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: MdTheme.dark
              ? [top.withValues(alpha: 0.85), bottom.withValues(alpha: 0.95)]
              : [top, bottom],
        ),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: Colors.white.withValues(alpha: MdTheme.dark ? 0.14 : 0.28),
          width: 0.75,
        ),
        boxShadow: [
          BoxShadow(
            color: bottom.withValues(alpha: MdTheme.dark ? 0.25 : 0.22),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: icon != null
          ? Icon(icon, color: Colors.white, size: 21)
          : Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.42,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
    );
  }
}

/// [at] as the chat list shows it: the time today, '昨天', the weekday
/// within the week, the date before that.
String _when(DateTime at) {
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  final then = DateTime(at.year, at.month, at.day);
  final days = day.difference(then).inDays;
  if (days <= 0) {
    final hour = at.hour.toString().padLeft(2, '0');
    final minute = at.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
  if (days == 1) return '昨天';
  if (days < 7) {
    return const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][then.weekday -
        1];
  }
  return '${at.month}月${at.day}日';
}

/// Classifies a project's environment from its path: SSH/WSL (`remote`) or local.
_WorkspaceScope _scopeOf(ProjectInfo? project) {
  final path = (project?.path ?? '').trim().toLowerCase();
  if (path.startsWith('ssh://') ||
      path.startsWith('ssh:') ||
      path.startsWith('remote+ssh:') ||
      path.startsWith('wsl://') ||
      path.startsWith('wsl:') ||
      path.startsWith(r'\\wsl') ||
      path.startsWith('//wsl')) {
    return _WorkspaceScope.remote;
  }
  return _WorkspaceScope.local;
}

/// 对话: the computer's workspaces as the official app lists them — a
/// workspace's name and how many agents it has, its latest one's words
/// under it, opening its sessions on a tap.
class _ChatsTab extends StatelessWidget {
  const _ChatsTab({
    this.link,
    this.scope = _WorkspaceScope.all,
    this.sort = _WorkspaceSort.recent,
    this.onlyProjects = const {},
    this.onResetFilter,
    this.onOpenSearch,
  });

  final PhoneLink? link;
  final _WorkspaceScope scope;
  final _WorkspaceSort sort;
  final Set<String> onlyProjects;
  final VoidCallback? onResetFilter;
  final VoidCallback? onOpenSearch;

  @override
  Widget build(BuildContext context) {
    if (link == null) {
      return const BEmptyState(
        icon: Icons.cloud_off_outlined,
        title: '电脑不在线',
        subtitle: '请确认电脑上的 LangshenAgent 已打开并联网。',
      );
    }
    return ListenableBuilder(
      listenable: link!,
      builder: (context, _) {
        final link = this.link!;
        final state = link.state;
        if (state == null) {
          return LinkUnavailableBody(
            link: link,
            offlineTitle: '无法加载对话',
            offlineSubtitle: '连接电脑后即可查看工作区与会话。',
            onRetry: () => link.retryNow(force: true),
          );
        }
        // A workspace's row: its sessions, the newest first; workspaces
        // sorted by pinned then recent activity or name.
        final byProject = <String, List<SessionSummary>>{};
        for (final session in state.sessions) {
          byProject.putIfAbsent(session.project, () => []).add(session);
        }
        final rows = <(ProjectInfo?, List<SessionSummary>)>[
          for (final entry in byProject.entries)
            (
              state.projects
                  .where((p) => p.id == entry.key)
                  .firstOrNull,
              entry.value
                ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
            ),
        ];
        if (scope != _WorkspaceScope.all) {
          rows.retainWhere((row) => _scopeOf(row.$1) == scope);
        }
        if (onlyProjects.isNotEmpty) {
          rows.retainWhere(
            (row) => row.$1 != null && onlyProjects.contains(row.$1!.id),
          );
        }
        rows.sort((a, b) {
          final ap = a.$1?.pinned ?? false;
          final bp = b.$1?.pinned ?? false;
          if (ap != bp) return ap ? -1 : 1;
          if (sort == _WorkspaceSort.name) {
            final an = (a.$1?.name ?? a.$2.first.title).toLowerCase();
            final bn = (b.$1?.name ?? b.$2.first.title).toLowerCase();
            return an.compareTo(bn);
          }
          return b.$2.first.updatedAt.compareTo(a.$2.first.updatedAt);
        });
        if (rows.isEmpty && state.projects.isEmpty) {
          return const BEmptyState(
            icon: Codicons.commentDiscussion,
            title: '还没有对话',
            subtitle: '在电脑上打开项目后，工作区会显示在这里。',
          );
        }
        final filteredEmpty =
            rows.isEmpty &&
            (scope != _WorkspaceScope.all || onlyProjects.isNotEmpty);
        return RefreshIndicator(
          onRefresh: () => link.refresh(),
          color: AppColors.accent,
          child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
          children: [
            if (onOpenSearch != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _SearchTriggerBar(onTap: onOpenSearch!),
              ),
            if (filteredEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: BEmptyState(
                  icon: Icons.filter_list_off_rounded,
                  title: '没有符合筛选条件的工作区',
                  subtitle: '调整范围或项目筛选条件即可查看全部工作区。',
                  actionLabel: onResetFilter != null ? '重置筛选' : null,
                  onAction: onResetFilter,
                ),
              )
            else if (rows.isNotEmpty)
              BCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var index = 0; index < rows.length; index++) ...[
                      Builder(
                        builder: (context) {
                          final (project, sessions) = rows[index];
                          final newest = sessions.first;
                          final unread = sessions.where((s) => s.unread).length;
                          final running = sessions
                              .where(
                                (s) => s.status == LinkSessionStatus.running,
                              )
                              .length;
                          final waiting = sessions
                              .where(
                                (s) => s.status == LinkSessionStatus.needsInput,
                              )
                              .length;
                          final activeColor = running > 0
                              ? AppColors.accent
                              : waiting > 0
                              ? Theme.of(context).colorScheme.error
                              : null;
                          return BSlidable(
                            pinned: project?.pinned ?? false,
                            onPin: project == null
                                ? null
                                : () => link.pinProject(
                                    project.id,
                                    !(project.pinned ?? false),
                                  ),
                            child: BInboxRow(
                              highlightColor: activeColor,
                              leading: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  _GroupTile(
                                    name: project?.name ?? newest.title,
                                  ),
                                  if (running > 0)
                                    const Positioned(
                                      right: -2,
                                      bottom: -2,
                                      child: BPulseDot(),
                                    )
                                  else if (waiting > 0)
                                    Positioned(
                                      right: -2,
                                      bottom: -2,
                                      child: BPulseDot(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                      ),
                                    ),
                                ],
                              ),
                              title:
                                  '${project?.name ?? newest.title}'
                                  '${sessions.length > 1 ? '（${sessions.length}）' : ''}',
                              titleTrailing: running > 0
                                  ? _StatusPill(
                                      label: running > 1
                                          ? '$running 进行中'
                                          : '进行中',
                                      color: AppColors.accent,
                                    )
                                  : waiting > 0
                                  ? _StatusPill(
                                      label: waiting > 1
                                          ? '$waiting 待输入'
                                          : '待输入',
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    )
                                  : null,
                              subtitle: Builder(
                                builder: (context) {
                                  final appState = AppScope.of(context);
                                  String? draft;
                                  for (final s in sessions) {
                                    final d = appState.draftOf(s.id);
                                    if (d.isNotEmpty) {
                                      draft = d;
                                      break;
                                    }
                                  }
                                  if (draft != null) {
                                    return Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text: '[草稿] ',
                                            style: TextStyle(
                                              color: AppColors.removed,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          TextSpan(
                                            text: draft
                                                .replaceAll(RegExp(r'\s+'), ' ')
                                                .trim(),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  return Text(newest.title);
                                },
                              ),
                              time: _when(newest.updatedAt),
                              badge: unread,
                              pinned: unread == 0 && (project?.pinned ?? false),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => _WorkspacePage(
                                    link: link,
                                    project: project,
                                    fallback: newest.title,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      if (index < rows.length - 1) const BDivider(),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 12),
            BCard(
              padding: EdgeInsets.zero,
              child: BInboxRow(
                titleWeight: FontWeight.w500,
                title: '添加工作区',
                subtitle: Text(
                  '从电脑上选择工作区',
                  style: TextStyle(color: AppColors.textFaint),
                ),
                leading: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.25),
                      width: 0.75,
                    ),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(Codicons.add, color: AppColors.accent, size: 20),
                ),
                onTap: () => _pickWorkspace(context, link, state),
              ),
            ),
          ],
        ),
        );
      },
    );
  }
}

/// Banner shown when other apps shared files into LangshenAgent.
class _SharedIncomingBanner extends StatelessWidget {
  const _SharedIncomingBanner({
    required this.count,
    required this.onSend,
    required this.onDismiss,
  });

  final int count;
  final VoidCallback onSend;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
    child: BCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          Icon(Icons.file_present_rounded, size: 18, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '收到 $count 个待发送的分享文件',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          BButton(label: '选择发送', primary: true, onPressed: onSend),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(Codicons.close, size: 16, color: AppColors.textMuted),
            visualDensity: VisualDensity.compact,
            onPressed: onDismiss,
          ),
        ],
      ),
    ),
  );
}

/// The computer's workspaces to add one of: all of them the chats don't
/// lead with — the sheets shows each by its icon tile and path.
void _pickWorkspace(
  BuildContext context,
  PhoneLink link,
  LinkState state,
) {
  final projects = [...state.projects]..sort((a, b) {
    if ((a.pinned ?? false) != (b.pinned ?? false)) {
      return (b.pinned ?? false) ? 1 : -1;
    }
    return a.name.compareTo(b.name);
  });
  showBActions<String>(
    context,
    title: '添加工作区',
    leadingOf: (value) {
      for (final p in projects) {
        if (p.id == value) return _Tile(name: p.name);
      }
      return null;
    },
    actions: [
        (Icons.folder_open, '在电脑上选择文件夹…', null, 'browse'),
        for (final project in projects)
          (null, project.name, project.path, project.id),
    ],
  ).then((picked) async {
    if (picked == null || !context.mounted) return;
    ProjectInfo? project;
    if (picked == 'browse') {
      project = await Navigator.of(context).push<ProjectInfo>(
        MaterialPageRoute(builder: (_) => BrowsePage(link: link)),
      );
    } else {
      for (final p in projects) {
        if (p.id == picked) project = p;
      }
    }
    if (project == null || !context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _WorkspacePage(
          link: link,
          project: project,
          fallback: project!.name,
        ),
      ),
    );
  });
}

/// A workspace's avatar tile: refined tinted squircle with crisp monogram
/// and subtle workspace badge.
class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => _Tile(name: name);
}

/// High-visibility status pill for active ("进行中") or waiting ("待输入")
/// workspaces and sessions.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: MdTheme.dark ? 0.2 : 0.13),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: color.withValues(alpha: MdTheme.dark ? 0.45 : 0.35),
        width: 0.75,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BPulseDot(size: 6, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
            height: 1.15,
          ),
        ),
      ],
    ),
  );
}

/// A workspace's page (as the official's project view): its name on top,
/// its agents under it, each opening its conversation.
class _WorkspacePage extends StatelessWidget {
  const _WorkspacePage({
    required this.link,
    required this.project,
    required this.fallback,
  });

  final PhoneLink link;
  final ProjectInfo? project;

  /// The name to show when the workspace is gone from the list.
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final name = project?.name ?? fallback;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17),
            ),
            Text(
              link.computer.name,
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_square),
            tooltip: '新建对话',
            onPressed: project == null
                ? null
                : () async {
                    try {
                      final session = await link.draft(project!.id);
                      if (session != null && context.mounted) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                ChatPage(link: link, sessionId: session),
                          ),
                        );
                      }
                    } on Object catch (failure) {
                      if (context.mounted) {
                        showBToast(context, '$failure');
                      }
                    }
                  },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: link,
        builder: (context, _) {
          final sessions = [
            for (final session in link.state?.sessions ??
                const <SessionSummary>[])
              if (project == null || session.project == project!.id) session,
          ]..sort((a, b) {
              if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
              return b.updatedAt.compareTo(a.updatedAt);
            });
          if (sessions.isEmpty) {
            return const BEmptyState(
              icon: Icons.chat_bubble_outline,
              title: '还没有会话',
              subtitle: '点右上角可以在此工作区新建对话。',
            );
          }
          return RefreshIndicator(
            onRefresh: () => link.refresh(),
            color: AppColors.accent,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
              children: [
                BCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var index = 0; index < sessions.length; index++) ...[
                        _SessionRow(link: link, session: sessions[index]),
                        if (index < sessions.length - 1) const BDivider(),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.link, required this.session});

  final PhoneLink link;
  final SessionSummary session;

  @override
  Widget build(BuildContext context) {
    ProjectInfo? project;
    for (final p in link.state?.projects ?? const <ProjectInfo>[]) {
      if (p.id == session.project) project = p;
    }
    final isRunning = session.status == LinkSessionStatus.running;
    final needsInput = session.status == LinkSessionStatus.needsInput;
    final activeColor = isRunning
        ? AppColors.accent
        : needsInput
        ? Theme.of(context).colorScheme.error
        : null;
    return BSlidable(
      pinned: session.pinned,
      onPin: () => link.pin(session.id, !session.pinned),
      onDelete: () => _delete(context),
      child: BInboxRow(
        highlightColor: activeColor,
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            _Tile(name: session.title.isEmpty ? '对' : session.title),
            if (isRunning)
              const Positioned(right: -1, bottom: -1, child: BPulseDot())
            else if (needsInput)
              Positioned(
                right: -1,
                bottom: -1,
                child: BPulseDot(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
          ],
        ),
        title: session.title.isEmpty ? '未命名' : session.title,
        titleTrailing: isRunning
            ? _StatusPill(label: '进行中', color: AppColors.accent)
            : needsInput
            ? _StatusPill(
                label: '待输入',
                color: Theme.of(context).colorScheme.error,
              )
            : null,
        titleWeight: session.unread || isRunning || needsInput
            ? FontWeight.w600
            : FontWeight.w500,
        subtitle: Builder(
          builder: (context) {
            final draft = AppScope.of(context).draftOf(session.id);
            if (draft.isNotEmpty) {
              return Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '[草稿] ',
                      style: TextStyle(
                        color: AppColors.removed,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    TextSpan(
                      text: draft.replaceAll(RegExp(r'\s+'), ' ').trim(),
                    ),
                  ],
                ),
              );
            }
            return Text(
              [
                if (!isRunning && !needsInput) '已完成',
                if (project != null) project.name,
                if (session.model != null) session.model!,
              ].join(' · '),
            );
          },
        ),
        time: _when(session.updatedAt),
        badge: session.unread ? 1 : 0,
        pinned: !session.unread && session.pinned,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatPage(link: link, sessionId: session.id),
          ),
        ),
        onLongPress: () => _manage(context),
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    if (await showBConfirm(context, title: '删除这个会话？', confirm: '删除', danger: true)) {
      await link.delete(session.id);
    }
  }

  Future<void> _manage(BuildContext context) async {
    final action = await showBActions<String>(
      context,
      danger: const {'delete'},
      actions: [
        (
          Icons.push_pin_outlined,
          session.pinned ? '取消置顶' : '置顶',
          null,
          'pin',
        ),
        (Icons.drive_file_rename_outline, '重命名', null, 'rename'),
        (Icons.archive_outlined, '归档', null, 'archive'),
        (Icons.delete_outline, '删除', null, 'delete'),
      ],
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'pin':
        await link.pin(session.id, !session.pinned);
      case 'rename':
        final title = await showBPrompt(
          context,
          title: '重命名',
          initial: session.title,
        );
        if (title != null && title.isNotEmpty) {
          await link.rename(session.id, title);
        }
      case 'archive':
        await link.archive(session.id);
      case 'delete':
        if (await showBConfirm(
          context,
          title: '删除这个会话？',
          confirm: '删除',
          danger: true,
        )) {
          await link.delete(session.id);
        }
    }
  }
}

/// Bot: the computer's bots, their status and last word.
class _BotsTab extends StatelessWidget {
  const _BotsTab({this.link});

  final PhoneLink? link;

  @override
  Widget build(BuildContext context) {
    if (link == null) {
      return const BEmptyState(
        icon: Icons.cloud_off_outlined,
        title: '电脑不在线',
        subtitle: '连接电脑后才能查看 Bot 与群聊。',
      );
    }
    return ListenableBuilder(
      listenable: link!,
      builder: (context, _) {
        final linkState = link!.state;
        if (linkState == null) {
          return LinkUnavailableBody(
            link: link!,
            offlineTitle: '无法加载 Bot',
            offlineSubtitle: '连接电脑后即可查看 Bot 与群聊。',
            onRetry: () => link!.retryNow(force: true),
          );
        }
        final bots = linkState.bots;
        final groups = linkState.groups;
        if (bots.isEmpty && groups.isEmpty) {
          return const BEmptyState(
            icon: Codicons.hubot,
            title: '还没有 Bot',
            subtitle: '在电脑上创建 Bot 后会显示在这里。',
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
          children: [
            if (bots.isNotEmpty)
              BSection(
                title: 'Bot',
                children: [
                  for (var i = 0; i < bots.length; i++) ...[
                    BInboxRow(
                      leading: BotAvatar(link: link!, bot: bots[i]),
                      title: bots[i].name,
                      titleWeight: bots[i].unread > 0
                          ? FontWeight.w600
                          : FontWeight.w500,
                      subtitle: Text(bots[i].last ?? bots[i].signature),
                      time: bots[i].updatedAt == null
                          ? null
                          : _when(bots[i].updatedAt!),
                      badge: bots[i].unread,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChatPage(link: link!, bot: bots[i]),
                        ),
                      ),
                      onLongPress: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              BotEditPage(link: link!, bot: bots[i]),
                        ),
                      ),
                    ),
                    if (i < bots.length - 1) const BDivider(),
                  ],
                ],
              ),
            if (groups.isNotEmpty)
              BSection(
                title: '群聊',
                children: [
                  for (var i = 0; i < groups.length; i++) ...[
                    BInboxRow(
                      leading: _Tile(name: groups[i].name),
                      title: groups[i].name,
                      titleWeight: groups[i].unread > 0
                          ? FontWeight.w600
                          : FontWeight.w500,
                      subtitle: Text(
                        [
                          if (groups[i].members.isNotEmpty)
                            '${groups[i].members.length} 个成员',
                          if (groups[i].typing.isNotEmpty) '正在输入…',
                        ].join(' · '),
                      ),
                      time: groups[i].updatedAt == null
                          ? null
                          : _when(groups[i].updatedAt!),
                      badge: groups[i].unread,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              GroupPage(link: link!, group: groups[i]),
                        ),
                      ),
                      onLongPress: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              GroupEditPage(link: link!, group: groups[i]),
                        ),
                      ),
                    ),
                    if (i < groups.length - 1) const BDivider(),
                  ],
                ],
              ),
            BCard(
              padding: EdgeInsets.zero,
              child: BInboxRow(
                titleWeight: FontWeight.w500,
                title: '新建群聊',
                subtitle: Text(
                  '创建多 Bot 群聊',
                  style: TextStyle(color: AppColors.textFaint),
                ),
                leading: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.25),
                      width: 0.75,
                    ),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(Codicons.add, color: AppColors.accent, size: 20),
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GroupEditPage(link: link!),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 文件: the computer's projects; a tap opens its browser.
class _FilesTab extends StatelessWidget {
  const _FilesTab({this.link});

  final PhoneLink? link;

  @override
  Widget build(BuildContext context) {
    if (link == null) {
      return const BEmptyState(
        icon: Icons.cloud_off_outlined,
        title: '电脑不在线',
        subtitle: '连接电脑后才能浏览项目文件。',
      );
    }
    return ListenableBuilder(
      listenable: link!,
      builder: (context, _) {
        final linkState = link!.state;
        if (linkState == null) {
          return LinkUnavailableBody(
            link: link!,
            offlineTitle: '无法加载项目',
            offlineSubtitle: '连接电脑后即可浏览项目文件。',
            onRetry: () => link!.retryNow(force: true),
          );
        }
        final projects = [...linkState.projects]
          ..sort((a, b) {
            if (a.pinned == true && b.pinned != true) return -1;
            if (b.pinned == true && a.pinned != true) return 1;
            return a.name.compareTo(b.name);
          });
        if (projects.isEmpty) {
          return const BEmptyState(
            icon: Codicons.folder,
            title: '还没有项目',
            subtitle: '在电脑上打开文件夹作为工作区后会出现在这里。',
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
          children: [
            BCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var index = 0; index < projects.length; index++) ...[
                    BInboxRow(
                      leading: _Tile(
                        name: projects[index].name,
                        icon: Icons.folder_rounded,
                      ),
                      title: projects[index].name,
                      pinned: projects[index].pinned == true,
                      subtitle: Text(
                        [
                          projects[index].path,
                          if (projects[index].branch != null)
                            '⎇ ${projects[index].branch}',
                        ].join('  '),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FolderPage(
                            link: link!,
                            project: projects[index],
                          ),
                        ),
                      ),
                    ),
                    if (index < projects.length - 1) const BDivider(),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Tappable search bar at the top of the workspace list that opens [_SearchPage].
class _SearchTriggerBar extends StatelessWidget {
  const _SearchTriggerBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceRaised,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.partBorder, width: 0.75),
        ),
        child: Row(
          children: [
            Icon(Codicons.search, size: 17, color: AppColors.textFaint),
            const SizedBox(width: 9),
            Text(
              '搜索工作区、会话或 Bot',
              style: TextStyle(fontSize: 14, color: AppColors.textFaint),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Filter sheet for scope (全部/本机/SSH/WSL), sort (最近活动/名称), and
/// project multi-select with "全部项目" selected by default. Selecting scope or
/// sort immediately filters & sorts both the project list below and the
/// workspace list behind the sheet.
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.scope,
    required this.sort,
    required this.onlyProjects,
    required this.projects,
    required this.sessions,
    required this.onChanged,
  });

  final _WorkspaceScope scope;
  final _WorkspaceSort sort;
  final Set<String> onlyProjects;
  final List<ProjectInfo> projects;
  final List<SessionSummary> sessions;
  final void Function(
    _WorkspaceScope scope,
    _WorkspaceSort sort,
    Set<String> onlyProjects,
  ) onChanged;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late _WorkspaceScope _scope = widget.scope;
  late _WorkspaceSort _sort = widget.sort;
  late final Set<String> _onlyProjects = Set.of(widget.onlyProjects);

  bool get _dirty =>
      _scope != _WorkspaceScope.all ||
      _sort != _WorkspaceSort.recent ||
      _onlyProjects.isNotEmpty;

  void _emit() => widget.onChanged(_scope, _sort, Set.of(_onlyProjects));

  @override
  Widget build(BuildContext context) {
    final latestByProject = <String, DateTime>{};
    for (final s in widget.sessions) {
      final prev = latestByProject[s.project];
      if (prev == null || s.updatedAt.isAfter(prev)) {
        latestByProject[s.project] = s.updatedAt;
      }
    }
    final filteredProjects = [
      for (final p in widget.projects)
        if (_scope == _WorkspaceScope.all || _scopeOf(p) == _scope) p,
    ]..sort((a, b) {
        if (_sort == _WorkspaceSort.name) {
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        }
        final at = latestByProject[a.id];
        final bt = latestByProject[b.id];
        if (at != null && bt != null) return bt.compareTo(at);
        if (at != null) return -1;
        if (bt != null) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.78,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 12, 8),
              child: Row(
                children: [
                  Text(
                    '筛选与排序',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  if (_dirty)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _scope = _WorkspaceScope.all;
                          _sort = _WorkspaceSort.recent;
                          _onlyProjects.clear();
                        });
                        _emit();
                      },
                      child: Text(
                        '重置',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  BButton(
                    label: '完成',
                    primary: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                children: [
                  _sheetHeading('范围'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (value, label) in const [
                        (_WorkspaceScope.all, '全部'),
                        (_WorkspaceScope.local, '本机'),
                        (_WorkspaceScope.remote, 'SSH/WSL'),
                      ])
                        _filterChip(
                          label: label,
                          selected: _scope == value,
                          onTap: () {
                            setState(() {
                              _scope = value;
                              // Drop project picks outside the new scope.
                              if (value != _WorkspaceScope.all) {
                                final allowed = {
                                  for (final p in widget.projects)
                                    if (_scopeOf(p) == value) p.id,
                                };
                                _onlyProjects.retainWhere(allowed.contains);
                              }
                            });
                            _emit();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _sheetHeading('排序'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (value, label) in const [
                        (_WorkspaceSort.recent, '最近活动'),
                        (_WorkspaceSort.name, '名称'),
                      ])
                        _filterChip(
                          label: label,
                          selected: _sort == value,
                          onTap: () {
                            setState(() => _sort = value);
                            _emit();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      _sheetHeading('只看项目'),
                      const SizedBox(width: 6),
                      Text(
                        '(${filteredProjects.length})',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textFaint,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: AppColors.bubbleFill,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.partBorder,
                        width: 0.75,
                      ),
                    ),
                    child: Column(
                      children: [
                        _projectCheckRow(
                          title: '全部项目',
                          subtitle: _scope == _WorkspaceScope.all
                              ? '显示所有工作区'
                              : '显示当前范围下的全部工作区',
                          checked: _onlyProjects.isEmpty,
                          onTap: () {
                            setState(() => _onlyProjects.clear());
                            _emit();
                          },
                        ),
                        if (filteredProjects.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            child: Text(
                              '当前范围下没有项目',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textFaint,
                              ),
                            ),
                          )
                        else
                          for (final project in filteredProjects) ...[
                            Divider(
                              height: 0.5,
                              indent: 46,
                              color: AppColors.partBorder,
                            ),
                            _projectCheckRow(
                              title: project.name,
                              subtitle: project.path,
                              checked: _onlyProjects.contains(project.id),
                              onTap: () {
                                setState(() {
                                  if (_onlyProjects.contains(project.id)) {
                                    _onlyProjects.remove(project.id);
                                  } else {
                                    _onlyProjects.add(project.id);
                                  }
                                });
                                _emit();
                              },
                            ),
                          ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetHeading(String text) => Text(
    text,
    style: TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: AppColors.textMuted,
    ),
  );

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.accent.withValues(alpha: MdTheme.dark ? 0.2 : 0.13)
            : AppColors.bubbleFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? AppColors.accent : AppColors.partBorder,
          width: selected ? 1.2 : 0.75,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? AppColors.accent : AppColors.textPrimary,
        ),
      ),
    ),
  );

  Widget _projectCheckRow({
    required String title,
    required String subtitle,
    required bool checked,
    required VoidCallback onTap,
  }) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(
            checked ? Icons.check_box_rounded : Icons.check_box_outline_blank,
            size: 20,
            color: checked ? AppColors.accent : AppColors.textFaint,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: checked ? FontWeight.w600 : FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Dedicated search page for workspaces, sessions, and bots.
class _SearchPage extends StatefulWidget {
  const _SearchPage({required this.link});

  final PhoneLink link;

  @override
  State<_SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<_SearchPage> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needle = _query.text.trim().toLowerCase();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 14),
          child: TextField(
            controller: _query,
            autofocus: true,
            style: TextStyle(fontSize: 15, color: AppColors.textPrimary),
            decoration: BTextField.decoration(
              hint: '搜索工作区、会话或 Bot',
              radius: 12,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 9,
              ),
            ).copyWith(
              suffixIcon: _query.text.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(
                        Codicons.close,
                        size: 16,
                        color: AppColors.textMuted,
                      ),
                      onPressed: () => setState(() => _query.clear()),
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ),
      body: ListenableBuilder(
        listenable: widget.link,
        builder: (context, _) {
          final state = widget.link.state;
          if (state == null) {
            return LinkUnavailableBody(
              link: widget.link,
              offlineTitle: '电脑未连接',
              offlineSubtitle: '连接电脑后即可搜索工作区与会话。',
              onRetry: () => widget.link.retryNow(force: true),
            );
          }
          if (needle.isEmpty) {
            return const BEmptyState(
              icon: Codicons.search,
              title: '搜索工作区与对话',
              subtitle: '输入项目名、路径、会话标题或 Bot 名称。',
            );
          }
          final projects = [
            for (final p in state.projects)
              if (p.name.toLowerCase().contains(needle) ||
                  p.path.toLowerCase().contains(needle))
                p,
          ];
          final sessions = [
            for (final s in state.sessions)
              if (s.title.toLowerCase().contains(needle)) s,
          ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          final bots = [
            for (final b in state.bots)
              if (b.name.toLowerCase().contains(needle) ||
                  b.signature.toLowerCase().contains(needle))
                b,
          ];
          if (projects.isEmpty && sessions.isEmpty && bots.isEmpty) {
            return const BEmptyState(
              icon: Codicons.search,
              title: '没有找到匹配结果',
              subtitle: '换个关键词试试。',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
            children: [
              if (projects.isNotEmpty)
                BSection(
                  title: '工作区',
                  children: [
                    for (var i = 0; i < projects.length; i++) ...[
                      BInboxRow(
                        leading: _Tile(name: projects[i].name),
                        title: projects[i].name,
                        subtitle: Text(projects[i].path),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => _WorkspacePage(
                              link: widget.link,
                              project: projects[i],
                              fallback: projects[i].name,
                            ),
                          ),
                        ),
                      ),
                      if (i < projects.length - 1) const BDivider(),
                    ],
                  ],
                ),
              if (sessions.isNotEmpty)
                BSection(
                  title: '会话',
                  children: [
                    for (var i = 0; i < sessions.length; i++) ...[
                      _SessionRow(link: widget.link, session: sessions[i]),
                      if (i < sessions.length - 1) const BDivider(),
                    ],
                  ],
                ),
              if (bots.isNotEmpty)
                BSection(
                  title: 'Bot',
                  children: [
                    for (var i = 0; i < bots.length; i++) ...[
                      BInboxRow(
                        leading: BotAvatar(link: widget.link, bot: bots[i]),
                        title: bots[i].name,
                        subtitle: Text(bots[i].last ?? bots[i].signature),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                ChatPage(link: widget.link, bot: bots[i]),
                          ),
                        ),
                      ),
                      if (i < bots.length - 1) const BDivider(),
                    ],
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
