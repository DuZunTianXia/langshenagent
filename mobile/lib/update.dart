import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// The build's own update channel: GitHub Pages serves a small JSON
/// (`/update/latest.json`) naming the newest APK under `/apk/`; the app
/// fetches it, downloads the package over IPv6 and hands it to the
/// native installer (`langshenagent/update` channel).
class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.build,
    required this.url,
    this.notes = '',
    this.size = 0,
  });

  factory AppUpdate.fromJson(Map<String, Object?> json) {
    final path = json['apk'] as String? ?? '';
    return AppUpdate(
      version: json['version'] as String? ?? '',
      build: (json['build'] as num?)?.toInt() ?? 0,
      url: path.startsWith('http') ? path : '${Updates.base}$path',
      notes: json['notes'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
    );
  }

  /// Its name and versionCode, as `latest.json` writes them.
  final String version;
  final int build;

  /// The APK's address (absolute).
  final String url;

  /// What it brings, shown in the dialog.
  final String notes;

  /// The APK's byte size, as `latest.json` writes it: progress when the
  /// service doesn't report a length, and the download's completeness
  /// check (a whole file is re-used rather than fetched again).
  final int size;
}

abstract final class Updates {
  /// The release's assets, for a relative `apk` in the manifest
  /// (`mobile-v<x.y.z>/<file>`).
  static const base =
      'https://github.com/DuZunTianXia/baocode/releases/download';

  /// Where it tells what the newest build is: the Pages manifest the
  /// release writes (langshen-release.yml's publish-mobile).
  static const manifest =
      'https://duzuntianxia.github.io/baocode/releases/mobile/latest.json';

  /// Whether the manifest names a build newer than this one; null when the
  /// service can't be asked (offline, down) — not an update.
  static Future<AppUpdate?> check() async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      try {
        final response = await (await client.getUrl(
          Uri.parse(manifest),
        )).close();
        if (response.statusCode != 200) return null;
        final json = jsonDecode(await response.transform(utf8.decoder).join());
        if (json is! Map) return null;
        final update = AppUpdate.fromJson(json.cast<String, Object?>());
        if (update.build <= 0 || update.url.isEmpty) return null;
        final info = await PackageInfo.fromPlatform();
        final mine = int.tryParse(info.buildNumber) ?? 0;
        // A higher build, or the same version number at a higher build.
        return update.build > mine ? update : null;
      } finally {
        client.close();
      }
    } on Object {
      return null;
    }
  }

  /// [update]'s APK, downloaded to a cache file; [onProgress] gets
  /// `(received, total)` bytes as they come — `total` is the body's
  /// length, or the manifest's `size` when the service doesn't say. A
  /// file already there at the right size is used as is (checking for
  /// updates again doesn't download again).
  static Future<File> download(
    AppUpdate update, {
    void Function(int received, int total)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/update/langshenagent-${update.version}.apk');
    await file.parent.create(recursive: true);
    if (update.size > 0 &&
        await file.exists() &&
        await file.length() == update.size) {
      onProgress?.call(update.size, update.size);
      return file;
    }
    final client = HttpClient();
    try {
      final response = await (await client.getUrl(
        Uri.parse(update.url),
      )).close();
      if (response.statusCode != 200) {
        throw HttpException(
          '下载失败（${response.statusCode}）',
          uri: Uri.parse(update.url),
        );
      }
      final total = response.contentLength > 0
          ? response.contentLength
          : update.size;
      var received = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }
      if (update.size > 0 && received != update.size) {
        await file.delete().catchError((_) => file);
        throw HttpException(
          '下载不完整（$received / ${update.size} 字节）',
          uri: Uri.parse(update.url),
        );
      }
      return file;
    } finally {
      client.close();
    }
  }
}
