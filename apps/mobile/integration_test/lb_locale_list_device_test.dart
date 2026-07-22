// On-device regression for the Luxembourgish "grey block" bug.
//
// `intl` ships no date-symbol data for `lb`, so DateFormat('lb') threw
// ArgumentError mid-build and the home-screen document list rendered as a grey
// ErrorWidget for lb users with documents. This runs the REAL document
// widgets under the app's exact `lb` localization stack ON the device/simulator
// engine (host `flutter test` uses a different intl init path), proving the
// fix holds on real iOS/Android runtimes.
//
// Run: flutter test integration_test/lb_locale_list_device_test.dart -d <device-id>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/document_summary.dart';
import 'package:mobile/features/library/widgets/document_grid_card.dart';
import 'package:mobile/features/library/widgets/documents_list_view.dart';
import 'package:mobile/l10n/l10n.dart';
import 'package:mobile/l10n/lb_fallback_delegates.dart';
import 'package:mobile/theme/ream_theme.dart';

DocumentSummary _summary() => DocumentSummary(
  document: Document(
    id: 7,
    name: 'Konviktioun',
    createdAt: DateTime(2026, 6, 27, 20, 26),
    modifiedAt: DateTime(2026, 6, 27, 20, 26),
  ),
  pageCount: 3,
  thumbnailPath: null,
);

Future<void> _pumpLb(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      theme: ReamTheme.light(),
      locale: const Locale('lb'),
      supportedLocales: const [Locale('lb')],
      localizationsDelegates: const [
        ...kLbFallbackDelegates,
        ...AppLocalizations.localizationsDelegates,
      ],
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('lb: grid card builds on device (no grey ErrorWidget)', (
    tester,
  ) async {
    await _pumpLb(tester, DocumentGridCard(summary: _summary()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('Konviktioun'), findsOneWidget);
  });

  testWidgets('lb: documents list builds on device (no grey ErrorWidget)', (
    tester,
  ) async {
    await _pumpLb(
      tester,
      DocumentsListView(summaries: [_summary()], onOpen: (_) {}),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('Konviktioun'), findsOneWidget);
    expect(find.byKey(const Key('document-tile-7')), findsOneWidget);
  });
}
