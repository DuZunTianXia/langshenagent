import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../link/link_store.dart';
import '../link/phone_link.dart';
import '../main.dart';
import 'home_page.dart';
import 'pair_page.dart';
import 'widgets.dart';
import 'sessions_page.dart';
import 'settings_page.dart';

/// The home: the computers paired with this phone, and those nearby that
/// could be paired.
class ComputersPage extends StatelessWidget {
  const ComputersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('宝码'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: '配对电脑',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PairPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final computers = state.computers;
          final nearby = [
            for (final advert in state.nearby.values)
              if (!state.store!.computers.containsKey(advert.id)) advert,
          ];
          if (computers.isEmpty && nearby.isEmpty) {
            return _Empty(onPair: () => _pair(context));
          }
          return ListView(
            children: [
              if (computers.isNotEmpty) ...[
                const _Heading('已配对的电脑'),
                for (final computer in computers)
                  _ComputerTile(computer: computer),
              ],
              if (nearby.isNotEmpty) ...[
                const _Heading('附近的电脑'),
                for (final advert in nearby)
                  _NearbyTile(advert: advert),
              ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _pair(context),
        icon: const Icon(Icons.add),
        label: const Text('配对电脑'),
      ),
    );
  }

  void _pair(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PairPage()),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onPair});

  final VoidCallback onPair;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.laptop_mac_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text('还没有电脑', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '与运行 LangshenAgent 的电脑配对，即可在这里与它的智能体对话。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onPair,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('配对电脑'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComputerTile extends StatelessWidget {
  const _ComputerTile({required this.computer});

  final PairedComputer computer;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final link = state.linkOf(computer.id);
    return ListenableBuilder(
      listenable: link ?? state,
      builder: (context, _) {
        final phase = link?.phase ?? PhonePhase.offline;
        final online = phase == PhonePhase.online;
        final sessions = link?.state?.sessions ?? const [];
        final unread = sessions.where((s) => s.unread).length;
        final needsInput = sessions
            .where((s) => s.status == LinkSessionStatus.needsInput)
            .length;
        return ListTile(
          leading: _ComputerIcon(kind: computer.kind, online: online),
          title: Text(
            computer.name.isEmpty ? '电脑' : computer.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            _statusText(phase, link?.error, unread, needsInput),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: needsInput > 0
              ? Badge(label: Text('$needsInput'))
              : online
              ? const Icon(Icons.chevron_right)
              : null,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SessionsPage(computerId: computer.id),
            ),
          ),
          onLongPress: () => _unpair(context, state),
        );
      },
    );
  }

  String _statusText(
    PhonePhase phase,
    String? error,
    int unread,
    int needsInput,
  ) {
    if (error == 'unpaired') return '需要重新配对';
    if (needsInput > 0) return '$needsInput 个待回答';
    if (unread > 0) return '$unread 条未读';
    return switch (phase) {
      PhonePhase.online => '在线',
      PhonePhase.pairing => '正在配对…',
      PhonePhase.connecting => '正在连接…',
      PhonePhase.offline => error == null ? '离线' : '离线（$error）',
    };
  }

  Future<void> _unpair(BuildContext context, AppState state) async {
    if (await showBConfirm(
      context,
      title: '取消配对？',
      body:
          '此手机将忘记${computer.name.isEmpty ? '这台电脑' : computer.name}。'
          '再次配对需要在电脑上重新显示配对码。',
      confirm: '取消配对',
      danger: true,
    )) {
      await state.unpair(computer.id);
    }
  }
}

class _ComputerIcon extends StatelessWidget {
  const _ComputerIcon({required this.kind, required this.online});

  final String kind;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = switch (kind) {
      'windows' => Icons.laptop_windows_outlined,
      'linux' => Icons.developer_board_outlined,
      _ => Icons.laptop_mac_outlined,
    };
    return Badge(
      isLabelVisible: online,
      backgroundColor: theme.colorScheme.primary,
      child: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
    );
  }
}

class _NearbyTile extends StatelessWidget {
  const _NearbyTile({required this.advert});

  final LinkAdvert advert;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return ListTile(
      leading: const Icon(Icons.wifi_find),
      title: Text(advert.name),
      subtitle: Text(
        advert.pairing ? '正在配对' : '同一网络',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        await state.pair(advert: advert);
        if (context.mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HomePage()),
            (route) => false,
          );
        }
      },
    );
  }
}
