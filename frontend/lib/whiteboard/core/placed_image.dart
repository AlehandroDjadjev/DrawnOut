import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// A raster image placed on the whiteboard with world-space coordinates.
///
/// Used for showing reference images as an underlay while drawing
/// vector strokes on top.
class PlacedImage {
  /// The decoded Flutter image
  final ui.Image image;

  /// Center position in world coordinates
  Offset worldCenter;

  /// Size in world coordinates
  Size worldSize;

  /// Optional identifier for this image
  final String? id;

  /// Opacity for rendering (0.0 - 1.0)
  final double opacity;

  PlacedImage({
    required this.image,
    required this.worldCenter,
    required this.worldSize,
    this.id,
    this.opacity = 1.0,
  });

  /// Create from image with automatic sizing based on scale factor
  factory PlacedImage.fromImage({
    required ui.Image image,
    required Offset center,
    double scale = 1.0,
    String? id,
    double opacity = 1.0,
  }) {
    return PlacedImage(
      image: image,
      worldCenter: center,
      worldSize: Size(
        image.width.toDouble() * scale,
        image.height.toDouble() * scale,
      ),
      id: id,
      opacity: opacity,
    );
  }

  /// Original image width in pixels
  int get imageWidth => image.width;

  /// Original image height in pixels
  int get imageHeight => image.height;

  /// The bounding rectangle in world coordinates
  Rect get worldRect {
    return Rect.fromCenter(
      center: worldCenter,
      width: worldSize.width,
      height: worldSize.height,
    );
  }

  /// Top-left corner in world coordinates
  Offset get topLeft => worldCenter - Offset(worldSize.width / 2, worldSize.height / 2);

  /// Source rectangle for the full image
  Rect get sourceRect => Rect.fromLTWH(
    0,
    0,
    image.width.toDouble(),
    image.height.toDouble(),
  );

  /// Update the position
  PlacedImage moveTo(Offset newCenter) {
    return PlacedImage(
      image: image,
      worldCenter: newCenter,
      worldSize: worldSize,
      id: id,
      opacity: opacity,
    );
  }

  /// Update the size
  PlacedImage resize(Size newSize) {
    return PlacedImage(
      image: image,
      worldCenter: worldCenter,
      worldSize: newSize,
      id: id,
      opacity: opacity,
    );
  }

  /// Scale the image by a factor
  PlacedImage scale(double factor) {
    return PlacedImage(
      image: image,
      worldCenter: worldCenter,
      worldSize: Size(worldSize.width * factor, worldSize.height * factor),
      id: id,
      opacity: opacity,
    );
  }

  /// Create a copy with different opacity
  PlacedImage withOpacity(double newOpacity) {
    return PlacedImage(
      image: image,
      worldCenter: worldCenter,
      worldSize: worldSize,
      id: id,
      opacity: newOpacity.clamp(0.0, 1.0),
    );
  }

  @override
  String toString() => 'PlacedImage(${id ?? 'unnamed'}, ${worldSize.width.toInt()}x${worldSize.height.toInt()} at $worldCenter)';
}
