import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class HarvestPlacesSqliteStore {
  HarvestPlacesSqliteStore._();
  static final HarvestPlacesSqliteStore instance = HarvestPlacesSqliteStore._();

  static const _dbName = 'harvest_places_local.db';
  static const _dbVersion = 1;
  static const _tableName = 'harvest_places';
  static const _seedAssetPath = 'export/harvest_places.json';
  static const _legacyAssetPath = 'assets/data/harvest_places_2025.json';

  Database? _db;

  Future<void> init() async {
    if (_db != null) return;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, _dbName),
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName(
            id TEXT PRIMARY KEY,
            name TEXT,
            postcode TEXT,
            state TEXT,
            latitude REAL,
            longitude REAL,
            description TEXT,
            raw_json TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_harvest_state ON $_tableName(state)',
        );
      },
    );
  }

  Future<int> count() async {
    final db = await _database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM $_tableName',
    );
    final rawValue = result.first['count'];
    if (rawValue is int) return rawValue;
    if (rawValue is num) return rawValue.toInt();
    return int.tryParse(rawValue?.toString() ?? '') ?? 0;
  }

  Future<bool> get hasData async => (await count()) > 0;

  Future<void> importSeedAssetIfEmpty() async {
    if (await hasData) return;

    final entries = await _loadSeedEntries();
    if (entries.isEmpty) {
      debugPrint('ℹ️ harvest seed asset is empty');
      return;
    }

    await replaceAll(entries);
    debugPrint('🗄️ SQLITE seed imported: ${entries.length} harvest places');
  }

  Future<void> replaceAll(List<Map<String, dynamic>> entries) async {
    final db = await _database;
    final normalizedRows = entries
        .map(_normalizePlace)
        .where((row) => row['id']!.toString().trim().isNotEmpty)
        .toList(growable: false);

    await db.transaction((txn) async {
      await txn.delete(_tableName);
      final batch = txn.batch();
      for (final row in normalizedRows) {
        batch.insert(
          _tableName,
          _toDbRow(row),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Map<String, dynamic>>> getAll() async {
    final db = await _database;
    final rows = await db.query(_tableName);
    return rows
        .map((row) {
          final rawJson = row['raw_json']?.toString();
          if (rawJson == null || rawJson.isEmpty) {
            return <String, dynamic>{};
          }
          final decoded = jsonDecode(rawJson);
          if (decoded is! Map) {
            return <String, dynamic>{};
          }
          return Map<String, dynamic>.from(decoded);
        })
        .where((row) => row.isNotEmpty)
        .toList(growable: false);
  }

  Future<Database> get _database async {
    await init();
    return _db!;
  }

  Future<List<Map<String, dynamic>>> _loadSeedEntries() async {
    try {
      final rawJson = await rootBundle.loadString(_seedAssetPath);
      final decoded = jsonDecode(rawJson);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
      }
    } on FlutterError catch (_) {
      // Fallback below.
    }

    final legacyRaw = await rootBundle.loadString(_legacyAssetPath);
    final legacyDecoded = jsonDecode(legacyRaw);
    if (legacyDecoded is! Map) return const <Map<String, dynamic>>[];
    final states = (legacyDecoded['states'] as List?) ?? const [];
    final year = legacyDecoded['year'];
    final sourceUrl = legacyDecoded['source_url']?.toString() ?? '';
    final entries = <Map<String, dynamic>>[];

    for (final stateEntry in states) {
      if (stateEntry is! Map) continue;
      final stateCode = (stateEntry['state'] ?? '').toString().toUpperCase();
      final places = (stateEntry['places'] as List?) ?? const [];
      for (final place in places) {
        if (place is! Map) continue;
        final name = (place['name'] ?? place['place'] ?? '').toString().trim();
        final postcode = (place['postcode'] ?? '').toString().trim();
        if (name.isEmpty || postcode.isEmpty) continue;
        final id = (place['id'] ?? _buildId(stateCode, postcode, name))
            .toString();
        entries.add({
          'id': id,
          'name': name,
          'postcode': postcode,
          'state': stateCode,
          'year': year,
          'source_url': sourceUrl,
          'map_url': (place['map_url'] ?? '').toString(),
          'latitude': (place['latitude'] as num?)?.toDouble() ?? 0.0,
          'longitude': (place['longitude'] as num?)?.toDouble() ?? 0.0,
          'description': place['description']?.toString(),
          'coords_placeholder':
              ((place['latitude'] ?? 0) == 0 || (place['longitude'] ?? 0) == 0),
        });
      }
    }

    return entries;
  }

  Map<String, dynamic> _toDbRow(Map<String, dynamic> place) {
    final normalized = _normalizePlace(place);
    return {
      'id': normalized['id'],
      'name': normalized['name'],
      'postcode': normalized['postcode']?.toString(),
      'state': normalized['state'],
      'latitude': _asDouble(normalized['latitude'] ?? normalized['lat']),
      'longitude': _asDouble(normalized['longitude'] ?? normalized['lng']),
      'description': normalized['description']?.toString(),
      'raw_json': jsonEncode(_sanitizeForJson(normalized)),
    };
  }

  Map<String, dynamic> _normalizePlace(Map<String, dynamic> src) {
    final normalized = Map<String, dynamic>.from(src);
    final id =
        (normalized['id'] ?? normalized['docId'] ?? normalized['name'] ?? '')
            .toString();
    normalized['id'] = id;
    normalized['docId'] = id;
    normalized['state'] = (normalized['state'] ?? '').toString().toUpperCase();
    return normalized;
  }

  Map<String, dynamic> _sanitizeForJson(Map<String, dynamic> src) {
    final out = <String, dynamic>{};
    src.forEach((key, value) {
      out[key] = _convertValue(value);
    });
    return out;
  }

  dynamic _convertValue(dynamic value) {
    if (value is DateTime) return value.toIso8601String();
    if (value is Uint8List) return base64Encode(value);
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _convertValue(v)));
    }
    if (value is Iterable) {
      return value.map(_convertValue).toList();
    }
    return value;
  }

  double? _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  String _buildId(String state, String postcode, String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return '${state}_${postcode}_$slug';
  }
}
