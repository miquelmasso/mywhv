import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'map_markers_service.dart';
import 'restaurant_sqlite_store.dart';

class MapRestaurantsRefreshResult {
  const MapRestaurantsRefreshResult({
    required this.count,
    required this.exportJsonPath,
  });

  final int count;
  final String exportJsonPath;
}

class MapRestaurantsRefreshService {
  MapRestaurantsRefreshService._();

  static const String _workspaceExportPath = String.fromEnvironment(
    'WORKSPACE_RESTAURANTS_JSON_PATH',
    defaultValue:
        '/Users/miquelmassomoreno/Desktop/GENERAL/app/mywhv/export/restaurants.json',
  );
  static const String _workspaceBackupExportPath = String.fromEnvironment(
    'WORKSPACE_RESTAURANTS_BACKUP_JSON_PATH',
    defaultValue:
        '/Users/miquelmassomoreno/Desktop/GENERAL/app/mywhv/export/restaurants_previous.json',
  );

  static final MapRestaurantsRefreshService instance =
      MapRestaurantsRefreshService._();

  Future<MapRestaurantsRefreshResult> refreshFromFirebase() async {
    final result = await MapMarkersService.syncRestaurantsFromFirebaseIfNeeded(
      force: true,
    );
    final store = RestaurantSqliteStore.instance;
    await store.init();
    final restaurants = await store.getAll();
    final outputPath = await _writeWorkspaceJson(restaurants);

    debugPrint(
      '🗄️ Restaurants refreshed from Firebase: remote ${result.remoteCount}, merged ${restaurants.length} -> $outputPath',
    );

    return MapRestaurantsRefreshResult(
      count: restaurants.length,
      exportJsonPath: outputPath,
    );
  }

  Future<String> _writeWorkspaceJson(
    List<Map<String, dynamic>> restaurants,
  ) async {
    final file = File(_workspaceExportPath);
    final parent = file.parent;
    if (!parent.existsSync()) {
      await parent.create(recursive: true);
    }
    await _rotateWorkspaceExports(file);
    final tempFile = File('${file.path}.tmp');
    await tempFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(restaurants),
      flush: true,
    );
    if (file.existsSync()) {
      await file.delete();
    }
    await tempFile.rename(file.path);
    return file.path;
  }

  Future<void> _rotateWorkspaceExports(File currentFile) async {
    final backupFile = File(_workspaceBackupExportPath);
    if (backupFile.existsSync()) {
      await backupFile.delete();
    }

    if (currentFile.existsSync()) {
      await currentFile.copy(backupFile.path);
    }
  }
}
