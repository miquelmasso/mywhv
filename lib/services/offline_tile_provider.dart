import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;

/// Simple tile provider that first checks a local cache directory and
/// falls back to network if the tile is missing.
class OfflineTileProvider extends TileProvider {
  OfflineTileProvider(Directory? cacheDir, {BaseCacheManager? cacheManager})
      : _cacheDir = cacheDir,
        _cacheManager = cacheManager;

  Directory? _cacheDir;
  final BaseCacheManager? _cacheManager;
  final http.Client _httpClient = http.Client();

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final dir = _ensureCacheDir();
    final filePath =
        '${dir.path}${Platform.pathSeparator}${coordinates.z}${Platform.pathSeparator}${coordinates.x}${Platform.pathSeparator}${coordinates.y}.png';
    final file = File(filePath);
    if (file.existsSync()) {
      return FileImage(file);
    }

    final url = _buildUrl(options.urlTemplate ?? '', coordinates);
    return _OfflineCacheImageProvider(
      url: url,
      fallbackFile: file,
      cacheManager: _cacheManager,
      httpClient: _httpClient,
    );
  }

  String _buildUrl(String template, TileCoordinates coords) {
    return template
        .replaceAll('{x}', '${coords.x}')
        .replaceAll('{y}', '${coords.y}')
        .replaceAll('{z}', '${coords.z}');
  }

  Directory _ensureCacheDir() {
    if (_cacheDir != null) return _cacheDir!;
    final dir =
        Directory('${Directory.systemTemp.path}${Platform.pathSeparator}osm_tiles_runtime');
    dir.createSync(recursive: true);
    _cacheDir = dir;
    return dir;
  }

}

class _OfflineCacheImageProvider extends ImageProvider<_OfflineCacheImageProvider> {
  const _OfflineCacheImageProvider({
    required this.url,
    required this.fallbackFile,
    required this.httpClient,
    this.cacheManager,
  });

  final String url;
  final File fallbackFile;
  final BaseCacheManager? cacheManager;
  final http.Client httpClient;

  @override
  Future<_OfflineCacheImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_OfflineCacheImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _OfflineCacheImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(decode),
      scale: 1.0,
    );
  }

  Future<ui.Codec> _loadAsync(ImageDecoderCallback decode) async {
    try {
      if (fallbackFile.existsSync()) {
        final bytes = await fallbackFile.readAsBytes();
        if (bytes.isNotEmpty) {
          return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
        }
      }

      if (cacheManager != null) {
        final file = await cacheManager!.getSingleFile(url);
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
        }
      }

      final response = await httpClient
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        await fallbackFile.parent.create(recursive: true);
        unawaited(fallbackFile.writeAsBytes(response.bodyBytes, flush: false));
        if (cacheManager != null) {
          unawaited(cacheManager!.putFile(url, response.bodyBytes, fileExtension: 'png'));
        }
        return decode(await ui.ImmutableBuffer.fromUint8List(response.bodyBytes));
      }
    } catch (_) {
      // ignore and return a transparent placeholder
    }

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 1, 1),
      ui.Paint()..color = Colors.transparent,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(1, 1);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return decode(
      await ui.ImmutableBuffer.fromUint8List(byteData!.buffer.asUint8List()),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _OfflineCacheImageProvider &&
          other.url == url &&
          other.fallbackFile.path == fallbackFile.path;

  @override
  int get hashCode => Object.hash(url, fallbackFile.path);
}
