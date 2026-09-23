import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/construction_domain_records.dart';
import 'construction_application_contact_classifier.dart';

class ConstructionSqliteStore {
  ConstructionSqliteStore._();
  static final ConstructionSqliteStore instance = ConstructionSqliteStore._();

  static const _dbName = 'construction_companies_local.db';
  static const _dbVersion = 3;
  static const _tableName = 'construction_companies';
  static const _companiesTable = 'construction_company_entities';
  static const _worksitesTable = 'construction_worksites';
  static const _linksTable = 'construction_company_worksite_links';
  static const _identitiesTable = 'construction_company_identities';
  static const _seedAssetPath = 'export/construction_companies.json';

  Database? _db;

  Future<void> init() async {
    if (_db != null) return;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, _dbName),
      version: _dbVersion,
      onCreate: (db, version) async {
        await _createLegacyTable(db);
        await _createDomainTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createDomainTables(db);
          final legacyRows = await db.query(_tableName, columns: ['raw_json']);
          await _upsertDomainRows(
            db,
            legacyRows.map((stored) {
              final decoded = jsonDecode(stored['raw_json'].toString());
              return Map<String, dynamic>.from(decoded as Map);
            }),
          );
        }
        if (oldVersion < 3) {
          await _rebuildDomainProjection(db);
        }
      },
    );
  }

  static Future<void> _createLegacyTable(DatabaseExecutor db) async {
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
      'CREATE INDEX idx_construction_companies_name ON $_tableName(name)',
    );
  }

  static Future<void> _createDomainTables(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS $_companiesTable(
      id TEXT PRIMARY KEY, canonical_name TEXT NOT NULL, website TEXT,
      phone TEXT, email TEXT, careers_page TEXT, raw_json TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS $_worksitesTable(
      id TEXT PRIMARY KEY, name TEXT NOT NULL, state TEXT, postcode TEXT,
      latitude REAL, longitude REAL, source TEXT, raw_json TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS $_linksTable(
      company_id TEXT NOT NULL, worksite_id TEXT NOT NULL, role TEXT NOT NULL,
      corroborated INTEGER NOT NULL DEFAULT 0, evidence TEXT,
      raw_json TEXT NOT NULL, PRIMARY KEY(company_id, worksite_id, role))''');
    await db.execute('''CREATE TABLE IF NOT EXISTS $_identitiesTable(
      normalized_alias TEXT PRIMARY KEY, company_id TEXT NOT NULL,
      alias TEXT NOT NULL, identity_kind TEXT NOT NULL,
      verified_domain TEXT, evidence TEXT, raw_json TEXT NOT NULL)''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_construction_links_worksite ON $_linksTable(worksite_id)',
    );
  }

  Future<void> _rebuildDomainProjection(DatabaseExecutor db) async {
    // These four tables are a replaceable projection. The legacy catalogue is
    // the preserved source of truth and is never deleted by this migration.
    await db.delete(_linksTable);
    await db.delete(_identitiesTable);
    await db.delete(_worksitesTable);
    await db.delete(_companiesTable);
    final legacyRows = await db.query(_tableName, columns: ['raw_json']);
    await _upsertDomainRows(
      db,
      legacyRows.map((stored) {
        final decoded = jsonDecode(stored['raw_json'].toString());
        return Map<String, dynamic>.from(decoded as Map);
      }),
    );
  }

  Future<int> count() async {
    final db = await _database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM $_tableName',
    );
    return _asInt(result.first['count']);
  }

  Future<bool> get hasData async => (await count()) > 0;

  Future<List<Map<String, dynamic>>> loadSeedAssetCompanies() async {
    final rawJson = await rootBundle.loadString(_seedAssetPath);
    final decoded = jsonDecode(rawJson);
    if (decoded is! List) {
      throw const FormatException(
        'construction_companies.json must contain a JSON array',
      );
    }
    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<void> importSeedAssetIfEmpty() async {
    if (await hasData) return;
    final companies = await loadSeedAssetCompanies();
    if (companies.isEmpty) {
      debugPrint('⚠️ construction seed asset is empty');
      return;
    }
    await replaceAll(companies);
  }

  Future<void> replaceAll(List<Map<String, dynamic>> companies) async {
    final db = await _database;
    final normalized = companies
        .map(_normalizeCompany)
        .where((row) => row['id']!.toString().trim().isNotEmpty)
        .toList(growable: false);
    await db.transaction((txn) async {
      await txn.delete(_tableName);
      final batch = txn.batch();
      for (final row in normalized) {
        batch.insert(
          _tableName,
          _toDbRow(row),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      await _upsertDomainRows(txn, normalized);
    });
  }

  Future<List<Map<String, dynamic>>> getCompanies() async =>
      _readRawTable(_companiesTable);

  Future<List<Map<String, dynamic>>> getWorksites() async =>
      _readRawTable(_worksitesTable);

  Future<List<Map<String, dynamic>>> getCompanyWorksiteLinks() async =>
      _readRawTable(_linksTable);

  Future<Map<String, int>> getDomainMetrics() async {
    final db = await _database;
    Future<int> countTable(String table) async => _asInt(
      (await db.rawQuery(
        'SELECT COUNT(*) AS count FROM $table',
      )).first['count'],
    );
    final companies = await countTable(_companiesTable);
    final worksites = await countTable(_worksitesTable);
    final links = await countTable(_linksTable);
    final linkedWorksites = _asInt(
      (await db.rawQuery(
        'SELECT COUNT(DISTINCT worksite_id) AS count FROM $_linksTable WHERE corroborated = 1 AND role IN (?, ?)',
        ['operator', 'contractor'],
      )).first['count'],
    );
    return {
      'employers': companies,
      'worksites': worksites,
      'links': links,
      'linked_worksites': linkedWorksites,
    };
  }

  Future<List<Map<String, dynamic>>> _readRawTable(String table) async {
    final db = await _database;
    final rows = await db.query(table, columns: ['raw_json']);
    return rows
        .map((stored) {
          final decoded = jsonDecode(stored['raw_json'].toString());
          return Map<String, dynamic>.from(decoded as Map);
        })
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> getAll() async {
    final db = await _database;
    final rows = await db.query(_tableName);
    return rows
        .map((row) {
          final raw = row['raw_json']?.toString() ?? '';
          final decoded = raw.isEmpty ? null : jsonDecode(raw);
          return decoded is Map
              ? Map<String, dynamic>.from(decoded)
              : <String, dynamic>{};
        })
        .where((row) => row.isNotEmpty)
        .toList(growable: false);
  }

  Future<Map<String, dynamic>?> getById(String docId) async {
    if (docId.trim().isEmpty) return null;
    final db = await _database;
    final rows = await db.query(
      _tableName,
      columns: ['raw_json'],
      where: 'id = ?',
      whereArgs: [docId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['raw_json']?.toString() ?? '';
    if (raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  Future<List<Map<String, dynamic>>> searchByName(
    String query, {
    int limit = 25,
  }) async {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return const <Map<String, dynamic>>[];
    final companies = await getAll();
    final startsWith = <Map<String, dynamic>>[];
    final contains = <Map<String, dynamic>>[];
    for (final company in companies) {
      final name = (company['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final lowerName = name.toLowerCase();
      if (lowerName.startsWith(normalizedQuery)) {
        startsWith.add(company);
      } else if (lowerName.contains(normalizedQuery)) {
        contains.add(company);
      }
    }
    final results = <Map<String, dynamic>>[...startsWith, ...contains];
    return results.length <= limit
        ? results
        : results.take(limit).toList(growable: false);
  }

  Future<void> updateCompanyFields(
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
      final rawJson = rows.first['raw_json']?.toString() ?? '';
      var payload = <String, dynamic>{'id': docId, 'docId': docId};
      if (rawJson.isNotEmpty) {
        final decoded = jsonDecode(rawJson);
        if (decoded is Map) payload = Map<String, dynamic>.from(decoded);
      }
      payload.addAll(updates);
      ConstructionDomainRecords.attachDerivedIds(payload);
      await txn.update(
        _tableName,
        _toDbRow(payload),
        where: 'id = ?',
        whereArgs: [docId],
      );
      await _upsertDomainRows(txn, [payload]);
    });
  }

  Future<void> deleteById(String docId) async {
    if (docId.trim().isEmpty) return;
    final db = await _database;
    await db.delete(_tableName, where: 'id = ?', whereArgs: [docId]);
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

      final current = _asInt(rows.first['worked_here_count']);
      final next = (current + delta).clamp(0, 1 << 31);
      final rawJson = rows.first['raw_json']?.toString() ?? '';
      var payload = <String, dynamic>{'id': docId, 'docId': docId};
      if (rawJson.isNotEmpty) {
        final decoded = jsonDecode(rawJson);
        if (decoded is Map) payload = Map<String, dynamic>.from(decoded);
      }
      payload['worked_here_count'] = next;

      await txn.update(
        _tableName,
        _toDbRow(payload),
        where: 'id = ?',
        whereArgs: [docId],
      );
    });
  }

  Future<int> deleteOsmCompaniesForPostcode(String postcode) async {
    final companies = await getAll();
    final remaining = <Map<String, dynamic>>[];
    var deleted = 0;
    for (final company in companies) {
      final companyPostcode =
          (company['postcode_display'] ?? company['postcode'] ?? '')
              .toString()
              .padLeft(4, '0');
      final source = (company['source'] ?? '').toString();
      final sourceId = (company['source_place_id'] ?? '').toString();
      final id = (company['docId'] ?? company['id'] ?? '').toString();
      final isOsm =
          source == 'osm' ||
          sourceId.startsWith('osm:') ||
          id.startsWith('osm_construction_');
      if (companyPostcode == postcode && isOsm) {
        deleted++;
      } else {
        remaining.add(company);
      }
    }
    if (deleted > 0) await replaceAll(remaining);
    return deleted;
  }

  Future<Database> get _database async {
    await init();
    return _db!;
  }

  Map<String, dynamic> _toDbRow(Map<String, dynamic> company) {
    final row = _normalizeCompany(company);
    return {
      'id': row['id'],
      'name': row['name'],
      'address': row['address'],
      'postcode': row['postcode']?.toString(),
      'postcode_display': row['postcode_display']?.toString(),
      'state': row['state'],
      'latitude': _asDouble(row['latitude'] ?? row['lat']),
      'longitude': _asDouble(row['longitude'] ?? row['lng']),
      'phone': row['phone'],
      'email': row['email'],
      'facebook_url': row['facebook_url'],
      'instagram_url': row['instagram_url'],
      'careers_page': row['careers_page'],
      'website': row['website'],
      'source_place_id': row['source_place_id'],
      'blocked': _asInt(row['blocked']) > 0 ? 1 : 0,
      'worked_here_count': _asInt(row['worked_here_count']),
      'timestamp': row['timestamp']?.toString(),
      'raw_json': jsonEncode(_convertValue(row)),
    };
  }

  Map<String, dynamic> _normalizeCompany(Map<String, dynamic> source) {
    final row = Map<String, dynamic>.from(source);
    final id = (row['id'] ?? row['docId'] ?? row['source_place_id'] ?? '')
        .toString();
    row['id'] = id;
    row['docId'] = id;
    row['place_type'] = 'construction';
    row['marker_kind'] = 'construction';
    ConstructionDomainRecords.attachDerivedIds(row);
    ConstructionApplicationContactClassifier.applyDerivedFields(row);
    return row;
  }

  Future<void> _upsertDomainRows(
    DatabaseExecutor db,
    Iterable<Map<String, dynamic>> rows,
  ) async {
    for (final source in rows) {
      final row = Map<String, dynamic>.from(source);
      ConstructionDomainRecords.attachDerivedIds(row);
      final companyId = (row['company_id'] ?? '').toString();
      if (companyId.isNotEmpty) {
        await db.insert(_companiesTable, {
          'id': companyId,
          'canonical_name': (row['name'] ?? '').toString(),
          'website': (row['website'] ?? '').toString(),
          'phone': (row['phone'] ?? '').toString(),
          'email': (row['email'] ?? '').toString(),
          'careers_page': (row['careers_page'] ?? '').toString(),
          'raw_json': jsonEncode(_convertValue(row)),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        final aliases = <String>{(row['name'] ?? '').toString().trim()};
        final learnedAliases = row['company_identity_aliases'];
        if (learnedAliases is List) {
          aliases.addAll(
            learnedAliases
                .map((value) => value.toString().trim())
                .where((value) => value.isNotEmpty),
          );
        }
        for (final key in const [
          'trading_name',
          'parent_company_name',
          'subsidiary_name',
        ]) {
          final value = (row[key] ?? '').toString().trim();
          if (value.isNotEmpty) aliases.add(value);
        }
        for (final alias in aliases) {
          final normalized = ConstructionDomainRecords.normalizeIdentity(alias);
          if (normalized.isEmpty) continue;
          await db.insert(_identitiesTable, {
            'normalized_alias': normalized,
            'company_id': companyId,
            'alias': alias,
            'identity_kind': alias == (row['name'] ?? '').toString().trim()
                ? 'source_name'
                : 'verified_alias',
            'verified_domain':
                Uri.tryParse((row['website'] ?? '').toString())?.host ?? '',
            'evidence': (row['classification_source'] ?? '').toString(),
            'raw_json': jsonEncode(
              _convertValue({
                'company_id': companyId,
                'alias': alias,
                'identity_kind': alias == (row['name'] ?? '').toString().trim()
                    ? 'source_name'
                    : 'verified_alias',
              }),
            ),
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
      if (!ConstructionDomainRecords.isWorksite(row)) continue;
      final worksiteId = (row['worksite_id'] ?? '').toString();
      if (worksiteId.isEmpty) continue;
      await db.insert(_worksitesTable, {
        'id': worksiteId,
        'name': (row['worksite_name'] ?? row['name'] ?? '').toString(),
        'state': (row['state'] ?? '').toString(),
        'postcode': (row['postcode_display'] ?? row['postcode'] ?? '')
            .toString(),
        'latitude': _asDouble(row['latitude'] ?? row['lat']),
        'longitude': _asDouble(row['longitude'] ?? row['lng']),
        'source': (row['source'] ?? '').toString(),
        'raw_json': jsonEncode(_convertValue(row)),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      final role = ConstructionCompanyWorksiteRole.fromRow(row);
      if (companyId.isEmpty || role == null) continue;
      final corroborated = ConstructionDomainRecords.hasCorroboratedHiringLink(
        row,
      );
      final link = {
        'company_id': companyId,
        'worksite_id': worksiteId,
        'role': role.id,
        'corroborated': corroborated,
        'evidence': (row['company_worksite_evidence'] ?? '').toString(),
      };
      await db.insert(_linksTable, {
        ...link,
        'corroborated': corroborated ? 1 : 0,
        'raw_json': jsonEncode(_convertValue(link)),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  dynamic _convertValue(dynamic value) {
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is GeoPoint) {
      return {'lat': value.latitude, 'lng': value.longitude};
    }
    if (value is DateTime) return value.toIso8601String();
    if (value is Uint8List) return base64Encode(value);
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key.toString(), _convertValue(item)),
      );
    }
    if (value is Iterable) return value.map(_convertValue).toList();
    return value;
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is bool) return value ? 1 : 0;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}
