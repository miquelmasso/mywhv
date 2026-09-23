import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'construction_sqlite_store.dart';
import 'construction_publication_policy.dart';
import 'map_markers_service.dart';

class MapConstructionRefreshResult {
  const MapConstructionRefreshResult({
    required this.count,
    required this.exportJsonPath,
  });

  final int count;
  final String exportJsonPath;
}

class MapConstructionRefreshService {
  MapConstructionRefreshService._();
  static final MapConstructionRefreshService instance =
      MapConstructionRefreshService._();

  static const _workspaceExportPath = String.fromEnvironment(
    'WORKSPACE_CONSTRUCTION_JSON_PATH',
    defaultValue:
        '/Users/paulafernandeziplanaguma/Developer/workyday-local/mywhv/export/construction_companies.json',
  );
  static const _workspaceBackupPath = String.fromEnvironment(
    'WORKSPACE_CONSTRUCTION_BACKUP_JSON_PATH',
    defaultValue:
        '/Users/paulafernandeziplanaguma/Developer/workyday-local/mywhv/export/construction_companies_previous.json',
  );

  Future<MapConstructionRefreshResult> refreshFromFirebase() async {
    final sync =
        await MapMarkersService.syncConstructionCompaniesFromFirebase();
    final store = ConstructionSqliteStore.instance;
    await store.init();
    final companies = (await store.getAll())
        .where(ConstructionPublicationPolicy.canAppearOnMap)
        .toList(growable: false);
    final path = await _writeWorkspaceJson(companies);
    debugPrint(
      'Construction refreshed: remote ${sync.remoteCount}, merged ${companies.length}',
    );
    return MapConstructionRefreshResult(
      count: companies.length,
      exportJsonPath: path,
    );
  }

  Future<MapConstructionRefreshResult>
  exportLocalConstructionCompanies() async {
    final store = ConstructionSqliteStore.instance;
    await store.init();
    final companies = (await store.getAll())
        .where(ConstructionPublicationPolicy.canAppearOnMap)
        .toList(growable: false);
    final path = await _writeWorkspaceJson(companies);
    return MapConstructionRefreshResult(
      count: companies.length,
      exportJsonPath: path,
    );
  }

  Future<String> _writeWorkspaceJson(
    List<Map<String, dynamic>> companies,
  ) async {
    final file = File(_workspaceExportPath);
    await file.parent.create(recursive: true);
    final backup = File(_workspaceBackupPath);
    if (backup.existsSync()) await backup.delete();
    if (file.existsSync()) await file.copy(backup.path);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(companies),
      flush: true,
    );
    if (file.existsSync()) await file.delete();
    await temporary.rename(file.path);
    return file.path;
  }
}
