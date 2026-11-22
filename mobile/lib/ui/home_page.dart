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
import 'chat_page.dart';
import 'files_page.dart';
import 'md/md_theme.dart';
import 'widgets.dart';
import 'pair_page.dart';
import 'settings_page.dart';
import 'update_dialog.dart';

/// The app's home: the official phone app's shell — a computer picked at
/// the top, its conversations, bots, files and settings in the bottom
/// bar's four tabs.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int _tab = 0;
  String? _computerId;
  bool _searching = false;
  final _search = TextEditingController();
  DateTime _checkedUpdateAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
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

  /// The computer the tabs show: the picked one, else any online, else
  /// the first paired.
  PhoneLink? get _link {
    final links = _state.links;
    if (_computerId != null && links.containsKey(_computerId)) {
      return links[_computerId];
    }
    for (final link in links.values) {
      if (link.phase == PhonePhase.online) return link;
    }
    return links.values.firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    // The app's colors follow the system's light or dark; kept here so
    // the AppColors below (which read it) are right before any page's
    // markdown sets it again.
    MdTheme.dark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final state = _state;
    if (state.store?.computers.isNotEmpty != true) {
      return _NoComputers(state: state);
    }
    final link = _link;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                decoration: BTextField.decoration(hint: '搜索工作区或会话'),
                onChanged: (_) => setState(() {}),
              )
            : _ComputerTitle(
                state: state,
                selected: link,
                onPick: (id) => setState(() => _computerId = id),
              ),
        actions: [
          IconButton(
            icon: Icon(_searching ? Codicons.close : Codicons.search),
            tooltip: _searching ? '关闭搜索' : '搜索',
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _search.clear();
            }),
          ),
          _PlusMenu(
            link: link,
            onPair: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const PairPage())),
            onNewChat: link == null ? null : () => _newChat(link),
          ),
        ],
      ),
      body: switch (_tab) {
        0 => _ChatsTab(
            link: link,
            query: _searching ? _search.text.trim() : '',
          ),
        1 => _BotsTab(link: link),
        2 => _FilesTab(link: link),
        _ => SettingsPage(link: link),
      },
      bottomNavigationBar: _BottomBar(
        tab: _tab,
        unread: link == null ? 0 : _unread(link),
        onSelect: (tab) => setState(() => _tab = tab),
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
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: ColorFiltered(
                colorFilter: const ColorFilter.mode(
                  Color(0xFFBBBBBB),
                  BlendMode.modulate,
                ),
                child: Image.asset(
                  'assets/branding/app_icon.png',
                  width: 96,
                  height: 96,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '还没有配对的电脑',
              style: TextStyle(fontSize: 17, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              '与电脑上的 LangshenAgent 配对后，就能在这\n里查看和操作它的智能体。',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, height: 1.5),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const PairPage())),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('配对新电脑'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
              ),
            ),
          ],
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
    final online = selected?.phase == PhonePhase.online;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final id = await showBActions<String>(
          context,
          selected: selected?.computer.id,
          actions: [
            for (final computer
                in state.store?.computers.values ?? const <PairedComputer>[])
              (
                Icons.computer_outlined,
                computer.name,
                switch (state.links[computer.id]?.phase) {
                  PhonePhase.online => '在线',
                  PhonePhase.connecting => '连接中…',
                  _ => '离线',
                },
                computer.id,
              ),
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.circle,
              size: 8,
              color: online ? AppColors.accent : AppColors.textFaint,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                selected?.computer.name ?? '未连接',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down, size: 18),
            if (selected != null)
              ListenableBuilder(
                listenable: selected!,
                builder: (context, _) {
                  final running = selected!.state?.sessions
                          .where(
                            (s) => s.status == LinkSessionStatus.running,
                          )
                          .length ??
                      0;
                  if (running == 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const BPulseDot(size: 8),
                        const SizedBox(width: 4),
                        Text(
                          '$running',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// The `+` at the top right: a new chat, a pairing.
class _PlusMenu extends StatelessWidget {
  const _PlusMenu({this.link, this.onPair, this.onNewChat});

  final PhoneLink? link;
  final VoidCallback? onPair;
  final VoidCallback? onNewChat;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: const Icon(Icons.add_circle_outline),
    onPressed: () async {
      final action = await showBActions<String>(
        context,
        actions: const [
          (Icons.chat_bubble_outline, '新建对话', null, 'chat'),
          (Icons.add_link, '配对新电脑', null, 'pair'),
        ],
      );
      if (action == 'chat') {
        onNewChat?.call();
      } else if (action == 'pair') {
        onPair?.call();
      }
    },
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
    final items = [
      (Codicons.commentDiscussion, '对话', unread),
      (Codicons.hubot, 'Bot', 0),
      (Codicons.folder, '文件', 0),
      (Codicons.gear, '设置', 0),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        border: Border(
          top: BorderSide(color: AppColors.partBorder, width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _TabItem(
                    icon: items[i].$1,
                    label: items[i].$2,
                    badge: items[i].$3,
                    selected: tab == i,
                    onTap: () => onSelect(i),
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
/// icon in a soft green pill while selected.
class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.icon,
    required this.label,
    required this.badge,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
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
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: selected ? 52 : 40,
                height: 30,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.accent.withValues(alpha: 0.14)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              if (badge > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: _CountBadge(count: badge),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              color: color,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

/// The red unread capsule at a tab icon's corner.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 16),
    height: 16,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFFA5151),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.surfaceRaised, width: 1.5),
    ),
    alignment: Alignment.center,
    child: Text(
      count > 99 ? '99+' : '$count',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 9.5,
        fontWeight: FontWeight.w600,
        height: 1,
      ),
    ),
  );
}

/// A name's avatar tile: its first letter on a color its hash picks, as
/// the official app draws conversation icons.
class _Tile extends StatelessWidget {
  const _Tile({required this.name, this.size = 44});

  final String name;
  final double size;

  static const _colors = [
    Color(0xFF5B8FF9),
    Color(0xFF5AD8A6),
    Color(0xFF9270CA),
    Color(0xFFF6BD16),
    Color(0xFFE8684A),
    Color(0xFF6DC8EC),
    Color(0xFFFF9D4D),
    Color(0xFF269A99),
  ];

  @override
  Widget build(BuildContext context) {
    final label = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final color = _colors[name.hashCode.abs() % _colors.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w600,
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

/// 对话: the computer's workspaces as the official app lists them — a
/// workspace's name and how many agents it has, its latest one's words
/// under it, opening its sessions on a tap.
class _ChatsTab extends StatelessWidget {
  const _ChatsTab({this.link, this.query = ''});

  final PhoneLink? link;
  final String query;

  @override
  Widget build(BuildContext context) {
    if (link == null) {
      return const Center(child: Text('电脑不在线'));
    }
    return ListenableBuilder(
      listenable: link!,
      builder: (context, _) {
        final link = this.link!;
        final state = link.state;
        if (state == null) {
          return const Center(child: CircularProgressIndicator());
        }
        // A workspace's row: its sessions, the newest first; workspaces
        // by their newest.
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
        ]..sort((a, b) {
            final ap = a.$1?.pinned ?? false;
            final bp = b.$1?.pinned ?? false;
            if (ap != bp) return ap ? -1 : 1;
            return b.$2.first.updatedAt.compareTo(a.$2.first.updatedAt);
          });
        if (query.isNotEmpty) {
          final needle = query.toLowerCase();
          rows.retainWhere(
            (row) =>
                (row.$1?.name.toLowerCase().contains(needle) ?? false) ||
                (row.$1?.path.toLowerCase().contains(needle) ?? false) ||
                row.$2.any((s) => s.title.toLowerCase().contains(needle)),
          );
        }
        if (rows.isEmpty && state.projects.isEmpty) {
          return Center(
            child: Text('还没有对话', style: TextStyle(color: AppColors.textMuted)),
          );
        }
        // A last row adds a workspace the computer already has — one the
        // chats don't show yet, e.g. a fresh or an empty one.
        return ListView.separated(
          itemCount: rows.length + 1,
          separatorBuilder: (_, _) => Divider(
            height: 0.5,
            indent: 72,
            color: AppColors.partBorder,
          ),
          itemBuilder: (context, index) {
            if (index == rows.length) {
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                leading: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.partBorder),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Codicons.add, color: AppColors.textMuted),
                ),
                title: Text(
                  '添加工作区',
                  style: TextStyle(color: AppColors.textMuted),
                ),
                onTap: () => _pickWorkspace(context, link, state),
              );
            }
            final (project, sessions) = rows[index];
            final newest = sessions.first;
            final unread = sessions.where((s) => s.unread).length;
            final running = sessions
                .where((s) => s.status == LinkSessionStatus.running)
                .length;
            final waiting = sessions
                .where((s) => s.status == LinkSessionStatus.needsInput)
                .length;
            return BSlidable(
              pinned: project?.pinned ?? false,
              onPin: project == null
                  ? null
                  : () => link.pinProject(
                      project.id,
                      !(project.pinned ?? false),
                    ),
              child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ),
              leading: Stack(
                clipBehavior: Clip.none,
                children: [
                  _GroupTile(name: project?.name ?? newest.title),
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
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
              title: Text(
                '${project?.name ?? newest.title}'
                '${sessions.length > 1 ? '（${sessions.length}）' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text.rich(
                TextSpan(
                  children: [
                    if (running > 0)
                      TextSpan(
                        text: '$running 个进行中 · ',
                        style: TextStyle(color: AppColors.accent),
                      )
                    else if (waiting > 0)
                      TextSpan(
                        text: '$waiting 个待输入 · ',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    TextSpan(text: newest.title),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _when(newest.updatedAt),
                    style: TextStyle(fontSize: 11.5, color: AppColors.textFaint),
                  ),
                  const SizedBox(height: 4),
                  if (unread > 0)
                    Badge(label: Text('$unread'))
                  else if (project?.pinned ?? false)
                    Icon(
                      Icons.push_pin,
                      size: 14,
                      color: AppColors.textFaint,
                    ),
                ],
              ),
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
        );
      },
    );
  }
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

/// A workspace's icon: up to four of its name's characters in a square
/// of tinted cells, as the official app draws them.
class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.name});

  final String name;

  static const _tints = [
    Color(0xFF5B8FF9),
    Color(0xFF5AD8A6),
    Color(0xFF9270CA),
    Color(0xFFE8684A),
    Color(0xFF6DC8EC),
    Color(0xFFF6BD16),
  ];

  @override
  Widget build(BuildContext context) {
    final chars = name.trim().isEmpty
        ? ['?']
        : name.trim().split('').take(4).toList();
    final cells = chars.length <= 2 ? 1 : 2;
    return Container(
      width: 44,
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.bubbleFill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: GridView.count(
        crossAxisCount: cells,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        children: [
          for (final (i, char) in chars.indexed)
            Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _tints[i % _tints.length],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                char,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: cells == 1 ? 16 : 9.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
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
            return Center(
              child: Text(
                '还没有会话',
                style: TextStyle(color: AppColors.textMuted),
              ),
            );
          }
          return ListView.separated(
            itemCount: sessions.length,
            separatorBuilder: (_, _) => Divider(
              height: 0.5,
              indent: 72,
              color: AppColors.partBorder,
            ),
            itemBuilder: (context, index) =>
                _SessionRow(link: link, session: sessions[index]),
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
    return BSlidable(
      pinned: session.pinned,
      onPin: () => link.pin(session.id, !session.pinned),
      onDelete: () => _delete(context),
      child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          _Tile(name: session.title.isEmpty ? '对' : session.title),
          if (session.status == LinkSessionStatus.running)
            const Positioned(right: -1, bottom: -1, child: BPulseDot())
          else if (session.status == LinkSessionStatus.needsInput)
            Positioned(
              right: -1,
              bottom: -1,
              child: BPulseDot(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
        ],
      ),
      title: Text(
        session.title.isEmpty ? '未命名' : session.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: session.unread ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      subtitle: Text(
        [
          switch (session.status) {
            LinkSessionStatus.running => '进行中',
            LinkSessionStatus.needsInput => '待输入',
            LinkSessionStatus.idle => '已完成',
          },
          if (project != null) project.name,
          if (session.model != null) session.model!,
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _when(session.updatedAt),
            style: TextStyle(fontSize: 11.5, color: AppColors.textFaint),
          ),
          const SizedBox(height: 4),
          if (session.unread)
            const Badge(label: Text("1"))
          else if (session.pinned)
            Icon(Icons.push_pin, size: 14, color: AppColors.textFaint),
        ],
      ),
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
      return const Center(child: Text('电脑不在线'));
    }
    return ListenableBuilder(
      listenable: link!,
      builder: (context, _) {
        final linkState = link!.state;
        final bots = linkState?.bots ?? const <LinkBot>[];
        final groups = linkState?.groups ?? const <LinkGroup>[];
        return ListView(
          children: [
            for (final bot in bots) ...[
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                leading: _Tile(name: bot.name),
                title: Text(bot.name),
                subtitle: Text(
                  bot.last ?? bot.signature,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      bot.updatedAt == null ? '' : _when(bot.updatedAt!),
                      style:
                          TextStyle(fontSize: 11.5, color: AppColors.textFaint),
                    ),
                    const SizedBox(height: 4),
                    if (bot.unread > 0) Badge(label: Text("${bot.unread}")),
                  ],
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChatPage(link: link!, bot: bot),
                  ),
                ),
                onLongPress: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BotEditPage(link: link!, bot: bot),
                  ),
                ),
              ),
              Divider(height: 0.5, indent: 72, color: AppColors.partBorder),
            ],
            if (groups.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Text(
                  '群聊',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
              ),
            for (final group in groups) ...[
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                leading: _Tile(name: group.name),
                title: Text(group.name),
                subtitle: Text(
                  [
                    if (group.members.isNotEmpty)
                      '${group.members.length} 个成员',
                    if (group.typing.isNotEmpty) '正在输入…',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      group.updatedAt == null ? '' : _when(group.updatedAt!),
                      style:
                          TextStyle(fontSize: 11.5, color: AppColors.textFaint),
                    ),
                    const SizedBox(height: 4),
                    if (group.unread > 0) Badge(label: Text("${group.unread}")),
                  ],
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GroupPage(link: link!, group: group),
                  ),
                ),
                onLongPress: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        GroupEditPage(link: link!, group: group),
                  ),
                ),
              ),
              Divider(height: 0.5, indent: 72, color: AppColors.partBorder),
            ],
            ListTile(
              leading: Icon(Codicons.add, color: AppColors.textMuted),
              title: Text(
                '新建群聊',
                style: TextStyle(color: AppColors.textMuted),
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GroupEditPage(link: link!),
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
      return const Center(child: Text('电脑不在线'));
    }
    return ListenableBuilder(
      listenable: link!,
      builder: (context, _) {
        final projects = [...?link!.state?.projects]
          ..sort((a, b) {
            if (a.pinned == true && b.pinned != true) return -1;
            if (b.pinned == true && a.pinned != true) return 1;
            return a.name.compareTo(b.name);
          });
        if (projects.isEmpty) {
          return Center(
            child: Text('还没有项目', style: TextStyle(color: AppColors.textMuted)),
          );
        }
        return ListView.separated(
          itemCount: projects.length,
          separatorBuilder: (_, _) =>
              Divider(height: 0.5, indent: 72, color: AppColors.partBorder),
          itemBuilder: (context, index) {
            final project = projects[index];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ),
              leading: _Tile(name: project.name),
              title: Text(project.name),
              subtitle: Text(
                [
                  project.path,
                  if (project.branch != null) '⎇ ${project.branch}',
                ].join('  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FolderPage(link: link!, project: project),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
