// Regression + guardrail for the "opens but never loads" white-screen bug.
//
// Root cause it guards: after the opencv_dart 2.x upgrade the app builds with
// Dart native assets, which made sqlite3 a native asset. Opening the DB in a
// spawned background isolate (NativeDatabase.createInBackground) then never
// completed, so createRepository() hung and the home sat on its loading spinner
// forever. The fix opens the DB on the root isolate; this test locks in the
// cold-start watchdog that turns any such hang into a visible, named error
// instead of an endless white/spinner screen.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document_repository.dart';
import 'package:mobile/features/library/home_screen.dart';
import 'package:mobile/features/library/library_dependencies.dart';

import '../../support/fake_library.dart';

// createRepository() that never completes — simulates the wedged native DB open.
LibraryDependencies _hangingLibraryDependencies() => LibraryDependencies(
  createRepository: () => Completer<DocumentRepository>().future,
);

void main() {
  testWidgets(
    'cold-start watchdog surfaces a named timeout error when the library '
    'never opens (instead of an endless spinner)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(libraryDependencies: _hangingLibraryDependencies()),
        ),
      );

      // First frame: the loading spinner is shown while startup runs.
      expect(find.byKey(const Key('documents-loading')), findsOneWidget);
      expect(find.byKey(const Key('documents-error')), findsNothing);

      // Advance past the cold-start budget so the watchdog fires.
      await tester.pump(
        HomeScreen.coldStartStepTimeout + const Duration(seconds: 1),
      );
      await tester.pump();

      // The endless spinner is gone; a named, retryable error is shown instead.
      expect(find.byKey(const Key('documents-loading')), findsNothing);
      expect(find.byKey(const Key('documents-error')), findsOneWidget);
      expect(
        find.text('Startup timed out while opening the library.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('documents-retry')), findsOneWidget);
    },
  );

  testWidgets('normal cold start completes to the Documents home', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          libraryDependencies: fakeLibraryDependencies(
            FakeDocumentRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Reached a usable home: no spinner, no timeout error, empty-state visible.
    expect(find.byKey(const Key('documents-loading')), findsNothing);
    expect(find.byKey(const Key('documents-error')), findsNothing);
    expect(find.widgetWithText(AppBar, 'Documents'), findsOneWidget);
    expect(find.text('No documents yet'), findsOneWidget);
  });
}
