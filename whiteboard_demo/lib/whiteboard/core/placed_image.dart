import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// A raster image placed at a specific position in world coordinates.
///
/// Used for displaying reference images under sketch animations.
class PlacedImage {
  final ui.Image image;
  Offset worldCenter;
  Size worldSize;

  PlacedImage({
    required this.image,
    required this.worldCenter,
    required this.worldSize,
  });
}
