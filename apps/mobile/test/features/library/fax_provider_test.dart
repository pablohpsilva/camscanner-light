import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/fax_provider.dart';

void main() {
  group('UnavailableFaxProvider', () {
    const provider = UnavailableFaxProvider();

    test('is not available', () {
      expect(provider.isAvailable, isFalse);
    });

    test('sendFax throws UnsupportedError', () {
      expect(
        () => provider.sendFax(filePaths: const ['/tmp/a.pdf'], faxNumber: '123'),
        throwsUnsupportedError,
      );
    });
  });
}
