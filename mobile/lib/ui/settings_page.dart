import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat/edit_detail.dart';
import '../chat/user_message_style.dart';
import '../link/link_store.dart';
import '../link/phone_link.dart';
import '../main.dart';
import 'bot_edit_page.dart';
import 'link_status.dart';
import 'md/md_theme.dart';
import 'profile_edit_page.dart';
import 'providers_page.dart';
import 'skills_page.dart';
import 'update_dialog.dart';
import 'usage_stats_page.dart';
import 'widgets.dart';

/// The phone's own settings: who its user is (told to the bots), the
/// paired computers, the bots' configuration, and about.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.link});

  /// The computer the bots to configure are on.
  final PhoneLink? link;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _meName = '';
  String _meSignature = '';
  String _version = '';

  @override
  void initState() {
    super.initState();
    _load();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() => _version = '${info.version}+${info.buildNumber}');
      }
    });
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _meName = prefs.getString('phoneName') ?? '';
        _meSignature = prefs.getString('meSignature') ?? '';
      });
    }
  }

  Future<void> _editProfile() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ProfileEditPage()),
    );
    if (saved == true) {
      _load();
      if (mounted) showBToast(context, '已保存');
    }
  }

  Future<void> _pickThemeMode() async {
    final state = AppScope.of(context);
    final picked = await showBActions<ThemeMode>(
      context,
      title: '外观主题',
      selected: state.themeMode,
      actions: const [
        (Icons.brightness_auto_rounded, '跟随系统', '自动匹配系统深浅色', ThemeMode.system),
        (Icons.light_mode_outlined, '浅色模式', '始终使用浅色界面', ThemeMode.light),
        (Icons.dark_mode_outlined, '深色模式', '始终使用深色界面', ThemeMode.dark),
      ],
    );
    if (picked == null || !mounted) return;
    await state.setThemeMode(picked);
  }

  Future<void> _pickSendWhileLive() async {
    final state = AppScope.of(context);
    final picked = await showBActions<bool>(
      context,
      title: '工作中发送消息',
      selected: state.sendNowWhileLive,
      actions: const [
        (
          Icons.schedule_rounded,
          '排队等待',
          '等当前回复结束后自动按顺序发送',
          false,
        ),
        (
          Icons.bolt_rounded,
          '中断并发送',
          '立即中断当前工作并马上发送新消息',
          true,
        ),
      ],
    );
    if (picked == null || !mounted) return;
    await state.setSendNowWhileLive(picked);
  }

  Future<void> _pickMessageStyle() async {
    final picked = await showBActions<UserMessageStyle>(
      context,
      title: '用户消息样式',
      selected: UserMessageStyle.current.value,
      actions: const [
        (
          Icons.vertical_align_top_rounded,
          '整宽滚动吸顶',
          '整宽显示，滚动时当前这轮的消息停在顶部',
          UserMessageStyle.sticky,
        ),
        (
          Icons.chat_bubble_outline_rounded,
          '靠右气泡',
          '像聊天一样靠右显示为气泡，随内容滚走',
          UserMessageStyle.bubble,
        ),
      ],
    );
    if (picked == null || !mounted) return;
    await AppScope.of(context).setUserMessageStyle(picked);
  }

  Future<void> _pickEditDetail() async {
    final picked = await showBActions<EditDetail>(
      context,
      title: '文件编辑样式',
      selected: EditDetail.current.value,
      actions: const [
        (
          Icons.compress_rounded,
          '紧凑一行',
          '每个文件编辑收成一行，点开看差异',
          EditDetail.compact,
        ),
        (
          Icons.difference_outlined,
          '完整卡片',
          '文件编辑直接展开为差异卡片',
          EditDetail.card,
        ),
      ],
    );
    if (picked == null || !mounted) return;
    await AppScope.of(context).setEditDetail(picked);
  }

  Future<void> _unpair(BuildContext context, PairedComputer computer) async {
    final state = AppScope.of(context);
    final name = computer.name.isEmpty ? '这台电脑' : computer.name;
    if (await showBConfirm(
      context,
      title: '取消配对？',
      body: '此手机将忘记$name，电脑上的配对记录也会一并清除。再次配对需要重新扫码。',
      confirm: '取消配对',
      danger: true,
    )) {
      await state.unpair(computer.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          BSection(
            title: '个人资料',
            children: [
              InkWell(
                onTap: _editProfile,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      SettingsAvatar(
                        name: _meName,
                        avatarBytes: state.meAvatarBytes,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _meName.isEmpty ? '未设置名字' : _meName,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: _meName.isEmpty
                                    ? AppColors.textFaint
                                    : AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _meSignature.isEmpty
                                  ? '设置名字、签名，让 Bot 认识你'
                                  : _meSignature,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: AppColors.textFaint,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          BSection(
            title: '已配对的电脑',
            children: [
              if (state.computers.isEmpty)
                BCell(
                  title: '还没有配对的电脑',
                  titleColor: AppColors.textMuted,
                  showChevron: false,
                ),
              for (final computer in state.computers) ...[
                _ComputerCell(
                  computer: computer,
                  link: state.linkOf(computer.id),
                  onUnpair: () => _unpair(context, computer),
                ),
                if (computer != state.computers.last) const BDivider(),
              ],
            ],
          ),
          if (widget.link != null)
            BSection(
              title: 'Bot 配置',
              children: [
                ListenableBuilder(
                  listenable: widget.link!,
                  builder: (context, _) {
                    final bots =
                        widget.link!.state?.bots ?? const <LinkBot>[];
                    final subtitle = widget.link!.state == null
                        ? '连接电脑后管理所有 Bot'
                        : bots.isEmpty
                        ? '还没有 Bot，点此添加'
                        : '管理全部 ${bots.length} 个 Bot 的人设、能力与记忆';
                    return BCell(
                      icon: Icons.smart_toy_outlined,
                      title: '管理 Bot',
                      subtitle: subtitle,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => _BotsConfigPage(link: widget.link!),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          if (widget.link != null)
            BSection(
              title: '技能',
              children: [
                BCell(
                  icon: Icons.extension_outlined,
                  title: '技能与 MCP',
                  subtitle: '配置 Skill、MCP 服务、子代理与插件',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SkillsPage(link: widget.link!),
                    ),
                  ),
                ),
              ],
            ),
          if (widget.link != null)
            BSection(
              title: '模型与用量',
              children: [
                BCell(
                  icon: Icons.hub_outlined,
                  title: '渠道与默认模型',
                  subtitle: '管理模型渠道、配置各任务使用的模型',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProvidersPage(link: widget.link!),
                    ),
                  ),
                ),
                const BDivider(),
                BCell(
                  icon: Icons.bar_chart_rounded,
                  title: '用量统计',
                  subtitle: '查看 Token 消耗、估算费用与模型分布',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => UsageStatsPage(link: widget.link!),
                    ),
                  ),
                ),
              ],
            ),
          BSection(
            title: '通用',
            children: [
              BCell(
                icon: Icons.palette_outlined,
                title: '外观主题',
                subtitle: switch (state.themeMode) {
                  ThemeMode.system => '跟随系统',
                  ThemeMode.light => '浅色模式',
                  ThemeMode.dark => '深色模式',
                },
                onTap: _pickThemeMode,
              ),
              const BDivider(),
              BCell(
                icon: Icons.send_time_extension_outlined,
                title: '工作中发送消息',
                subtitle: state.sendNowWhileLive
                    ? '中断并发送 · 立即打断当前任务'
                    : '排队等待 · 按顺序依次发送',
                onTap: _pickSendWhileLive,
              ),
              const BDivider(),
              ValueListenableBuilder(
                valueListenable: UserMessageStyle.current,
                builder: (context, style, _) => BCell(
                  icon: Icons.chat_bubble_outline,
                  title: '用户消息样式',
                  subtitle: style == UserMessageStyle.sticky
                      ? '整宽显示，滚动时吸顶'
                      : '靠右气泡，随内容滚走',
                  onTap: _pickMessageStyle,
                ),
              ),
              const BDivider(),
              ValueListenableBuilder(
                valueListenable: EditDetail.current,
                builder: (context, detail, _) => BCell(
                  icon: Icons.difference_outlined,
                  title: '文件编辑样式',
                  subtitle: detail == EditDetail.compact
                      ? '紧凑一行，点开看差异'
                      : '完整卡片，直接展开差异',
                  onTap: _pickEditDetail,
                ),
              ),
              const BDivider(),
              BCell(
                icon: Icons.system_update_alt,
                title: '检查更新',
                subtitle: '当前版本 $_version',
                onTap: () => checkForUpdate(context, loud: true),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _Footer(version: _version),
        ],
      ),
    );
  }
}

/// A paired computer's row: its platform icon, a live online dot, and the
/// unpair button.
class _ComputerCell extends StatelessWidget {
  const _ComputerCell({
    required this.computer,
    required this.link,
    required this.onUnpair,
  });

  final PairedComputer computer;
  final PhoneLink? link;
  final VoidCallback onUnpair;

  @override
  Widget build(BuildContext context) {
    final icon = switch (computer.system) {
      final s when s.contains('Windows') => Icons.laptop_windows_outlined,
      final s when s.contains('Linux') => Icons.developer_board_outlined,
      _ => Icons.laptop_mac_outlined,
    };
    final link = this.link;
    BCell cell(PhonePhase phase, String? error) {
      final online = phase == PhonePhase.online;
      final connecting =
          phase == PhonePhase.connecting || phase == PhonePhase.pairing;
      final status = linkPhaseLabel(phase, error: error);
      final pathLabel = online && link != null
          ? describeLinkPath(link.path)
          : null;
      return BCell(
        icon: icon,
        iconColor: online
            ? AppColors.accent
            : connecting
            ? AppColors.caution
            : AppColors.textMuted,
        title: computer.name.isEmpty ? '电脑' : computer.name,
        subtitle: [
          if (computer.system.isNotEmpty) computer.system,
          status,
          ?pathLabel,
        ].join(' · '),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!online && !connecting && link != null && !link.needsRePair) ...[
              BButton(
                label: '重连',
                primary: true,
                onPressed: () => link.retryNow(force: true),
              ),
              const SizedBox(width: 8),
            ],
            BButton(label: '取消配对', onPressed: onUnpair),
          ],
        ),
        showChevron: false,
      );
    }
    if (link == null) return cell(PhonePhase.offline, null);
    return ListenableBuilder(
      listenable: link,
      builder: (context, _) => cell(link.phase, link.error),
    );
  }
}

/// The centred sign-off at the bottom of the page.
class _Footer extends StatelessWidget {
  const _Footer({required this.version});

  final String version;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.terminal, size: 16, color: AppColors.accent),
          const SizedBox(width: 6),
          Text(
            'LangshenAgent',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        '与电脑上的编程智能体对话，全程端到端加密。',
        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
      ),
      if (version.isNotEmpty) ...[
        const SizedBox(height: 2),
        Text(
          'v$version',
          style: TextStyle(fontSize: 11.5, color: AppColors.textFaint),
        ),
      ],
    ],
  );
}

/// Dedicated Bot management page opened from Settings → Bot 配置.
class _BotsConfigPage extends StatelessWidget {
  const _BotsConfigPage({required this.link});

  final PhoneLink link;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bot 配置'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: '添加 Bot',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => BotEditPage(link: link)),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: link,
        builder: (context, _) {
          final state = link.state;
          if (state == null) {
            return LinkUnavailableBody(
              link: link,
              offlineTitle: '无法加载 Bot',
              offlineSubtitle: '连接电脑后即可配置所有 Bot。',
              onRetry: () => link.retryNow(force: true),
            );
          }
          final bots = state.bots;
          if (bots.isEmpty) {
            return BEmptyState(
              icon: Icons.smart_toy_outlined,
              title: '还没有 Bot',
              subtitle: '创建一个 Bot，设定它的身份、风格和能力。',
              actionLabel: '添加 Bot',
              onAction: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => BotEditPage(link: link)),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
            children: [
              BCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < bots.length; i++) ...[
                      BInboxRow(
                        leading: BotAvatar(link: link, bot: bots[i], size: 40),
                        title: bots[i].name,
                        subtitle: Text(
                          [
                            if (bots[i].model != null) bots[i].model!,
                            if (bots[i].signature.isNotEmpty) bots[i].signature,
                            if (bots[i].model == null &&
                                bots[i].signature.isEmpty)
                              '默认模型',
                          ].join(' · '),
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                BotEditPage(link: link, bot: bots[i]),
                          ),
                        ),
                      ),
                      if (i < bots.length - 1) const BDivider(),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
