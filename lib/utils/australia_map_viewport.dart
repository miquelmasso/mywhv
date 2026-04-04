import 'dart:math' as math;

import 'package:flutter/widgets.dart';

class AustraliaMapViewport {
  AustraliaMapViewport._();

  static const double west = 111.0;
  static const double south = -44.0;
  static const double east = 155.0;
  static const double north = -9.0;
  static const double horizontalPaddingFraction = 0.16;
  static const double verticalPaddingFraction = 0.12;
  static const double longitudeSpan = east - west;
  static const double latitudeSpan = north - south;
  static const double viewportWest =
      west - longitudeSpan * horizontalPaddingFraction;
  static const double viewportSouth =
      south - latitudeSpan * verticalPaddingFraction;
  static const double viewportEast =
      east + longitudeSpan * horizontalPaddingFraction;
  static const double viewportNorth =
      north + latitudeSpan * verticalPaddingFraction;
  static const double viewportLongitudeSpan = viewportEast - viewportWest;
  static const double fallbackMinZoom = 4.6;

  static double clampLatitude(double latitude) {
    return latitude.clamp(south, north).toDouble();
  }

  static double clampLongitude(double longitude) {
    return longitude.clamp(west, east).toDouble();
  }

  static double clampViewportLatitude(double latitude) {
    return latitude.clamp(viewportSouth, viewportNorth).toDouble();
  }

  static double clampViewportLongitude(double longitude) {
    return longitude.clamp(viewportWest, viewportEast).toDouble();
  }

  static double minimumViewportZoom(
    Size viewportSize, {
    double fallbackZoom = fallbackMinZoom,
  }) {
    final width = viewportSize.width;
    final height = viewportSize.height;

    if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
      return fallbackZoom;
    }

    final mercatorSpan = (_mercatorY(viewportNorth) - _mercatorY(viewportSouth))
        .abs();

    final widthZoom =
        math.log(width * 360.0 / (256.0 * viewportLongitudeSpan)) / math.ln2;
    final heightZoom =
        math.log(height * 2.0 * math.pi / (256.0 * mercatorSpan)) / math.ln2;

    return math.max(widthZoom, heightZoom) + 0.05;
  }

  static double _mercatorY(double latitude) {
    final latitudeRadians = latitude * math.pi / 180.0;
    return math.log(math.tan(math.pi / 4.0 + latitudeRadians / 2.0));
  }
}
