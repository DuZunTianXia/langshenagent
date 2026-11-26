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
import 'md/md_theme.dart';
import 'profile_edit_page.dart';
import 'providers_page.dart';
import 'update_dialog.dart';
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
                      SettingsAvatar(name: _meName),
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
                    if (bots.isEmpty) {
                      return BCell(
                        title: '电脑不在线或没有 Bot',
                        titleColor: AppColors.textMuted,
                        showChevron: false,
                      );
                    }
                    return Column(
                      children: [
                        for (var i = 0; i < bots.length; i++) ...[
                          BCell(
                            icon: Icons.smart_toy_outlined,
                            title: bots[i].name,
                            subtitle: bots[i].model ?? '默认模型',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => BotEditPage(
                                  link: widget.link!,
                                  bot: bots[i],
                                ),
                              ),
                            ),
                          ),
                          if (i < bots.length - 1) const BDivider(),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          if (widget.link != null)
            BSection(
              title: '模型',
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
              ],
            ),
          BSection(
            title: '通用',
            children: [
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
    BCell cell(bool online) => BCell(
      icon: icon,
      iconColor: online ? AppColors.accent : AppColors.textMuted,
      title: computer.name.isEmpty ? '电脑' : computer.name,
      subtitle: '${computer.system} · ${online ? '在线' : '离线'}',
      trailing: BButton(label: '取消配对', onPressed: onUnpair),
      showChevron: false,
    );
    final link = this.link;
    if (link == null) return cell(false);
    return ListenableBuilder(
      listenable: link,
      builder: (context, _) => cell(link.phase == PhonePhase.online),
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
