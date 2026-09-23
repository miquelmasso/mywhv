import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class ConstructionIssueReportStore {
  ConstructionIssueReportStore._();

  static final instance = ConstructionIssueReportStore._();
  static const _databaseName = 'construction_issue_reports_local.db';
  static const _tableName = 'construction_issue_reports';

  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final root = await getDatabasesPath();
    _db = await openDatabase(
      p.join(root, _databaseName),
      version: 1,
      onCreate: (db, version) => db.execute('''
        CREATE TABLE $_tableName(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          created_at TEXT NOT NULL,
          issue_type TEXT NOT NULL,
          note TEXT NOT NULL,
          company_id TEXT NOT NULL,
          worksite_id TEXT NOT NULL,
          company_name TEXT NOT NULL,
          source TEXT NOT NULL,
          snapshot_json TEXT NOT NULL
        )
      '''),
    );
    return _db!;
  }

  Future<void> add({
    required Map<String, dynamic> company,
    required String issueType,
    String note = '',
  }) async {
    final db = await _database;
    await db.insert(_tableName, {
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'issue_type': issueType,
      'note': note.trim(),
      'company_id': _first(company, const [
        'company_id',
        'construction_company_id',
        'docId',
        'id',
      ]),
      'worksite_id': _first(company, const [
        'worksite_id',
        'construction_worksite_id',
        'source_place_id',
      ]),
      'company_name': (company['name'] ?? '').toString().trim(),
      'source': _first(company, const ['source', 'source_name', 'data_source']),
      // Keep the displayed record intact as evidence. Reports never update or
      // delete the Construction catalogue or its source data.
      'snapshot_json': jsonEncode(company),
    });
  }

  Future<List<Map<String, dynamic>>> getAll() async {
    final db = await _database;
    return db.query(_tableName, orderBy: 'created_at DESC');
  }

  Future<int> count() async {
    final db = await _database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS total FROM $_tableName');
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  static String _first(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = (row[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }
}
