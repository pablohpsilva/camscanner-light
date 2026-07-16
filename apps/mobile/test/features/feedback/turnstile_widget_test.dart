import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/feedback/turnstile_widget.dart';

/// P14 SF-3: the Turnstile site key is interpolated into an
/// `JavaScriptMode.unrestricted` WebView's HTML. It is validated against the
/// Cloudflare key charset first, so a misconfigured/hostile value can't inject.
void main() {
  group('isValidTurnstileSiteKey', () {
    test('accepts a real Cloudflare key charset', () {
      expect(isValidTurnstileSiteKey('0x4AAAAAAA_bcd-EFG'), isTrue);
    });
    test('rejects HTML/JS metacharacters', () {
      expect(isValidTurnstileSiteKey('"><script>alert(1)</script>'), isFalse);
      expect(isValidTurnstileSiteKey('key with spaces'), isFalse);
      expect(isValidTurnstileSiteKey(''), isFalse);
    });
  });

  group('buildTurnstileHtml', () {
    test('interpolates a valid key', () {
      final html = buildTurnstileHtml('0x4AAAAAAA');
      expect(html, contains('data-sitekey="0x4AAAAAAA"'));
    });

    test('drops an injection payload — no script leaks into the HTML', () {
      final html = buildTurnstileHtml('"><script>alert(1)</script>');
      expect(html.contains('<script>alert(1)'), isFalse);
      expect(html, contains('data-sitekey=""'));
    });
  });
}
