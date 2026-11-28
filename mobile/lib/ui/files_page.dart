import 'dart:convert';
import 'dart:typed_data';

import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';

import '../link/phone_link.dart';
import 'chat_page.dart';
import 'file_viewer.dart';
import 'link_status.dart';
import 'md/md_theme.dart';
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
          return LinkUnavailableBody(
            link: link,
            offlineTitle: '无法加载项目',
            offlineSubtitle: '连接电脑后即可浏览文件。',
            onRetry: link.retryNow,
          );
        }
        final projects = [...state.projects]
          ..sort((a, b) {
            if (a.pinned == true && b.pinned != true) return -1;
            if (b.pinned == true && a.pinned != true) return 1;
            return a.name.compareTo(b.name);
          });
        if (projects.isEmpty) {
          return const BEmptyState(
            icon: Icons.folder_off_outlined,
            title: '没有项目',
            subtitle: '在电脑上打开文件夹作为工作区后会出现在这里。',
          );
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
    return BInboxRow(
      leading: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: _ProjectIcon(link: link, icon: project.icon),
      ),
      title: project.name,
      subtitle: Text(
        [
          project.path,
          ?project.branch,
        ].join(' · '),
      ),
      pinned: project.pinned == true,
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
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: '搜索项目文件',
            onPressed: _searchFiles,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? BEmptyState(
              icon: Icons.cloud_off_outlined,
              title: '无法加载文件夹',
              subtitle: '$_error',
              actionLabel: '重试',
              onAction: _load,
            )
          : folders.isEmpty && files.isEmpty
          ? const BEmptyState(
              icon: Icons.folder_open_outlined,
              title: '空文件夹',
              subtitle: '这个目录里还没有文件或子文件夹。',
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                key: PageStorageKey('files.${widget.project.id}.${widget.path}'),
                children: [
                  for (final name in folders)
                    _FileRow(
                      name: name,
                      isFolder: true,
                      onTap: () => _openFolder(name),
                    ),
                  for (final name in files)
                    _FileRow(
                      name: name,
                      isFolder: false,
                      onTap: () => _openFile(name),
                    ),
                ],
              ),
            ),
    );
  }

  Future<void> _searchFiles() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _ProjectFileSearchSheet(
        link: widget.link,
        project: widget.project,
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    try {
      await FileViewPage.open(
        context,
        link: widget.link,
        project: widget.project,
        path: picked,
      );
    } on Object catch (failure) {
      if (mounted) showBToast(context, '$failure', isError: true);
    }
  }

  static String _base(String path) => path.split('/').last;
}

class _ProjectFileSearchSheet extends StatefulWidget {
  const _ProjectFileSearchSheet({
    required this.link,
    required this.project,
  });

  final PhoneLink link;
  final ProjectInfo project;

  @override
  State<_ProjectFileSearchSheet> createState() =>
      _ProjectFileSearchSheetState();
}

class _ProjectFileSearchSheetState extends State<_ProjectFileSearchSheet> {
  final _query = TextEditingController();
  List<String> _paths = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.link.files(widget.project.id);
      final raw = result['paths'];
      final paths = <String>[
        for (final p in raw is List ? raw : const [])
          if (p is String && p.isNotEmpty) p,
      ];
      if (mounted) {
        setState(() {
          _paths = paths;
          _loading = false;
        });
      }
    } on Object catch (failure) {
      if (mounted) {
        setState(() {
          _error = '$failure';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final needle = _query.text.trim().toLowerCase();
    final filtered = needle.isEmpty
        ? _paths.take(200).toList()
        : _paths
              .where((p) => p.toLowerCase().contains(needle))
              .take(200)
              .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '搜索 ${widget.project.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (!_loading && _error == null)
                    Text(
                      '${_paths.length} 个文件',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textFaint,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                controller: _query,
                autofocus: true,
                style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                decoration: BTextField.decoration(hint: '输入文件名或路径…'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(color: AppColors.accent),
                    )
                  : _error != null
                  ? BEmptyState(
                      icon: Icons.cloud_off_outlined,
                      title: '无法加载文件列表',
                      subtitle: _error,
                      actionLabel: '重试',
                      onAction: _load,
                    )
                  : filtered.isEmpty
                  ? const BEmptyState(
                      icon: Icons.search_off_rounded,
                      title: '没有匹配的文件',
                      subtitle: '换个关键词试试。',
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const BDivider(),
                      itemBuilder: (context, index) {
                        final path = filtered[index];
                        final slash = path.lastIndexOf('/');
                        final name =
                            slash < 0 ? path : path.substring(slash + 1);
                        final dir = slash < 0 ? '' : path.substring(0, slash);
                        return InkWell(
                          onTap: () => Navigator.of(context).pop(path),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                BFileIcon(name: name, size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      if (dir.isNotEmpty)
                                        Text(
                                          dir,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: AppColors.textMuted,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A file or folder row of a [FolderPage]: compact, but in the visual
/// language of a [BCell] — a tinted icon box, the name, a chevron.
/// The link's `folder` reply carries names only, so there is no size,
/// item count or date to show under the name.
class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.name,
    required this.isFolder,
    required this.onTap,
  });

  final String name;
  final bool isFolder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isFolder ? AppColors.accent : AppColors.textMuted;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: BFileIcon(
                name: isFolder ? 'folder' : name,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14.5, color: AppColors.textPrimary),
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: AppColors.textFaint),
          ],
        ),
      ),
    );
  }
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
          ? BEmptyState(
              icon: Icons.broken_image_outlined,
              title: '无法加载图片',
              subtitle: '$_error',
              actionLabel: '重试',
              onAction: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _load();
              },
            )
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
