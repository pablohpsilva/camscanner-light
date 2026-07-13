import 'package:flutter/material.dart';
import '../document_summary.dart';
import '../folder.dart';

/// The active folder filter: everything, only unfiled, or one folder id.
sealed class FolderFilter {
  const FolderFilter();
  const factory FolderFilter.all() = _AllFilter;
  const factory FolderFilter.unfiled() = _UnfiledFilter;
  const factory FolderFilter.folder(int id) = _FolderFilter;

  /// Whether [s] belongs under this filter. Implemented here (not via
  /// cross-file pattern matching) because the concrete subtypes are private
  /// to this file.
  bool matches(DocumentSummary s);
}

class _AllFilter extends FolderFilter {
  const _AllFilter();
  @override
  bool matches(DocumentSummary s) => true;
  @override
  bool operator ==(Object other) => other is _AllFilter;
  @override
  int get hashCode => 0;
}

class _UnfiledFilter extends FolderFilter {
  const _UnfiledFilter();
  @override
  bool matches(DocumentSummary s) => s.folderId == null;
  @override
  bool operator ==(Object other) => other is _UnfiledFilter;
  @override
  int get hashCode => 1;
}

class _FolderFilter extends FolderFilter {
  final int id;
  const _FolderFilter(this.id);
  @override
  bool matches(DocumentSummary s) => s.folderId == id;
  @override
  bool operator ==(Object other) => other is _FolderFilter && other.id == id;
  @override
  int get hashCode => Object.hash(2, id);
}

/// Horizontal, single-select filter chips: All · Unfiled · each folder (n) · ＋.
/// Rendered by HomeScreen only when at least one folder exists.
class FolderFilterBar extends StatelessWidget {
  final List<Folder> folders;
  final Map<int?, int> counts; // folderId (null=unfiled) -> document count
  final FolderFilter active;
  final ValueChanged<FolderFilter> onChanged;
  final VoidCallback onCreateFolder;

  const FolderFilterBar({
    super.key,
    required this.folders,
    required this.counts,
    required this.active,
    required this.onChanged,
    required this.onCreateFolder,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _chip(context, const FolderFilter.all(), 'All', null),
          _chip(context, const FolderFilter.unfiled(), 'Unfiled', counts[null]),
          for (final f in folders)
            _chip(context, FolderFilter.folder(f.id), f.name, counts[f.id]),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: ActionChip(
              key: const Key('folder-create'),
              label: const Icon(Icons.add, size: 18),
              onPressed: onCreateFolder,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, FolderFilter f, String label, int? count) {
    final selected = f == active;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(count == null ? label : '$label ($count)'),
        selected: selected,
        onSelected: (_) => onChanged(f),
      ),
    );
  }
}
