import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'construction_source_models.dart';

/// Separate, local-only bookkeeping database. Source data remains in the
/// existing Construction catalogue and is never deleted by this store.
class ConstructionStateBuilderStore {
  ConstructionStateBuilderStore._();
  static final instance = ConstructionStateBuilderStore._();
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await openDatabase(
      p.join(await getDatabasesPath(), 'construction_state_builder_local.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''CREATE TABLE source_instructions(
          id TEXT PRIMARY KEY, state TEXT NOT NULL, title TEXT NOT NULL,
          publisher TEXT, catalogue_url TEXT, data_url TEXT, format TEXT,
          license TEXT, attribution TEXT, mapping_json TEXT, status TEXT,
          is_government INTEGER, last_fingerprint TEXT, last_error TEXT,
          updated_at TEXT)''');
        await db.execute('''CREATE TABLE build_jobs(
          id TEXT PRIMARY KEY, run_id TEXT, state TEXT, stage TEXT,
          target_id TEXT, status TEXT, attempts INTEGER DEFAULT 0,
          payload_json TEXT, error TEXT, updated_at TEXT)''');
        await db.execute('''CREATE TABLE snapshots(
          id TEXT PRIMARY KEY, run_id TEXT, state TEXT, created_at TEXT,
          metrics_json TEXT, record_ids_json TEXT)''');
        await db.execute('''CREATE TABLE run_reports(
          run_id TEXT PRIMARY KEY, state TEXT, status TEXT, started_at TEXT,
          finished_at TEXT, before_json TEXT, after_json TEXT,
          sources_ready INTEGER, sources_review INTEGER,
          errors_json TEXT, publication_safe INTEGER)''');
        await db.execute('''CREATE TABLE source_claims(
          id TEXT PRIMARY KEY, state TEXT, source_id TEXT, source_record_id TEXT,
          worksite_name TEXT, company_name TEXT, role TEXT, evidence TEXT,
          raw_json TEXT, observed_at TEXT)''');
      },
    );
    return _db!;
  }

  Future<void> saveInstruction(ConstructionSourceInstruction source) async {
    final db = await database;
    await db.insert(
      'source_instructions',
      source.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ConstructionSourceInstruction>> sourcesFor(String state) async {
    final db = await database;
    return (await db.query(
      'source_instructions',
      where: 'state IN (?, ?)',
      whereArgs: [state, 'AU'],
    )).map(ConstructionSourceInstruction.fromMap).toList();
  }

  Future<List<ConstructionSourceInstruction>> allSources() async {
    final db = await database;
    return (await db.query(
      'source_instructions',
      orderBy: 'state, title',
    )).map(ConstructionSourceInstruction.fromMap).toList();
  }

  Future<void> snapshot(
    String runId,
    String state,
    Map<String, int> metrics,
    List<String> ids,
  ) async {
    final db = await database;
    await db.insert('snapshots', {
      'id': '$runId:before',
      'run_id': runId,
      'state': state,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'metrics_json': jsonEncode(metrics),
      'record_ids_json': jsonEncode(ids),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> queueStage(
    String runId,
    String state,
    ConstructionBuildStage stage, {
    String targetId = '',
  }) async {
    final db = await database;
    final id = '$runId:${stage.name}:$targetId';
    await db.insert('build_jobs', {
      'id': id,
      'run_id': runId,
      'state': state,
      'stage': stage.name,
      'target_id': targetId,
      'status': 'pending',
      'attempts': 0,
      'payload_json': '{}',
      'error': '',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> setJobStatus(
    String runId,
    ConstructionBuildStage stage,
    String status, {
    String targetId = '',
    String error = '',
  }) async {
    final db = await database;
    await db.update(
      'build_jobs',
      {
        'status': status,
        'error': error,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: ['$runId:${stage.name}:$targetId'],
    );
  }

  Future<void> saveReport(ConstructionBuildReport report) async {
    final db = await database;
    await db.insert('run_reports', {
      'run_id': report.runId,
      'state': report.state,
      'status': report.status,
      'started_at': report.runId.split('_').last,
      'finished_at': DateTime.now().toUtc().toIso8601String(),
      'before_json': jsonEncode(report.before),
      'after_json': jsonEncode(report.after),
      'sources_ready': report.sourcesReady,
      'sources_review': report.sourcesNeedingReview,
      'errors_json': jsonEncode(report.errors),
      'publication_safe': report.publicationSafe ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> reports({String? state}) async {
    final db = await database;
    return db.query(
      'run_reports',
      where: state == null ? null : 'state = ?',
      whereArgs: state == null ? null : [state],
      orderBy: 'finished_at DESC',
    );
  }
}
