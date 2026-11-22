import 'dart:convert';
import 'dart:typed_data';

import 'identity.dart';
import 'relays.dart';

/// Where an end can be reached: its id (what is dialled, and proven), the
/// relays it keeps to, and the addresses it was last seen at (`ip:port`).
/// The addresses are hints: tried at once, with the relays, the first way
/// through kept.
class LinkAddress {
  const LinkAddress(this.id, {this.relays = const [], this.addrs = const []});

  /// As [toJson] wrote it; null for something else.
  static LinkAddress? fromJson(Object? json) => switch (json) {
    {'id': final String id} when keyOfDeviceId(id) != null => LinkAddress(
      id,
      relays: [...?(json['relays'] as List?)?.whereType<String>()],
      addrs: [...?(json['addrs'] as List?)?.whereType<String>()],
    ),
    _ => null,
  };

  final String id;
  final List<String> relays;
  final List<String> addrs;

  LinkAddress copyWith({List<String>? relays, List<String>? addrs}) =>
      LinkAddress(
        id,
        relays: relays ?? this.relays,
        addrs: addrs ?? this.addrs,
      );

  Map<String, Object?> toJson() => {'id': id, 'relays': relays, 'addrs': addrs};

  @override
  bool operator ==(Object other) =>
      other is LinkAddress &&
      other.id == id &&
      _sameList(other.relays, relays) &&
      _sameList(other.addrs, addrs);

  @override
  int get hashCode =>
      Object.hash(id, Object.hashAll(relays), Object.hashAll(addrs));

  @override
  String toString() => 'LinkAddress($id, $relays, $addrs)';
}

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// What a desktop's QR code holds, for a phone to pair with it: its public
/// key, a one-time secret that only who saw the code knows, and where it can
/// be reached (its relays, its addresses).
class PairingOffer {
  const PairingOffer({
    required this.name,
    required this.key,
    required this.token,
    required this.expires,
    this.relays = const [],
    this.addrs = const [],
    this.direct = false,
  });

  /// As [uri] wrote it, or as the code's text is pasted. A code of before
  /// (version 1) is a [PairingVersionException]: the desktop needs
  /// updating.
  factory PairingOffer.parse(String text) {
    final Uri uri;
    try {
      uri = Uri.parse(text.trim());
    } on FormatException {
      throw FormatException('Not a pairing code', text);
    }
    final data = uri.queryParameters['d'];
    if (uri.scheme != scheme || uri.host != 'pair' || data == null) {
      throw FormatException('Not a pairing code', text);
    }
    final Uint8List bytes;
    try {
      bytes = decodeKey(data);
    } on Object {
      throw FormatException('Not a pairing code', text);
    }
    // Versions 3+ pack the offer into bytes directly; versions 1–2 were
    // a JSON object under the same base64 (so they start with '{').
    if (bytes.isNotEmpty && bytes.first != 0x7B) {
      return switch (bytes.first) {
        3 => PairingOffer._parseV3(bytes, text),
        == version => PairingOffer._parseV4(bytes, text),
        > version => throw PairingVersionException(bytes.first),
        _ => throw FormatException('Not a pairing code', text),
      };
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw FormatException('Not a pairing code', text);
    }
    if (json case {'v': final int v} when v != 2) {
      throw PairingVersionException(v);
    }
    if (json case {
      'n': final String name,
      'k': final String key,
      't': final String token,
      'x': final int expires,
    }) {
      final decoded = decodeKey(key);
      if (decoded.length != 32) {
        throw FormatException('Not a pairing code', text);
      }
      return PairingOffer(
        name: name,
        key: decoded,
        token: decodeKey(token),
        expires: DateTime.fromMillisecondsSinceEpoch(expires * 1000),
        relays: [...?(json['r'] as List?)?.whereType<String>()],
        addrs: [...?(json['a'] as List?)?.whereType<String>()],
        direct: json['d'] == true,
      );
    }
    throw FormatException('Not a pairing code', text);
  }

  /// An offer as [uri] writes it since version 3 — `v flags x key token
  /// name relays… addrs…`, every string a u8 length plus its UTF-8.
  factory PairingOffer._parseV3(Uint8List b, String text) {
    FormatException bad() => FormatException('Not a pairing code', text);
    var i = 6;
    if (b.length < i + 48) throw bad();
    final key = Uint8List.fromList(b.sublist(i, i + 32));
    final token = Uint8List.fromList(b.sublist(i + 32, i + 48));
    i += 48;
    final name = _v3String(b, i, bad);
    final relays = _v3List(b, name.$2, bad, defaultLinkRelays);
    final addrs = _v3List(b, relays.$2, bad, const []);
    return PairingOffer(
      name: utf8.decode(name.$1),
      key: key,
      token: token,
      expires: DateTime.fromMillisecondsSinceEpoch(
        (b[2] | b[3] << 8 | b[4] << 16 | b[5] << 24) * 1000,
      ),
      relays: relays.$1,
      addrs: addrs.$1,
      direct: b[1] & 1 == 1,
    );
  }

  /// An offer as [uri] writes it since version 4 — `v flags x key token
  /// name relays… addrs…`; the default relays go untold, and addresses
  /// ride along only when no relay does (a direct pairing).
  factory PairingOffer._parseV4(Uint8List b, String text) {
    FormatException bad() => FormatException('Not a pairing code', text);
    var i = 6;
    if (b.length < i + 40) throw bad();
    final key = Uint8List.fromList(b.sublist(i, i + 32));
    final token = Uint8List.fromList(b.sublist(i + 32, i + 40));
    i += 40;
    final name = _v3String(b, i, bad);
    final custom = _v3List(b, name.$2, bad, const []);
    final addrs = _v3List(b, custom.$2, bad, const []);
    final direct = b[1] & 1 == 1;
    return PairingOffer(
      name: utf8.decode(name.$1),
      key: key,
      token: token,
      expires: DateTime.fromMillisecondsSinceEpoch(
        (b[2] | b[3] << 8 | b[4] << 16 | b[5] << 24) * 1000,
      ),
      relays: direct ? const [] : linkRelays(custom.$1),
      addrs: addrs.$1,
      direct: direct,
    );
  }

  static (Uint8List, int) _v3String(
    Uint8List b,
    int i,
    FormatException Function() bad,
  ) {
    if (i >= b.length || i + 1 + b[i] > b.length) throw bad();
    return (b.sublist(i + 1, i + 1 + b[i]), i + 1 + b[i]);
  }

  /// A u8 count then each entry: `0xFF index` for one of [known], else
  /// a u8-length string.
  static (List<String>, int) _v3List(
    Uint8List b,
    int i,
    FormatException Function() bad,
    List<String> known,
  ) {
    if (i >= b.length) throw bad();
    final count = b[i++];
    final out = <String>[];
    for (var j = 0; j < count; j++) {
      if (i >= b.length) throw bad();
      if (b[i] == 0xFF) {
        if (++i >= b.length || b[i] >= known.length) throw bad();
        out.add(known[b[i++]]);
      } else {
        final (s, next) = _v3String(b, i, bad);
        out.add(utf8.decode(s));
        i = next;
      }
    }
    return (out, i);
  }

  static const scheme = 'langshenagent';
  static const version = 4;

  /// The desktop's name, shown while pairing.
  final String name;

  /// The desktop's public key: its id.
  final Uint8List key;

  /// The one-time secret the phone proves it saw the code with.
  final Uint8List token;

  /// When [token] stops being taken.
  final DateTime expires;

  /// The relays the desktop keeps to (URLs).
  final List<String> relays;

  /// Its addresses (`ip:port`): on the LAN first.
  final List<String> addrs;

  /// It keeps to no relay: [relays] is empty on purpose.
  final bool direct;

  String get id => deviceIdOf(key);

  /// Where to dial the desktop.
  LinkAddress get address => LinkAddress(id, relays: relays, addrs: addrs);

  bool expiredAt(DateTime now) => !now.isBefore(expires);

  /// `langshenagent://pair?d=…`: what the QR code holds. Sparse on
  /// purpose: only what the phone cannot already know goes in — the key
  /// and token raw, the name, relays beyond the defaults, and addresses
  /// only when no relay could reach the desktop at all.
  String get uri {
    final x = expires.millisecondsSinceEpoch ~/ 1000;
    final out = BytesBuilder()
      ..addByte(version)
      ..addByte(direct ? 1 : 0)
      ..add([x & 0xFF, x >> 8 & 0xFF, x >> 16 & 0xFF, x >> 24 & 0xFF])
      ..add(key)
      ..add(token)
      ..add(_v3Encode(name));
    final custom = [
      for (final r in relays)
        if (!defaultLinkRelays.contains(r)) r,
    ];
    out.addByte(custom.length);
    for (final s in custom) {
      out.add(_v3Encode(s));
    }
    final hinted = relays.isEmpty ? addrs : const <String>[];
    out.addByte(hinted.length);
    for (final s in hinted) {
      out.add(_v3Encode(s));
    }
    return '$scheme://pair?d=${encodeKey(out.toBytes())}';
  }

  static Uint8List _v3Encode(String s) {
    final b = utf8.encode(s);
    return Uint8List.fromList([b.length, ...b]);
  }
}

/// A pairing code of another version than this app's.
class PairingVersionException implements Exception {
  const PairingVersionException(this.version);

  final int version;

  /// The code is older: the desktop needs updating.
  bool get older => version < PairingOffer.version;

  @override
  String toString() => 'PairingVersionException($version)';
}
