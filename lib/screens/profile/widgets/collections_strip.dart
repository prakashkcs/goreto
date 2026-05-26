import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:love_vibe_pro/models/collection.dart';

/// Horizontal strip of collection cards with add functionality
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Collections',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (canAddCollection)
                GestureDetector(
                  onTap: onAddCollection,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF007F).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFFF007F),
                        width: 1,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, color: Color(0xFFFF007F), size: 14),
                        SizedBox(width: 4),
                        Text(
                          'Add',
                          style: TextStyle(
                            color: Color(0xFFFF007F),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Collections horizontal list
        SizedBox(
          height: 120,
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
    return GestureDetector(
      onTap: () => onCollectionTap?.call(collection),
      onLongPress: () => onCollectionLongPress?.call(collection),
      child: Container(
        width: 100,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.black, // Dark background
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(
              0xFF00E5FF,
            ).withValues(alpha: 0.6), // Cyan border
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(
                0xFF00E5FF,
              ).withValues(alpha: 0.2), // Cyan glow
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Cover image
              (collection.coverThumb != null && collection.coverThumb!.isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: collection.coverThumb!,
                      fit: BoxFit.cover,
                      memCacheWidth: 200,
                      errorWidget: (_, __, ___) => _coverPlaceholder(),
                    )
                  : _coverPlaceholder(),

              // Gradient overlay
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.8),
                    ],
                  ),
                ),
              ),

              // Title & count
              Positioned(
                bottom: 8,
                left: 8,
                right: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      collection.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${collection.itemCount} items',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),

              // Delete button (own profile only)
              if (onCollectionLongPress != null)
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () => onCollectionLongPress!.call(collection),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.delete_outline_rounded,
                        color: Color(0xFFFF007F),
                        size: 14,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _coverPlaceholder() => Container(
        color: const Color(0xFF1A1A2E),
        child: const Icon(Icons.folder, color: Color(0xFF00E5FF), size: 30),
      );

  Widget _buildAddNewCard() {
    return GestureDetector(
      onTap: onAddCollection,
      child: Container(
        width: 100,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.black, // Dark background
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(
              0xFFFF007F,
            ).withValues(alpha: 0.6), // Pink border
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(
                0xFFFF007F,
              ).withValues(alpha: 0.2), // Pink glow
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFFF007F), width: 1.5),
              ),
              child: const Icon(Icons.add, color: Color(0xFFFF007F), size: 20),
            ),
            const SizedBox(height: 8),
            const Text(
              'New',
              style: TextStyle(
                color: Color(0xFFFF007F),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
