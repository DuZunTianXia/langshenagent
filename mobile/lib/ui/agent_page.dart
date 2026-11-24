import 'package:flutter/material.dart';

import '../chat/chat_models.dart';
import '../link/chat_codec.dart';
import '../link/phone_link.dart';
import 'chat_items.dart';
import 'md/md_theme.dart';

/// A subagent's own conversation, opened from its card: what it was asked
/// (its prompt) first, its steps ([AgentItem.children]) and its report
/// (result) last — as the desktop's SubagentFeed shows them, followed live
/// from the session's feed so it updates as the subagent works.
class AgentPage extends StatelessWidget {
  const AgentPage({super.key, required this.feed, required this.agentId});

  /// The session's feed the subagent's card is in.
  final SessionFeed feed;

  /// The tool call that started it ([AgentItem.id]).
  final String agentId;

  /// The subagent in the feed's latest items, nested ones found by their
  /// ids ([path] from the page's own: a child card's opens deeper).
  static AgentItem? find(SessionFeed feed, List<String> path) {
    AgentItem? agent;
    outer:
    for (final id in path) {
      final children = agent == null
          ? feed.items.map(ChatCodec.decode).whereType<AgentItem>()
          : agent.children.whereType<AgentItem>();
      for (final child in children) {
        if (child.id == id) {
          agent = child;
          continue outer;
        }
      }
      return null;
    }
    return agent;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: feed,
      builder: (context, _) {
        final agent = find(feed, [agentId]);
        final items = <ChatItem>[
          if (agent?.prompt case final prompt? when prompt.isNotEmpty)
            UserMessageItem(text: prompt),
          ...?agent?.children,
          if (agent?.result case final result? when result.isNotEmpty)
            AssistantTextItem(result),
          if (agent?.status == CommandStatus.running)
            const LiveStatusItem('Planning next move', whimsical: true),
        ];
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  agent?.description.isEmpty == false
                      ? agent!.description
                      : '子代理',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  [
                    ?agent?.agentType,
                    switch (agent?.status) {
                      CommandStatus.running => '进行中',
                      CommandStatus.failed => '失败',
                      _ => '已完成',
                    },
                    ?agent?.model,
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          body: items.isEmpty
              ? Center(
                  child: Text(
                    agent == null ? '子代理已不在会话中' : '还没有内容',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ChatItemView(
                      item: item,
                      onAgent: item is AgentItem && item.id != null
                          ? (child) => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => AgentPage(
                                  feed: feed,
                                  agentId: child.id!,
                                ),
                              ),
                            )
                          : null,
                    );
                  },
                ),
        );
      },
    );
  }
}
