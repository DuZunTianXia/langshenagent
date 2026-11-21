import 'package:flutter/material.dart';

import '../phone_platform.dart';
import '../update.dart';
import 'md/md_theme.dart';
import 'widgets.dart';

/// Asks the server for a newer build and, when one answers, offers to
/// download and install it. Quiet when nothing is newer or the service
/// is unreachable, unless [loud].
Future<void> checkForUpdate(BuildContext context, {bool loud = false}) async {
  final update = await Updates.check();
  if (!context.mounted) return;
  if (update == null) {
    if (loud) showBToast(context, '已是最新版本');
    return;
  }
  final yes =
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surfaceRaised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            '新版本 ${update.version}',
            style: const TextStyle(fontSize: 16),
          ),
          content: Text(
            update.notes.isEmpty ? '有新的构建可以安装。' : update.notes,
            style: TextStyle(fontSize: 13.5, color: AppColors.textMuted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('以后', style: TextStyle(color: AppColors.textMuted)),
            ),
            BButton(
              label: '下载并安装',
              primary: true,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ) ??
      false;
  if (!yes || !context.mounted) return;
  await _downloadAndInstall(context, update);
}

Future<void> _downloadAndInstall(
  BuildContext context,
  AppUpdate update,
) async {
  // The system's "install unknown apps" permission comes first.
  if (!await PhonePlatform.canInstall()) {
    final go =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.surfaceRaised,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            content: const Text('安装更新需要先允许「安装未知应用」。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('取消', style: TextStyle(color: AppColors.textMuted)),
              ),
              BButton(
                label: '去设置',
                primary: true,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ) ??
        false;
    if (!go || !context.mounted) return;
    await PhonePlatform.openInstallSettings();
    // Whether it was allowed is answered on the next try.
    if (!await PhonePlatform.canInstall()) return;
  }
  if (!context.mounted) return;
  final progress = ValueNotifier<({int received, int total})>(
    (received: 0, total: 0),
  );
  final fail = ValueNotifier<Object?>(null);
  unawaitedShowDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => _DownloadDialog(progress: progress, fail: fail),
  );
  void close() {
    if (context.mounted) Navigator.of(context).pop();
  }

  try {
    final file = await Updates.download(
      update,
      onProgress: (received, total) =>
          progress.value = (received: received, total: total),
    );
    // total == -1: the install session stage (copying the APK into the
    // PackageInstaller session) — the bar is indeterminate again.
    progress.value = (received: 0, total: -1);
    await PhonePlatform.install(file.path);
    close();
  } on Object catch (failure) {
    fail.value = failure;
    close();
    if (context.mounted) {
      showBToast(context, '更新失败：$failure', isError: true);
    }
  }
}

/// `showDialog` without a returned value: the progress dialog is closed
/// by the download, not by an answer.
void unawaitedShowDialog({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  showDialog<void>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: builder,
  );
}

class _DownloadDialog extends StatelessWidget {
  const _DownloadDialog({required this.progress, required this.fail});

  final ValueNotifier<({int received, int total})> progress;
  final ValueNotifier<Object?> fail;

  static String _mb(int bytes) => (bytes / 1048576).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: AppColors.surfaceRaised,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: const Text('正在下载更新', style: TextStyle(fontSize: 16)),
    content: ValueListenableBuilder<({int received, int total})>(
      valueListenable: progress,
      builder: (context, value, _) {
        final installing = value.total < 0;
        final known = value.total > 0;
        final fraction = known
            ? (value.received / value.total).clamp(0.0, 1.0)
            : null;
        final percent = fraction == null
            ? null
            : (fraction * 100).clamp(0, 100).toStringAsFixed(0);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),
            Center(
              child: Text(
                installing ? '正在准备安装…' : (percent == null ? '连接中…' : '$percent%'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                backgroundColor: AppColors.textFaint.withValues(alpha: 0.25),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                installing
                    ? '正在将安装包交给系统安装器'
                    : known
                    ? '${_mb(value.received)} / ${_mb(value.total)} MB'
                    : '已下载 ${_mb(value.received)} MB',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ),
          ],
        );
      },
    ),
  );
}
