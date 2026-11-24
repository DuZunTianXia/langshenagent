import 'package:langshenagent/link/phone_downloads.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('phoneDownloadUrlsFrom', () {
    test('a relative apk hangs on the GitHub assets', () {
      expect(
        phoneDownloadUrlsFrom({
          'apk': '/mobile-v1.0.35/langshenagent-1.0.35.apk',
        })['android'],
        'https://github.com/DuZunTianXia/langshenagent/releases/download'
        '/mobile-v1.0.35/langshenagent-1.0.35.apk',
      );
    });

    test('an absolute apk is kept as it is', () {
      const url = 'https://example.com/langshenagent.apk';
      expect(
        phoneDownloadUrlsFrom({'apk': url})['android'],
        url,
      );
    });

    test('ios takes the link the release kept', () {
      const url = 'https://testflight.apple.com/join/abcd1234';
      expect(
        phoneDownloadUrlsFrom({
          'ios': {'version': '1.0.35', 'build': 36, 'url': url},
        })['ios'],
        url,
      );
    });

    test('one not named falls back to the downloads page', () {
      final urls = phoneDownloadUrlsFrom(const {});
      expect(urls['android'], phoneDownloadsPage);
      expect(urls['ios'], phoneDownloadsPage);
    });
  });
}
