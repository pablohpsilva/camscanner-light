// Regression for T3: a cold-start failure must be reported through the
// injected AppLogger (not debugPrint), so on-device diagnosis doesn't depend
// on a debug console being attached.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/logging/app_logger.dart';
import 'package:mobile/features/library/document_repository.dart';
import 'package:mobile/features/library/home_screen.dart';
import 'package:mobile/features/library/library_dependencies.dart';

import '../../support/localized_app.dart';

// createRepository() that never completes — forces the cold-start watchdog
// to fire _failStartup('opening the library', ...), same trigger as
// cold_start_watchdog_test.dart.
LibraryDependencies _hangingLibraryDependencies(AppLogger logger) =>
    LibraryDependencies(
      createRepository: () => Completer<DocumentRepository>().future,
      logger: () => logger,
    );

void main() {
  testWidgets(
    'a cold-start failure is reported through the injected AppLogger',
    (tester) async {
      final silent = SilentAppLogger();

      await tester.pumpWidget(
        localizedTestApp(
          home: HomeScreen(
            libraryDependencies: _hangingLibraryDependencies(silent),
          ),
        ),
      );

      await tester.pump(
        HomeScreen.coldStartStepTimeout + const Duration(seconds: 1),
      );
      await tester.pump();

      expect(find.byKey(const Key('documents-error')), findsOneWidget);
      expect(silent.records, hasLength(1));
      expect(silent.records.single.context, contains('opening the library'));
    },
  );
}
