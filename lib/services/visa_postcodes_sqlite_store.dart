import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class VisaPostcodesSqliteStore {
  VisaPostcodesSqliteStore._();
  static final VisaPostcodesSqliteStore instance = VisaPostcodesSqliteStore._();

  static const _dbName = 'visa_postcodes_local.db';
  static const _dbVersion = 1;
  static const _tableName = 'visa_postcodes';
  static const _seedAssetPath = 'export/visa_postcodes.json';

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
            industry TEXT,
            postcodes_json TEXT NOT NULL,
            raw_json TEXT NOT NULL
          )
        ''');
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
      throw const FormatException(
        'visa_postcodes.json must contain a JSON array',
      );
    }

    final entries = decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);

    if (entries.isEmpty) {
      debugPrint('⚠️ visa_postcodes seed asset is empty');
      return;
    }

    await replaceAll(entries);
    debugPrint('🗄️ SQLITE seed imported: ${entries.length} visa_postcodes');
  }

  Future<void> replaceAll(List<Map<String, dynamic>> entries) async {
    final db = await _database;
    final normalizedRows = entries
        .map(_normalizeEntry)
        .where((row) => row['id']!.toString().trim().isNotEmpty)
        .toList(growable: false);

    await db.transaction((txn) async {
      await txn.delete(_tableName);
      final batch = txn.batch();
      for (final row in normalizedRows) {
        batch.insert(_tableName, {
          'id': row['id'],
          'industry': row['industry'],
          'postcodes_json': jsonEncode(row['postcodes'] ?? const []),
          'raw_json': jsonEncode(row),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
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
          if (rawJson == null || rawJson.isEmpty) return <String, dynamic>{};
          final decoded = jsonDecode(rawJson);
          if (decoded is! Map) return <String, dynamic>{};
          return Map<String, dynamic>.from(decoded);
        })
        .where((row) => row.isNotEmpty)
        .toList(growable: false);
  }

  Future<Database> get _database async {
    await init();
    return _db!;
  }

  Map<String, dynamic> _normalizeEntry(Map<String, dynamic> src) {
    final normalized = Map<String, dynamic>.from(src);
    final id = (normalized['id'] ?? normalized['industry'] ?? '').toString();
    normalized['id'] = id;
    normalized['industry'] = (normalized['industry'] ?? id).toString();
    final rawPostcodes = normalized['postcodes'];
    if (rawPostcodes is List) {
      normalized['postcodes'] = rawPostcodes
          .map((pc) => int.tryParse(pc.toString()) ?? pc)
          .toList(growable: false);
    } else {
      normalized['postcodes'] = const <dynamic>[];
    }
    return normalized;
  }
}
