import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/logging/app_logger.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/document_sort.dart';
import 'package:mobile/features/library/library_controller.dart';
import 'package:mobile/features/library/library_dependencies.dart';

import '../../support/fake_library.dart';

/// Unit tests for the home library orchestration (P06 tasks 9-11) — NO widget
/// is pumped.
void main() {
  const fast = Duration(milliseconds: 100);

  Document doc(int id, String name) => Document(
    id: id,
    name: name,
    createdAt: DateTime.utc(2026, 1, id),
    modifiedAt: DateTime.utc(2026, 1, id),
  );

  LibraryController make(FakeDocumentRepository repo, {AppLogger? logger}) =>
      LibraryController(
        dependencies: LibraryDependencies(
          createRepository: () async => repo,
          logger: () => logger ?? const PrintAppLogger(),
          share: FakeShareChannel(),
        ),
        coldStartStepTimeout: fast,
      );

  group('lifecycle', () {
    test('init loads summaries and clears loading', () async {
      final c = make(FakeDocumentRepository(documents: [doc(1, 'A')]));
      await c.init();
      expect(c.loading, isFalse);
      expect(c.error, isFalse);
      expect(c.summaries, hasLength(1));
      expect(c.sortedSummaries, hasLength(1));
    });

    test('a cold-start timeout surfaces a named, logged failure', () async {
      final logger = SilentAppLogger();
      final c = LibraryController(
        dependencies: LibraryDependencies(
          // Never completes → the watchdog times out.
          createRepository: () => Completer<Never>().future,
          logger: () => logger,
        ),
        coldStartStepTimeout: fast,
      );
      await c.init();
      expect(c.error, isTrue);
      expect(c.loading, isFalse);
      expect(c.startupFailure, contains('opening the library'));
      expect(logger.records, isNotEmpty);
    });
  });

  group('sort', () {
    test('setSortCriterion recomputes the cached sorted list', () async {
      final c = make(
        FakeDocumentRepository(documents: [doc(1, 'Zebra'), doc(2, 'Apple')]),
      );
      await c.init();
      c.setSortCriterion(SortCriterion.name);
      expect(c.sortedSummaries.first.document.name, 'Apple');
    });
  });

  group('search', () {
    test('empty query clears results; a match populates them', () async {
      final c = make(
        FakeDocumentRepository(
          documents: [doc(1, 'Invoice'), doc(2, 'Receipt')],
        ),
      );
      await c.init();
      await c.onQueryChanged('Inv');
      expect(c.searching, isTrue);
      expect(c.searchResults.map((s) => s.document.name), ['Invoice']);
      await c.onQueryChanged('');
      expect(c.searching, isFalse);
      expect(c.searchResults, isEmpty);
    });

    test(
      'race guard: a stale result is discarded when a newer query wins',
      () async {
        final c = make(
          FakeDocumentRepository(documents: [doc(1, 'Alpha'), doc(2, 'Beta')]),
        );
        await c.init();
        final stale = c.onQueryChanged('Alpha'); // in flight
        final fresh = c.onQueryChanged('Beta'); // supersedes
        await Future.wait([stale, fresh]);
        expect(c.query, 'Beta');
        expect(c.searchResults.map((s) => s.document.name), ['Beta']);
      },
    );
  });

  group('selection', () {
    test('toggle / start / clear', () async {
      final c = make(FakeDocumentRepository(documents: [doc(1, 'A')]));
      await c.init();
      final s = c.summaries.first;
      c.startSelection(s);
      expect(c.selectionMode, isTrue);
      c.toggleSelect(s); // deselect
      expect(c.selectionMode, isFalse);
    });
  });

  test('rename refreshes the list on success', () async {
    final repo = FakeDocumentRepository(documents: [doc(1, 'Old')]);
    final c = make(repo);
    await c.init();
    expect(await c.rename(1, 'New'), isTrue);
    expect(repo.renamedTo, contains('New'));
  });

  test('shareDocument toggles sharing and returns success', () async {
    final c = make(FakeDocumentRepository(documents: [doc(1, 'A')]));
    await c.init();
    final busy = <bool>[];
    c.addListener(() => busy.add(c.sharing));
    expect(await c.shareDocument(c.summaries.first), isTrue);
    expect(c.sharing, isFalse);
    expect(busy, contains(true));
  });

  test('suppresses notifications after dispose', () async {
    final c = make(FakeDocumentRepository(documents: [doc(1, 'A')]));
    await c.init();
    var notified = false;
    c.addListener(() => notified = true);
    c.dispose();
    await c.load();
    expect(notified, isFalse);
  });
}
