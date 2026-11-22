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
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(46),
            child: _SegmentTabs(),
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
                    ? CircularProgressIndicator(color: AppColors.accent)
                    : Text(
                        link.phase == PhonePhase.pairing
                            ? '正在配对…'
                            : '离线 — ${link.error ?? '未连接'}',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textMuted),
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

/// The tab row as a segmented switch: one track, the tab under way a
/// raised pill.
class _SegmentTabs extends StatelessWidget {
  const _SegmentTabs();

  static const _labels = ['智能体', '机器人', '群聊'];

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Container(
          height: 34,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: AppColors.bubbleFill,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            children: [
              for (final (i, label) in _labels.indexed)
                Expanded(
                  child: GestureDetector(
                    onTap: () => controller.animateTo(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOut,
                      alignment: Alignment.center,
                      decoration: i == controller.index.round()
                          ? BoxDecoration(
                              color: AppColors.surfaceRaised,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: 0.06,
                                  ),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            )
                          : null,
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: i == controller.index.round()
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: i == controller.index.round()
                              ? AppColors.textPrimary
                              : AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An empty tab: a faint icon over a word.
class _Empty extends StatelessWidget {
  const _Empty(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 42, color: AppColors.textFaint),
        const SizedBox(height: 10),
        Text(text, style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
      ],
    ),
  );
}

/// The unread count, as the tab bar's red pill.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge(this.count);

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 18),
    height: 18,
    padding: const EdgeInsets.symmetric(horizontal: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFFA5151),
      borderRadius: BorderRadius.circular(9),
    ),
    alignment: Alignment.center,
    child: Text(
      count > 99 ? '99+' : '$count',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// A list row's leading: the icon in its tinted box, as [BCell]'s.
class _IconBox extends StatelessWidget {
  const _IconBox(this.icon, this.color);

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Icon(icon, size: 19, color: color),
  );
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
      return const _Empty(Icons.forum_outlined, '还没有智能体');
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
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      size: 13,
                      color: AppColors.textFaint,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        _projectName(state, entry.key).isEmpty
                            ? entry.key
                            : _projectName(state, entry.key),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              for (final session in entry.value)
                _SessionTile(link: link, session: session),
            ],
          ],
        ),
        if (state.projects.isNotEmpty)
          Positioned(right: 16, bottom: 16, child: _NewChatButton(link: link, state: state)),
      ],
    );
  }
}

/// The floating "新建对话" pill.
class _NewChatButton extends StatelessWidget {
  const _NewChatButton({required this.link, required this.state});

  final PhoneLink link;
  final LinkState state;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: () => _newChat(context),
      borderRadius: BorderRadius.circular(24),
      child: Ink(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.add_comment_outlined, size: 17, color: Colors.white),
            SizedBox(width: 7),
            Text(
              '新建对话',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  /// Picks a project and starts its next conversation, as the desktop's
  /// New Chat does.
  Future<void> _newChat(BuildContext context) async {
    final projects = [...state.projects]
      ..sort((a, b) {
        if (a.pinned == true && b.pinned != true) return -1;
        if (b.pinned == true && a.pinned != true) return 1;
        return a.name.compareTo(b.name);
      });
    final project = await showBActions<ProjectInfo>(
      context,
      title: '选择项目',
      actions: [
        for (final p in projects)
          (Icons.folder_outlined, p.name, p.path, p),
      ],
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
    final (icon, color) = switch (session.status) {
      LinkSessionStatus.running => (Icons.sync_rounded, AppColors.accent),
      LinkSessionStatus.needsInput => (Icons.help_outline, AppColors.caution),
      LinkSessionStatus.idle => (
        Icons.chat_bubble_outline_rounded,
        AppColors.textFaint,
      ),
    };
    return BSlidable(
      pinned: session.pinned,
      onPin: () => link.pin(session.id, !session.pinned),
      onDelete: () async {
        if (await _confirm(context, '删除这个智能体？此操作无法撤销。')) {
          await link.delete(session.id);
        }
      },
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatPage(link: link, sessionId: session.id),
          ),
        ),
        onLongPress: () => _menu(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              _IconBox(icon, color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.title.isEmpty ? '未命名' : session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        color: AppColors.textPrimary,
                        fontWeight: session.unread
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                    if (session.model != null || session.mode != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        [
                          ?session.model,
                          ?session.mode,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (session.unread) ...[
                const SizedBox(width: 8),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFA5151),
                    shape: BoxShape.circle,
                  ),
                ),
              ] else if (session.pinned)
                Icon(Icons.push_pin, size: 14, color: AppColors.textFaint),
            ],
          ),
        ),
      ),
    );
  }

  /// The session's management, as the desktop's session menu has it:
  /// rename, pin, archive, delete.
  Future<void> _menu(BuildContext context) async {
    final action = await showBActions<String>(
      context,
      danger: const {'delete'},
      actions: [
        (Icons.edit_outlined, '重命名', null, 'rename'),
        (
          session.pinned ? Icons.push_pin_outlined : Icons.push_pin,
          session.pinned ? '取消置顶' : '置顶',
          null,
          session.pinned ? 'unpin' : 'pin',
        ),
        (Icons.archive_outlined, '归档', null, 'archive'),
        (Icons.delete_outline, '删除', null, 'delete'),
      ],
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

  Future<String?> _renameDialog(BuildContext context) => showBPrompt(
    context,
    title: '重命名智能体',
    initial: session.title,
    hint: '标题',
  );

  Future<bool> _confirm(BuildContext context, String message) => showBConfirm(
    context,
    title: message,
    confirm: '删除',
    danger: true,
  );
}

class _BotsTab extends StatelessWidget {
  const _BotsTab({required this.link, required this.state});

  final PhoneLink link;
  final LinkState state;

  @override
  Widget build(BuildContext context) {
    if (state.bots.isEmpty) {
      return const _Empty(Icons.smart_toy_outlined, '还没有机器人');
    }
    return ListView(
      children: [
        for (final bot in state.bots)
          InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatPage(link: link, bot: bot),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      bot.name.isEmpty ? '?' : bot.name.characters.first,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bot.name.isEmpty ? '未命名' : bot.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Builder(
                          builder: (context) {
                            final subtitle = [
                              if (bot.status == BotStatus.typing) '正在输入…',
                              ?bot.last,
                            ].join(' · ');
                            if (subtitle.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: bot.status == BotStatus.typing
                                      ? AppColors.accent
                                      : AppColors.textMuted,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  if (bot.unread > 0) ...[
                    const SizedBox(width: 8),
                    _UnreadBadge(bot.unread),
                  ],
                ],
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
      return const _Empty(Icons.groups_outlined, '还没有群聊');
    }
    return ListView(
      children: [
        for (final group in state.groups)
          InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GroupPage(link: link, group: group),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              child: Row(
                children: [
                  _IconBox(Icons.groups_outlined, AppColors.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Builder(
                          builder: (context) {
                            final subtitle = [
                              if (group.members.length > 1)
                                '${group.members.length - 1} 个机器人',
                              if (group.typing.isNotEmpty) '正在输入…',
                            ].join(' · ');
                            if (subtitle.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: group.typing.isNotEmpty
                                      ? AppColors.accent
                                      : AppColors.textMuted,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  if (group.unread > 0) ...[
                    const SizedBox(width: 8),
                    _UnreadBadge(group.unread),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
