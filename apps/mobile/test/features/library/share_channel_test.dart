import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/library_dependencies.dart';
import 'package:mobile/features/library/share_channel.dart';

import '../../support/fake_library.dart';

void main() {
  test('SystemShareChannel is a ShareChannel (interface extension point)', () {
    const channel = SystemShareChannel();
    expect(channel, isA<ShareChannel>());
  });

  test('LibraryDependencies defaults share to SystemShareChannel', () {
    const deps = LibraryDependencies();
    expect(deps.share, isA<SystemShareChannel>());
  });

  test('FakeShareChannel records the last share call', () async {
    final fake = FakeShareChannel();
    await fake.share(['/tmp/a.pdf'], subject: 'Doc');
    expect(fake.calls, 1);
    expect(fake.lastFilePaths, ['/tmp/a.pdf']);
    expect(fake.lastSubject, 'Doc');
  });

  test('FakeShareChannel throws when configured to', () {
    final fake = FakeShareChannel(throwOnShare: true);
    expect(() => fake.share(['/tmp/a.pdf']), throwsException);
  });
}
