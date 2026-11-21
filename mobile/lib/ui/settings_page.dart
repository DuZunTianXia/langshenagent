import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat/user_message_style.dart';
import '../link/phone_link.dart';
import '../main.dart';
import 'bot_edit_page.dart';
import 'md/md_theme.dart';
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
  final _name = TextEditingController();
  final _signature = TextEditingController();
  String _gender = '';
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
    final name = prefs.getString('phoneName');
    if (mounted) {
      setState(() {
        if (name != null && name.isNotEmpty) _name.text = name;
        _signature.text = prefs.getString('meSignature') ?? '';
        _gender = prefs.getString('meGender') ?? '';
      });
    }
  }

  Future<void> _saveProfile() async {
    final name = _name.text.trim();
    await AppScope.of(context).setMeProfile(
      name: name,
      gender: _gender,
      signature: _signature.text.trim(),
    );
    if (mounted) showBToast(context, '已保存');
  }

  Future<void> _pickMessageStyle(BuildContext context) async {
    final picked = await showModalBottomSheet<UserMessageStyle>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in const [
              (UserMessageStyle.sticky, '整宽滚动吸顶', '整宽显示，滚动时当前这轮的消息停在顶部'),
              (UserMessageStyle.bubble, '靠右气泡', '像聊天一样靠右显示为气泡，随内容滚走'),
            ])
              ListTile(
                title: Text(entry.$2),
                subtitle: Text(entry.$3),
                onTap: () => Navigator.of(sheetContext).pop(entry.$1),
              ),
          ],
        ),
      ),
    );
    if (picked != null) {
      await AppScope.of(context).setUserMessageStyle(picked);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _signature.dispose();
    super.dispose();
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
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '电脑和上面的 Bot 会这样称呼你、认识你。',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    BTextField(
                      controller: _name,
                      hint: '名字，例如：小浪',
                      onSubmitted: (_) => _saveProfile(),
                    ),
                    const SizedBox(height: 10),
                    BDropdown<String>(
                      value: _gender,
                      hint: '性别',
                      items: const [
                        ('', '不透露'),
                        ('male', '男'),
                        ('female', '女'),
                      ],
                      onChanged: (v) => setState(() => _gender = v),
                    ),
                    const SizedBox(height: 10),
                    BTextField(
                      controller: _signature,
                      hint: '签名，一句话介绍自己',
                      onSubmitted: (_) => _saveProfile(),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: BButton(
                        label: '保存',
                        primary: true,
                        onPressed: _saveProfile,
                      ),
                    ),
                  ],
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
                BCell(
                  icon: switch (computer.system) {
                    final s when s.contains('Windows') =>
                      Icons.laptop_windows_outlined,
                    final s when s.contains('Linux') =>
                      Icons.developer_board_outlined,
                    _ => Icons.laptop_mac_outlined,
                  },
                  iconColor: AppColors.textMuted,
                  title: computer.name.isEmpty ? '电脑' : computer.name,
                  subtitle: computer.system,
                  trailing: BButton(
                    label: '取消配对',
                    onPressed: () => state.unpair(computer.id),
                  ),
                  showChevron: false,
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
                  onTap: () => _pickMessageStyle(context),
                ),
              ),
              const BDivider(),
              BCell(
                icon: Icons.system_update_alt,
                title: '检查更新',
                subtitle: '当前版本 $_version',
                onTap: () => checkForUpdate(context, loud: true),
              ),
              const BDivider(),
              BCell(
                icon: Icons.info_outline,
                iconColor: AppColors.textMuted,
                title: '关于 LangshenAgent',
                subtitle: '与电脑上的编程智能体对话，全程端到端加密。',
                showChevron: false,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
