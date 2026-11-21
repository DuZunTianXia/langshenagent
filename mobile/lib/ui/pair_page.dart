import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../link/phone_link.dart';
import '../main.dart';
import '../phone_platform.dart';
import 'home_page.dart';

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
          flex: 3,
          child: ClipRect(
            child: MobileScanner(
              controller: _controller,
              errorBuilder: (context, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.no_photography_outlined, size: 40),
                      const SizedBox(height: 12),
                      Text(
                        '无法使用相机：请在系统设置中允许本应用访问相机',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                        onPressed: _controller.start,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
              onDetect: (capture) {
                if (_handled) return;
                final value = capture.barcodes.firstOrNull?.rawValue;
                if (value != null) _scanned(value);
              },
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '将摄像头对准电脑上显示的二维码，或粘贴配对链接。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _paste,
                    icon: const Icon(Icons.link),
                    label: const Text('粘贴配对链接'),
                  ),
                ],
              ),
              if (state.nearby.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  '附近的电脑',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                for (final advert in state.nearby.values)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.wifi_find, size: 20),
                    title: Text(advert.name),
                    subtitle: Text(
                      advert.pairing ? '正在配对' : '同一网络',
                    ),
                    onTap: () => _nearby(advert),
                  ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
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
    final text = await showDialog<String>(
      context: context,
      builder: (context) => const _PasteDialog(),
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

class _PasteDialog extends StatefulWidget {
  const _PasteDialog();

  @override
  State<_PasteDialog> createState() => _PasteDialogState();
}

class _PasteDialogState extends State<_PasteDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('配对链接'),
      content: TextField(
        controller: _text,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: '粘贴 langshenagent://pair?d=… 链接',
          border: OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _text.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_text.text.trim()),
          child: const Text('配对'),
        ),
      ],
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
    final theme = Theme.of(context);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('核对安全码', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            approval
                ? '电脑上应显示相同的四组数字。若一致，请在此确认——'
                      '并在电脑上也允许配对。'
                : '电脑上应显示相同的四组数字。若一致，请两端都确认。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final code in codes)
                Text(
                  code,
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    letterSpacing: 2,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            name,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () {
              PhonePlatform.haptic('confirm');
              onConfirm();
            },
            child: const Text('安全码一致'),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onCancel, child: const Text('取消')),
        ],
      ),
    );
  }
}
