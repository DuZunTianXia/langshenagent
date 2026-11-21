import 'dart:async';

import 'package:flutter/material.dart';

import '../link/phone_link.dart';
import 'md/md_theme.dart';
import 'widgets.dart';

/// The desktop's folders, browsed on the phone to pick a new workspace:
/// `browse` lists each folder's subfolders; 选择此文件夹 adds it
/// (`addProject`) and answers the project made.
class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key, required this.link});

  final PhoneLink link;

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  String _path = '';
  String _home = '';
  String? _parent;
  List<Map<String, String>> _dirs = const [];
  bool _truncated = false;
  bool _loading = true;
  bool _adding = false;
  String? _error;
  final _manual = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_go(null));
  }

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  Future<void> _go(String? path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.link.browse(path);
      if (!mounted) return;
      setState(() {
        _path = result['path'] as String? ?? '';
        _home = result['home'] as String? ?? '';
        _parent = result['parent'] as String?;
        _truncated = result['truncated'] == true;
        _dirs = [
          for (final dir in result['dirs'] as List? ?? const [])
            if (dir is Map)
              {
                'name': '${dir['name'] ?? ''}',
                'path': '${dir['path'] ?? ''}',
              },
        ];
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _choose() async {
    if (_path.isEmpty || _adding) return;
    setState(() => _adding = true);
    try {
      final project = await widget.link.addProject(_path);
      if (!mounted) return;
      Navigator.of(context).pop(project);
    } catch (error) {
      if (!mounted) return;
      setState(() => _adding = false);
      showBToast(context, '添加失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择文件夹'),
        actions: [
          if (_home.isNotEmpty && _path != _home)
            IconButton(
              tooltip: '回到主目录',
              icon: const Icon(Icons.home_outlined),
              onPressed: () => _go(_home),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            color: AppColors.surface,
            child: Row(
              children: [
                if (_parent != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: _loading ? null : () => _go(_parent),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.arrow_upward, size: 18),
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    _path.isEmpty ? '…' : _path,
                    maxLines: 2,
                    style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                        const SizedBox(height: 10),
                        BButton(label: '重试', onPressed: () => _go(_path)),
                      ],
                    ),
                  )
                : ListView(
                    children: [
                      for (final dir in _dirs)
                        ListTile(
                          dense: true,
                          leading: Icon(
                            Icons.folder_outlined,
                            color: AppColors.textMuted,
                          ),
                          title: Text(dir['name']!, maxLines: 1),
                          trailing: Icon(
                            Icons.chevron_right,
                            color: AppColors.textFaint,
                            size: 18,
                          ),
                          onTap: () => _go(dir['path']),
                        ),
                      if (_dirs.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            '这个文件夹里没有子文件夹',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textMuted),
                          ),
                        ),
                      if (_truncated)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            '条目过多，仅显示前 500 个',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textFaint,
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                        child: Row(
                          children: [
                            Expanded(
                              child: BTextField(
                                controller: _manual,
                                hint: '或直接输入路径，如 ~/Code/project',
                                onSubmitted: (value) {
                                  var path = value.trim();
                                  if (path.startsWith('~/') &&
                                      _home.isNotEmpty) {
                                    path = '$_home/${path.substring(2)}';
                                  } else if (path == '~') {
                                    path = _home;
                                  }
                                  if (path.isNotEmpty) _go(path);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: BButton(
                primary: true,
                expand: true,
                busy: _adding,
                label: '选择此文件夹',
                onPressed: _loading ? null : _choose,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
