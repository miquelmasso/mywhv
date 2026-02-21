import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;

/// Simple tile provider that first checks a local cache directory and
/// falls back to network if the tile is missing.
class OfflineTileProvider extends TileProvider {
  OfflineTileProvider(Directory? cacheDir) : _cacheDir = cacheDir;

  Directory? _cacheDir;

  @override
  ImageProvider getImage(TileCoordinates coords, TileLayer options) {
    final dir = _ensureCacheDir();
    final filePath = p.join(dir.path, '${coords.z}', '${coords.x}', '${coords.y}.png');
    final file = File(filePath);
    if (file.existsSync()) {
      return FileImage(file);
    }

    _saveTileIfOnline(options.urlTemplate ?? '', coords, file);

    final url = _buildUrl(options.urlTemplate ?? '', coords);
    return NetworkImage(url);
  }

  String _buildUrl(String template, TileCoordinates coords) {
    return template
        .replaceAll('{x}', '${coords.x}')
        .replaceAll('{y}', '${coords.y}')
        .replaceAll('{z}', '${coords.z}');
  }

  Directory _ensureCacheDir() {
    if (_cacheDir != null) return _cacheDir!;
    final dir = Directory(p.join(Directory.systemTemp.path, 'osm_tiles_runtime'));
    dir.createSync(recursive: true);
    _cacheDir = dir;
    return dir;
  }

  Future<void> _saveTileIfOnline(String template, TileCoordinates coords, File target) async {
    final url = _buildUrl(template, coords);
    try {
      final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        await target.parent.create(recursive: true);
        await target.writeAsBytes(resp.bodyBytes, flush: true);
      }
    } catch (_) {
      // ignore
    }
  }
}
