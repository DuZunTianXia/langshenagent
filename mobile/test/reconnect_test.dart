import 'dart:async';
import 'dart:io';

import 'package:bao_link/bao_link.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/link/link_store.dart';
import 'package:mobile/link/phone_link.dart';
import 'package:mobile/ui/link_status.dart';

/// A controllable [LinkNode] wrapper for testing hung dials, address
/// overrides, and zombie connections.
class _ControllableNode implements LinkNode {
  _ControllableNode(this._delegate);

  final MemoryLinkNode _delegate;
  final List<LinkAddress> dialed = [];
  Completer<LinkConnection>? nextDialGate;

  @override
  String get id => _delegate.id;

  @override
  Stream<LinkConnection> get incoming => _delegate.incoming;

  @override
  Future<LinkConnection> connect(
    LinkAddress address, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    dialed.add(address);
    final gate = nextDialGate;
    if (gate != null) {
      nextDialGate = null;
      return gate.future;
    }
    return _delegate.connect(address, timeout: timeout);
  }

  @override
  Future<LinkNodeInfo> info() => _delegate.info();

  @override
  Stream<LinkNodeInfo> get changes => _delegate.changes;

  @override
  void networkChanged() => _delegate.networkChanged();

  @override
  Future<void> close() => _delegate.close();
}

void main() {
  late Directory tempDir;
  late LinkStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('phone_link_test_');
    store = await LinkStore.loadFromFile(File('${tempDir.path}/link.json'));
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Attaches a fake desktop server to [desktopNode] that answers `hello`,
  /// `state`, and `open` requests.
  StreamSubscription<LinkConnection> serveDesktop(
    MemoryLinkNode desktopNode, {
    bool Function()? hangState,
    void Function(LinkPeer peer)? onPeer,
  }) {
    return desktopNode.incoming.listen((conn) async {
      final peer = await LinkPeer.accept(
        conn,
        onRequest: (method, params) async {
          switch (method) {
            case LinkMethods.hello:
              return {
                'device': const DeviceInfo(
                  name: 'MacBook Pro',
                  kind: 'mac',
                  system: 'macOS',
                  addrs: ['192.168.1.10:47100'],
                ).toJson(),
              };
            case LinkMethods.state:
              if (hangState?.call() == true) {
                return Completer<Object?>().future;
              }
              return {
                'device': const DeviceInfo(
                  name: 'MacBook Pro',
                  kind: 'mac',
                  system: 'macOS',
                ).toJson(),
                'projects': const [],
                'sessions': const [],
                'bots': const [],
                'groups': const [],
              };
            case LinkMethods.open:
              return {
                'session': params['session'],
                'start': 0,
                'count': 1,
                'items': const [
                  {'t': 'assistant', 'text': 'hello after reconnect'},
                ],
                'live': false,
              };
            default:
              return const {};
          }
        },
      );
      onPeer?.call(peer);
    });
  }

  test('describeLinkErrorCode translates unreachable:* codes cleanly', () {
    expect(describeLinkErrorCode('unreachable:timed out'), '连接超时，正在重试');
    expect(describeLinkErrorCode('unreachable:closed'), '连接已断开，正在重连');
    expect(
      describeLinkErrorCode('unreachable:nowhere to reach it'),
      '暂未找到电脑地址',
    );
    expect(describeLinkErrorCode('unreachable:other'), '无法连接电脑');
    expect(describeLinkErrorCode('unpaired'), '需要重新配对');
  });

  test('SessionFeed stays alive and receives updates across reconnect', () async {
    final network = MemoryLinkNetwork();
    final phoneNode = _ControllableNode(network.node('phone-1'));
    final desktopNode = network.node('desktop-1');
    final peers = <LinkPeer>[];
    final sub = serveDesktop(desktopNode, onPeer: peers.add);
    addTearDown(sub.cancel);

    final computer = PairedComputer(
      id: 'desktop-1',
      name: 'MacBook Pro',
      kind: 'mac',
      system: 'macOS',
      pairedAt: DateTime.now(),
    );
    final link = PhoneLink(
      store: store,
      computer: computer,
      node: () async => phoneNode,
      phoneName: 'Test Phone',
      phoneSystem: 'Android',
    );
    addTearDown(link.dispose);

    await link.connect();
    expect(link.phase, PhonePhase.online);

    final feed = await link.open('sess-1');
    var notified = 0;
    feed.addListener(() => notified++);

    // Simulate connection drop from desktop side.
    await peers.last.close();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(link.phase, PhonePhase.offline);

    // Feed must NOT be disposed; adding a listener must still work.
    expect(() => feed.addListener(() {}), returnsNormally);

    // Reconnect and verify the SAME SessionFeed instance is reused & updated.
    link.retryNow(force: true);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(link.phase, PhonePhase.online);
    expect(identical(link.feeds['sess-1'], feed), isTrue);
    expect(notified, greaterThan(0));
  });

  test('retryNow(force: true) aborts hung dial and connects fresh', () async {
    final network = MemoryLinkNetwork();
    final phoneNode = _ControllableNode(network.node('phone-1'));
    final desktopNode = network.node('desktop-1');
    final sub = serveDesktop(desktopNode);
    addTearDown(sub.cancel);

    // First dial hangs indefinitely.
    final hungDial = Completer<LinkConnection>();
    phoneNode.nextDialGate = hungDial;

    final link = PhoneLink(
      store: store,
      computer: PairedComputer(
        id: 'desktop-1',
        name: 'MacBook Pro',
        kind: 'mac',
        system: 'macOS',
        pairedAt: DateTime.now(),
      ),
      node: () async => phoneNode,
      phoneName: 'Test Phone',
      phoneSystem: 'Android',
    );
    addTearDown(link.dispose);

    unawaited(link.connect());
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(link.phase, PhonePhase.connecting);

    // Force retry aborts the hung dial and immediately connects cleanly.
    link.retryNow(force: true);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(link.phase, PhonePhase.online);
    expect(phoneNode.dialed.length, 2);

    // If the old hung dial eventually resolves, it must be closed and ignored.
    final (staleA, _) = MemoryLinkConnection.pair(a: 'phone-1', b: 'desktop-1');
    hungDial.complete(staleA);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(staleA.isClosed, isTrue);
    expect(link.phase, PhonePhase.online);
  });

  test('probe detects zombie online socket and auto-reconnects', () async {
    final network = MemoryLinkNetwork();
    final phoneNode = _ControllableNode(network.node('phone-1'));
    final desktopNode = network.node('desktop-1');
    var shouldHangState = false;
    final sub = serveDesktop(
      desktopNode,
      hangState: () => shouldHangState,
    );
    addTearDown(sub.cancel);

    final link = PhoneLink(
      store: store,
      computer: PairedComputer(
        id: 'desktop-1',
        name: 'MacBook Pro',
        kind: 'mac',
        system: 'macOS',
        pairedAt: DateTime.now(),
      ),
      node: () async => phoneNode,
      phoneName: 'Test Phone',
      phoneSystem: 'Android',
    );
    addTearDown(link.dispose);

    await link.connect();
    expect(link.phase, PhonePhase.online);
    expect(phoneNode.dialed.length, 1);

    // Simulate zombie socket where state call never answers, then recovers on
    // the new connection.
    shouldHangState = true;
    final probing = link.probe(timeout: const Duration(milliseconds: 120));
    await Future<void>.delayed(const Duration(milliseconds: 160));
    shouldHangState = false;
    await probing;
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(link.phase, PhonePhase.online);
    expect(phoneNode.dialed.length, greaterThanOrEqualTo(2));
  });

  test('updateNearbyAddrs prepends fresh LAN addresses on reconnect', () async {
    final network = MemoryLinkNetwork();
    final phoneNode = _ControllableNode(network.node('phone-1'));
    final desktopNode = network.node('desktop-1');
    final sub = serveDesktop(desktopNode);
    addTearDown(sub.cancel);

    final link = PhoneLink(
      store: store,
      computer: PairedComputer(
        id: 'desktop-1',
        name: 'MacBook Pro',
        kind: 'mac',
        system: 'macOS',
        addrs: const ['192.168.1.99:47100'],
        pairedAt: DateTime.now(),
      ),
      node: () async => phoneNode,
      phoneName: 'Test Phone',
      phoneSystem: 'Android',
    );
    addTearDown(link.dispose);

    link.updateNearbyAddrs(const ['192.168.1.42:47100']);
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(link.phase, PhonePhase.online);
    expect(phoneNode.dialed.last.addrs.first, '192.168.1.42:47100');
    expect(phoneNode.dialed.last.addrs, contains('192.168.1.99:47100'));
  });
}
