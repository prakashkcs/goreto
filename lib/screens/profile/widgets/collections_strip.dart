import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:love_vibe_pro/models/collection.dart';

/// Horizontal strip of collection "albums" on the profile, in the app's neon
/// style: stacked-pages cards with a pink→purple→cyan frame, title + item
/// count on a dark fade, and a create card / empty-state CTA for the owner.
class CollectionsStrip extends StatelessWidget {
  final List<Collection> collections;
  final VoidCallback? onAddCollection;
  final bool canAddCollection;
  final void Function(Collection)? onCollectionTap;
  final void Function(Collection)? onCollectionLongPress;

  const CollectionsStrip({
    super.key,
    required this.collections,
    this.onAddCollection,
    this.canAddCollection = true,
    this.onCollectionTap,
    this.onCollectionLongPress,
  });

  static const _pink = Color(0xFFFF007F);
  static const _purple = Color(0xFFD946EF);
  static const _cyan = Color(0xFF06B6D4);
  static const _cardW = 124.0;
  static const _cardH = 164.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header: gradient title + count, "New" pill for the owner.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              ShaderMask(
                shaderCallback: (b) =>
                    const LinearGradient(colors: [_purple, _cyan]).createShader(b),
                child: const Text(
                  'Collections',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900),
                ),
              ),
              if (collections.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${collections.length}',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
              ],
              const Spacer(),
              if (canAddCollection && collections.isNotEmpty)
                GestureDetector(
                  onTap: onAddCollection,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [_pink, _purple]),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                            color: _pink.withValues(alpha: 0.35), blurRadius: 10),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, color: Colors.white, size: 15),
                        SizedBox(width: 3),
                        Text('New',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (collections.isEmpty && canAddCollection)
          _buildEmptyCta()
        else
          SizedBox(
            height: _cardH + 14,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: collections.length + (canAddCollection ? 1 : 0),
              itemBuilder: (context, index) {
                if (canAddCollection && index == collections.length) {
                  return _buildAddNewCard();
                }
                return _buildCollectionCard(collections[index]);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildCollectionCard(Collection collection) {
    final hasCover =
        collection.coverThumb != null && collection.coverThumb!.isNotEmpty;
    return GestureDetector(
      onTap: () => onCollectionTap?.call(collection),
      onLongPress: () => onCollectionLongPress?.call(collection),
      child: Container(
        width: _cardW,
        margin: const EdgeInsets.fromLTRB(4, 8, 8, 6),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Stacked "pages" behind the cover — reads as an album.
            Positioned(
              left: 10,
              right: 10,
              top: -8,
              height: 30,
              child: Container(
                decoration: BoxDecoration(
                  color: _cyan.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            Positioned(
              left: 5,
              right: 5,
              top: -4,
              height: 30,
              child: Container(
                decoration: BoxDecoration(
                  color: _purple.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            // Gradient frame + cover.
            Positioned.fill(
              child: Container(
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_pink, _purple, _cyan],
                  ),
                  boxShadow: [
                    BoxShadow(
                        color: _purple.withValues(alpha: 0.25),
                        blurRadius: 14,
                        spreadRadius: -2),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16.5),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      hasCover
                          ? CachedNetworkImage(
                              imageUrl: collection.coverThumb!,
                              fit: BoxFit.cover,
                              memCacheWidth: 300,
                              errorWidget: (_, __, ___) => _coverPlaceholder(),
                            )
                          : _coverPlaceholder(),
                      // Dark fade for the label.
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: [0.45, 1.0],
                            colors: [Colors.transparent, Color(0xE6000000)],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 9,
                        right: 9,
                        bottom: 9,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              collection.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.18)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.photo_library_rounded,
                                      color: _cyan, size: 10),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${collection.itemCount} '
                                    '${collection.itemCount == 1 ? 'item' : 'items'}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Owner: small menu instead of a bare delete icon.
                      if (onCollectionLongPress != null)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: GestureDetector(
                            onTap: () => onCollectionLongPress!.call(collection),
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.2)),
                              ),
                              child: const Icon(Icons.more_horiz_rounded,
                                  color: Colors.white, size: 16),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coverPlaceholder() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2D1B4E), Color(0xFF0D0818)],
          ),
        ),
        child: const Center(
          child: Icon(Icons.collections_bookmark_rounded,
              color: _purple, size: 34),
        ),
      );

  Widget _buildAddNewCard() {
    return GestureDetector(
      onTap: onAddCollection,
      child: Container(
        width: _cardW,
        margin: const EdgeInsets.fromLTRB(4, 8, 8, 6),
        decoration: BoxDecoration(
          color: const Color(0xFF12101C),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _pink.withValues(alpha: 0.55), width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [_pink, _purple]),
                boxShadow: [
                  BoxShadow(color: _pink.withValues(alpha: 0.4), blurRadius: 12),
                ],
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 10),
            const Text('New collection',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  /// Owner with no collections yet: one wide, inviting card instead of an
  /// empty row with a lone "New" tile.
  Widget _buildEmptyCta() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: onAddCollection,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(colors: [
              _pink.withValues(alpha: 0.14),
              _purple.withValues(alpha: 0.10),
              _cyan.withValues(alpha: 0.10),
            ]),
            border: Border.all(color: _purple.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(colors: [_pink, _purple]),
                ),
                child: const Icon(Icons.collections_bookmark_rounded,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Create your first collection',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800)),
                    SizedBox(height: 3),
                    Text('Group your favourite posts into albums',
                        style: TextStyle(color: Colors.white60, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}
