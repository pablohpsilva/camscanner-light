import 'dart:io';

import 'package:flutter/material.dart';

import '../page_image.dart';

/// Horizontal scrollable strip of page thumbnails for [PageViewerScreen].
/// [currentIndex] is 0-based (matching [PageController]). Auto-scrolls to
/// keep the active tile visible when [currentIndex] changes.
/// Tapping tile i calls [onTap](i).
/// When [onReorder] is provided, tiles are long-press-draggable to reorder.
class PageThumbnailStrip extends StatefulWidget {
  final List<PageImage> pages;
  final int currentIndex;
  final void Function(int index) onTap;
  final void Function(int oldIndex, int newIndex)? onReorder;

  const PageThumbnailStrip({
    super.key,
    required this.pages,
    required this.currentIndex,
    required this.onTap,
    this.onReorder,
  });

  @override
  State<PageThumbnailStrip> createState() => _PageThumbnailStripState();
}

class _PageThumbnailStripState extends State<PageThumbnailStrip> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  @override
  void didUpdateWidget(PageThumbnailStrip old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      _scrollToCurrent();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrent() {
    if (!_scrollController.hasClients) return;
    const double kSlot = 64.0; // 56 tile + 4 left margin + 4 right margin
    const double kPad = 8.0;   // ListView horizontal padding start
    final target = (kPad + widget.currentIndex * kSlot)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  /// Builds the tile for page at [index]. The tile's Container carries
  /// Key('page-thumb-$index') so tests can find it regardless of whether
  /// the parent list is ListView or ReorderableListView.
  Widget _buildTile(BuildContext context, int index) {
    final isSelected = index == widget.currentIndex;
    final page = widget.pages[index];
    final scheme = Theme.of(context).colorScheme;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final placeholder = Container(
      width: 56,
      height: 80,
      color: scheme.surfaceContainerHighest,
      child:
          Icon(Icons.description_outlined, color: scheme.onSurfaceVariant),
    );
    return GestureDetector(
      onTap: () => widget.onTap(index),
      child: Container(
        key: Key('page-thumb-$index'),
        width: 56,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        foregroundDecoration: isSelected
            ? BoxDecoration(
                border: Border.all(color: scheme.primary, width: 2),
                borderRadius: BorderRadius.circular(4),
              )
            : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.file(
            File(page.displayPath),
            width: 56,
            height: 80,
            fit: BoxFit.cover,
            cacheWidth: (56 * dpr).round(),
            errorBuilder: (_, _, _) => placeholder,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      color: Colors.black,
      child: widget.onReorder != null
          ? ReorderableListView.builder(
              key: const Key('page-thumbnail-strip'),
              scrollController: _scrollController,
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              onReorder: widget.onReorder!,
              itemCount: widget.pages.length,
              itemBuilder: (context, index) => ReorderableDragStartListener(
                key: ValueKey('page-thumb-item-$index'),
                index: index,
                child: _buildTile(context, index),
              ),
            )
          : ListView.builder(
              key: const Key('page-thumbnail-strip'),
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              itemCount: widget.pages.length,
              itemBuilder: _buildTile,
            ),
    );
  }
}
