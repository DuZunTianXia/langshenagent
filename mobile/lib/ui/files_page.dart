import 'dart:convert';
import 'dart:typed_data';

import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';

import '../link/phone_link.dart';
import 'chat_page.dart';
import 'file_viewer.dart';
import 'widgets.dart';

/// A computer's projects and their files, as the desktop's Explorer has
/// them: projects, then folders down to a file, read or shown.
class FilesPage extends StatelessWidget {
  const FilesPage({super.key, required this.link});

  final PhoneLink link;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: link,
      builder: (context, _) {
        final state = link.state;
        if (state == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final projects = [...state.projects]
          ..sort((a, b) {
            if (a.pinned == true && b.pinned != true) return -1;
            if (b.pinned == true && a.pinned != true) return 1;
            return a.name.compareTo(b.name);
          });
        if (projects.isEmpty) {
          return const Center(child: Text('没有项目'));
        }
        return ListView(
          key: const PageStorageKey('files.root'),
          children: [
            for (final project in projects)
              _ProjectTile(link: link, project: project),
          ],
        );
      },
    );
  }
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({required this.link, required this.project});

  final PhoneLink link;
  final ProjectInfo project;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _ProjectIcon(link: link, icon: project.icon),
      title: Text(project.name),
      subtitle: Text(
        [
          project.path,
          ?project.branch,
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: project.pinned == true
          ? const Icon(Icons.push_pin_outlined, size: 18)
          : null,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FolderPage(link: link, project: project),
        ),
      ),
      onLongPress: () => _menu(context),
    );
  }

  Future<void> _menu(BuildContext context) async {
    final pinned = project.pinned == true;
    final action = await showBActions<String>(
      context,
      actions: [
        (Icons.chat_bubble_outline, '新建对话', null, 'chat'),
        (
          pinned ? Icons.push_pin_outlined : Icons.push_pin,
          pinned ? '取消置顶项目' : '置顶项目',
          null,
          pinned ? 'unpin' : 'pin',
        ),
        (Icons.visibility_off_outlined, '隐藏项目', null, 'hide'),
      ],
    );
    if (!context.mounted || action == null) return;
    try {
      switch (action) {
        case 'chat':
          final session = await link.draft(project.id);
          if (session != null && context.mounted) {
            // ignore: use_build_context_synchronously
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatPage(link: link, sessionId: session),
              ),
            );
          }
        case 'pin':
          await link.pinProject(project.id, true);
        case 'unpin':
          await link.pinProject(project.id, false);
        case 'hide':
          await link.hideProject(project.id);
      }
    } on Object catch (failure) {
      if (context.mounted) {
        showBToast(context, '$failure');
      }
    }
  }
}

/// A project's icon as the desktop keeps it: an emoji, a VS Code codicon
/// name (shown as a folder glyph — the codicon font is not bundled), an
/// image read by [PhoneLink.icon], or a model maker's brand.
class _ProjectIcon extends StatefulWidget {
  const _ProjectIcon({required this.link, required this.icon});

  final PhoneLink link;
  final Map<String, Object?>? icon;

  @override
  State<_ProjectIcon> createState() => _ProjectIconState();
}

class _ProjectIconState extends State<_ProjectIcon> {
  Uint8List? _image;
  String? _asked;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_ProjectIcon old) {
    super.didUpdateWidget(old);
    if (old.icon?['id'] != widget.icon?['id']) _load();
  }

  Future<void> _load() async {
    final icon = widget.icon;
    if (icon?['type'] != 'image' || icon?['id'] is! String) return;
    final id = icon!['id'] as String;
    _asked = id;
    try {
      final result = await widget.link.icon(id);
      final data = result['data'];
      if (!mounted || _asked != id || data is! String) return;
      setState(() => _image = base64Decode(data));
    } on Object {
      // No icon: the folder glyph stays.
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = widget.icon;
    if (_image != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.memory(_image!, width: 24, height: 24, fit: BoxFit.cover),
      );
    }
    return switch (icon?['type']) {
      'emoji' => Text(
        icon?['emoji'] as String? ?? '📁',
        style: const TextStyle(fontSize: 20),
      ),
      _ => const Icon(Icons.folder_outlined),
    };
  }
}

/// One folder of a project: its folders and files, by name. [path] is the
/// `/`-separated path from the project's root (`""` its top, where a
/// workspace's folders are named).
class FolderPage extends StatefulWidget {
  const FolderPage({
    super.key,
    required this.link,
    required this.project,
    this.path = '',
  });

  final PhoneLink link;
  final ProjectInfo project;
  final String path;

  @override
  State<FolderPage> createState() => FolderPageState();
}

class FolderPageState extends State<FolderPage> {
  Map<String, Object?>? _listing;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listing = await widget.link.folder(widget.project.id, widget.path);
      if (mounted) {
        setState(() {
          _listing = listing;
          _loading = false;
        });
      }
    } on Object catch (failure) {
      if (mounted) {
        setState(() {
          _error = failure;
          _loading = false;
        });
      }
    }
  }

  String _child(String name) =>
      widget.path.isEmpty ? name : '${widget.path}/$name';

  void _openFolder(String name) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FolderPage(
          link: widget.link,
          project: widget.project,
          path: _child(name),
        ),
      ),
    );
  }

  Future<void> _openFile(String name) async {
    final path = _child(name);
    try {
      await FileViewPage.open(
        context,
        link: widget.link,
        project: widget.project,
        path: path,
      );
    } on Object catch (failure) {
      if (mounted) {
        showBToast(context, '$failure');
      }
    }
    // The folder's file list may carry change marks; reload quietly.
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final listing = _listing;
    final folders = [
      for (final name in (listing?['folders'] as List?) ?? const [])
        if (name is String) name,
    ]..sort();
    final files = [
      for (final name in (listing?['files'] as List?) ?? const [])
        if (name is String) name,
    ]..sort();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.path.isEmpty ? widget.project.name : _base(widget.path),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$_error'),
                  TextButton(onPressed: _load, child: const Text('重试')),
                ],
              ),
            )
          : folders.isEmpty && files.isEmpty
          ? const Center(child: Text('空文件夹'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                key: PageStorageKey('files.${widget.project.id}.${widget.path}'),
                children: [
                  for (final name in folders)
                    ListTile(
                      dense: true,
                      leading: const BFileIcon(name: 'folder', size: 26),
                      title: Text(name),
                      onTap: () => _openFolder(name),
                    ),
                  for (final name in files)
                    ListTile(
                      dense: true,
                      leading: BFileIcon(name: name, size: 26),
                      title: Text(name),
                      onTap: () => _openFile(name),
                    ),
                ],
              ),
            ),
    );
  }

  static String _base(String path) => path.split('/').last;
}

/// Opens [path] of [project] the right way: a picture as an image, a text
/// file in the viewer, anything else offered as a download.
class FileViewPage extends StatelessWidget {
  const FileViewPage._({required this.link, required this.project, required this.path});

  final PhoneLink link;
  final ProjectInfo project;
  final String path;

  static const _images = {'png', 'jpg', 'jpeg', 'gif', 'webp'};

  static Future<void> open(
    BuildContext context, {
    required PhoneLink link,
    required ProjectInfo project,
    required String path,
  }) async {
    final dot = path.lastIndexOf('.');
    final ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
    if (_images.contains(ext)) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              _ImageView(link: link, project: project, path: path),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FileViewPage._(link: link, project: project, path: path),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FileViewer(link: link, project: project, path: path);
  }
}

class _ImageView extends StatefulWidget {
  const _ImageView({required this.link, required this.project, required this.path});

  final PhoneLink link;
  final ProjectInfo project;
  final String path;

  @override
  State<_ImageView> createState() => _ImageViewState();
}

class _ImageViewState extends State<_ImageView> {
  Map<String, Object?>? _image;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final image = await widget.link.image(widget.project.id, widget.path);
      if (mounted) {
        setState(() {
          _image = image;
          _loading = false;
        });
      }
    } on Object catch (failure) {
      if (mounted) {
        setState(() {
          _error = failure;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _image?['data'];
    return Scaffold(
      appBar: AppBar(title: Text(_base(widget.path))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('$_error'))
          : data is! String
          ? const Center(child: Text('不是图片'))
          : InteractiveViewer(
              child: Center(
                child: Image.memory(
                  base64Decode(data),
                  fit: BoxFit.contain,
                ),
              ),
            ),
    );
  }

  static String _base(String path) => path.split('/').last;
}
