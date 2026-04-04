import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart';

class LocalVectorStyleService {
  LocalVectorStyleService._();

  static final LocalVectorStyleService instance = LocalVectorStyleService._();

  Future<Style> loadFromAsset({
    required String assetPath,
    required Map<String, String> replacements,
  }) async {
    var styleText = await rootBundle.loadString(assetPath);
    replacements.forEach((key, value) {
      styleText = styleText.replaceAll(key, value);
    });

    final decoded = jsonDecode(styleText);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'The vector style asset must contain a JSON object.',
      );
    }

    final providerByName = await _readProviderByName(decoded['sources']);
    final spriteUri = decoded['sprite'] as String?;
    final sprites = await _loadSpriteStyle(spriteUri);

    final center = decoded['center'];
    LatLng? centerPoint;
    if (center is List && center.length == 2) {
      centerPoint = LatLng(
        (center[1] as num).toDouble(),
        (center[0] as num).toDouble(),
      );
    }
    final zoom = (decoded['zoom'] as num?)?.toDouble();

    return Style(
      name: decoded['name'] as String?,
      theme: ThemeReader().read(decoded),
      providers: TileProviders(providerByName),
      sprites: sprites,
      center: centerPoint,
      zoom: zoom,
    );
  }

  Future<Map<String, VectorTileProvider>> _readProviderByName(
    dynamic rawSources,
  ) async {
    if (rawSources is! Map) {
      throw const FormatException(
        'The vector style must contain a "sources" object.',
      );
    }

    final providers = <String, VectorTileProvider>{};
    for (final entry in rawSources.entries) {
      final sourceName = entry.key.toString();
      final source = entry.value;
      if (source is! Map) continue;
      final sourceType = source['type']?.toString();
      if (sourceType != TileProviderType.vector.name) continue;

      final sourceUrl = source['url']?.toString().trim();
      if (sourceUrl != null && sourceUrl.startsWith('pmtiles://')) {
        final archiveUrl = sourceUrl.substring('pmtiles://'.length).trim();
        if (archiveUrl.isEmpty) {
          throw FormatException(
            'Source "$sourceName" contains an empty PMTiles URL.',
          );
        }
        providers[sourceName] = await PmTilesVectorTileProvider.fromSource(
          archiveUrl,
        );
        continue;
      }

      final resolvedSource = await _resolveSource(source);
      final tiles = resolvedSource['tiles'];
      if (tiles is! List || tiles.isEmpty) {
        throw FormatException(
          'Source "$sourceName" does not contain any tile URLs.',
        );
      }

      providers[sourceName] = NetworkVectorTileProvider(
        urlTemplate: tiles.first.toString(),
        maximumZoom: (resolvedSource['maxzoom'] as num?)?.toInt() ?? 14,
        minimumZoom: (resolvedSource['minzoom'] as num?)?.toInt() ?? 0,
      );
    }

    if (providers.isEmpty) {
      throw const FormatException(
        'No vector tile sources were found in the style asset.',
      );
    }
    return providers;
  }

  Future<Map<String, dynamic>> _resolveSource(Map source) async {
    final sourceUrl = source['url']?.toString().trim();
    if (sourceUrl == null || sourceUrl.isEmpty) {
      return Map<String, dynamic>.from(source);
    }

    final response = await http.get(Uri.parse(sourceUrl));
    if (response.statusCode != 200) {
      throw StateError(
        'Could not load the vector source definition (${response.statusCode}).',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'The vector source definition must be a JSON object.',
      );
    }
    return decoded;
  }

  Future<SpriteStyle?> _loadSpriteStyle(String? spriteUri) async {
    if (spriteUri == null || spriteUri.trim().isEmpty) return null;

    final jsonResponse = await http.get(Uri.parse('$spriteUri.json'));
    if (jsonResponse.statusCode != 200) {
      return null;
    }

    final decoded = jsonDecode(jsonResponse.body);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    return SpriteStyle(
      atlasProvider: () => _loadSpriteAtlas('$spriteUri.png'),
      index: SpriteIndexReader().read(decoded),
    );
  }

  Future<Uint8List> _loadSpriteAtlas(String imageUrl) async {
    final response = await http.get(Uri.parse(imageUrl));
    if (response.statusCode != 200) {
      throw StateError('Could not load the vector sprite atlas.');
    }
    return response.bodyBytes;
  }
}
