import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/feature_flags.dart';
import 'package:mobile/features/library/share/share_action.dart';

import '../../../support/localized_app.dart';

void main() {
  group('availableShareActions', () {
    test(
      'default flags (fax off) yield the export family minus fax, in order',
      () {
        final kinds = availableShareActions(
          const FeatureFlags(),
        ).map((a) => a.kind).toList();
        expect(kinds, const [
          ShareActionKind.exportPdf,
          ShareActionKind.shareImage,
          ShareActionKind.exportAllImages,
          ShareActionKind.print,
          ShareActionKind.protect,
          ShareActionKind.shareLink,
        ]);
      },
    );

    test('fax on appends fax last', () {
      final kinds = availableShareActions(
        const FeatureFlags(fax: true),
      ).map((a) => a.kind).toList();
      expect(kinds, const [
        ShareActionKind.exportPdf,
        ShareActionKind.shareImage,
        ShareActionKind.exportAllImages,
        ShareActionKind.print,
        ShareActionKind.protect,
        ShareActionKind.shareLink,
        ShareActionKind.fax,
      ]);
    });

    test('a disabled flag hides exactly its action, order preserved', () {
      final kinds = availableShareActions(
        const FeatureFlags(print: false),
      ).map((a) => a.kind).toList();
      expect(kinds.contains(ShareActionKind.print), isFalse);
      expect(kinds, const [
        ShareActionKind.exportPdf,
        ShareActionKind.shareImage,
        ShareActionKind.exportAllImages,
        ShareActionKind.protect,
        ShareActionKind.shareLink,
      ]);
    });

    test('every sub-action off yields an empty list', () {
      expect(
        availableShareActions(
          const FeatureFlags(
            exportPdf: false,
            shareImage: false,
            exportAllImages: false,
            print: false,
            protectWithPassword: false,
            shareLink: false,
          ),
        ),
        isEmpty,
      );
    });
  });

  group('keyFor preserves the historical menu keys', () {
    // The exact suffixes the widget/BDD suites already assert. If any of these
    // drift, page_viewer_share_sheet_flags_test / documents_list_view tests break.
    const expected = {
      ShareActionKind.exportPdf: 'export',
      ShareActionKind.shareImage: 'export-image',
      ShareActionKind.exportAllImages: 'export-all-images',
      ShareActionKind.print: 'print',
      ShareActionKind.protect: 'protect',
      ShareActionKind.shareLink: 'share-link',
      ShareActionKind.fax: 'fax',
    };

    test('page-viewer prefix reproduces the sheet keys', () {
      for (final entry in expected.entries) {
        final action = ShareAction(entry.key);
        expect(
          action.keyFor('page-viewer'),
          Key('page-viewer-${entry.value}'),
          reason: entry.key.name,
        );
      }
    });

    test('document-<id> prefix reproduces the per-row extras keys', () {
      expect(
        ShareAction(ShareActionKind.shareLink).keyFor('document-42'),
        const Key('document-42-share-link'),
      );
      expect(
        ShareAction(ShareActionKind.fax).keyFor('document-42'),
        const Key('document-42-fax'),
      );
    });
  });

  group('shareExtras', () {
    test('is share-link (+ fax when on), in order', () {
      expect(
        shareExtras(const FeatureFlags()).map((a) => a.kind).toList(),
        const [ShareActionKind.shareLink],
      );
      expect(
        shareExtras(const FeatureFlags(fax: true)).map((a) => a.kind).toList(),
        const [ShareActionKind.shareLink, ShareActionKind.fax],
      );
    });

    test('drops share-link when its flag is off', () {
      expect(
        shareExtras(
          const FeatureFlags(shareLink: false, fax: true),
        ).map((a) => a.kind).toList(),
        const [ShareActionKind.fax],
      );
    });
  });

  group('shouldShowShareButton', () {
    test('true for default flags', () {
      expect(shouldShowShareButton(const FeatureFlags()), isTrue);
    });

    test('false when the umbrella share flag is off', () {
      expect(shouldShowShareButton(const FeatureFlags(share: false)), isFalse);
    });

    test('false when share on but every sub-action off', () {
      expect(
        shouldShowShareButton(
          const FeatureFlags(
            exportPdf: false,
            shareImage: false,
            exportAllImages: false,
            print: false,
            protectWithPassword: false,
            shareLink: false,
          ),
        ),
        isFalse,
      );
    });

    test('true when share on and at least one sub-action on', () {
      expect(
        shouldShowShareButton(
          const FeatureFlags(
            exportPdf: true,
            shareImage: false,
            exportAllImages: false,
            print: false,
            protectWithPassword: false,
            shareLink: false,
          ),
        ),
        isTrue,
      );
    });
  });

  group('label + icon reuse the existing l10n getters / material icons', () {
    testWidgets('labels resolve to the existing getters', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        localizedTestApp(
          home: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final l10n = ctx.l10n;
      expect(ShareAction(ShareActionKind.exportPdf).label(l10n), 'Export PDF');
      expect(ShareAction(ShareActionKind.fax).label(l10n), 'Fax');
      expect(ShareAction(ShareActionKind.shareLink).icon, Icons.link);
    });
  });
}
