import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ProductImage extends StatelessWidget {
  final String? imageSource;
  final double width;
  final double height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const ProductImage({
    super.key,
    required this.imageSource,
    this.width = 90,
    this.height = 90,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(12);
    final int targetCacheWidth = (width.isFinite && width > 0)
        ? (width * 2).round().clamp(120, 600)
        : 240;

    Widget imageWidget;

    if (imageSource == null || imageSource!.trim().isEmpty) {
      imageWidget = _buildPlaceholder();
    } else {
      final src = imageSource!.trim();
      if (src.startsWith('http://') || src.startsWith('https://')) {
        // Caché en disco y memoria con memCacheWidth y placeholder estático a 60 FPS
        imageWidget = CachedNetworkImage(
          imageUrl: src,
          width: width,
          height: height,
          memCacheWidth: targetCacheWidth,
          fit: fit,
          fadeInDuration: const Duration(milliseconds: 120),
          placeholder: (context, url) => _buildPlaceholder(),
          errorWidget: (context, url, error) => _buildPlaceholder(),
        );
      } else if (src.startsWith('data:image') ||
          (src.length > 100 && !src.contains('/') && !src.contains('\\'))) {
        try {
          final cleanBase64 = src.contains(',') ? src.split(',').last : src;
          final bytes = base64Decode(cleanBase64);
          imageWidget = Image.memory(
            bytes,
            width: width,
            height: height,
            cacheWidth: targetCacheWidth,
            fit: fit,
            errorBuilder: (ctx, err, stack) => _buildPlaceholder(),
          );
        } catch (_) {
          imageWidget = _buildPlaceholder();
        }
      } else {
        final file = File(src);
        if (file.existsSync()) {
          imageWidget = Image.file(
            file,
            width: width,
            height: height,
            cacheWidth: targetCacheWidth,
            fit: fit,
            errorBuilder: (ctx, err, stack) => _buildPlaceholder(),
          );
        } else {
          imageWidget = _buildPlaceholder();
        }
      }
    }

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: radius,
        child: imageWidget,
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: width,
      height: height,
      color: AppTheme.softPinkBg,
      child: Center(
        child: Icon(
          Icons.shopping_bag_outlined,
          color: AppTheme.darkPink,
          size: 28,
        ),
      ),
    );
  }
}
