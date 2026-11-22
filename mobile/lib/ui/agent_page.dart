import 'package:flutter/material.dart';

import '../chat/chat_models.dart';
import 'chat_items.dart';
import 'md/md_theme.dart';

/// A subagent's own conversation: what it was asked (its prompt), its
/// steps ([AgentItem.children]) and its report (result) — as the desktop
/// shows a subagent opened from its card.
class AgentPage extends StatelessWidget {
  const AgentPage({super.key, required this.agent, this.depth = 1});

  final AgentItem agent;

  /// How deep inside subagents this one is, for the title.
  final int depth;

  @override
  Widget build(BuildContext context) {
    final items = <ChatItem>[
      if (agent.prompt case final prompt? when prompt.isNotEmpty)
        UserMessageItem(text: prompt),
      ...agent.children,
      if (agent.result case final result? when result.isNotEmpty)
        AssistantTextItem(result),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              agent.description.isEmpty ? '子代理' : agent.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              [
                ?agent.agentType,
                switch (agent.status) {
                  CommandStatus.running => '进行中',
                  CommandStatus.succeeded => '已完成',
                  CommandStatus.failed => '失败',
                },
                ?agent.model,
              ].join(' · '),
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
      body: items.isEmpty
          ? Center(
              child: Text('还没有内容', style: TextStyle(color: AppColors.textMuted)),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return ChatItemView(
                  item: item,
                  onAgent: item is AgentItem
                      ? (child) => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                AgentPage(agent: child, depth: depth + 1),
                          ),
                        )
                      : null,
                );
              },
            ),
    );
  }
}
