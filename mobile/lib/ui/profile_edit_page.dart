import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../phone_platform.dart';
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
  Uint8List? _avatarBytes;
  String? _avatarType;
  bool _avatarChanged = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      final state = AppScope.of(context);
      setState(() {
        _name.text = prefs.getString('phoneName') ?? '';
        _signature.text = prefs.getString('meSignature') ?? '';
        _gender = prefs.getString('meGender') ?? '';
        _avatarBytes = state.meAvatarBytes;
        _avatarType = state.meAvatarType;
      });
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _signature.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final action = await showBActions<String>(
      context,
      title: '设置头像',
      danger: const {'clear'},
      actions: [
        (Icons.photo_library_outlined, '从相册选择', '支持 PNG / JPG / WebP', 'gallery'),
        (Icons.photo_camera_outlined, '拍照', null, 'camera'),
        if (_avatarBytes != null)
          (Icons.restore_outlined, '恢复默认头像', null, 'clear'),
      ],
    );
    if (action == null || !mounted) return;
    if (action == 'clear') {
      setState(() {
        _avatarBytes = null;
        _avatarType = null;
        _avatarChanged = true;
      });
      return;
    }
    if (action == 'camera') {
      final path = await PhonePlatform.takePhoto();
      if (path == null || !mounted) return;
      final file = File(path);
      try {
        final bytes = await file.readAsBytes();
        _applyAvatar(bytes, 'image/jpeg');
      } finally {
        unawaited(file.delete().catchError((Object _) => file));
      }
      return;
    }
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
    );
    if (files.isEmpty || !mounted) return;
    final picked = files.first;
    final bytes = await picked.readAsBytes();
    final ext = (picked.extension ?? '').toLowerCase();
    final mime = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    _applyAvatar(bytes, mime);
  }

  void _applyAvatar(Uint8List bytes, String mime) {
    if (!mounted) return;
    if (bytes.isEmpty || bytes.length > 2 * 1024 * 1024) {
      showBToast(context, '头像图片不能超过 2 MB', isError: true);
      return;
    }
    setState(() {
      _avatarBytes = bytes;
      _avatarType = mime;
      _avatarChanged = true;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    await AppScope.of(context).setMeProfile(
      name: _name.text.trim(),
      gender: _gender,
      signature: _signature.text.trim(),
      avatarBytes: _avatarBytes,
      avatarType: _avatarType,
      updateAvatar: _avatarChanged,
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
                child: GestureDetector(
                  onTap: _pickAvatar,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ValueListenableBuilder(
                        valueListenable: _name,
                        builder: (context, _, _) => SettingsAvatar(
                          name: _name.text.trim(),
                          avatarBytes: _avatarBytes,
                          size: 72,
                        ),
                      ),
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.surfaceRaised,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  '点击头像上传图片 · 电脑和 Bot 会这样认识你',
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

/// A profile picture: uploaded image when set, else the name's first
/// character on the accent wash, or a person glyph while no name is set.
class SettingsAvatar extends StatelessWidget {
  const SettingsAvatar({
    super.key,
    required this.name,
    this.avatarBytes,
    this.size = 52,
  });

  final String name;
  final Uint8List? avatarBytes;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.27);
    if (avatarBytes != null && avatarBytes!.isNotEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.memory(
          avatarBytes!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    }
    final initial = name.isEmpty ? null : name.characters.first;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.16),
        borderRadius: radius,
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.25),
          width: 0.75,
        ),
      ),
      child: Center(
        child: initial == null
            ? Icon(
                Icons.person_outline,
                size: size * 0.5,
                color: AppColors.accent,
              )
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
