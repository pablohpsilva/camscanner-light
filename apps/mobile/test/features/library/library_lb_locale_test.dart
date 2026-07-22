import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/document_summary.dart';
import 'package:mobile/features/library/widgets/document_grid_card.dart';
import 'package:mobile/features/library/widgets/documents_list_view.dart';
import 'package:mobile/l10n/l10n.dart';
import 'package:mobile/l10n/lb_fallback_delegates.dart';
import 'package:mobile/theme/ream_theme.dart';

/// Regression for the "grey block" bug: with Luxembourgish (`lb`) selected AND
/// documents present, the home-screen document list rendered as a grey
/// ErrorWidget. Cause: the document card/row formats each document's date via
/// `intl`'s DateFormat, which has no `lb` date-symbol data and threw
/// `ArgumentError` mid-build. These pump the REAL widgets under the app's exact
/// `lb` localization stack (Locale('lb') + kLbFallbackDelegates, matching
/// main.dart) and assert the list builds — no thrown exception, document shown.

DocumentSummary _summary() => DocumentSummary(
  document: Document(
    id: 7,
    name: 'Konviktioun',
    createdAt: DateTime(2026, 6, 27, 20, 26),
    modifiedAt: DateTime(2026, 6, 27, 20, 26),
  ),
  pageCount: 3,
  thumbnailPath: null, // null path -> placeholder (no file I/O)
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
  testWidgets('grid card builds under lb locale (no grey ErrorWidget)', (
    tester,
  ) async {
    await _pumpLb(tester, DocumentGridCard(summary: _summary()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('Konviktioun'), findsOneWidget);
  });

  testWidgets('documents list builds under lb locale (no grey ErrorWidget)', (
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
