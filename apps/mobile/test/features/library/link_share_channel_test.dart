import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/link_share_channel.dart';

void main() {
  group('UnavailableLinkShareChannel', () {
    const channel = UnavailableLinkShareChannel();

    test('is not available', () {
      expect(channel.isAvailable, isFalse);
    });

    test('createLink throws UnsupportedError', () {
      expect(() => channel.createLink('/tmp/a.pdf'), throwsUnsupportedError);
    });
  });
}
