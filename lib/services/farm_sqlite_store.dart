import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class FarmExistingKeys {
  const FarmExistingKeys({required this.placeIds, required this.altKeys});

  final Set<String> placeIds;
  final Set<String> altKeys;
}

class FarmSqliteStore {
  FarmSqliteStore._();
  static final FarmSqliteStore instance = FarmSqliteStore._();

  static const _dbName = 'farms_local.db';
  static const _dbVersion = 1;
  static const _tableName = 'farms';
  static const _seedAssetPath = 'export/farms.json';

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
            state TEXT,
            postcode TEXT,
            postcode_display TEXT,
            latitude REAL,
            longitude REAL,
            source_place_id TEXT,
            raw_json TEXT NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX idx_farms_state ON $_tableName(state)');
        await db.execute(
          'CREATE INDEX idx_farms_postcode_display ON $_tableName(postcode_display)',
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

    try {
      final rawJson = await rootBundle.loadString(_seedAssetPath);
      final decoded = jsonDecode(rawJson);
      if (decoded is! List) {
        throw const FormatException('farms.json must contain a JSON array');
      }

      final farms = decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);

      if (farms.isEmpty) {
        debugPrint('ℹ️ farms seed asset is empty');
        return;
      }

      await replaceAll(farms);
      debugPrint('🗄️ SQLITE seed imported: ${farms.length} farms');
    } on FlutterError catch (error) {
      debugPrint('ℹ️ No local farms seed asset found: $error');
    }
  }

  Future<void> replaceAll(List<Map<String, dynamic>> farms) async {
    final db = await _database;
    final normalizedRows = farms
        .map(_normalizeFarm)
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

  Future<void> upsertMany(List<Map<String, dynamic>> farms) async {
    if (farms.isEmpty) return;
    final db = await _database;
    final normalizedRows = farms
        .map(_normalizeFarm)
        .where((row) => row['id']!.toString().trim().isNotEmpty)
        .toList(growable: false);

    await db.transaction((txn) async {
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

  Future<int> deleteByState(String stateCode) async {
    final normalized = stateCode.trim().toUpperCase();
    if (normalized.isEmpty) return 0;
    final db = await _database;
    return db.delete(_tableName, where: 'state = ?', whereArgs: [normalized]);
  }

  Future<FarmExistingKeys> loadExistingKeysForPostcode(
    String postcodeDisplay,
  ) async {
    final normalizedPostcode = postcodeDisplay.trim().padLeft(4, '0');
    final farms = await getAll();
    final placeIds = <String>{};
    final altKeys = <String>{};

    for (final data in farms) {
      final candidatePostcode =
          (data['postcode_display'] ?? data['postcode'] ?? '')
              .toString()
              .padLeft(4, '0');
      if (candidatePostcode != normalizedPostcode) continue;

      final placeId = (data['source_place_id'] ?? '').toString();
      if (placeId.isNotEmpty) {
        placeIds.add(placeId);
      }

      final alt = _buildAltKey(
        name: (data['name'] ?? '').toString(),
        postcodeDisplay: normalizedPostcode,
        lat: data['latitude'] ?? data['lat'],
        lng: data['longitude'] ?? data['lng'],
      );
      if (alt != null) {
        altKeys.add(alt);
      }
    }

    return FarmExistingKeys(placeIds: placeIds, altKeys: altKeys);
  }

  Future<Database> get _database async {
    await init();
    return _db!;
  }

  Map<String, dynamic> _toDbRow(Map<String, dynamic> farm) {
    final normalized = _normalizeFarm(farm);
    return {
      'id': normalized['id'],
      'state': (normalized['state'] ?? '').toString().toUpperCase(),
      'postcode': normalized['postcode']?.toString(),
      'postcode_display': normalized['postcode_display']?.toString(),
      'latitude': _asDouble(normalized['latitude'] ?? normalized['lat']),
      'longitude': _asDouble(normalized['longitude'] ?? normalized['lng']),
      'source_place_id': normalized['source_place_id']?.toString(),
      'raw_json': jsonEncode(_sanitizeForJson(normalized)),
    };
  }

  Map<String, dynamic> _normalizeFarm(Map<String, dynamic> src) {
    final normalized = Map<String, dynamic>.from(src);
    final id =
        (normalized['id'] ??
                normalized['docId'] ??
                normalized['source_place_id'] ??
                '')
            .toString();
    normalized['id'] = id;
    normalized['docId'] = id;
    normalized['state'] = (normalized['state'] ?? '').toString().toUpperCase();
    normalized['postcode_display'] =
        (normalized['postcode_display'] ?? normalized['postcode'] ?? '')
            .toString()
            .padLeft(4, '0');
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

  String? _buildAltKey({
    required String name,
    required String postcodeDisplay,
    required dynamic lat,
    required dynamic lng,
  }) {
    final latD = _asDouble(lat);
    final lngD = _asDouble(lng);
    if (latD == null || lngD == null) return null;
    final normalizedName = name.trim().toLowerCase();
    return '$normalizedName|$postcodeDisplay|${latD.toStringAsFixed(5)}|${lngD.toStringAsFixed(5)}';
  }
}
