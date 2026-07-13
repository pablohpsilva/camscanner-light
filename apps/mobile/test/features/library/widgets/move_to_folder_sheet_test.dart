import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/folder.dart';
import 'package:mobile/features/library/widgets/move_to_folder_sheet.dart';

import '../../../support/ream_pump.dart';

void main() {
  Folder folder(int id, String name) =>
      Folder(id: id, name: name, createdAt: DateTime.utc(2026));

  final folders = [folder(1, 'Work'), folder(2, 'Personal')];

  group('MoveToFolderSheet', () {
    testWidgets('renders an Unfiled row plus one row per folder', (
      tester,
    ) async {
      await pumpReam(
        tester,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showMoveToFolderSheet(
              context,
              folders: folders,
              onCreateFolder: (name) async =>
                  Folder(id: 99, name: name, createdAt: DateTime.utc(2026)),
            ),
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('move-to-folder-unfiled')), findsOneWidget);
      expect(find.byKey(const Key('move-to-folder-1')), findsOneWidget);
      expect(find.byKey(const Key('move-to-folder-2')), findsOneWidget);
      expect(find.byKey(const Key('move-to-folder-new')), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('Personal'), findsOneWidget);
    });

    testWidgets('selecting a folder returns its id wrapped in a result', (
      tester,
    ) async {
      MoveToFolderResult? result;
      await pumpReam(
        tester,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showMoveToFolderSheet(
                context,
                folders: folders,
                onCreateFolder: (name) async =>
                    Folder(id: 99, name: name, createdAt: DateTime.utc(2026)),
              );
            },
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('move-to-folder-1')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.folderId, 1);
    });

    testWidgets('selecting Unfiled returns a non-null result with null id', (
      tester,
    ) async {
      MoveToFolderResult? result;
      await pumpReam(
        tester,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showMoveToFolderSheet(
                context,
                folders: folders,
                onCreateFolder: (name) async =>
                    Folder(id: 99, name: name, createdAt: DateTime.utc(2026)),
              );
            },
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('move-to-folder-unfiled')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.folderId, isNull);
    });

    testWidgets('dismissing without a choice returns null (cancelled)', (
      tester,
    ) async {
      MoveToFolderResult? result = const MoveToFolderResult(123);
      var completed = false;
      await pumpReam(
        tester,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showMoveToFolderSheet(
                context,
                folders: folders,
                onCreateFolder: (name) async =>
                    Folder(id: 99, name: name, createdAt: DateTime.utc(2026)),
              );
              completed = true;
            },
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Swipe-dismiss the modal bottom sheet.
      await tester.tapAt(const Offset(20, 20)); // tap the scrim, above the sheet
      await tester.pumpAndSettle();

      expect(completed, true);
      expect(result, isNull);
    });

    testWidgets(
      'New folder creates via the callback, adds it to the list, and selects it',
      (tester) async {
        MoveToFolderResult? result;
        var createdName = '';
        await pumpReam(
          tester,
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showMoveToFolderSheet(
                  context,
                  folders: folders,
                  onCreateFolder: (name) async {
                    createdName = name;
                    return Folder(
                      id: 42,
                      name: name,
                      createdAt: DateTime.utc(2026),
                    );
                  },
                );
              },
              child: const Text('open'),
            ),
          ),
        );

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('move-to-folder-new')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('create-folder-field')),
          'Taxes',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('create-folder-save')));
        await tester.pumpAndSettle();

        expect(createdName, 'Taxes');
        expect(find.text('Taxes'), findsOneWidget);

        await tester.tap(find.byKey(const Key('move-to-folder-42')));
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        expect(result!.folderId, 42);
      },
    );
  });
}
