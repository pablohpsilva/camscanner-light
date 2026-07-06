import 'package:flutter_test/flutter_test.dart';
import '../../support/fake_library.dart';

void main() {
  test('records the mimeType passed to share', () async {
    final fake = FakeShareChannel();
    await fake.share(['/tmp/documents.zip'], mimeType: 'application/zip');
    expect(fake.lastMimeType, 'application/zip');
    expect(fake.lastFilePaths, ['/tmp/documents.zip']);
  });

  test('mimeType defaults to null (existing callers unchanged)', () async {
    final fake = FakeShareChannel();
    await fake.share(['/tmp/a.pdf'], subject: 'A');
    expect(fake.lastMimeType, isNull);
    expect(fake.lastSubject, 'A');
  });
}
