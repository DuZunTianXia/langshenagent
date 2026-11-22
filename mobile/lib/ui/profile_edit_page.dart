import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import 'md/md_theme.dart';
import 'widgets.dart';

/// The phone user's own profile editor — reached from the settings'
/// profile card. Saves with `setMe` so every linked computer learns who
/// this user is.
class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _name = TextEditingController();
  final _signature = TextEditingController();
  String _gender = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(() {
        _name.text = prefs.getString('phoneName') ?? '';
        _signature.text = prefs.getString('meSignature') ?? '';
        _gender = prefs.getString('meGender') ?? '';
      });
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _signature.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    await AppScope.of(context).setMeProfile(
      name: _name.text.trim(),
      gender: _gender,
      signature: _signature.text.trim(),
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('个人资料')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        BCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: ValueListenableBuilder(
                  valueListenable: _name,
                  builder: (context, _, _) =>
                      SettingsAvatar(name: _name.text.trim(), size: 64),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  '电脑和上面的 Bot 会这样称呼你、认识你。',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ),
              const SizedBox(height: 16),
              BTextField(
                controller: _name,
                label: '名字',
                hint: '例如：小浪',
                onSubmitted: (_) => _save(),
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
                label: '签名',
                hint: '一句话介绍自己',
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              BButton(
                label: '保存',
                primary: true,
                expand: true,
                busy: _saving,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// A profile picture: the name's first character on the accent wash, a
/// person glyph while no name is set.
class SettingsAvatar extends StatelessWidget {
  const SettingsAvatar({super.key, required this.name, this.size = 52});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? null : name.characters.first;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.27),
      ),
      child: Center(
        child: initial == null
            ? Icon(Icons.person_outline, size: size * 0.5, color: AppColors.accent)
            : Text(
                initial,
                style: TextStyle(
                  fontSize: size * 0.42,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accent,
                ),
              ),
      ),
    );
  }
}
