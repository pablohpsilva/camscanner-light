import 'dart:io';

import 'package:flutter/material.dart';

import '../../../theme/ream_colors.dart';
import '../page_image.dart';

/// Thumbnail tile geometry — the SINGLE source for the tile size + its scroll
/// advance (P13 kSlot-magic-number). Auto-scroll targeting derives from these,
/// so a tile-size tweak can't silently drift the scroll off by a slot.
const double kTileWidth = 56;
const double kTileHeight = 80;
const double kTileMargin = 4; // symmetric horizontal margin per tile
const double kSlot = kTileWidth + 2 * kTileMargin; // one tile's scroll advance
const double kThumbListPad = 8; // ListView horizontal padding start

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
    final target = (kThumbListPad + widget.currentIndex * kSlot).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
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
    final ream = context.ream;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final placeholder = Container(
      width: kTileWidth,
      height: kTileHeight,
      color: ream.surface,
      child: Icon(Icons.description_outlined, color: ream.muted),
    );
    return GestureDetector(
      onTap: () => widget.onTap(index),
      child: Container(
        key: Key('page-thumb-$index'),
        width: kTileWidth,
        margin: const EdgeInsets.symmetric(horizontal: kTileMargin),
        foregroundDecoration: isSelected
            ? BoxDecoration(
                border: Border.all(color: ream.green, width: 2),
                borderRadius: BorderRadius.circular(4),
              )
            : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.file(
            File(page.displayPath),
            width: kTileWidth,
            height: kTileHeight,
            fit: BoxFit.cover,
            cacheWidth: (kTileWidth * dpr).round(),
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
              onReorderItem: widget.onReorder!,
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
