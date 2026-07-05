import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'harvest_places_sqlite_store.dart';

class HarvestPlace {
  final String id;
  final String name;
  final String postcode;
  final String state;
  final double latitude;
  final double longitude;
  final String? description;
  final List<int> activeMonths;
  final List<String> crops;
  final Map<int, List<String>> cropsByMonth;

  HarvestPlace({
    required this.id,
    required this.name,
    required this.postcode,
    required this.state,
    required this.latitude,
    required this.longitude,
    this.description,
    this.activeMonths = const [],
    this.crops = const [],
    this.cropsByMonth = const {},
  });
}

class HarvestPlacesService {
  static const _completeSeasonalAssetPath =
      'export/harvest_places_2025_complete_with_coords.json';

  static Future<List<HarvestPlace>> loadHarvestPlaces({
    required bool fromServer,
  }) async {
    if (fromServer) {
      debugPrint(
        'ℹ️ loadHarvestPlaces(fromServer: true) ignored: local SQLite mode',
      );
    }
    final store = HarvestPlacesSqliteStore.instance;
    await store.init();
    await store.importSeedAssetIfEmpty();
    final places = await store.getAll();
    debugPrint('🗄️ SQLITE harvest loaded: ${places.length}');
    return places
        .map((data) {
          final lat = (data['latitude'] ?? data['lat'])?.toDouble();
          final lng = (data['longitude'] ?? data['lng'])?.toDouble();
          if (lat == null || lng == null) return null;
          return HarvestPlace(
            id: (data['id'] ?? data['docId'] ?? '').toString(),
            name: (data['name'] ?? '').toString(),
            postcode: (data['postcode'] ?? '').toString(),
            state: (data['state'] ?? '').toString(),
            latitude: lat,
            longitude: lng,
            description: data['description']?.toString(),
            activeMonths: _activeMonths(data['months']),
            crops: _allCrops(data['months']),
            cropsByMonth: _cropsByMonth(data['months']),
          );
        })
        .whereType<HarvestPlace>()
        .toList();
  }

  static Future<List<HarvestPlace>> loadCompleteHarvestPlaces() async {
    final entries = await _loadAssetEntries(_completeSeasonalAssetPath);
    return _toHarvestPlaces(entries);
  }

  static Future<List<Map<String, dynamic>>> _loadAssetEntries(
    String assetPath,
  ) async {
    final raw = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(raw);
    final rawEntries = decoded is List
        ? decoded
        : decoded is Map && decoded['places'] is List
        ? decoded['places'] as List
        : const <dynamic>[];
    return rawEntries
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: false);
  }

  static List<HarvestPlace> _toHarvestPlaces(
    List<Map<String, dynamic>> entries,
  ) {
    return entries
        .map((data) {
          final lat = (data['latitude'] ?? data['lat']) as num?;
          final lng = (data['longitude'] ?? data['lng']) as num?;
          final id = (data['id'] ?? data['docId'] ?? '').toString();
          if (id.isEmpty || lat == null || lng == null) return null;
          if (lat == 0 || lng == 0) return null;
          return HarvestPlace(
            id: id,
            name: (data['name'] ?? data['place'] ?? '').toString(),
            postcode: (data['postcode'] ?? '').toString(),
            state: (data['state'] ?? '').toString(),
            latitude: lat.toDouble(),
            longitude: lng.toDouble(),
            description: data['description']?.toString(),
            activeMonths: _activeMonths(data['months']),
            crops: _allCrops(data['months']),
            cropsByMonth: _cropsByMonth(data['months']),
          );
        })
        .whereType<HarvestPlace>()
        .toList(growable: false);
  }

  static List<int> _activeMonths(dynamic rawMonths) {
    if (rawMonths is! List) return const [];
    return rawMonths
        .whereType<Map>()
        .where((month) => _monthCrops(month).isNotEmpty)
        .map((month) => (month['month'] as num?)?.toInt())
        .whereType<int>()
        .where((month) => month >= 1 && month <= 12)
        .toList(growable: false);
  }

  static List<String> _allCrops(dynamic rawMonths) {
    if (rawMonths is! List) return const [];
    final crops = <String>{};
    for (final month in rawMonths.whereType<Map>()) {
      crops.addAll(_monthCrops(month));
    }
    final sorted = crops.where((crop) => crop.isNotEmpty).toList()..sort();
    return sorted;
  }

  static Map<int, List<String>> _cropsByMonth(dynamic rawMonths) {
    if (rawMonths is! List) return const {};
    final result = <int, List<String>>{};
    for (final month in rawMonths.whereType<Map>()) {
      final monthNumber = (month['month'] as num?)?.toInt();
      if (monthNumber == null || monthNumber < 1 || monthNumber > 12) continue;
      final crops = _monthCrops(month);
      if (crops.isNotEmpty) result[monthNumber] = crops;
    }
    return result;
  }

  static List<String> _monthCrops(Map month) {
    final crops = <String>{};
    for (final category in const ['fruits', 'vegetables', 'other']) {
      final entries = month[category] as List? ?? const [];
      for (final crop in entries.whereType<Map>()) {
        final name = (crop['name'] ?? '').toString().trim();
        if (name.isNotEmpty) crops.add(name);
      }
    }
    return crops.toList(growable: false);
  }
}
