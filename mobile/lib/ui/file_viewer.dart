import 'dart:convert';

import 'package:bao_link/bao_link.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';
import 'package:bao_editor/monaco/flutter/monaco_syntax.dart';
import 'package:bao_editor/monaco/flutter/theme_assets.dart';
import 'package:bao_editor/monaco/vs/editor/common/diff/default_lines_diff_computer/default_lines_diff_computer.dart';
import 'package:bao_editor/monaco/vs/editor/common/diff/range_mapping.dart';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../link/phone_link.dart';
import 'markdown.dart';
import 'md/md_theme.dart';
import 'widgets.dart';

/// A project file on the computer, read through the link: its text with
/// syntax highlighting, and — when the agent changed it and the desktop
/// still knows the original — a diff of what changed.
///
/// The link has no write method, so this is a viewer: what is on the
/// computer stays there.
class FileViewer extends StatefulWidget {
  const FileViewer({
    super.key,
    required this.link,
    required this.project,
    required this.path,
  });

  final PhoneLink link;
  final ProjectInfo project;
  final String path;

  @override
  State<FileViewer> createState() => _FileViewerState();
}

/// 预览 / 编辑 — the two-mode switch under the title.
class _ModePicker extends StatelessWidget {
  const _ModePicker({required this.editing, required this.onChanged});

  final bool editing;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: 32,
    decoration: BoxDecoration(
      color: AppColors.bubbleFill,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        for (final (label, value) in [('预览', false), ('编辑', true)])
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: editing == value
                      ? AppColors.surfaceRaised
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: editing == value
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: editing == value
                        ? AppColors.textPrimary
                        : AppColors.textMuted,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _FileViewerState extends State<FileViewer> {
  static final _syntax = MonacoSyntaxService();

  Map<String, Object?>? _file;
  Object? _error;
  bool _loading = true;
  late final Future<MonacoBuiltinTheme> _theme = _loadTheme();

  /// `null` shows the file, `true` the diff against its original.
  bool? _diff;

  /// 预览 renders it (markdown as the chat shows it, code highlighted);
  /// 编辑 the plain editor, its text changeable for the phone's own use.
  bool _editing = false;
  bool _opening = false;
  EditorSurfaceController? _controller;
  TextEditingController? _editText;
  Map<int, List<TextSpan>>? _styledLines;
  TokenizedDocument? _tokenized;
  int _tokenizeRequest = 0;

  /// The text [_styledLines] was painted for; editing makes it stale,
  /// and stale spans would show the old text in the field.
  String? _styledText;
  Timer? _retokenizeTimer;
  final _editScroll = ScrollController();
  final _gutterScroll = ScrollController();

  String get _name => widget.path.split('/').last;

  @override
  void initState() {
    super.initState();
    _editScroll.addListener(_syncGutter);
    _load();
  }

  /// The editor's own scroll drives its line-number gutter.
  void _syncGutter() {
    if (_gutterScroll.hasClients) {
      _gutterScroll.jumpTo(_editScroll.offset);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _editText?.dispose();
    _retokenizeTimer?.cancel();
    _editScroll.dispose();
    _gutterScroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final file = await widget.link.read(widget.project.id, widget.path);
      if (!mounted) return;
      setState(() {
        _file = file;
        _loading = false;
      });
      _setup(file);
    } on Object catch (failure) {
      if (mounted) {
        setState(() {
          _error = failure;
          _loading = false;
        });
      }
    }
  }

  void _setup(Map<String, Object?> file) {
    final text = file['text'];
    if (text is! String) return;
    _controller?.dispose();
    _editText?.dispose();
    _editText = _HighlightingController(
      text: text,
      styledFor: () =>
          _styledText == _editText?.text ? _styledLines : null,
    )..addListener(_scheduleRetokenize);
    final document = EditorDocumentModel(text);
    _controller = EditorSurfaceController(document: document);
    _tokenize(document, widget.path);
  }

  /// Retokenize a moment after the last edit so the editor's
  /// highlighting follows typing without tokenizing per keystroke.
  void _scheduleRetokenize() {
    _retokenizeTimer?.cancel();
    _retokenizeTimer = Timer(const Duration(milliseconds: 200), () {
      final text = _editText?.text;
      if (!mounted || text == null || text == _styledText) return;
      _tokenize(EditorDocumentModel(text), widget.path);
    });
  }

  Future<MonacoBuiltinTheme> _loadTheme() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return const MonacoThemeAssets().load(dark ? 'vs-dark' : 'vs');
  }

  /// Monarch highlighting for the file's language, reusing the last
  /// tokenization of the same document where it still fits.
  /// Extensions and names with no registration of their own fall back to
  /// the nearest bundled grammar's extension ([_extensionAlias]).
  static const _extAliases = {
    // No bundled JSON grammar: JavaScript's object-literal tokens are
    // the closest fit (strings, numbers, true/false/null, comments).
    'json': 'js', 'jsonc': 'js', 'json5': 'js', 'jsonl': 'js',
    'ndjson': 'js', 'hjson': 'js', 'jsonnet': 'js', 'map': 'js',
    'ipynb': 'js', 'arb': 'js', 'tfstate': 'js', 'mcmeta': 'js',
    'tsbuildinfo': 'js', 'webmanifest': 'js', 'har': 'js',
    'geojson': 'js', 'jsonld': 'js', 'bowerrc': 'js', 'jscsrc': 'js',
    'jslintrc': 'js', 'jshintrc': 'js', 'hintrc': 'js', 'babelrc': 'js',
    'eslintrc': 'js', 'prettierrc': 'js', 'swcrc': 'js',
    'lintstagedrc': 'js', 'vuerc': 'js', 'qml': 'js',
    // Config formats.
    'toml': 'ini', 'env': 'ini', 'cfg': 'ini', 'conf': 'ini',
    'properties': 'ini', 'editorconfig': 'ini', 'reg': 'ini',
    'url': 'ini', 'desktop': 'ini', 'service': 'ini', 'socket': 'ini',
    'timer': 'ini', 'path': 'ini', 'mount': 'ini', 'automount': 'ini',
    'slice': 'ini', 'scope': 'ini', 'device': 'ini', 'htaccess': 'ini',
    'npmrc': 'ini', 'yarnrc': 'ini', 'gitmodules': 'ini',
    'xcconfig': 'ini', 'gitignore': 'ini', 'dockerignore': 'ini',
    'npmignore': 'ini', 'prettierignore': 'ini', 'eslintignore': 'ini',
    'nomad': 'tf', 'cue': 'tf', 'tfbackend': 'tf',
    'lock': 'yaml', 'condarc': 'yaml',
    // Languages without a bundled grammar.
    'hs': 'fs', 'elm': 'fs',
    'cr': 'rb',
    'erl': 'pl', 'hrl': 'pl', 'awk': 'pl',
    'nim': 'py', 'vpy': 'py', 'pyx': 'py', 'pyi': 'py',
    'star': 'py', 'bzl': 'py', 'starlark': 'py',
    'thrift': 'proto', 'capnp': 'proto',
    'move': 'rs', 'cairo': 'rs',
    'nix': 'yaml',
    'hack': 'php',
    'luau': 'lua', 'fnl': 'lua', 'wlua': 'lua',
    'lisp': 'scm', 'lsp': 'scm', 'el': 'scm', 'sld': 'scm',
    'd': 'cpp', 'metal': 'cpp', 'ino': 'cpp', 'cu': 'cpp', 'cuh': 'cpp',
    'mm': 'm',
    'glsl': 'cpp', 'vert': 'cpp', 'frag': 'cpp', 'geom': 'cpp',
    'comp': 'cpp', 'cg': 'cpp', 'cginc': 'cpp', 'shader': 'cpp',
    'fx': 'cpp', 'fxh': 'cpp', 'hlsl': 'cpp', 'hlsli': 'cpp',
    'compute': 'cpp', 'vsh': 'cpp', 'psh': 'cpp',
    'vala': 'cs',
    'gradle': 'java', 'gvy': 'java', 'nf': 'java',
    // Markup and templates.
    'vue': 'html', 'svelte': 'html', 'astro': 'html',
    'jinja': 'html', 'jinja2': 'html', 'j2': 'html', 'eta': 'html',
    'njk': 'html', 'ejs': 'html', 'erb': 'html',
    'mustache': 'handlebars',
    'wxml': 'xml', 'wxss': 'css', 'ui': 'xml', 'resx': 'xml',
    'plist': 'xml', 'storyboard': 'xml', 'xib': 'xml',
    'entitlements': 'xml', 'pbxproj': 'xml', 'vbproj': 'xml',
    'fsproj': 'xml', 'iml': 'xml', 'rss': 'xml', 'atom': 'xml',
    'opml': 'xml', 'wsf': 'xml',
    // Shells and scripting.
    'zsh': 'sh', 'fish': 'sh', 'csh': 'sh', 'ksh': 'sh', 'ash': 'sh',
    'shrc': 'sh', 'kshrc': 'sh', 'xinitrc': 'sh', 'envrc': 'sh',
    'ps1xml': 'ps1', 'btm': 'bat',
    'mk': 'sh', 'mak': 'sh', 'am': 'sh', 'cmake': 'sh',
    // Docs and styles.
    'adoc': 'md', 'asciidoc': 'md', 'org': 'md', 'wiki': 'md',
    'styl': 'scss', 'sass': 'scss', 'postcss': 'css', 'pcss': 'css',
    'lessc': 'less',
    'psql': 'sql', 'pgsql': 'sql', 'plsql': 'sql', 'hql': 'sql',
  };

  /// Dotfiles and extensionless names whose language comes from the
  /// name itself, not the extension.
  static const _nameAliases = {
    'podfile': 'rb', 'brewfile': 'rb', 'vagrantfile': 'rb',
    'fastfile': 'rb', 'appfile': 'rb', 'guardfile': 'rb',
    'capfile': 'rb', 'thorfile': 'rb',
    'jenkinsfile': 'java',
    'cmakelists.txt': 'sh', 'cmakelists': 'sh',
    'meson.build': 'py', 'sconstruct': 'py', 'sconscript': 'py',
    'wscript': 'py', 'build': 'py', 'build.bazel': 'py',
    'workspace': 'py', 'workspace.bazel': 'py', 'buck': 'py',
    'gradlew': 'sh',
    'zshrc': 'sh', 'bashrc': 'sh', 'bash_profile': 'sh',
    'bash_login': 'sh', 'profile': 'sh', 'zprofile': 'sh',
    'zshenv': 'sh', 'zlogin': 'sh', 'shrc': 'sh', 'kshrc': 'sh',
    'xinitrc': 'sh', 'xsession': 'sh', 'bash_aliases': 'sh',
    'vimrc': 'ini', 'gvimrc': 'ini',
    'gitmodules': 'ini', 'sshd_config': 'ini', 'ssh_config': 'ini',
    'gdbinit': 'ini', 'lldbinit': 'ini', 'inputrc': 'ini',
    'condarc': 'yaml', 'clang-format': 'yaml', 'clang-tidy': 'yaml',
    'yamllint': 'yaml',
    'composer.lock': 'js', 'podfile.lock': 'yaml',
    'license': 'md', 'copying': 'md', 'notice': 'md',
    'changelog': 'md', 'history': 'md', 'news': 'md',
  };

  /// The bundled grammar's extension [path] falls back to: null when
  /// its own (or no) extension resolves — the bundled names checked
  /// here, then the alias map above.
  static String? _extensionAlias(String path) {
    final name = path.split('/').last.toLowerCase();
    if (name.startsWith('dockerfile') || name.startsWith('containerfile')) {
      return 'dockerfile';
    }
    if (name.startsWith('.env')) return 'ini';
    if (name.startsWith('makefile') || name == 'gnumakefile') {
      return 'sh';
    }
    final named = _nameAliases[name];
    if (named != null) return named;
    final dot = name.lastIndexOf('.');
    if (dot <= 0) {
      // No extension, or a dotfile like ".zshrc": try the name after
      // the leading dot as both a name and an extension (".env").
      final bare = dot == 0 ? name.substring(1) : name;
      return _nameAliases[bare] ?? _extAliases[bare];
    }
    return _extAliases[name.substring(dot + 1)];
  }

  Future<void> _tokenize(EditorDocumentModel document, String path) async {
    final request = ++_tokenizeRequest;
    try {
      final theme = await _theme;
      var tokenized = await _syntax.tokenizeFileIncremental(
        document.snapshot,
        path,
        previous: _tokenized,
      );
      // The extension registered no language: the nearest bundled
      // grammar's extension may ("main.kts" → "main.kts.java").
      if (tokenized == null) {
        final alias = _extensionAlias(path);
        if (alias != null) {
          tokenized = await _syntax.tokenizeFileIncremental(
            document.snapshot,
            '$path.$alias',
          );
        }
      }
      if (!mounted || request != _tokenizeRequest || tokenized == null) return;
      final result = tokenized;
      setState(() {
        _tokenized = result;
        _styledText = document.text;
        _styledLines = _syntax.styledLines(
          document.snapshot,
          result.lines,
          theme.styleForToken,
        );
      });
    } on Object {
      // No grammar for it (or none bundled): plain text.
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            BFileIcon(name: _name, size: 22),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(38),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: _ModePicker(
              editing: _editing,
              onChanged: (editing) =>
                  setState(() => _editing = editing),
            ),
          ),
        ),
        actions: [
          if (file?['original'] is String)
            IconButton(
              tooltip: _diff == true ? '查看文件' : '查看更改',
              icon: Icon(
                _diff == true
                    ? Icons.article_outlined
                    : Icons.difference_outlined,
              ),
              onPressed: () => setState(() => _diff = _diff != true),
            ),
          if (file?['text'] is String)
            IconButton(
              tooltip: '复制',
              icon: const Icon(Icons.copy_outlined),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: file!['text']! as String));
                showBToast(context, '已复制');
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _Failure(error: _error!, onRetry: _load)
          : file == null
          ? const Center(child: Text('未读取'))
          : _body(file, theme),
    );
  }

  /// Office and other binary documents the viewer can't render: pulled
  /// down to the cache and opened by the system — no dialogs in between.
  static const _docExts = {
    'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'pdf', 'csv', 'pages',
    'key', 'numbers', 'rtf', 'zip', 'apk',
  };

  bool get _isDoc {
    final dot = widget.path.lastIndexOf('.');
    return dot >= 0 &&
        _docExts.contains(widget.path.substring(dot + 1).toLowerCase());
  }

  Widget _body(Map<String, Object?> file, ThemeData theme) {
    if (_isDoc || file['binary'] == true) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined,
                size: 44, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text('无法用内置查看器打开', style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 16),
            BButton(
              label: '用其他应用打开',
              icon: Icons.open_in_new,
              primary: true,
              busy: _opening,
              onPressed: _openExternal,
            ),
          ],
        ),
      );
    }
    if (file['tooLarge'] == true) {
      final size = file['size'];
      return Center(
        child: Text(
          '文件过大'
          '${size is int ? '（${_size(size)}）' : ''}',
        ),
      );
    }
    final text = file['text'];
    if (text is! String) {
      return Center(
        child: TextButton.icon(
          onPressed: _download,
          icon: const Icon(Icons.download_outlined),
          label: const Text('下载'),
        ),
      );
    }
    if (_diff == true && file['original'] is String) {
      return _DiffView(
        original: file['original']! as String,
        modified: text,
        path: widget.path,
      );
    }
    final controller = _controller;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    // 预览: markdown renders as the conversation renders it; anything
    // else is the highlighted, read-only editor.
    if (!_editing &&
        (widget.path.endsWith('.md') || widget.path.endsWith('.markdown'))) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: AppColors.text, fontSize: 15, height: 1.65),
          child: ChatMarkdown(text: text),
        ),
      );
    }
    // The desktop editor's gestures are mouse-shaped (drag = selection);
    // on a phone a plain field scrolls and selects like users expect.
    final body = TextStyle(
      fontFamily: 'monospace',
      fontSize: 13,
      height: 1.5,
      color: theme.colorScheme.onSurface,
    );
    if (!_editing) {
      // No wrap: one source line stays one line, scrolled sideways,
      // with the syntax colors the tokenizer already painted.
      final lines = controller.document.text.split('\n');
      final styled = _styledLines;
      final gutter = _Gutter(
        lines: lines.length,
        style: body.copyWith(color: AppColors.textFaint),
      );
      // Scrollable everywhere, even when the file is short: the text
      // spans at least the viewport so empty space still drags both
      // axes instead of dead space under and right of the lines.
      return LayoutBuilder(
        builder: (context, viewport) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              gutter,
              const SizedBox(width: 12),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth:
                          viewport.maxWidth - 48 - gutter.width,
                      minHeight: viewport.maxHeight - 16,
                    ),
                    child: SelectableText.rich(
                      TextSpan(
                        children: [
                          for (var i = 0; i < lines.length; i++) ...[
                            // The styled map is keyed 1-based.
                            if (styled?[i + 1] != null)
                              TextSpan(children: styled![i + 1])
                            else
                              TextSpan(text: lines[i]),
                            if (i < lines.length - 1)
                              const TextSpan(text: '\n'),
                          ],
                        ],
                      ),
                      style: body,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final editText = _editText;
    if (editText == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            controller: _gutterScroll,
            physics: const NeverScrollableScrollPhysics(),
            child: ValueListenableBuilder(
              valueListenable: editText,
              builder: (context, value, _) => _Gutter(
                lines: value.text.split('\n').length,
                style: body.copyWith(color: AppColors.textFaint),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: editText,
              scrollController: _editScroll,
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.top,
              style: body,
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Downloads the file to the cache and hands it to the system
  /// ("用其他应用打开") — the FileProvider already covers `cache/`.
  Future<void> _openExternal() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final result = await widget.link.download(
        widget.project.id,
        widget.path,
      );
      final data = result['data'];
      if (data is! String) {
        if (mounted) showBToast(context, '文件过大，无法下载');
        return;
      }
      final dir = await getApplicationCacheDirectory();
      final name = widget.path.split('/').last;
      final file = await File('${dir.path}/docs/$name').create(
        recursive: true,
      );
      await file.writeAsBytes(base64Decode(data), flush: true);
      await OpenFilex.open(file.path);
    } on Object catch (failure) {
      if (mounted) showBToast(context, '打开失败：$failure');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _download() async {
    try {
      final result = await widget.link.download(widget.project.id, widget.path);
      final data = result['data'];
      if (data is! String) {
        if (mounted) {
          showBToast(context, '文件过大，无法下载');
        }
        return;
      }
      if (!mounted) return;
      // Saved where the user picks; nothing leaves the phone otherwise.
      showBToast(context, '已下载（${_size(base64Decode(data).length)}）');
    } on Object catch (failure) {
      if (mounted) {
        showBToast(context, '$failure');
      }
    }
  }

  static String _size(int bytes) => bytes < 1024
      ? '$bytes B'
      : bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _Failure extends StatelessWidget {
  const _Failure({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$error', textAlign: TextAlign.center),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

/// The file's changes against the original the desktop sent: removed
/// lines in red, added in green, the rest plain — the diff the desktop's
/// `read` offers for a file the agent touched.
class _DiffView extends StatefulWidget {
  const _DiffView({
    required this.original,
    required this.modified,
    required this.path,
  });

  final String original;
  final String modified;
  final String path;

  @override
  State<_DiffView> createState() => _DiffViewState();
}

class _DiffViewState extends State<_DiffView> {
  List<Widget>? _rows;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  void _compute() {
    try {
      final original = widget.original.split('\n');
      final modified = widget.modified.split('\n');
      // Monaco's own line diff; both sides nonempty as it requires.
      final diff = DefaultLinesDiffComputer().computeDiff(
        original.isEmpty ? const [''] : original,
        modified.isEmpty ? const [''] : modified,
        const LinesDiffComputerOptions(maxComputationTimeMs: 2000),
      );
      if (!mounted) return;
      setState(() {
        _rows = _rowsOf(diff.changes, original, modified);
      });
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  List<Widget> _rowsOf(
    List<DetailedLineRangeMapping> changes,
    List<String> original,
    List<String> modified,
  ) {
    final theme = Theme.of(context);
    final rows = <Widget>[];
    var shown = 0;
    void unchanged(List<String> lines, int from, int to) {
      for (var i = from; i < to && i < lines.length; i++) {
        if (i >= shown) {
          rows.add(_line(theme, ' ', lines[i], null));
          shown = i + 1;
        }
      }
    }

    for (final change in changes) {
      final oStart = change.original.startLineNumber - 1;
      final oEnd = change.original.endLineNumberExclusive - 1;
      final mStart = change.modified.startLineNumber - 1;
      final mEnd = change.modified.endLineNumberExclusive - 1;
      // Up to three unchanged lines before the change.
      final before = oStart < mStart ? oStart : mStart;
      unchanged(original, before - 3 < 0 ? 0 : before - 3, oStart);
      for (var i = oStart; i < oEnd && i < original.length; i++) {
        rows.add(_line(theme, '−', original[i], theme.colorScheme.error));
      }
      for (var i = mStart; i < mEnd && i < modified.length; i++) {
        rows.add(_line(theme, '+', modified[i], Colors.green.shade700));
      }
      shown = oEnd > mEnd ? oEnd : mEnd;
    }
    // The unchanged tail.
    final tail = original.length > modified.length
        ? original.length
        : modified.length;
    final lines = original.length > modified.length ? original : modified;
    for (var i = shown; i < tail && i < lines.length; i++) {
      rows.add(_line(theme, ' ', lines[i], null));
    }
    return rows;
  }

  Widget _line(ThemeData theme, String mark, String text, Color? color) {
    final style = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
      color: color ?? theme.colorScheme.onSurface,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 14,
            child: Text(mark, style: style?.copyWith(color: color)),
          ),
          Expanded(child: SelectableText(text, style: style)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    if (_failed) return const Center(child: Text('无法对比差异'));
    if (rows == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index],
    );
  }
}

/// A line-number column in the code font's metrics; [width] is what the
/// caller leaves for it beside the text.
class _Gutter extends StatelessWidget {
  const _Gutter({required this.lines, required this.style});

  final int lines;
  final TextStyle style;

  double get width => lines.toString().length * 8 + 4;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Text(
      [for (var i = 1; i <= lines; i++) '$i'].join('\n'),
      style: style,
      textAlign: TextAlign.right,
    ),
  );
}

/// A [TextEditingController] painting the file's Monaco-styled spans.
/// [styledFor] returns null while the painted lines no longer match the
/// text — stale spans carry their own text and would resurrect the
/// pre-edit content.
class _HighlightingController extends TextEditingController {
  _HighlightingController({super.text, required this.styledFor});

  final Map<int, List<TextSpan>>? Function() styledFor;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final styled = styledFor();
    if (styled == null) {
      return TextSpan(style: style, text: text);
    }
    final lines = text.split('\n');
    return TextSpan(
      style: style,
      children: [
        for (var i = 0; i < lines.length; i++) ...[
          // The styled map is keyed 1-based.
          if (styled[i + 1] case final spans?)
            TextSpan(children: spans)
          else
            TextSpan(text: lines[i]),
          if (i < lines.length - 1) const TextSpan(text: '\n'),
        ],
      ],
    );
  }
}
