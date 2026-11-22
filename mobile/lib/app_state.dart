import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_link/bao_link_io.dart';
import 'package:bonsoir/bonsoir.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat/edit_detail.dart';
import 'chat/user_message_style.dart';
import 'link/phone_link.dart';
import 'link/link_store.dart';
import 'phone_platform.dart';

/// The app's state: the store (this phone's key, the paired computers),
/// the one [LinkNode] they share, a [PhoneLink] each, the computers
/// found nearby, and the app's lifecycle.
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  LinkStore? store;
  bool ready = false;

  /// This phone's name and OS, as `hello` tells each computer.
  String _phoneName = '';
  String meGender = '';
  String meSignature = '';
  String get phoneName => _phoneName;
  set phoneName(String value) {
    _phoneName = value;
    notifyListeners();
  }

  String phoneSystem = '';

  IrohLinkNode? _node;
  List<String> _nodeRelays = const [];

  /// The paired computers' links, by computer id.
  final Map<String, PhoneLink> links = {};

  /// The computers found nearby, by id, as they last advertised.
  final Map<String, LinkAdvert> nearby = {};

  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _discoveryEvents;
  bool _disposed = false;

  /// Whether the app is in the background (for `away` and notifications).
  bool away = false;

  /// Files other apps shared into LangshenAgent, waiting to be sent on to an
  /// agent (`{"path", "name", "mime"}` each).
  List<Map<String, Object?>> shared = const [];

  /// Loads the store, binds the node, links the paired computers, and
  /// starts looking for computers nearby.
  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    store = await LinkStore.load();
    await _phone();
    await _ensureNode();
    shared = await PhonePlatform.take();
    ready = true;
    notifyListeners();
    // Keep the link alive in the background so session notifications
    // arrive; the service carries its own ongoing notification.
    unawaited(
      PhonePlatform.keepAlive(
        title: '宝码',
        text: '保持与已配对电脑的连接',
      ),
    );
    unawaited(PhonePlatform.requestNotifications());
    // Doze would freeze the link: ask to join the battery whitelist
    // once (declining is remembered, we don't nag).
    unawaited(() async {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('batteryExemptAsked') == true) return;
      await prefs.setBool('batteryExemptAsked', true);
      await PhonePlatform.ensureBatteryExempt();
    }());
    for (final computer in store!.computers.values) {
      unawaited(_linkFor(computer).connect());
    }
    await _discover();
  }

  Future<void> _phone() async {
    String? custom;
    try {
      final prefs = await SharedPreferences.getInstance();
      custom = prefs.getString('phoneName');
      meGender = prefs.getString('meGender') ?? '';
      meSignature = prefs.getString('meSignature') ?? '';
      UserMessageStyle.current.value =
          prefs.getString('userMessageStyle') == 'bubble'
          ? UserMessageStyle.bubble
          : UserMessageStyle.sticky;
      EditDetail.current.value =
          prefs.getString('editDetail') == 'card'
          ? EditDetail.card
          : EditDetail.compact;
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        phoneName = android.model;
        phoneSystem = 'Android ${android.version.release}';
      } else if (Platform.isIOS) {
        final ios = await info.iosInfo;
        phoneName = ios.name.isEmpty ? ios.model : ios.name;
        phoneSystem = 'iOS ${ios.systemVersion}';
      } else {
        phoneName = Platform.localHostname;
        phoneSystem = Platform.operatingSystem;
      }
    } on Object {
      phoneName = '';
      phoneSystem = '';
    }
    if (custom != null && custom.isNotEmpty) phoneName = custom;
    if (phoneName.isEmpty) phoneName = '手机';
  }

  // --- The node -----------------------------------------------------------------

  /// The relays the node keeps to changed (a computer paired, or told
  /// new ones): bind again. Connections drop and the links try again.
  Future<IrohLinkNode> _ensureNode() async {
    final relays = store!.nodeRelays;
    if (_node != null && listEquals(_nodeRelays, relays)) return _node!;
    await _node?.close();
    _node = await IrohLinkNode.bind(
      identity: store!.identity,
      relays: relays,
      accept: false,
    );
    _nodeRelays = relays;
    return _node!;
  }

  Future<LinkNode> _nodeFor() async => _ensureNode();

  // --- Links ----------------------------------------------------------------------

  PhoneLink _linkFor(PairedComputer computer) => links.putIfAbsent(
    computer.id,
    () {
      final link = PhoneLink(
        store: store!,
        computer: computer,
        node: _nodeFor,
        phoneName: phoneName,
        phoneSystem: phoneSystem,
      );
      link.updateMe(
        name: phoneName,
        gender: meGender,
        signature: meSignature,
      );
      unawaited(_readMarks(link));
      link.onAttention = _attention;
      link.addListener(_linkChanged);
      return link;
    },
  );

  /// The link's read marks: loaded once into it, written back when a
  /// session is opened (so an update or restart keeps sessions read).
  Future<void> _readMarks(PhoneLink link) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('readMarks.${link.computer.id}');
      if (saved != null) {
        final map = jsonDecode(saved);
        if (map is Map) {
          for (final entry in map.entries) {
            final ms = entry.value;
            if (entry.key is String && ms is num) {
              link.readMarks[entry.key as String] = ms.toInt();
            }
          }
        }
      }
      link.onReadMarks = () {
        prefs.setString(
          'readMarks.${link.computer.id}',
          jsonEncode(link.readMarks),
        );
      };
      link.onReadMarks!();
    } on Object {}
  }

  /// Pairs with the computer [offer] (a QR code's or a pasted link's) or
  /// [advert] (one found nearby) names.
  Future<PhoneLink> pair({PairingOffer? offer, LinkAdvert? advert}) async {
    assert(offer != null || advert != null);
    final id = offer?.id ?? advert!.id;
    final computer =
        store!.computers[id] ??
        PairedComputer(
          id: id,
          name: offer?.name ?? advert!.name,
          kind: '',
          system: '',
          pairedAt: DateTime.now(),
        );
    final link = _linkFor(computer);
    await link.connect(offer: offer, advert: advert);
    return link;
  }

  /// Who the user is to the bots: kept in the preferences, told to every
  /// computer ([PhoneLink.updateMe]).
  Future<void> setMeProfile({
    required String name,
    required String gender,
    required String signature,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('phoneName', name);
    await prefs.setString('meGender', gender);
    await prefs.setString('meSignature', signature);
    phoneName = name;
    meGender = gender;
    meSignature = signature;
    for (final link in links.values) {
      link.updateMe(name: name, gender: gender, signature: signature);
    }
    notifyListeners();
  }

  /// Settings → 用户消息样式.
  Future<void> setUserMessageStyle(UserMessageStyle style) async {
    UserMessageStyle.current.value = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userMessageStyle', style.name);
  }

  /// Settings → 编辑详情样式.
  Future<void> setEditDetail(EditDetail detail) async {
    EditDetail.current.value = detail;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('editDetail', detail.name);
  }

  /// Unpairs the computer: forgotten here, and unpaired on it.
  Future<void> unpair(String id) async {
    final link = links.remove(id);
    if (link != null) {
      link.removeListener(_linkChanged);
      await link.forget();
      link.dispose();
    }
    await store!.remove(id);
    await _ensureNode();
    notifyListeners();
  }

  /// The computers paired, as the store keeps them.
  List<PairedComputer> get computers => store!.computers.values.toList();

  PhoneLink? linkOf(String id) => links[id];

  /// A computer's link, made if it is not yet.
  PhoneLink linkFor(PairedComputer computer) => _linkFor(computer);

  void _linkChanged() => notifyListeners();

  /// A followed session came to need the user: a notification when the
  /// app is away, and the keep-alive service reminded.
  void _attention(String session, SessionFeed feed) {
    final link = links.values
        .where((link) => link.feeds[session] == feed)
        .firstOrNull;
    final title = link?.computer.name ?? '';
    PhonePlatform.notify(
      title: title,
      body: feed.interaction != null
          ? '需要你回答'
          : '已完成',
    );
  }

  // --- Discovery -------------------------------------------------------------------

  Future<void> _discover() async {
    final discovery = _discovery = BonsoirDiscovery(
      type: LinkDiscovery.type,
    );
    try {
      await discovery.initialize();
      _discoveryEvents = discovery.eventStream?.listen(_discovered);
      await discovery.start();
    } on Object {
      // Discovery is a convenience: pairing by code works without it.
    }
  }

  void _discovered(BonsoirDiscoveryEvent event) {
    final service = switch (event) {
      BonsoirDiscoveryServiceFoundEvent(:final service) => service,
      BonsoirDiscoveryServiceResolvedEvent(:final service) => service,
      BonsoirDiscoveryServiceUpdatedEvent(:final service) => service,
      BonsoirDiscoveryServiceLostEvent(:final service) => service,
      _ => null,
    };
    if (service == null) return;
    final advert = LinkAdvert.parse(
      name: service.name,
      port: service.port,
      attributes: service.attributes,
      addresses: service.hostAddresses,
    );
    if (advert == null) return;
    if (event is BonsoirDiscoveryServiceLostEvent) {
      nearby.remove(advert.id);
    } else {
      nearby[advert.id] = advert;
      // A paired computer seen again may be reachable now.
      links[advert.id]?.retryNow();
    }
    notifyListeners();
  }

  // --- Lifecycle --------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        away = false;
        _node?.networkChanged();
        unawaited(_takeShared());
        for (final link in links.values) {
          link.away(false);
          link.retryNow();
        }
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        away = true;
        for (final link in links.values) {
          link.away(true);
        }
    }
  }

  /// Files shared in since the last take, added to [shared].
  Future<void> _takeShared() async {
    final taken = await PhonePlatform.take();
    if (taken.isNotEmpty) {
      shared = [...shared, ...taken];
      notifyListeners();
    }
  }

  /// The shared files, taken (the list emptied): to send on to an agent.
  List<Map<String, Object?>> takeShared() {
    final taken = shared;
    shared = const [];
    return taken;
  }

  /// The network changed (Wi-Fi and cellular): the node looks again, and
  /// the computers are tried at once.
  void networkChanged() {
    _node?.networkChanged();
    for (final link in links.values) {
      link.retryNow();
    }
  }

  /// Whether any computer is connected: the keep-alive service runs then.
  bool get anyOnline => links.values.any((link) => link.phase == PhonePhase.online);

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_discoveryEvents?.cancel());
    unawaited(_discovery?.stop());
    for (final link in links.values) {
      link.removeListener(_linkChanged);
      link.dispose();
    }
    links.clear();
    unawaited(_node?.close());
    super.dispose();
  }
}
