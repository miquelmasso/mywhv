import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/construction_category.dart';
import '../models/construction_domain_records.dart';
import 'construction_application_contact_classifier.dart';
import 'restaurant_sqlite_store.dart';
import 'construction_sqlite_store.dart';
import 'construction_validation_catalog_service.dart';
import 'offline_bootstrap_service.dart';
import 'offline_state.dart';

class RestaurantsFirebaseSyncResult {
  const RestaurantsFirebaseSyncResult({
    required this.remoteCount,
    required this.localCount,
    required this.mergedCount,
    required this.didRun,
  });

  final int remoteCount;
  final int localCount;
  final int mergedCount;
  final bool didRun;
}

class ConstructionCompaniesCacheWriteResult {
  const ConstructionCompaniesCacheWriteResult({
    required this.added,
    required this.updated,
    required this.total,
  });

  final int added;
  final int updated;
  final int total;
}

class ConstructionFirebaseSyncResult {
  const ConstructionFirebaseSyncResult({
    required this.remoteCount,
    required this.localCount,
    required this.mergedCount,
    required this.didRun,
  });

  final int remoteCount;
  final int localCount;
  final int mergedCount;
  final bool didRun;
}

class MapMarkersService {
  static const _cacheKeyJson = 'restaurants_cache_json';
  static const _cacheKeySynced = 'restaurants_cache_synced';
  static const _cacheKeyAppVersion = 'restaurants_cache_app_version';
  static const _constructionLocalCacheKey =
      'construction_companies_local_cache_json';
  static const _constructionFirebaseLastSyncKey =
      'construction_companies_firebase_last_sync';
  static const _constructionFirebaseSyncInterval = Duration(days: 30);
  static const _localWorkedHereMinCountsKey =
      'worked_here_local_min_counts_json';
  static const _constructionWorkedHereMinCountsKey =
      'construction_worked_here_local_min_counts_json';
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static List<Map<String, dynamic>>? _memoryRestaurants;
  static String? _memoryCacheVersion;
  static List<Map<String, dynamic>>? _memoryMapRestaurants;
  static String? _memoryMapCacheVersion;
  static List<Map<String, dynamic>>? _memoryConstructionCompanies;

  static Future<List<Map<String, dynamic>>> loadConstructionCompanies({
    bool lightweight = true,
    bool syncFromFirebaseIfNeeded = false,
  }) async {
    if (syncFromFirebaseIfNeeded) {
      await syncConstructionCompaniesFromFirebaseIfNeeded();
    }
    final cached = _memoryConstructionCompanies;
    if (cached != null) return cached;

    final store = ConstructionSqliteStore.instance;
    await store.init();
    await store.importSeedAssetIfEmpty();
    var rows = await store.getAll();
    var validationChanged = false;
    for (final row in rows) {
      final channelFieldsBefore = jsonEncode({
        'email_contact_type': row['email_contact_type'],
        'email_public_eligible': row['email_public_eligible'],
        'careers_public_eligible': row['careers_public_eligible'],
        'email_identity_status': row['email_identity_status'],
      });
      ConstructionApplicationContactClassifier.applyDerivedFields(row);
      final channelFieldsAfter = jsonEncode({
        'email_contact_type': row['email_contact_type'],
        'email_public_eligible': row['email_public_eligible'],
        'careers_public_eligible': row['careers_public_eligible'],
        'email_identity_status': row['email_identity_status'],
      });
      if (channelFieldsBefore != channelFieldsAfter) validationChanged = true;
      final name = (row['name'] ?? '').toString();
      final evidence = await ConstructionValidationCatalogService.instance
          .findOpenDataEvidence(name);
      final validated =
          evidence != null ||
          await ConstructionValidationCatalogService.instance
              .isValidatedCompanyName(name);
      final nextStatus = validated
          ? 'validated_active_company'
          : 'osm_only_needs_review';
      final classification = ConstructionCategory.classifyRowDetailed(row);
      var category = classification.category;
      var entityKind = classification.entityKindId;
      var confidence = classification.confidence;
      var reason = classification.reason;
      var classificationSource = 'osm_tags';
      if (evidence != null &&
          entityKind != 'supplier_retail' &&
          entityKind != 'project_site') {
        final categories = evidence['construction_categories'];
        if (categories is List && categories.isNotEmpty) {
          category = ConstructionCategory.fromId(categories.first);
        }
        entityKind = 'employer';
        confidence = confidence < 90 ? 90 : confidence;
        reason = 'company and category corroborated by open-data sources';
        classificationSource = 'open_data_corroboration';
      }
      final sources = <String>{
        ...(row['catalog_sources'] is List
            ? (row['catalog_sources'] as List).map((e) => e.toString())
            : const <String>[]),
        if (evidence != null) (evidence['source_id'] ?? '').toString(),
        if (validated) 'asic_companies',
        'osm',
      }..removeWhere((source) => source.isEmpty);
      final updates = <String, dynamic>{
        'company_validation_status': nextStatus,
        'company_validation_source': validated ? 'asic_companies' : 'osm',
        'construction_category': category.id,
        'construction_category_label': category.label,
        'entity_kind': entityKind,
        'classification_confidence': confidence,
        'classification_reason': reason,
        'classification_source': classificationSource,
        'review_status': entityKind == 'employer' && confidence >= 70
            ? 'ready_for_map'
            : 'needs_review',
        'catalog_sources': sources.toList()..sort(),
      };
      for (final entry in updates.entries) {
        if (row[entry.key].toString() != entry.value.toString()) {
          row[entry.key] = entry.value;
          validationChanged = true;
        }
      }
    }
    if (validationChanged && rows.isNotEmpty) {
      await store.replaceAll(rows);
    }

    // One-time compatibility migration from the first construction prototype.
    if (rows.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_constructionLocalCacheKey);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        try {
          final decoded = jsonDecode(cachedJson);
          if (decoded is List) {
            rows = decoded
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList(growable: false);
            await store.replaceAll(rows);
            await prefs.remove(_constructionLocalCacheKey);
          }
        } catch (e) {
          debugPrint('⚠️ Error migrating construction cache to SQLite: $e');
        }
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final localWorkedHereMinCounts = _readLocalWorkedHereMinCountsForKey(
      prefs,
      _constructionWorkedHereMinCountsKey,
    );
    final merged = _applyLocalWorkedHereMinCounts(
      _dedupeConstructionRows(rows),
      localWorkedHereMinCounts,
    );
    _memoryConstructionCompanies = merged;
    if (merged.isNotEmpty) {
      debugPrint('🏗️ Construction companies loaded: ${rows.length}');
    }
    return merged;
  }

  /// Re-runs local classification and open-data corroboration without making
  /// network requests or publishing anything.
  static Future<List<Map<String, dynamic>>>
  reclassifyLocalConstructionCompanies() async {
    _memoryConstructionCompanies = null;
    return loadConstructionCompanies(
      lightweight: false,
      syncFromFirebaseIfNeeded: false,
    );
  }

  static Future<ConstructionCompaniesCacheWriteResult>
  upsertLocalConstructionCompanies(List<Map<String, dynamic>> companies) async {
    final store = ConstructionSqliteStore.instance;
    await store.init();
    final existing = await store.getAll();

    final merged = _dedupeConstructionRows(existing);
    final indexByKey = <String, int>{};
    for (var i = 0; i < merged.length; i++) {
      final key = _constructionDedupeKey(merged[i]);
      if (key.isNotEmpty) indexByKey[key] = i;
    }

    var added = 0;
    var updated = 0;
    for (final raw in companies) {
      final company = _normalizeConstructionCompanyRow(raw);
      if (company.isEmpty) continue;
      final key = _constructionDedupeKey(company);
      if (key.isEmpty) continue;
      final existingIndex = indexByKey[key];
      if (existingIndex == null) {
        indexByKey[key] = merged.length;
        merged.add(company);
        added++;
      } else {
        merged[existingIndex] = {...merged[existingIndex], ...company};
        updated++;
      }
    }

    await store.replaceAll(merged);
    _memoryConstructionCompanies = merged;
    return ConstructionCompaniesCacheWriteResult(
      added: added,
      updated: updated,
      total: merged.length,
    );
  }

  static Future<void> replaceLocalConstructionCompanies(
    List<Map<String, dynamic>> companies,
  ) async {
    final normalized = _dedupeConstructionRows(companies);
    final store = ConstructionSqliteStore.instance;
    await store.init();
    await store.replaceAll(normalized);
    _memoryConstructionCompanies = normalized;
  }

  static Future<void> updateLocalConstructionCompanyFields(
    String docId,
    Map<String, dynamic> updates,
  ) async {
    if (docId.trim().isEmpty || updates.isEmpty) return;
    final store = ConstructionSqliteStore.instance;
    await store.init();
    await store.updateCompanyFields(docId, updates);
    _memoryConstructionCompanies = _dedupeConstructionRows(
      await store.getAll(),
    );
  }

  static Future<void> updateConstructionCompanyFields(
    String docId,
    Map<String, dynamic> updates,
  ) async {
    if (docId.trim().isEmpty || updates.isEmpty) return;
    final sanitized = _sanitizeForJson(updates)
      ..['updated_at'] = FieldValue.serverTimestamp();
    await _firestore
        .collection('construction_companies')
        .doc(docId)
        .set(sanitized, SetOptions(merge: true));
    await updateLocalConstructionCompanyFields(docId, updates);
  }

  static Future<void> deleteConstructionCompany(String docId) async {
    if (docId.trim().isEmpty) return;
    await _firestore.collection('construction_companies').doc(docId).delete();
    await deleteLocalConstructionCompany(docId);
  }

  static Future<void> deleteLocalConstructionCompany(String docId) async {
    if (docId.trim().isEmpty) return;
    final store = ConstructionSqliteStore.instance;
    await store.init();
    await store.deleteById(docId);
    _memoryConstructionCompanies = _dedupeConstructionRows(
      await store.getAll(),
    );
  }

  static Future<void> upsertConstructionCompaniesToFirebase(
    List<Map<String, dynamic>> companies,
  ) async {
    if (companies.isEmpty) return;
    for (var offset = 0; offset < companies.length; offset += 400) {
      final batch = _firestore.batch();
      for (final raw in companies.skip(offset).take(400)) {
        final company = _normalizeConstructionCompanyRow(
          Map<String, dynamic>.from(raw),
        );
        final docId = (company['docId'] ?? company['id'] ?? '').toString();
        if (docId.isEmpty) continue;
        final data = _sanitizeForJson(company)
          ..['id'] = docId
          ..['docId'] = docId
          ..['place_type'] = 'construction'
          ..['marker_kind'] = 'construction'
          ..['updated_at'] = FieldValue.serverTimestamp()
          ..['synced_from'] = (company['source'] ?? '').toString().isEmpty
              ? 'app'
              : company['source'];
        data.removeWhere(
          (key, value) =>
              value is String &&
              value.trim().isEmpty &&
              key != 'id' &&
              key != 'docId',
        );
        batch.set(
          _firestore.collection('construction_companies').doc(docId),
          data,
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    }
  }

  static Future<ConstructionFirebaseSyncResult>
  syncConstructionCompaniesFromFirebase() async {
    return syncConstructionCompaniesFromFirebaseIfNeeded(force: true);
  }

  static Future<ConstructionFirebaseSyncResult>
  syncConstructionCompaniesFromFirebaseIfNeeded({bool force = false}) async {
    final store = ConstructionSqliteStore.instance;
    await store.init();
    await store.importSeedAssetIfEmpty();
    final local = await store.getAll();
    final prefs = await SharedPreferences.getInstance();
    final lastSync = DateTime.tryParse(
      prefs.getString(_constructionFirebaseLastSyncKey) ?? '',
    );
    if (!force &&
        lastSync != null &&
        DateTime.now().toUtc().difference(lastSync) <
            _constructionFirebaseSyncInterval) {
      return ConstructionFirebaseSyncResult(
        remoteCount: 0,
        localCount: local.length,
        mergedCount: local.length,
        didRun: false,
      );
    }
    final snapshot = await _firestore
        .collection('construction_companies')
        .get();
    final remote = snapshot.docs
        .map((doc) {
          final data = _sanitizeForJson(Map<String, dynamic>.from(doc.data()));
          data['id'] = (data['id'] ?? doc.id).toString();
          data['docId'] = doc.id;
          data['place_type'] = 'construction';
          data['marker_kind'] = 'construction';
          return data;
        })
        .toList(growable: false);
    final localWorkedHereMinCounts = _readLocalWorkedHereMinCountsForKey(
      prefs,
      _constructionWorkedHereMinCountsKey,
    );
    final merged = _applyLocalWorkedHereMinCounts(
      _dedupeConstructionRows([...local, ...remote]),
      localWorkedHereMinCounts,
    );
    await replaceLocalConstructionCompanies(merged);
    await prefs.setString(
      _constructionFirebaseLastSyncKey,
      DateTime.now().toUtc().toIso8601String(),
    );
    return ConstructionFirebaseSyncResult(
      remoteCount: remote.length,
      localCount: local.length,
      mergedCount: merged.length,
      didRun: true,
    );
  }

  static Future<void> updateConstructionWorkedHereCache(
    String docId,
    int delta,
  ) async {
    if (docId.trim().isEmpty || delta == 0) return;
    final store = ConstructionSqliteStore.instance;
    await store.init();
    await store.updateWorkedHereCount(docId, delta);

    final source = _memoryConstructionCompanies ?? await store.getAll();
    final updated = _updatedWorkedHereList(source, docId, delta);
    if (updated != null) _memoryConstructionCompanies = updated;
  }

  static Future<void> rememberLocalConstructionWorkedHereCount(
    String docId,
    int minCount,
  ) async {
    if (docId.trim().isEmpty || minCount < 0) return;
    final prefs = await SharedPreferences.getInstance();
    final counts = _readLocalWorkedHereMinCountsForKey(
      prefs,
      _constructionWorkedHereMinCountsKey,
    );
    final current = counts[docId] ?? 0;
    if (minCount <= current) return;
    counts[docId] = minCount;
    await prefs.setString(
      _constructionWorkedHereMinCountsKey,
      jsonEncode(counts),
    );
    if (_memoryConstructionCompanies != null) {
      _memoryConstructionCompanies = _applyLocalWorkedHereMinCounts(
        _memoryConstructionCompanies!,
        counts,
      );
    }
  }

  static Future<void> setLocalConstructionWorkedHereCount(
    String docId,
    int count,
  ) async {
    await _setLocalWorkedHereCountForKey(
      docId,
      count,
      key: _constructionWorkedHereMinCountsKey,
    );
  }

  static Future<void> deleteConstructionCompaniesFromFirebase(
    Iterable<String> docIds,
  ) async {
    final ids = docIds.where((id) => id.trim().isNotEmpty).toList();
    for (var offset = 0; offset < ids.length; offset += 400) {
      final batch = _firestore.batch();
      for (final id in ids.skip(offset).take(400)) {
        batch.delete(_firestore.collection('construction_companies').doc(id));
      }
      await batch.commit();
    }
  }

  static List<Map<String, dynamic>> _dedupeConstructionRows(
    List<Map<String, dynamic>> rows,
  ) {
    final merged = <Map<String, dynamic>>[];
    final indexByKey = <String, int>{};
    for (final raw in rows) {
      final row = _normalizeConstructionCompanyRow(raw);
      if (row.isEmpty) continue;
      final key = _constructionDedupeKey(row);
      if (key.isEmpty) continue;
      final existingIndex = indexByKey[key];
      if (existingIndex == null) {
        indexByKey[key] = merged.length;
        merged.add(row);
      } else {
        merged[existingIndex] = {...merged[existingIndex], ...row};
      }
    }
    return merged;
  }

  static Map<String, dynamic> _normalizeConstructionCompanyRow(
    Map<String, dynamic> data,
  ) {
    final id = (data['docId'] ?? data['id'] ?? data['source_place_id'] ?? '')
        .toString()
        .trim();
    if (id.isEmpty) return <String, dynamic>{};
    data['id'] = id;
    data['docId'] = id;
    data['place_type'] = 'construction';
    data['marker_kind'] = 'construction';
    data['source'] ??= 'osm';
    final classification = ConstructionCategory.classifyRowDetailed(data);
    final corroboratedEmployer =
        (data['entity_kind'] ?? '').toString() == 'employer' &&
        ConstructionDomainRecords.hasCorroboratedHiringLink(data);
    if (corroboratedEmployer) {
      data['construction_category'] ??= ConstructionCategory.miningCompany.id;
      data['construction_category_label'] ??=
          ConstructionCategory.miningCompany.label;
      data['entity_kind'] = 'employer';
      final storedConfidence =
          int.tryParse((data['classification_confidence'] ?? '').toString()) ??
          0;
      data['classification_confidence'] = storedConfidence < 95
          ? 95
          : storedConfidence;
      data['classification_reason'] ??=
          'Employer linked to a corroborated operator or contractor worksite';
    } else {
      data['construction_category'] = classification.category.id;
      data['construction_category_label'] = classification.category.label;
      data['entity_kind'] = classification.entityKindId;
      data['classification_confidence'] = classification.confidence;
      data['classification_reason'] = classification.reason;
    }
    data['classification_source'] ??= 'osm_tags';
    data['review_status'] =
        corroboratedEmployer ||
            (classification.isEmployer && classification.confidence >= 70)
        ? 'ready_for_map'
        : 'needs_review';
    final website = (data['website'] ?? '').toString().trim();
    if (_isOpenStreetMapUrl(website)) {
      data['osm_url'] = (data['osm_url'] ?? website).toString();
      data['website'] = '';
    }
    ConstructionApplicationContactClassifier.applyDerivedFields(data);
    return data;
  }

  static bool _isOpenStreetMapUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    final host = uri?.host.toLowerCase() ?? '';
    return host == 'openstreetmap.org' || host.endsWith('.openstreetmap.org');
  }

  static String _constructionDedupeKey(Map<String, dynamic> data) {
    final sourceId = (data['source_place_id'] ?? '').toString().trim();
    if (sourceId.isNotEmpty) return sourceId;
    return (data['docId'] ?? data['id'] ?? '').toString().trim();
  }

  static Future<List<Map<String, dynamic>>> loadRestaurants({
    required bool fromServer,
    bool lightweight = false,
  }) async {
    if (fromServer) {
      debugPrint(
        'ℹ️ loadRestaurants(fromServer: true) ignored: local SQLite mode',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    final sqliteStore = RestaurantSqliteStore.instance;
    await sqliteStore.init();
    final cachedJson = prefs.getString(_cacheKeyJson);
    final cacheSynced = prefs.getBool(_cacheKeySynced) ?? false;
    final cachedAppVersion = prefs.getString(_cacheKeyAppVersion);
    final localWorkedHereMinCounts = _readLocalWorkedHereMinCounts(prefs);
    final currentAppVersion = await _readCurrentAppVersion();
    final needsVersionRefresh =
        currentAppVersion != null && cachedAppVersion != currentAppVersion;

    final canUseMemoryCache = lightweight
        ? _memoryMapRestaurants != null &&
              _memoryMapCacheVersion == currentAppVersion &&
              !needsVersionRefresh
        : _memoryRestaurants != null &&
              _memoryCacheVersion == currentAppVersion &&
              !needsVersionRefresh;
    if (canUseMemoryCache) {
      return lightweight
          ? _applyLocalWorkedHereMinCounts(
              _memoryMapRestaurants!,
              localWorkedHereMinCounts,
            )
          : _memoryRestaurants!;
    }

    final canUsePersistentCache =
        cacheSynced &&
        cachedJson != null &&
        cachedJson.isNotEmpty &&
        !needsVersionRefresh;

    if (needsVersionRefresh) {
      await _refreshRestaurantsFromBundledSeed(
        prefs,
        sqliteStore,
        currentAppVersion: currentAppVersion,
        localWorkedHereMinCounts: localWorkedHereMinCounts,
      );
    }

    try {
      final sqliteRestaurants = lightweight
          ? await sqliteStore.getAllForMap()
          : await sqliteStore.getAll();
      if (sqliteRestaurants.isNotEmpty) {
        if (lightweight) {
          _primeMapMemoryCache(
            _applyLocalWorkedHereMinCounts(
              sqliteRestaurants,
              localWorkedHereMinCounts,
            ),
            appVersion: currentAppVersion ?? cachedAppVersion,
          );
        } else {
          _primeMemoryCache(
            sqliteRestaurants,
            synced: true,
            appVersion: currentAppVersion ?? cachedAppVersion,
          );
          _primeMapMemoryCache(
            _applyLocalWorkedHereMinCounts(
              _toMapRestaurantList(sqliteRestaurants),
              localWorkedHereMinCounts,
            ),
            appVersion: currentAppVersion ?? cachedAppVersion,
          );
          if (!canUsePersistentCache || needsVersionRefresh) {
            await _persistRestaurantsCache(
              prefs,
              sqliteRestaurants,
              appVersion: currentAppVersion,
            );
          }
        }
        debugPrint(
          '🗄️ SQLITE restaurants loaded${lightweight ? ' (lightweight)' : ''}: ${sqliteRestaurants.length}',
        );
        return sqliteRestaurants;
      }

      if (!OfflineState.instance.isFirstLaunchDone) {
        await OfflineBootstrapService.instance.init();
        final bootstrapRestaurants = lightweight
            ? await sqliteStore.getAllForMap()
            : await sqliteStore.getAll();
        if (bootstrapRestaurants.isNotEmpty) {
          if (lightweight) {
            _primeMapMemoryCache(
              _applyLocalWorkedHereMinCounts(
                bootstrapRestaurants,
                localWorkedHereMinCounts,
              ),
              appVersion: currentAppVersion ?? cachedAppVersion,
            );
          } else {
            _primeMemoryCache(
              bootstrapRestaurants,
              synced: true,
              appVersion: currentAppVersion ?? cachedAppVersion,
            );
            _primeMapMemoryCache(
              _applyLocalWorkedHereMinCounts(
                _toMapRestaurantList(bootstrapRestaurants),
                localWorkedHereMinCounts,
              ),
              appVersion: currentAppVersion ?? cachedAppVersion,
            );
            if (!canUsePersistentCache || needsVersionRefresh) {
              await _persistRestaurantsCache(
                prefs,
                bootstrapRestaurants,
                appVersion: currentAppVersion,
              );
            }
          }
          debugPrint(
            '🗄️ SQLITE restaurants loaded after bootstrap${lightweight ? ' (lightweight)' : ''}: ${bootstrapRestaurants.length}',
          );
          return bootstrapRestaurants;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error loading restaurants from SQLite: $e');
    }
    if (canUsePersistentCache) {
      try {
        final cachedList = _decodeCachedList(cachedJson);
        await sqliteStore.replaceAll(cachedList);
        final mapList = _toMapRestaurantList(cachedList);
        _primeMemoryCache(
          cachedList,
          synced: true,
          appVersion: cachedAppVersion,
        );
        _primeMapMemoryCache(
          _applyLocalWorkedHereMinCounts(mapList, localWorkedHereMinCounts),
          appVersion: cachedAppVersion,
        );
        debugPrint(
          '📦 CACHE restaurants loaded${lightweight ? ' (lightweight)' : ''}: ${lightweight ? mapList.length : cachedList.length}',
        );
        return lightweight
            ? _applyLocalWorkedHereMinCounts(mapList, localWorkedHereMinCounts)
            : cachedList;
      } catch (e) {
        debugPrint('⚠️ Error decoding restaurant cache: $e');
      }
    }

    if (cachedJson != null && cachedJson.isNotEmpty) {
      try {
        final cachedList = _decodeCachedList(cachedJson);
        final mapList = _toMapRestaurantList(cachedList);
        _primeMemoryCache(
          cachedList,
          synced: cacheSynced,
          appVersion: cachedAppVersion,
        );
        _primeMapMemoryCache(
          _applyLocalWorkedHereMinCounts(mapList, localWorkedHereMinCounts),
          appVersion: cachedAppVersion,
        );
        debugPrint(
          '📦 Using stale restaurants cache after SQLite miss${lightweight ? ' (lightweight)' : ''}: ${lightweight ? mapList.length : cachedList.length}',
        );
        return lightweight
            ? _applyLocalWorkedHereMinCounts(mapList, localWorkedHereMinCounts)
            : cachedList;
      } catch (cacheError) {
        debugPrint('⚠️ Error decoding stale restaurant cache: $cacheError');
      }
    }

    debugPrint('⚠️ No local restaurants found in SQLite or cache');
    return const <Map<String, dynamic>>[];
  }

  static Future<void> updateWorkedHereCache(String docId, int delta) async {
    if (docId.trim().isEmpty || delta == 0) return;
    final sqliteStore = RestaurantSqliteStore.instance;
    await sqliteStore.init();
    await sqliteStore.updateWorkedHereCount(docId, delta);

    final prefs = await SharedPreferences.getInstance();
    final localWorkedHereMinCounts = _readLocalWorkedHereMinCounts(prefs);
    final cachedJson = prefs.getString(_cacheKeyJson);
    final sourceList = _memoryRestaurants != null
        ? _memoryRestaurants!
        : (cachedJson != null && cachedJson.isNotEmpty)
        ? _decodeCachedList(cachedJson)
        : null;
    final effectiveSourceList = sourceList ?? await sqliteStore.getAll();
    if (effectiveSourceList.isEmpty) return;

    final updatedList = _updatedWorkedHereList(
      effectiveSourceList,
      docId,
      delta,
    );
    if (updatedList == null) return;

    await _persistRestaurantsCache(
      prefs,
      updatedList,
      appVersion: _memoryCacheVersion ?? prefs.getString(_cacheKeyAppVersion),
      localWorkedHereMinCounts: localWorkedHereMinCounts,
    );
  }

  static Future<void> rememberLocalWorkedHereCount(
    String docId,
    int minCount,
  ) async {
    if (docId.trim().isEmpty || minCount < 0) return;
    final prefs = await SharedPreferences.getInstance();
    final counts = _readLocalWorkedHereMinCounts(prefs);
    final current = counts[docId] ?? 0;
    if (minCount <= current) return;
    counts[docId] = minCount;
    await prefs.setString(_localWorkedHereMinCountsKey, jsonEncode(counts));

    if (_memoryMapRestaurants != null) {
      _memoryMapRestaurants = _applyLocalWorkedHereMinCounts(
        _memoryMapRestaurants!,
        counts,
      );
    }
  }

  static Future<void> setLocalWorkedHereCount(String docId, int count) async {
    await _setLocalWorkedHereCountForKey(
      docId,
      count,
      key: _localWorkedHereMinCountsKey,
    );
  }

  static Future<void> _setLocalWorkedHereCountForKey(
    String docId,
    int count, {
    required String key,
  }) async {
    if (docId.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final counts = _readLocalWorkedHereMinCountsForKey(prefs, key);
    final normalized = math.max(0, count);
    if (normalized == 0) {
      counts.remove(docId);
    } else {
      counts[docId] = normalized;
    }
    await prefs.setString(key, jsonEncode(counts));
  }

  static Future<void> replaceLocalRestaurants(
    List<Map<String, dynamic>> restaurants,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await _persistRestaurantsCache(
      prefs,
      restaurants,
      appVersion: await _readCurrentAppVersion(),
    );
  }

  static Future<void> _refreshRestaurantsFromBundledSeed(
    SharedPreferences prefs,
    RestaurantSqliteStore store, {
    required String? currentAppVersion,
    required Map<String, int> localWorkedHereMinCounts,
  }) async {
    try {
      final seedRestaurants = await store.loadSeedAssetRestaurants();
      if (seedRestaurants.isEmpty) {
        debugPrint('⚠️ Bundled restaurants seed is empty; keeping local data');
        return;
      }

      await _persistRestaurantsCache(
        prefs,
        seedRestaurants,
        appVersion: currentAppVersion,
        localWorkedHereMinCounts: localWorkedHereMinCounts,
      );
      debugPrint(
        '📦 Bundled restaurants refreshed for app version $currentAppVersion: ${seedRestaurants.length}',
      );
    } catch (e) {
      debugPrint('⚠️ Bundled restaurants refresh skipped: $e');
    }
  }

  static Future<RestaurantsFirebaseSyncResult>
  syncRestaurantsFromFirebaseIfNeeded({bool force = false}) async {
    if (!force) {
      final store = RestaurantSqliteStore.instance;
      await store.init();
      final localCount = await store.count();
      return RestaurantsFirebaseSyncResult(
        remoteCount: 0,
        localCount: localCount,
        mergedCount: localCount,
        didRun: false,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final currentAppVersion = await _readCurrentAppVersion();
    final store = RestaurantSqliteStore.instance;
    await store.init();
    if (!await store.hasData) {
      await OfflineBootstrapService.instance.init();
    }

    final localRestaurants = await store.getAll();
    final remoteRestaurants = await _loadRestaurantsFromFirebase();
    final merged = mergeRestaurantLists(
      localRestaurants,
      remoteRestaurants,
      incomingWins: true,
    );

    await _persistRestaurantsCache(
      prefs,
      merged,
      appVersion: currentAppVersion,
    );

    debugPrint(
      '☁️ Restaurants Firebase sync: remote ${remoteRestaurants.length}, local ${localRestaurants.length}, merged ${merged.length}',
    );

    return RestaurantsFirebaseSyncResult(
      remoteCount: remoteRestaurants.length,
      localCount: localRestaurants.length,
      mergedCount: merged.length,
      didRun: true,
    );
  }

  static Future<void> upsertRestaurantsToFirebase(
    List<Map<String, dynamic>> restaurants,
  ) async {
    final rows = restaurants
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => _firebaseDocIdForRestaurant(item).isNotEmpty)
        .toList(growable: false);
    if (rows.isEmpty) return;

    for (var start = 0; start < rows.length; start += 450) {
      final end = math.min(start + 450, rows.length);
      final batch = _firestore.batch();
      for (final row in rows.sublist(start, end)) {
        final docId = _firebaseDocIdForRestaurant(row);
        if (docId.isEmpty) continue;
        final data = _sanitizeForJson(row);
        data.removeWhere(
          (key, value) =>
              value is String &&
              value.trim().isEmpty &&
              key != 'id' &&
              key != 'docId',
        );
        data['id'] = docId;
        data['docId'] = docId;
        data['updated_at'] = FieldValue.serverTimestamp();
        data['synced_from'] = (data['source'] ?? '').toString().isEmpty
            ? 'app'
            : data['source'];
        batch.set(
          _firestore.collection('restaurants').doc(docId),
          data,
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    }
  }

  static Future<List<Map<String, dynamic>>>
  _loadRestaurantsFromFirebase() async {
    final snapshot = await _firestore.collection('restaurants').get();
    return snapshot.docs
        .map((doc) {
          final data = Map<String, dynamic>.from(doc.data());
          data['id'] = (data['id'] ?? doc.id).toString();
          data['docId'] = doc.id;
          return _sanitizeForJson(data);
        })
        .toList(growable: false);
  }

  static List<Map<String, dynamic>> mergeRestaurantLists(
    List<Map<String, dynamic>> base,
    List<Map<String, dynamic>> incoming, {
    bool incomingWins = false,
  }) {
    final merged = base
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => _localIdForRestaurant(item).isNotEmpty)
        .toList(growable: true);
    final indexById = <String, int>{};
    final indexBySource = <String, int>{};

    for (var i = 0; i < merged.length; i++) {
      final id = _localIdForRestaurant(merged[i]);
      if (id.isNotEmpty) indexById[id] = i;
      final sourceId = (merged[i]['source_place_id'] ?? '').toString();
      if (sourceId.isNotEmpty) indexBySource[sourceId] = i;
    }

    for (final row in incoming) {
      final normalized = Map<String, dynamic>.from(row);
      final incomingId = _localIdForRestaurant(normalized);
      if (incomingId.isNotEmpty) {
        normalized['id'] = incomingId;
        normalized['docId'] = incomingId;
      }
      final sourceId = (normalized['source_place_id'] ?? '').toString();
      final existingIndex =
          (sourceId.isNotEmpty ? indexBySource[sourceId] : null) ??
          (incomingId.isNotEmpty ? indexById[incomingId] : null) ??
          _findNearbyDuplicateIndex(merged, normalized);

      if (existingIndex != null) {
        merged[existingIndex] = _mergeRestaurantRecord(
          merged[existingIndex],
          normalized,
          incomingWins: incomingWins,
        );
        final mergedId = _localIdForRestaurant(merged[existingIndex]);
        if (mergedId.isNotEmpty) indexById[mergedId] = existingIndex;
        final mergedSourceId = (merged[existingIndex]['source_place_id'] ?? '')
            .toString();
        if (mergedSourceId.isNotEmpty) {
          indexBySource[mergedSourceId] = existingIndex;
        }
        continue;
      }

      if (incomingId.isEmpty) continue;
      final nextIndex = merged.length;
      merged.add(normalized);
      indexById[incomingId] = nextIndex;
      if (sourceId.isNotEmpty) indexBySource[sourceId] = nextIndex;
    }

    return merged;
  }

  static List<Map<String, dynamic>> _decodeCachedList(String cachedJson) {
    final decoded = jsonDecode(cachedJson) as List<dynamic>;
    return decoded
        .whereType<Map<String, dynamic>>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  static Set<Marker> buildMarkers(
    List<Map<String, dynamic>> docs,
    Function(Map<String, dynamic>) onTap,
  ) {
    return docs
        .map((data) {
          final double? lat = (data['latitude'] ?? data['lat'])?.toDouble();
          final double? lng = (data['longitude'] ?? data['lng'])?.toDouble();
          if (lat == null || lng == null) return null;
          final docId = data['docId']?.toString() ?? '';
          if (docId.isEmpty) return null;
          return Marker(
            markerId: MarkerId(docId),
            position: LatLng(lat, lng),
            infoWindow: const InfoWindow(title: ''),
            onTap: () => onTap(data),
          );
        })
        .whereType<Marker>()
        .toSet();
  }

  // 🔹 Incrementa el comptador "worked_here_count"
  static Future<void> incrementWorkedHere(String docId) async {
    if (docId.trim().isEmpty) {
      throw ArgumentError('Document ID is empty or invalid');
    }
    await _firestore.collection('restaurants').doc(docId).set({
      'worked_here_count': FieldValue.increment(1),
      'worked_here_updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> incrementConstructionWorkedHere(String docId) async {
    if (docId.trim().isEmpty) {
      throw ArgumentError('Document ID is empty or invalid');
    }
    await _firestore.collection('construction_companies').doc(docId).set({
      'worked_here_count': FieldValue.increment(1),
      'worked_here_updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // 🔹 Redueix el comptador "worked_here_count" si algú vol treure-ho
  static Future<void> decrementWorkedHere(String docId) async {
    if (docId.trim().isEmpty) {
      throw ArgumentError('Document ID is empty or invalid');
    }
    await _decrementWorkedHereInCollection('restaurants', docId);
  }

  static Future<void> decrementConstructionWorkedHere(String docId) async {
    if (docId.trim().isEmpty) {
      throw ArgumentError('Document ID is empty or invalid');
    }
    await _decrementWorkedHereInCollection('construction_companies', docId);
  }

  static Future<void> _decrementWorkedHereInCollection(
    String collection,
    String docId,
  ) async {
    final reference = _firestore.collection(collection).doc(docId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      final current = snapshot.exists
          ? _asInt(snapshot.data()?['worked_here_count'])
          : 0;
      transaction.set(reference, {
        'worked_here_count': math.max(0, current - 1),
        'worked_here_updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  // 🔹 Inicialitza el camp "worked_here_count" si no existeix
  static Future<void> ensureWorkedHereField() async {
    debugPrint('ℹ️ ensureWorkedHereField skipped: local SQLite mode');
  }

  static Future<void> _persistRestaurantsCache(
    SharedPreferences prefs,
    List<Map<String, dynamic>> restaurants, {
    String? appVersion,
    Map<String, int>? localWorkedHereMinCounts,
  }) async {
    _primeMemoryCache(restaurants, synced: true, appVersion: appVersion);
    final localCounts =
        localWorkedHereMinCounts ?? _readLocalWorkedHereMinCounts(prefs);
    _primeMapMemoryCache(
      _applyLocalWorkedHereMinCounts(
        _toMapRestaurantList(restaurants),
        localCounts,
      ),
      appVersion: appVersion,
    );
    try {
      final sqliteStore = RestaurantSqliteStore.instance;
      await sqliteStore.init();
      await sqliteStore.replaceAll(restaurants);
      final sanitized = restaurants.map(_sanitizeForJson).toList();
      final jsonStr = jsonEncode(sanitized);
      await prefs.setString(_cacheKeyJson, jsonStr);
      await prefs.setBool(_cacheKeySynced, true);
      if (appVersion != null && appVersion.isNotEmpty) {
        await prefs.setString(_cacheKeyAppVersion, appVersion);
      }
    } catch (e) {
      debugPrint('⚠️ Error caching restaurants: $e');
    }
  }

  static void _primeMemoryCache(
    List<Map<String, dynamic>> restaurants, {
    required bool synced,
    required String? appVersion,
  }) {
    _memoryRestaurants = restaurants
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    _memoryCacheVersion = appVersion;
  }

  static void _primeMapMemoryCache(
    List<Map<String, dynamic>> restaurants, {
    required String? appVersion,
  }) {
    _memoryMapRestaurants = restaurants
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    _memoryMapCacheVersion = appVersion;
  }

  static List<Map<String, dynamic>> _toMapRestaurantList(
    List<Map<String, dynamic>> restaurants,
  ) {
    return restaurants
        .map(
          (restaurant) => <String, dynamic>{
            'id': (restaurant['docId'] ?? restaurant['id'] ?? '').toString(),
            'docId': (restaurant['docId'] ?? restaurant['id'] ?? '').toString(),
            'name': (restaurant['name'] ?? '').toString(),
            'address': (restaurant['address'] ?? '').toString(),
            'postcode': (restaurant['postcode'] ?? '').toString(),
            'postcode_display': (restaurant['postcode_display'] ?? '')
                .toString(),
            'state': (restaurant['state'] ?? '').toString(),
            'latitude': _asDouble(restaurant['latitude'] ?? restaurant['lat']),
            'longitude': _asDouble(
              restaurant['longitude'] ?? restaurant['lng'],
            ),
            'lat': _asDouble(restaurant['latitude'] ?? restaurant['lat']),
            'lng': _asDouble(restaurant['longitude'] ?? restaurant['lng']),
            'phone': (restaurant['phone'] ?? '').toString(),
            'email': (restaurant['email'] ?? '').toString(),
            'facebook_url': (restaurant['facebook_url'] ?? '').toString(),
            'instagram_url': (restaurant['instagram_url'] ?? '').toString(),
            'careers_page': (restaurant['careers_page'] ?? '').toString(),
            'website': (restaurant['website'] ?? '').toString(),
            'source_place_id': (restaurant['source_place_id'] ?? '').toString(),
            'blocked':
                restaurant['blocked'] == true ||
                _asInt(restaurant['blocked']) > 0,
            'worked_here_count': _asInt(restaurant['worked_here_count']),
            'timestamp': restaurant['timestamp']?.toString() ?? '',
          },
        )
        .where(
          (restaurant) => (restaurant['docId'] ?? '').toString().isNotEmpty,
        )
        .toList(growable: false);
  }

  static List<Map<String, dynamic>> _applyLocalWorkedHereMinCounts(
    List<Map<String, dynamic>> restaurants,
    Map<String, int> localWorkedHereMinCounts,
  ) {
    if (localWorkedHereMinCounts.isEmpty) {
      return restaurants
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    }

    return restaurants
        .map((restaurant) {
          final next = Map<String, dynamic>.from(restaurant);
          final docId = (next['docId'] ?? next['id'] ?? '').toString();
          final minCount = localWorkedHereMinCounts[docId];
          if (minCount != null) {
            next['worked_here_count'] = math.max(
              _asInt(next['worked_here_count']),
              minCount,
            );
          }
          return next;
        })
        .toList(growable: false);
  }

  static List<Map<String, dynamic>>? _updatedWorkedHereList(
    List<Map<String, dynamic>>? sourceList,
    String docId,
    int delta,
  ) {
    if (sourceList == null || sourceList.isEmpty) {
      return null;
    }

    var updated = false;
    final updatedList = sourceList
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);

    for (final restaurant in updatedList) {
      final candidateId = (restaurant['docId'] ?? restaurant['id'] ?? '')
          .toString();
      if (candidateId != docId) continue;
      restaurant['worked_here_count'] = math.max(
        0,
        _asInt(restaurant['worked_here_count']) + delta,
      );
      updated = true;
      break;
    }

    return updated ? updatedList : null;
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double? _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static Map<String, int> _readLocalWorkedHereMinCounts(
    SharedPreferences prefs,
  ) {
    return _readLocalWorkedHereMinCountsForKey(
      prefs,
      _localWorkedHereMinCountsKey,
    );
  }

  static Map<String, int> _readLocalWorkedHereMinCountsForKey(
    SharedPreferences prefs,
    String key,
  ) {
    final raw = prefs.getString(key);
    if (raw == null || raw.trim().isEmpty) {
      return <String, int>{};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return <String, int>{};
      }
      final result = <String, int>{};
      decoded.forEach((key, value) {
        final docId = key.toString().trim();
        if (docId.isEmpty) return;
        result[docId] = _asInt(value);
      });
      return result;
    } catch (_) {
      return <String, int>{};
    }
  }

  static String _firebaseDocIdForRestaurant(Map<String, dynamic> restaurant) {
    final preferred = _localIdForRestaurant(restaurant);
    final raw = preferred.isNotEmpty
        ? preferred
        : (restaurant['name'] ?? '').toString();
    return raw
        .trim()
        .replaceAll(RegExp(r'[\/.#\$\[\]]'), '-')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_{2,}'), '_');
  }

  static String _localIdForRestaurant(Map<String, dynamic> restaurant) {
    return (restaurant['docId'] ?? restaurant['id'] ?? '').toString().trim();
  }

  static Map<String, dynamic> _mergeRestaurantRecord(
    Map<String, dynamic> existing,
    Map<String, dynamic> incoming, {
    required bool incomingWins,
  }) {
    final merged = Map<String, dynamic>.from(existing);
    incoming.forEach((key, value) {
      if (key == 'id' || key == 'docId') {
        if (_localIdForRestaurant(merged).isEmpty && _isUsefulValue(value)) {
          merged[key] = value;
        }
        return;
      }

      if (key == 'worked_here_count') {
        merged[key] = math.max(_asInt(merged[key]), _asInt(value));
        return;
      }

      final current = merged[key];
      final incomingIsUseful = _isUsefulValue(value);
      if (!incomingIsUseful) return;

      final currentIsEmpty = !_isUsefulValue(current);
      final shouldReplace =
          incomingWins ||
          currentIsEmpty ||
          _shouldReplaceWeakValue(key, current);
      if (shouldReplace) {
        merged[key] = value;
      }
    });

    final id = _localIdForRestaurant(merged);
    if (id.isNotEmpty) {
      merged['id'] = id;
      merged['docId'] = id;
    }
    return merged;
  }

  static bool _isUsefulValue(dynamic value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is Iterable) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }

  static bool _shouldReplaceWeakValue(String key, dynamic current) {
    if (key != 'website' || current is! String) return false;
    final lower = current.toLowerCase();
    return lower.contains('facebook.com') ||
        lower.contains('instagram.com') ||
        lower.contains('tripadvisor.') ||
        lower.contains('ubereats.') ||
        lower.contains('doordash.') ||
        lower.contains('menulog.') ||
        lower.contains('yellowpages.') ||
        lower.contains('restaurantguru.');
  }

  static int? _findNearbyDuplicateIndex(
    List<Map<String, dynamic>> existing,
    Map<String, dynamic> candidate,
  ) {
    final candidateName = _normalizeRestaurantName(candidate['name']);
    final candidatePostcode =
        (candidate['postcode_display'] ?? candidate['postcode'] ?? '')
            .toString()
            .padLeft(4, '0');
    final candidateLat = _asDouble(candidate['latitude'] ?? candidate['lat']);
    final candidateLng = _asDouble(candidate['longitude'] ?? candidate['lng']);
    if (candidateName.isEmpty || candidateLat == null || candidateLng == null) {
      return null;
    }

    for (var index = 0; index < existing.length; index++) {
      final row = existing[index];
      if (_normalizeRestaurantName(row['name']) != candidateName) continue;
      final rowPostcode = (row['postcode_display'] ?? row['postcode'] ?? '')
          .toString()
          .padLeft(4, '0');
      if (rowPostcode != candidatePostcode) continue;
      final rowLat = _asDouble(row['latitude'] ?? row['lat']);
      final rowLng = _asDouble(row['longitude'] ?? row['lng']);
      if (rowLat == null || rowLng == null) continue;
      if (_distanceMeters(candidateLat, candidateLng, rowLat, rowLng) <= 120) {
        return index;
      }
    }
    return null;
  }

  static String _normalizeRestaurantName(dynamic name) {
    return name.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static double _distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusMeters = 6371000.0;
    final latDelta = (lat2 - lat1) * math.pi / 180;
    final lngDelta = (lng2 - lng1) * math.pi / 180;
    final a =
        math.sin(latDelta / 2) * math.sin(latDelta / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(lngDelta / 2) *
            math.sin(lngDelta / 2);
    return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static Future<String?> _readCurrentAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      final build = info.buildNumber.trim();
      if (version.isEmpty && build.isEmpty) return null;
      if (build.isEmpty) return version;
      if (version.isEmpty) return build;
      return '$version+$build';
    } catch (e) {
      debugPrint('⚠️ Error reading app version for restaurants cache: $e');
      return null;
    }
  }

  static Map<String, dynamic> _sanitizeForJson(Map<String, dynamic> src) {
    final out = <String, dynamic>{};
    src.forEach((key, value) {
      out[key] = _convertValue(value);
    });
    return out;
  }

  static dynamic _convertValue(dynamic value) {
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    if (value is GeoPoint) {
      return {'lat': value.latitude, 'lng': value.longitude};
    }
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _convertValue(v)));
    }
    if (value is Iterable) {
      return value.map(_convertValue).toList();
    }
    return value;
  }
}
