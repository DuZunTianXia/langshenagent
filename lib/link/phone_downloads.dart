/// Where the phone app is downloaded: its links on the site, the same the
/// download page's buttons and QR codes lead to (site/download.html,
/// tool/make_download_qr.dart). Links that last: site-worker/index.js
/// points them at the release current when one is scanned, so a code
/// written into the page keeps working.
///
/// Settings → Mobile's codes go one better: they resolve the release
/// current themselves ([fetchPhoneDownloadUrls]), so a scan downloads or
/// opens the beta rather than a page to tap through.
library;

import 'dart:convert';
import 'dart:io';

/// The site they are on.
const phoneDownloadSite = 'https://langshenagent.dev';

/// Each phone's link on [phoneDownloadSite], by the download page's card:
/// Android's APK, iOS's TestFlight beta.
const phoneDownloadTargets = {'android': '/dl/android', 'ios': '/dl/ios'};

/// [os]'s download, in full.
String phoneDownloadUrl(String os) =>
    '$phoneDownloadSite${phoneDownloadTargets[os]}';

/// The phone releases' manifest on the site the app itself updates from
/// (langshen-release.yml's publish): it names the files current now —
/// what [phoneDownloadUrl]'s links lead to once langshenagent.dev is up.
const phoneDownloadsManifest =
    'https://agent.langshen.xyz/releases/mobile/latest.json';

/// GitHub Releases' asset base: a relative `apk` in the manifest hangs
/// under it (`mobile-v<x.y.z>/<file>`).
const phoneDownloadsBase =
    'https://github.com/DuZunTianXia/langshenagent/releases/download';

/// The phone cards' part of the downloads page: what a code holds until
/// the manifest answers, and when it can't — the page resolves the same
/// files from its own copy of it.
const phoneDownloadsPage =
    'https://agent.langshen.xyz/download.html#phone';

/// [json]'s downloads, as [fetchPhoneDownloadUrls] answers them: `apk`
/// the GitHub asset (a relative one hung on [phoneDownloadsBase]), `ios`
/// the beta's link the release kept. [phoneDownloadsPage] for one not
/// there.
Map<String, String> phoneDownloadUrlsFrom(Map<Object?, Object?> json) {
  final urls = {
    for (final os in phoneDownloadTargets.keys) os: phoneDownloadsPage,
  };
  if (json['apk'] case final String apk when apk.isNotEmpty) {
    urls['android'] =
        apk.startsWith('http') ? apk : '$phoneDownloadsBase$apk';
  }
  if (json['ios'] case {'url': final String url} when url.isNotEmpty) {
    urls['ios'] = url;
  }
  return urls;
}

/// The downloads the manifest names now, by the codes' `os`: the APK's
/// asset, the iOS beta's page. All of them [phoneDownloadsPage] when it
/// can't be asked.
Future<Map<String, String>> fetchPhoneDownloadUrls({
  HttpClient Function()? client,
}) async {
  try {
    final http = (client ?? HttpClient.new)()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final response = await (await http.getUrl(
        Uri.parse(phoneDownloadsManifest),
      ))
          .close();
      if (response.statusCode != 200) return phoneDownloadUrlsFrom(const {});
      final json = jsonDecode(await response.transform(utf8.decoder).join());
      if (json is! Map) return phoneDownloadUrlsFrom(const {});
      return phoneDownloadUrlsFrom(json);
    } finally {
      http.close();
    }
  } on Object {
    return phoneDownloadUrlsFrom(const {});
  }
}
