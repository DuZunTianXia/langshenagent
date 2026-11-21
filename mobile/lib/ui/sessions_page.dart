import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';

import '../link/phone_link.dart';
import '../main.dart';
import 'chat_page.dart';
import 'files_page.dart';
import 'group_page.dart';
import 'md/md_theme.dart';
import 'widgets.dart';

/// One computer's agents, bots and group chats.
class SessionsPage extends StatefulWidget {
  const SessionsPage({super.key, required this.computerId});

  final String computerId;

  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<SessionsPage> {
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final link = state.linkOf(widget.computerId);
    if (link == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold(body: SizedBox.shrink());
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(link.computer.name.isEmpty ? '电脑' : link.computer.name),
          bottom: const TabBar(
            tabs: [
              Tab(text: '智能体'),
              Tab(text: '机器人'),
              Tab(text: '群聊'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '项目与文件',
              icon: const Icon(Icons.folder_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('文件')),
                    body: FilesPage(link: link),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: ListenableBuilder(
          listenable: link,
          builder: (context, _) {
            final linkState = link.state;
            if (linkState == null) {
              return Center(
                child: link.phase == PhonePhase.online
                    ? const CircularProgressIndicator()
                    : Text(
                        link.phase == PhonePhase.pairing
                            ? '正在配对…'
                            : '离线 — ${link.error ?? '未连接'}',
                        textAlign: TextAlign.center,
                      ),
              );
            }
            return TabBarView(
              children: [
                _AgentsTab(link: link, state: linkState),
                _BotsTab(link: link, state: linkState),
                _GroupsTab(link: link, state: linkState),
              ],
            );
          },
        ),
      ),
    );
  }
}

String _projectName(LinkState state, String id) {
  for (final project in state.projects) {
    if (project.id == id) return project.name;
  }
  return '';
}

class _AgentsTab extends StatelessWidget {
  const _AgentsTab({required this.link, required this.state});

  final PhoneLink link;
  final LinkState state;

  @override
  Widget build(BuildContext context) {
    // Pinned first, then by most recent.
    final sessions = [...state.sessions]
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    if (sessions.isEmpty && state.projects.isEmpty) {
      return const Center(child: Text('还没有智能体'));
    }
    // Group by project, keeping the sorted order of first appearance.
    final byProject = <String, List<SessionSummary>>{};
    for (final session in sessions) {
      byProject.putIfAbsent(session.project, () => []).add(session);
    }
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.only(bottom: 88),
          children: [
        for (final entry in byProject.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              _projectName(state, entry.key).isEmpty
                  ? entry.key
                  : _projectName(state, entry.key),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final session in entry.value)
            _SessionTile(link: link, session: session),
        ],
          ],
        ),
        if (state.projects.isNotEmpty)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              heroTag: 'new-chat',
              onPressed: () => _newChat(context),
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('新建对话'),
            ),
          ),
      ],
    );
  }

  /// Picks a project and starts its next conversation, as the desktop's
  /// New Chat does.
  Future<void> _newChat(BuildContext context) async {
    final projects = [...state.projects]
      ..sort((a, b) {
        if (a.pinned == true && b.pinned != true) return -1;
        if (b.pinned == true && a.pinned != true) return 1;
        return a.name.compareTo(b.name);
      });
    final project = await showModalBottomSheet<ProjectInfo>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                '选择项目',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            for (final p in projects)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(p.name),
                subtitle: Text(
                  p.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.of(context).pop(p),
              ),
          ],
        ),
      ),
    );
    if (project == null || !context.mounted) return;
    try {
      final session = await link.draft(project.id);
      if (session != null && context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatPage(link: link, sessionId: session),
          ),
        );
      }
    } on Object catch (failure) {
      if (context.mounted) {
        showBToast(context, '$failure');
      }
    }
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.link, required this.session});

  final PhoneLink link;
  final SessionSummary session;

  @override
  Widget build(BuildContext context) {
    return BSlidable(
      pinned: session.pinned,
      onPin: () => link.pin(session.id, !session.pinned),
      onDelete: () async {
        if (await _confirm(context, '删除这个智能体？此操作无法撤销。')) {
          await link.delete(session.id);
        }
      },
      child: ListTile(
      leading: _statusIcon(session.status),
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
          if (session.model != null) session.model!,
          if (session.mode != null) session.mode!,
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: session.unread
          ? Icon(Icons.circle, size: 10, color: AppColors.accent)
          : session.pinned
          ? Icon(Icons.push_pin, size: 14, color: AppColors.textFaint)
          : null,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatPage(link: link, sessionId: session.id),
        ),
      ),
      onLongPress: () => _menu(context),
      ),
    );
  }

  /// The session's management, as the desktop's session menu has it:
  /// rename, pin, archive, delete.
  Future<void> _menu(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('重命名'),
              onTap: () => Navigator.of(context).pop('rename'),
            ),
            ListTile(
              leading: Icon(
                session.pinned ? Icons.push_pin_outlined : Icons.push_pin,
              ),
              title: Text(session.pinned ? '取消置顶' : '置顶'),
              onTap: () =>
                  Navigator.of(context).pop(session.pinned ? 'unpin' : 'pin'),
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('归档'),
              onTap: () => Navigator.of(context).pop('archive'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text(
                '删除',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () => Navigator.of(context).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    try {
      switch (action) {
        case 'rename':
          final title = await _renameDialog(context);
          if (title == null || title.isEmpty || title == session.title) {
            return;
          }
          await link.rename(session.id, title);
        case 'pin':
          await link.pin(session.id, true);
        case 'unpin':
          await link.pin(session.id, false);
        case 'archive':
          await link.archive(session.id);
        case 'delete':
          final confirmed = await _confirm(
            context,
            '删除这个智能体？此操作无法撤销。',
          );
          if (confirmed) await link.delete(session.id);
      }
    } on Object catch (failure) {
      if (context.mounted) {
        showBToast(context, '$failure');
      }
    }
  }

  Future<String?> _renameDialog(BuildContext context) {
    final controller = TextEditingController(text: session.title);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名智能体'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '标题'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirm(BuildContext context, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Widget _statusIcon(LinkSessionStatus status) => switch (status) {
    LinkSessionStatus.running => const Icon(
      Icons.sync,
      size: 18,
      color: Colors.blue,
    ),
    LinkSessionStatus.needsInput => const Icon(
      Icons.help_outline,
      size: 18,
      color: Colors.orange,
    ),
    LinkSessionStatus.idle => const Icon(
      Icons.chat_bubble_outline,
      size: 18,
      color: Colors.grey,
    ),
  };
}

class _BotsTab extends StatelessWidget {
  const _BotsTab({required this.link, required this.state});

  final PhoneLink link;
  final LinkState state;

  @override
  Widget build(BuildContext context) {
    if (state.bots.isEmpty) {
      return const Center(child: Text('还没有机器人'));
    }
    return ListView(
      children: [
        for (final bot in state.bots)
          ListTile(
            leading: CircleAvatar(
              child: Text(
                bot.name.isEmpty ? '?' : bot.name.characters.first,
              ),
            ),
            title: Text(bot.name),
            subtitle: Text(
              [
                if (bot.status == BotStatus.typing) '正在输入…',
                if (bot.unread > 0) '${bot.unread} 条未读',
                ?bot.last,
              ].whereType<String>().join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: bot.unread > 0 ? Badge(label: Text('${bot.unread}')) : null,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatPage(link: link, bot: bot),
              ),
            ),
          ),
      ],
    );
  }
}

class _GroupsTab extends StatelessWidget {
  const _GroupsTab({required this.link, required this.state});

  final PhoneLink link;
  final LinkState state;

  @override
  Widget build(BuildContext context) {
    if (state.groups.isEmpty) {
      return const Center(child: Text('还没有群聊'));
    }
    return ListView(
      children: [
        for (final group in state.groups)
          ListTile(
            leading: const Icon(Icons.groups_outlined),
            title: Text(group.name),
            subtitle: Text(
              [
                group.members.length > 1
                    ? '${group.members.length - 1} 个机器人'
                    : '',
                if (group.typing.isNotEmpty) '正在输入…',
              ].where((s) => s.isNotEmpty).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: group.unread > 0
                ? Badge(label: Text('${group.unread}'))
                : null,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GroupPage(link: link, group: group),
              ),
            ),
          ),
      ],
    );
  }
}
