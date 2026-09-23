import 'package:shared_preferences/shared_preferences.dart';

import 'construction_sqlite_store.dart';
import 'construction_publication_policy.dart';
import 'map_construction_refresh_service.dart';
import 'map_markers_service.dart';

class ConstructionPublishResult {
  const ConstructionPublishResult({
    required this.uploaded,
    required this.remaining,
    required this.jsonCount,
    required this.jsonPath,
  });

  final int uploaded;
  final int remaining;
  final int jsonCount;
  final String jsonPath;
}

class ConstructionPendingPublishService {
  ConstructionPendingPublishService._();

  static final ConstructionPendingPublishService instance =
      ConstructionPendingPublishService._();
  static const _pendingIdsKey = 'construction_pending_firebase_ids_v1';

  Future<Set<String>> getPendingIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_pendingIdsKey) ?? const <String>[])
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<Set<String>> getPublishablePendingIds({bool prune = true}) async {
    final pending = await getPendingIds();
    if (pending.isEmpty) return <String>{};
    final store = ConstructionSqliteStore.instance;
    await store.init();
    final publishable = (await store.getAll())
        .where(ConstructionPublicationPolicy.canAppearOnMap)
        .map((row) => (row['docId'] ?? row['id'] ?? '').toString())
        .where(pending.contains)
        .toSet();
    if (prune && publishable.length != pending.length) {
      await _savePendingIds(publishable);
    }
    return publishable;
  }

  Future<int> markPending(Iterable<String> ids) async {
    final pending = await getPendingIds();
    final requested = ids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (requested.isNotEmpty) {
      final store = ConstructionSqliteStore.instance;
      await store.init();
      final eligibleIds = (await store.getAll())
          .where(ConstructionPublicationPolicy.canAppearOnMap)
          .map((row) => (row['docId'] ?? row['id'] ?? '').toString())
          .where(requested.contains);
      pending.addAll(eligibleIds);
    }
    final allRows = await ConstructionSqliteStore.instance.getAll();
    final stillEligible = allRows
        .where(ConstructionPublicationPolicy.canAppearOnMap)
        .map((row) => (row['docId'] ?? row['id'] ?? '').toString())
        .toSet();
    pending.removeWhere((id) => !stillEligible.contains(id));
    await _savePendingIds(pending);
    return pending.length;
  }

  Future<void> removePending(Iterable<String> ids) async {
    final pending = await getPendingIds();
    pending.removeAll(ids);
    await _savePendingIds(pending);
  }

  Future<ConstructionPublishResult> publishPendingAndExportJson() async {
    final pending = await getPublishablePendingIds();
    final store = ConstructionSqliteStore.instance;
    await store.init();
    final allCompanies = await store.getAll();
    final companies = allCompanies
        .where((row) {
          final id = (row['docId'] ?? row['id'] ?? '').toString();
          return pending.contains(id) &&
              ConstructionPublicationPolicy.canAppearOnMap(row);
        })
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
    final publishedIds = companies
        .map((row) => (row['docId'] ?? row['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();

    if (companies.isNotEmpty) {
      await MapMarkersService.upsertConstructionCompaniesToFirebase(companies);
    }

    final jsonResult = await MapConstructionRefreshService.instance
        .exportLocalConstructionCompanies();
    if (publishedIds.isNotEmpty) await removePending(publishedIds);
    return ConstructionPublishResult(
      uploaded: companies.length,
      remaining: (await getPendingIds()).length,
      jsonCount: jsonResult.count,
      jsonPath: jsonResult.exportJsonPath,
    );
  }

  Future<void> _savePendingIds(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    final sorted = ids.toList()..sort();
    await prefs.setStringList(_pendingIdsKey, sorted);
  }
}
