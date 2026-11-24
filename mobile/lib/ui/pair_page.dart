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
      children: [
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
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
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.85),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                  const Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 32, 16, 16),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0x99000000)],
                          ),
                        ),
                        child: SizedBox(height: 56),
                      ),
                    ),
                  ),
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 20,
                    child: Text(
                      '对准电脑上的二维码',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
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
        Expanded(
          flex: 4,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Text(
                '将摄像头对准电脑上显示的二维码，或粘贴配对链接。',
                style: TextStyle(fontSize: 14, color: AppColors.textMuted),
              ),
              const SizedBox(height: 14),
              BButton(
                label: '粘贴配对链接',
                icon: Icons.link,
                expand: true,
                onPressed: _paste,
              ),
              if (state.nearby.isNotEmpty) ...[
                const SizedBox(height: 18),
                BSection(
                  title: '附近的电脑',
                  children: [
                    for (final advert in state.nearby.values)
                      BCell(
                        icon: Icons.wifi_find,
                        title: advert.name,
                        subtitle: advert.pairing ? '正在配对' : '同一网络',
                        onTap: () => _nearby(advert),
                      ),
                  ],
                ),
              ],
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
      setState(() {
        _link = link;
        _error = null;
      });
      _controller.stop();
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
