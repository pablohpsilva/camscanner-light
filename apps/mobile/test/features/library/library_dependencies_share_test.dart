import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/fax_provider.dart';
import 'package:mobile/features/library/library_dependencies.dart';
import 'package:mobile/features/library/link_share_channel.dart';

void main() {
  test('LibraryDependencies defaults link-share and fax to Unavailable impls', () {
    const deps = LibraryDependencies();
    expect(deps.linkShare, isA<UnavailableLinkShareChannel>());
    expect(deps.fax, isA<UnavailableFaxProvider>());
    expect(deps.linkShare.isAvailable, isFalse);
    expect(deps.fax.isAvailable, isFalse);
  });
}
