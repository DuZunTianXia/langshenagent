import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';

import '../link/phone_link.dart';
import 'md/md_theme.dart';
import 'widgets.dart';

/// Compact label for the active connection path and RTT (e.g. `局域网 · 4ms`).
String? describeLinkPath(LinkPath path) {
  final kind = switch (path.kind) {
    LinkPathKind.lan => '局域网',
    LinkPathKind.direct => '直连',
    LinkPathKind.relay => '中继',
    LinkPathKind.none => null,
  };
  if (kind == null) return null;
  final ms = path.rtt?.inMilliseconds;
  return ms != null && ms > 0 ? '$kind · ${ms}ms' : kind;
}

/// User-facing words for [PhoneLink.error] codes.
String describeLinkErrorCode(String? error) {
  if (error == null || error.isEmpty) return '未连接';
  if (error.startsWith('unreachable:')) {
    final detail = error.substring('unreachable:'.length).trim().toLowerCase();
    if (detail.contains('timed out') || detail.contains('timeout')) {
      return '连接超时，正在重试';
    }
    if (detail.contains('closed') || detail.contains('reset')) {
      return '连接已断开，正在重连';
    }
    if (detail.contains('nowhere')) {
      return '暂未找到电脑地址';
    }
    return '无法连接电脑';
  }
  return switch (error) {
    'unpaired' => '需要重新配对',
    'unreachable' => '无法连接电脑',
    'timeout' => '连接超时，正在重试',
    'failed' => '连接失败',
    'rejected' => '对方拒绝了配对',
    'closed' => '连接已断开',
    _ => error,
  };
}

/// Short status for a link's [PhonePhase].
String linkPhaseLabel(PhonePhase phase, {String? error}) {
  if (error == 'unpaired') return '需要重新配对';
  return switch (phase) {
    PhonePhase.online => '在线',
    PhonePhase.connecting => '正在连接…',
    PhonePhase.pairing => '正在配对…',
    PhonePhase.offline =>
      error == null ? '离线' : describeLinkErrorCode(error),
  };
}

/// Whether list/detail pages should wait for server `state`.
bool linkWaitsForState(PhoneLink link) =>
    link.phase == PhonePhase.online && link.state == null;

/// Floating status pill under the app bar when the computer is not online.
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
        final online = link.phase == PhonePhase.online;
        return AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: online
              ? const SizedBox.shrink()
              : _buildBanner(context),
        );
      },
    );
  }

  Widget _buildBanner(BuildContext context) {
    final pairing = link.phase == PhonePhase.pairing;
    final connecting = link.phase == PhonePhase.connecting;
    final needsRePair = link.needsRePair;
    final label = linkPhaseLabel(link.phase, error: link.error);
    final accent = pairing || connecting
        ? AppColors.accent
        : needsRePair
        ? AppColors.removed
        : AppColors.caution;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: MdTheme.dark ? 0.13 : 0.09),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: accent.withValues(alpha: MdTheme.dark ? 0.28 : 0.22),
            width: 0.75,
          ),
        ),
        child: Row(
          children: [
            if (connecting || pairing)
              SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: accent,
                ),
              )
            else
              Icon(
                needsRePair
                    ? Icons.link_off_rounded
                    : Icons.wifi_off_rounded,
                size: 17,
                color: accent,
              ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: accent,
                ),
              ),
            ),
            if (!pairing && !needsRePair && onRetry != null)
              GestureDetector(
                onTap: () => link.retryNow(force: true),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: MdTheme.dark ? 0.2 : 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    connecting ? '重试' : '重连',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
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
