import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/feature_flags.dart';
import 'package:mobile/features/library/library_dependencies.dart';

void main() {
  test('defaults: every feature on except fax', () {
    const f = FeatureFlags();
    expect(f.fax, isFalse, reason: 'fax is the only default-off flag');
    final onByDefault = <bool>[
      f.crop,
      f.rotate,
      f.filter,
      f.viewText,
      f.retake,
      f.share,
      f.deletePage,
      f.rename,
      f.merge,
      f.split,
      f.deleteDocument,
      f.exportPdf,
      f.shareImage,
      f.exportAllImages,
      f.print,
      f.protectWithPassword,
      f.shareLink,
      f.idCard,
      f.scan,
      f.import,
    ];
    expect(onByDefault, everyElement(isTrue));
  });

  test('an override changes only that flag', () {
    const f = FeatureFlags(print: false);
    expect(f.print, isFalse);
    expect(f.crop, isTrue);
    expect(f.fax, isFalse);
  });

  test('LibraryDependencies exposes default FeatureFlags', () {
    const deps = LibraryDependencies();
    expect(deps.features.fax, isFalse);
    expect(deps.features.crop, isTrue);
  });

  test('LibraryDependencies accepts a FeatureFlags override', () {
    const deps = LibraryDependencies(features: FeatureFlags(scan: false));
    expect(deps.features.scan, isFalse);
    expect(deps.features.import, isTrue);
  });
}
