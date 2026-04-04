import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class RestaurantSqliteStore {
  RestaurantSqliteStore._();
  static final RestaurantSqliteStore instance = RestaurantSqliteStore._();

  static const _dbName = 'restaurants_local.db';
  static const _dbVersion = 1;
  static const _tableName = 'restaurants';
  static const _seedAssetPath = 'export/restaurants.json';

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
            address TEXT,
            postcode TEXT,
            postcode_display TEXT,
            state TEXT,
            latitude REAL,
            longitude REAL,
            phone TEXT,
            email TEXT,
            facebook_url TEXT,
            instagram_url TEXT,
            careers_page TEXT,
            website TEXT,
            source_place_id TEXT,
            blocked INTEGER NOT NULL DEFAULT 0,
            worked_here_count INTEGER NOT NULL DEFAULT 0,
            timestamp TEXT,
            raw_json TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_restaurants_name ON $_tableName(name)',
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

    final rawJson = await rootBundle.loadString(_seedAssetPath);
    final decoded = jsonDecode(rawJson);
    if (decoded is! List) {
      throw const FormatException('restaurants.json must contain a JSON array');
    }

    final restaurants = decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);

    if (restaurants.isEmpty) {
      debugPrint('⚠️ restaurants seed asset is empty');
      return;
    }

    await replaceAll(restaurants);
    debugPrint('🗄️ SQLITE seed imported: ${restaurants.length} restaurants');
  }

  Future<void> replaceAll(List<Map<String, dynamic>> restaurants) async {
    final db = await _database;
    final normalizedRows = restaurants
        .map(_normalizeRestaurant)
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

  Future<List<Map<String, dynamic>>> getAllForMap() async {
    final db = await _database;
    final rows = await db.query(
      _tableName,
      columns: [
        'id',
        'name',
        'address',
        'postcode',
        'postcode_display',
        'state',
        'latitude',
        'longitude',
        'phone',
        'email',
        'facebook_url',
        'instagram_url',
        'careers_page',
        'website',
        'blocked',
        'worked_here_count',
        'timestamp',
      ],
    );
    return rows
        .map((row) {
          final id = row['id']?.toString() ?? '';
          if (id.trim().isEmpty) {
            return <String, dynamic>{};
          }
          final latitude = _asDouble(row['latitude']);
          final longitude = _asDouble(row['longitude']);
          return <String, dynamic>{
            'id': id,
            'docId': id,
            'name': row['name']?.toString() ?? '',
            'address': row['address']?.toString() ?? '',
            'postcode': row['postcode']?.toString() ?? '',
            'postcode_display': row['postcode_display']?.toString() ?? '',
            'state': row['state']?.toString() ?? '',
            'latitude': latitude,
            'longitude': longitude,
            'lat': latitude,
            'lng': longitude,
            'phone': row['phone']?.toString() ?? '',
            'email': row['email']?.toString() ?? '',
            'facebook_url': row['facebook_url']?.toString() ?? '',
            'instagram_url': row['instagram_url']?.toString() ?? '',
            'careers_page': row['careers_page']?.toString() ?? '',
            'website': row['website']?.toString() ?? '',
            'blocked': _asBool(row['blocked']),
            'worked_here_count': _asInt(row['worked_here_count']),
            'timestamp': row['timestamp']?.toString() ?? '',
          };
        })
        .where((row) => row.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> searchByName(
    String query, {
    int limit = 25,
  }) async {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return const <Map<String, dynamic>>[];
    final all = await getAll();

    final startsWith = <Map<String, dynamic>>[];
    final contains = <Map<String, dynamic>>[];

    for (final restaurant in all) {
      final name = (restaurant['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final lowerName = name.toLowerCase();
      if (lowerName.startsWith(normalizedQuery)) {
        startsWith.add(restaurant);
        continue;
      }
      if (lowerName.contains(normalizedQuery)) {
        contains.add(restaurant);
      }
    }

    final merged = <Map<String, dynamic>>[...startsWith, ...contains];
    if (merged.length <= limit) return merged;
    return merged.take(limit).toList(growable: false);
  }

  Future<void> updateRestaurantFields(
    String docId,
    Map<String, dynamic> updates,
  ) async {
    if (docId.trim().isEmpty || updates.isEmpty) return;
    final db = await _database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        _tableName,
        columns: ['raw_json'],
        where: 'id = ?',
        whereArgs: [docId],
        limit: 1,
      );
      if (rows.isEmpty) return;

      final rawJson = rows.first['raw_json']?.toString();
      Map<String, dynamic> payload = <String, dynamic>{
        'id': docId,
        'docId': docId,
      };
      if (rawJson != null && rawJson.isNotEmpty) {
        final decoded = jsonDecode(rawJson);
        if (decoded is Map) {
          payload = Map<String, dynamic>.from(decoded);
        }
      }
      payload.addAll(updates);

      await txn.update(
        _tableName,
        _toDbRow(payload),
        where: 'id = ?',
        whereArgs: [docId],
      );
    });
  }

  Future<void> updateWorkedHereCount(String docId, int delta) async {
    if (docId.trim().isEmpty || delta == 0) return;
    final db = await _database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        _tableName,
        columns: ['worked_here_count', 'raw_json'],
        where: 'id = ?',
        whereArgs: [docId],
        limit: 1,
      );
      if (rows.isEmpty) return;

      final existing = rows.first;
      final current = _asInt(existing['worked_here_count']);
      final next = (current + delta).clamp(0, 1 << 30);
      final rawJson = existing['raw_json']?.toString();
      Map<String, dynamic>? payload;
      if (rawJson != null && rawJson.isNotEmpty) {
        final decoded = jsonDecode(rawJson);
        if (decoded is Map) {
          payload = Map<String, dynamic>.from(decoded);
          payload['worked_here_count'] = next;
        }
      }

      await txn.update(
        _tableName,
        {
          'worked_here_count': next,
          if (payload != null) 'raw_json': jsonEncode(payload),
        },
        where: 'id = ?',
        whereArgs: [docId],
      );
    });
  }

  Future<Database> get _database async {
    await init();
    return _db!;
  }

  Map<String, dynamic> _toDbRow(Map<String, dynamic> restaurant) {
    final normalized = _normalizeRestaurant(restaurant);
    return {
      'id': normalized['id'],
      'name': normalized['name'],
      'address': normalized['address'],
      'postcode': normalized['postcode']?.toString(),
      'postcode_display': normalized['postcode_display']?.toString(),
      'state': normalized['state'],
      'latitude': _asDouble(normalized['latitude'] ?? normalized['lat']),
      'longitude': _asDouble(normalized['longitude'] ?? normalized['lng']),
      'phone': normalized['phone'],
      'email': normalized['email'],
      'facebook_url': normalized['facebook_url'],
      'instagram_url': normalized['instagram_url'],
      'careers_page': normalized['careers_page'],
      'website': normalized['website'],
      'source_place_id': normalized['source_place_id'],
      'blocked': _asBoolInt(normalized['blocked']),
      'worked_here_count': _asInt(normalized['worked_here_count']),
      'timestamp': normalized['timestamp']?.toString(),
      'raw_json': jsonEncode(_sanitizeForJson(normalized)),
    };
  }

  Map<String, dynamic> _normalizeRestaurant(Map<String, dynamic> src) {
    final normalized = Map<String, dynamic>.from(src);
    final id = (normalized['id'] ?? normalized['docId'] ?? '').toString();
    normalized['id'] = id;
    normalized['docId'] = id;
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

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is bool) return value ? 1 : 0;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _asBoolInt(dynamic value) {
    if (value is bool) return value ? 1 : 0;
    return _asInt(value) > 0 ? 1 : 0;
  }

  bool _asBool(dynamic value) {
    if (value is bool) return value;
    return _asInt(value) > 0;
  }

  double? _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}
