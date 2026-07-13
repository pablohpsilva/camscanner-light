import 'package:flutter/material.dart';

import '../folder.dart';
import 'create_folder_dialog.dart';

/// Wraps the folder id chosen from [MoveToFolderSheet] so the caller can tell
/// "user cancelled/dismissed the sheet" (a null [Future] result, the standard
/// `showModalBottomSheet<T>` behavior on swipe-dismiss) apart from "user
/// explicitly chose Unfiled" (a non-null result whose [folderId] is null).
/// A plain `int?` return type could not distinguish those two cases.
class MoveToFolderResult {
  final int? folderId; // null = Unfiled
  const MoveToFolderResult(this.folderId);
}

/// Shows [MoveToFolderSheet] as a modal bottom sheet and returns the chosen
/// folder wrapped in a [MoveToFolderResult], or null if dismissed without
/// choosing (e.g. swiped away).
Future<MoveToFolderResult?> showMoveToFolderSheet(
  BuildContext context, {
  required List<Folder> folders,
  required Future<Folder> Function(String name) onCreateFolder,
}) {
  return showModalBottomSheet<MoveToFolderResult>(
    context: context,
    builder: (_) => MoveToFolderSheet(
      folders: folders,
      onCreateFolder: onCreateFolder,
      onDone: (result) => Navigator.of(context).pop(result),
    ),
  );
}

/// Lists "Unfiled" plus every folder in [folders], plus a "New folder…" row
/// that creates a folder via [onCreateFolder] and adds it to the list
/// in-place. Selecting any row reports the choice via [onDone].
class MoveToFolderSheet extends StatefulWidget {
  final List<Folder> folders;
  final Future<Folder> Function(String name) onCreateFolder;
  final ValueChanged<MoveToFolderResult> onDone;

  const MoveToFolderSheet({
    super.key,
    required this.folders,
    required this.onCreateFolder,
    required this.onDone,
  });

  @override
  State<MoveToFolderSheet> createState() => _MoveToFolderSheetState();
}

class _MoveToFolderSheetState extends State<MoveToFolderSheet> {
  late final List<Folder> _folders = [...widget.folders];

  Future<void> _createFolder() async {
    final name = await showCreateFolderDialog(context);
    if (name == null || !mounted) return;
    final folder = await widget.onCreateFolder(name);
    if (!mounted) return;
    setState(() => _folders.add(folder));
  }

  @override
  Widget build(BuildContext context) {
    // Scrollable + bounded by a fraction of the screen height: an unbounded
    // Column here would overflow once there are more folders than fit the
    // available height (observed with as few as 3 folders on a small test
    // viewport, and a real concern once a user has accumulated many folders).
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Move to folder',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      key: const Key('move-to-folder-unfiled'),
                      title: const Text('Unfiled'),
                      onTap: () =>
                          widget.onDone(const MoveToFolderResult(null)),
                    ),
                    for (final f in _folders)
                      ListTile(
                        key: Key('move-to-folder-${f.id}'),
                        title: Text(f.name),
                        onTap: () => widget.onDone(MoveToFolderResult(f.id)),
                      ),
                    ListTile(
                      key: const Key('move-to-folder-new'),
                      leading: const Icon(Icons.add),
                      title: const Text('New folder…'),
                      onTap: _createFolder,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
