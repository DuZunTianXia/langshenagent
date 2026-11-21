import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bao_link/bao_link.dart';
import 'package:path_provider/path_provider.dart';

/// A computer paired with this phone, as the phone keeps it: who it is
/// ([DeviceInfo]), where it was last reached, and when.
class PairedComputer {
  const PairedComputer({
    required this.id,
    required this.name,
    required this.kind,
    required this.system,
    this.laptop = true,
    this.relays = const [],
    this.addrs = const [],
    this.direct = false,
    required this.pairedAt,
    this.lastSeen,
  });

  factory PairedComputer.fromJson(Map<String, Object?> json) => PairedComputer(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    kind: json['kind'] as String? ?? 'mac',
    system: json['system'] as String? ?? '',
    laptop: json['laptop'] as bool? ?? true,
    relays: [...?(json['relays'] as List?)?.whereType<String>()],
    addrs: [...?(json['addrs'] as List?)?.whereType<String>()],
    direct: json['direct'] == true,
    pairedAt: DateTime.fromMillisecondsSinceEpoch(
      json['pairedAt'] as int? ?? 0,
    ),
    lastSeen: switch (json['lastSeen']) {
      final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
      _ => null,
    },
  );

  /// Its id: its public key in hex (its iroh endpoint id).
  final String id;
  final String name;

  /// `mac`, `windows` or `linux`.
  final String kind;

  /// Its OS and version, e.g. `macOS 26.1`.
  final String system;
  final bool laptop;

  /// The relays it keeps to, and its addresses, as last told (the QR
  /// code's, then each `hello` answer's).
  final List<String> relays;
  final List<String> addrs;

  /// It keeps to no relay: [relays] empty on purpose.
  final bool direct;
  final DateTime pairedAt;
  final DateTime? lastSeen;

  /// Its public key's fingerprint, as both screens showed it pairing.
  String get fingerprint => fingerprintOf(keyOfDeviceId(id) ?? Uint8List(0));

  PairedComputer copyWith({
    String? name,
    String? system,
    List<String>? relays,
    List<String>? addrs,
    bool? direct,
    DateTime? lastSeen,
  }) => PairedComputer(
    id: id,
    name: name ?? this.name,
    kind: kind,
    system: system ?? this.system,
    laptop: laptop,
    relays: relays ?? this.relays,
    addrs: addrs ?? this.addrs,
    direct: direct ?? this.direct,
    pairedAt: pairedAt,
    lastSeen: lastSeen ?? this.lastSeen,
  );

  /// As [device] (a `hello` answer's) says it is now.
  PairedComputer withDevice(DeviceInfo device, {DateTime? lastSeen}) =>
      copyWith(
        name: device.name.isEmpty ? null : device.name,
        system: device.system.isEmpty ? null : device.system,
        relays: device.relays,
        addrs: device.addrs,
        direct: device.direct,
        lastSeen: lastSeen,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind,
    'system': system,
    'laptop': laptop,
    'relays': relays,
    'addrs': addrs,
    if (direct) 'direct': true,
    'pairedAt': pairedAt.millisecondsSinceEpoch,
    'lastSeen': ?lastSeen?.millisecondsSinceEpoch,
  };
}

/// What the phone keeps in its private directory's `link.json`: this
/// phone's key, and the computers paired with it.
class LinkStore {
  LinkStore._(this._file, this.identity, this.computers);

  final File _file;

  /// This phone's lasting key pair; never leaves the phone.
  LinkIdentity identity;

  /// The computers paired, by id.
  final Map<String, PairedComputer> computers;

  /// Loads it; a new phone's key made when there is none.
  static Future<LinkStore> load() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/link.json');
    Map<String, Object?> json = const {};
    try {
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, Object?>) json = decoded;
      }
    } on Object {
      // Unreadable: start over, as a new phone.
    }
    final identity =
        LinkIdentity.fromJson(
          json['identity'] is Map<String, Object?>
              ? json['identity']! as Map<String, Object?>
              : const {},
        ) ??
        LinkIdentity.generate();
    final computers = <String, PairedComputer>{};
    for (final computer in (json['computers'] as List?) ?? const []) {
      if (computer is Map<String, Object?>) {
        final paired = PairedComputer.fromJson(computer);
        if (paired.id.isNotEmpty) computers[paired.id] = paired;
      }
    }
    final store = LinkStore._(file, identity, computers);
    await store.save();
    return store;
  }

  Future<void> save() async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'identity': identity.toJson(),
        'computers': [
          for (final computer in computers.values) computer.toJson(),
        ],
      }),
    );
  }

  /// Pairs [computer] (as [PairingOffer] and the `hello` answer told it).
  Future<void> pair(PairedComputer computer) async {
    computers[computer.id] = computer;
    await save();
  }

  Future<void> remove(String id) async {
    computers.remove(id);
    await save();
  }

  /// The relays this phone's node keeps to: those its paired computers
  /// told it (a pairing's code, each `hello` answer); LangshenAgent's while it
  /// has none to ask, or while any is not direct-only — all direct-only,
  /// it keeps to none (see docs/mobile-link.md).
  List<String> get nodeRelays {
    if (computers.isEmpty) return linkRelays();
    if (computers.values.every((computer) => computer.direct)) return const [];
    return linkRelays([
      for (final computer in computers.values) ...computer.relays,
    ]);
  }

  /// Whether the node keeps to no relay (every computer direct-only).
  bool get directOnly =>
      computers.isNotEmpty && computers.values.every((c) => c.direct);
}
