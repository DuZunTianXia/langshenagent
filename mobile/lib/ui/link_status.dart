import 'package:flutter/material.dart';

import '../link/phone_link.dart';
import 'md/md_theme.dart';
import 'widgets.dart';

/// User-facing words for [PhoneLink.error] codes.
String describeLinkErrorCode(String? error) => switch (error) {
      'unpaired' => '需要重新配对',
      'unreachable' => '无法连接电脑',
      'timeout' => '连接超时',
      'failed' => '连接失败',
      'rejected' => '对方拒绝了配对',
      'closed' => '连接已断开',
      null || '' => '未连接',
      _ => error,
    };

/// Short status for a link's [PhonePhase].
String linkPhaseLabel(PhonePhase phase, {String? error}) {
  if (error == 'unpaired') return '需要重新配对';
  return switch (phase) {
    PhonePhase.online => '在线',
    PhonePhase.connecting => '连接中…',
    PhonePhase.pairing => '正在配对…',
    PhonePhase.offline =>
      error == null ? '离线' : describeLinkErrorCode(error),
  };
}

/// Whether list/detail pages should wait for server `state`.
bool linkWaitsForState(PhoneLink link) =>
    link.phase == PhonePhase.online && link.state == null;

/// Banner under the app bar when the computer is not fully online.
class BConnectionBanner extends StatelessWidget {
  const BConnectionBanner({
    super.key,
    required this.link,
    this.onRetry,
  });

  final PhoneLink link;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: link,
      builder: (context, _) {
        if (link.phase == PhonePhase.online) {
          return const SizedBox.shrink();
        }
        final pairing = link.phase == PhonePhase.pairing;
        final connecting = link.phase == PhonePhase.connecting;
        final needsRePair = link.needsRePair;
        final label = linkPhaseLabel(link.phase, error: link.error);
        final accent = pairing || connecting
            ? AppColors.accent
            : needsRePair
            ? AppColors.removed
            : AppColors.textMuted;
        return Material(
          color: accent.withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                if (connecting || pairing)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent,
                    ),
                  )
                else
                  Icon(
                    needsRePair
                        ? Icons.link_off_outlined
                        : Icons.cloud_off_outlined,
                    size: 18,
                    color: accent,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 13, color: accent),
                  ),
                ),
                if (!pairing &&
                    !needsRePair &&
                    onRetry != null &&
                    link.phase != PhonePhase.connecting)
                  TextButton(
                    onPressed: onRetry,
                    style: TextButton.styleFrom(
                      foregroundColor: accent,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('重连'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Centered placeholder while offline or syncing state.
class LinkUnavailableBody extends StatelessWidget {
  const LinkUnavailableBody({
    super.key,
    required this.link,
    this.offlineTitle = '电脑未连接',
    this.offlineSubtitle,
    this.onRetry,
  });

  final PhoneLink link;
  final String offlineTitle;
  final String? offlineSubtitle;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: link,
      builder: (context, _) {
        if (linkWaitsForState(link)) {
          return Center(
            child: CircularProgressIndicator(color: AppColors.accent),
          );
        }
        if (link.phase == PhonePhase.connecting ||
            link.phase == PhonePhase.pairing) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppColors.accent),
                const SizedBox(height: 14),
                Text(
                  linkPhaseLabel(link.phase, error: link.error),
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ],
            ),
          );
        }
        final subtitle = offlineSubtitle ??
            switch (link.error) {
              'unpaired' => '请在电脑上重新显示配对码后再试。',
              null || '' =>
                '请确认电脑上的 LangshenAgent 已打开并联网，应用会自动重连。',
              final e => describeLinkErrorCode(e),
            };
        return BEmptyState(
          icon: link.needsRePair
              ? Icons.link_off_outlined
              : Icons.cloud_off_outlined,
          title: link.needsRePair ? '需要重新配对' : offlineTitle,
          subtitle: subtitle,
          actionLabel:
              onRetry != null && !link.needsRePair ? '立即重连' : null,
          onAction: onRetry,
        );
      },
    );
  }
}
