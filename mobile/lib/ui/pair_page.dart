import 'dart:math' as math;

import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../link/phone_link.dart';
import '../main.dart';
import '../phone_platform.dart';
import 'home_page.dart';
import 'md/md_theme.dart';
import 'widgets.dart';

/// Pairing a computer: scan its QR code, paste its pairing link, or pick
/// one found nearby; then compare the safety codes both screens show.
class PairPage extends StatefulWidget {
  const PairPage({super.key});

  @override
  State<PairPage> createState() => _PairPageState();
}

class _PairPageState extends State<PairPage> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  PhoneLink? _link;
  String? _error;
  bool _handled = false;

  // The frame's outer size, its corner marks' reach, the scan line's travel.
  static const double _frameExtent = 286;
  static const double _cornerSpan = 26;
  static const double _scanInset = 12;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.of(context).refreshDiscovery();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final link = _link;
    return Scaffold(
      appBar: AppBar(
        title: Text(link == null ? '配对电脑' : '正在配对'),
      ),
      body: link == null ? _scan() : _pairing(link),
    );
  }

  // --- Scanning -----------------------------------------------------------------

  Widget _scan() {
    final state = AppScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Center(
          child: SizedBox.square(
            dimension: math.min(
              _frameExtent,
              MediaQuery.of(context).size.width - 64,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: _controller,
                    errorBuilder: (context, error) => ColoredBox(
                      color: AppColors.surface,
                      child: BEmptyState(
                        icon: Icons.no_photography_outlined,
                        title: '无法使用相机',
                        subtitle: '请在系统设置中允许本应用访问相机。',
                        actionLabel: '重试',
                        onAction: _controller.start,
                      ),
                    ),
                    onDetect: (capture) {
                      if (_handled) return;
                      final value = capture.barcodes.firstOrNull?.rawValue;
                      if (value != null) _scanned(value);
                    },
                  ),
                  const IgnorePointer(
                    child: CustomPaint(painter: _ScanFramePainter()),
                  ),
                  const IgnorePointer(
                    child: RepaintBoundary(
                      child: _ScanLine(inset: _scanInset),
                    ),
                  ),
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 12,
                    child: Text(
                      '对准电脑上的二维码',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        shadows: [
                          Shadow(blurRadius: 6, color: Color(0xAA000000)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text(
                '将摄像头对准电脑上显示的二维码，或粘贴配对链接。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              BButton(
                label: '粘贴配对链接',
                icon: Icons.link,
                expand: true,
                onPressed: _paste,
              ),
              const SizedBox(height: 18),
              ListenableBuilder(
                listenable: state,
                builder: (context, _) {
                  final nearby = state.nearby.values.toList()
                    ..sort((a, b) => a.name.compareTo(b.name));
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 0, 2, 8),
                        child: Row(
                          children: [
                            Text(
                              '局域网设备',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                                color: AppColors.textMuted,
                              ),
                            ),
                            if (state.discovering) ...[
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 11,
                                height: 11,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.6,
                                  color: AppColors.accent,
                                ),
                              ),
                            ],
                            const Spacer(),
                            GestureDetector(
                              onTap: () {
                                PhonePlatform.haptic('selection');
                                state.refreshDiscovery();
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                child: Text(
                                  '重新扫描',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.accent,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      BCard(
                        padding: EdgeInsets.zero,
                        child: nearby.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 20,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: AppColors.accent.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(11),
                                      ),
                                      child: Icon(
                                        Icons.wifi_tethering_rounded,
                                        size: 20,
                                        color: AppColors.accent,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            state.discovering
                                                ? '正在寻找局域网内的电脑…'
                                                : '暂未发现局域网内的电脑',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            '请确保手机与电脑在同一 Wi-Fi，且电脑端已打开 LangshenAgent。',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textMuted,
                                              height: 1.35,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : Column(
                                children: [
                                  for (var i = 0; i < nearby.length; i++) ...[
                                    BCell(
                                      icon: Icons.computer_rounded,
                                      title: nearby[i].name,
                                      subtitle: nearby[i].pairing
                                          ? '正在等待配对 · 同一局域网'
                                          : '同一局域网 · 点击配对',
                                      onTap: () => _nearby(nearby[i]),
                                    ),
                                    if (i < nearby.length - 1) const BDivider(),
                                  ],
                                ],
                              ),
                      ),
                    ],
                  );
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                BCard(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 18,
                        color: AppColors.removed,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.removed,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// What the code or the pasted link holds: a `langshenagent://pair` URI as the
  /// desktop writes it, or — generous — the data of any URI or JSON with
  /// its `d` parameter (a link shared through other apps can come back
  /// rewrapped).
  PairingOffer _parseOffer(String value) {
    final text = value.trim();
    try {
      return PairingOffer.parse(text);
    } on PairingVersionException {
      rethrow;
    } on Object {
      // Not a `langshenagent://pair` URI: look for its data deeper inside.
    }
    final uri = Uri.tryParse(text);
    final nested = uri?.queryParameters['d'];
    if (nested != null && nested != text) {
      return PairingOffer.parse('${PairingOffer.scheme}://pair?d=$nested');
    }
    throw FormatException('Not a pairing code', text);
  }

  Future<void> _scanned(String value) async {
    if (_handled) return;
    _handled = true;
    final PairingOffer offer;
    try {
      offer = _parseOffer(value);
    } on PairingVersionException {
      _fail('该二维码来自更新版本的应用，请升级电脑上的 LangshenAgent。');
      return;
    } on Object {
      _fail(
        '这不是配对码：${value.length > 60 ? '${value.substring(0, 60)}…' : value}',
      );
      return;
    }
    if (offer.expiredAt(DateTime.now())) {
      _fail('配对码已过期，请在电脑上重新显示。');
      return;
    }
    await _begin(offer: offer);
  }

  Future<void> _paste() async {
    final text = await showBPrompt(
      context,
      title: '配对链接',
      hint: '粘贴 langshenagent://pair?d=… 链接',
      confirm: '配对',
      lines: 3,
    );
    if (text == null || text.trim().isEmpty) return;
    await _scanned(text);
  }

  Future<void> _nearby(LinkAdvert advert) async {
    await _begin(advert: advert);
  }

  Future<void> _begin({PairingOffer? offer, LinkAdvert? advert}) async {
    final state = AppScope.of(context);
    try {
      final link = await state.pair(offer: offer, advert: advert);
      if (!mounted) return;
      // The scanner stops before the tree swaps: stopping it as the
      // MobileScanner unmounts races its teardown, and the debug build
      // throws in the framework.
      await _controller.stop();
      if (!mounted) return;
      setState(() {
        _link = link;
        _error = null;
      });
    } on Object catch (failure) {
      _fail(describeLinkError(failure));
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _error = message);
    _handled = false;
    PhonePlatform.haptic('reject');
  }

  // --- The safety codes -------------------------------------------------------------

  Widget _pairing(PhoneLink link) {
    return ListenableBuilder(
      listenable: link,
      builder: (context, _) {
        final pairing = link.pairing;
        if (pairing == null) {
          // Connected (or failed): leave when online.
          if (link.phase == PhonePhase.online) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                AppScope.of(context).selectComputer(link.computer.id);
                // Land on a fresh HomePage whatever route stack brought
                // us here — plain pop() could empty the stack.
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const HomePage()),
                  (route) => false,
                );
              }
            });
          }
          final error = link.error;
          if (error != null && link.phase == PhonePhase.offline) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      error == 'rejected'
                          ? '电脑拒绝了配对。'
                          : describeLinkError(
                              LinkRemoteException(error, error),
                            ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () async {
                        await link.forget();
                        if (mounted) setState(() => _link = null);
                        _controller.start();
                      },
                      child: const Text('返回'),
                    ),
                  ],
                ),
              ),
            );
          }
          return const Center(child: CircularProgressIndicator());
        }
        return _SafetyCodes(
          name: pairing.name,
          codes: pairing.codes,
          approval: pairing.approval,
          onConfirm: link.confirm,
          onCancel: () async {
            await link.cancelPairing();
            if (mounted) setState(() => _link = null);
            _controller.start();
          },
        );
      },
    );
  }
}

/// A pairing failure in a word or two the screens show.
String describeLinkError(Object failure) => switch (failure) {
  LinkRemoteException(:final code, :final message) => switch (code) {
    LinkErrors.unpaired => '这台手机尚未与它配对。',
    LinkErrors.badToken => '配对码未显示或已过期。',
    LinkErrors.notPairing => '电脑当前不在配对状态。',
    LinkErrors.busy => '另一台手机正在配对，请稍后再试。',
    _ => message,
  },
  LinkClosedException() => '无法连接到电脑。',
  _ => '配对失败：$failure',
};

/// The square scan frame's chrome over the camera: a faint rounded outline
/// and accent corner marks in the WeChat scan style.
class _ScanFramePainter extends CustomPainter {
  const _ScanFramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = const Radius.circular(20);
    final rrect = RRect.fromRectAndRadius(rect.deflate(1), radius);

    // The outline, faint so the corners carry the frame.
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.35),
    );

    // Accent corner marks: two short strokes meeting at each corner.
    const span = _PairPageState._cornerSpan;
    const stroke = 3.5;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = AppColors.accent;
    const inset = stroke / 2 + 1.5;
    final path = Path();
    for (final corner in [
      Alignment.topLeft,
      Alignment.topRight,
      Alignment.bottomLeft,
      Alignment.bottomRight,
    ]) {
      final dx = corner.x < 0 ? inset : size.width - inset;
      final dy = corner.y < 0 ? inset : size.height - inset;
      final sx = corner.x < 0 ? 1.0 : -1.0;
      final sy = corner.y < 0 ? 1.0 : -1.0;
      path
        ..moveTo(dx + sx * span, dy)
        ..lineTo(dx, dy)
        ..lineTo(dx, dy + sy * span);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ScanFramePainter old) => false;
}

/// The green scan line sweeping top to bottom and back, soft-edged by its
/// gradient, with a bright core.
class _ScanLine extends StatefulWidget {
  const _ScanLine({required this.inset});

  final double inset;

  @override
  State<_ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<_ScanLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accent;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final travel =
                constraints.maxHeight - widget.inset * 2 - 3;
            final t = Curves.easeInOut.transform(_controller.value);
            final top = widget.inset + travel * t;
            return Stack(
              children: [
                Positioned(
                  left: widget.inset,
                  right: widget.inset,
                  top: top,
                  height: 3,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: LinearGradient(
                        colors: [
                          accent.withValues(alpha: 0),
                          accent.withValues(alpha: 0.9),
                          accent.withValues(alpha: 0),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.55),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// The four groups of three digits both screens show, to be compared.
class _SafetyCodes extends StatelessWidget {
  const _SafetyCodes({
    required this.name,
    required this.codes,
    required this.approval,
    required this.onConfirm,
    required this.onCancel,
  });

  final String name;
  final List<String> codes;
  final bool approval;
  final Future<void> Function() onConfirm;
  final Future<void> Function() onCancel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Text(
            '核对安全码',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            approval
                ? '电脑上应显示相同的四组数字。若一致，请在此确认，并在电脑上也允许配对。'
                : '电脑上应显示相同的四组数字。若一致，请两端都确认。',
            style: TextStyle(fontSize: 14, height: 1.45, color: AppColors.textMuted),
          ),
          const SizedBox(height: 28),
          BCard(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final code in codes)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.bubbleFill,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          code,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            letterSpacing: 1.5,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          BButton(
            label: '安全码一致',
            primary: true,
            expand: true,
            onPressed: () {
              PhonePlatform.haptic('confirm');
              onConfirm();
            },
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: onCancel,
              child: Text('取消', style: TextStyle(color: AppColors.textMuted)),
            ),
          ),
        ],
      ),
    );
  }
}
