import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/construction_domain_records.dart';
import 'construction_generic_source_reader.dart';
import 'construction_government_source_discovery.dart';
import 'construction_pending_publish_service.dart';
import 'construction_source_inspector.dart';
import 'construction_source_models.dart';
import 'construction_sqlite_store.dart';
import 'construction_state_builder_store.dart';
import 'map_markers_service.dart';

typedef ConstructionStageCallback =
    Future<void> Function(ConstructionBuildControl control);
typedef ConstructionBuildProgress =
    void Function(ConstructionBuildStage stage, String message);

class ConstructionStateBuilderService {
  ConstructionStateBuilderService({
    ConstructionStateBuilderStore? book,
    ConstructionGenericSourceReader? reader,
    ConstructionGovernmentSourceDiscovery? discovery,
  }) : _book = book ?? ConstructionStateBuilderStore.instance,
       _reader = reader ?? ConstructionGenericSourceReader(),
       _discovery = discovery ?? ConstructionGovernmentSourceDiscovery();

  final ConstructionStateBuilderStore _book;
  final ConstructionGenericSourceReader _reader;
  final ConstructionGovernmentSourceDiscovery _discovery;
  final ConstructionSourceInspector _inspector = ConstructionSourceInspector();

  Future<ConstructionBuildReport> buildOrUpdate({
    required String state,
    required ConstructionBuildControl control,
    required ConstructionStageCallback runSpecialAdapters,
    required ConstructionStageCallback enrichContacts,
    ConstructionBuildProgress? onProgress,
    bool forceDiscovery = false,
  }) async {
    final normalizedState = state.toUpperCase();
    final runId =
        'build_${normalizedState}_${DateTime.now().toUtc().toIso8601String()}';
    final store = ConstructionSqliteStore.instance;
    await store.init();
    final beforeRows = await _stateRows(store, normalizedState);
    final before = _metrics(beforeRows);
    final pendingBefore = await ConstructionPendingPublishService.instance
        .getPendingIds();
    final ids = beforeRows
        .map((r) => (r['id'] ?? r['docId'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();
    final errors = <String>[];
    var ready = 0;
    var review = 0;

    Future<bool> begin(
      ConstructionBuildStage stage,
      String message, {
      String target = '',
    }) async {
      await _book.queueStage(runId, normalizedState, stage, targetId: target);
      if (control.isCancelled) {
        await _book.setJobStatus(runId, stage, 'cancelled', targetId: target);
        return false;
      }
      await _book.setJobStatus(runId, stage, 'running', targetId: target);
      onProgress?.call(stage, message);
      return true;
    }

    try {
      if (!await begin(
        ConstructionBuildStage.snapshot,
        'Saving a safety snapshot…',
      )) {
        throw const _Stopped();
      }
      await _book.snapshot(runId, normalizedState, before, ids);
      await _book.setJobStatus(
        runId,
        ConstructionBuildStage.snapshot,
        'completed',
      );

      if (!await begin(
        ConstructionBuildStage.discoverSources,
        'Checking the official source instruction book…',
      )) {
        throw const _Stopped();
      }
      for (final source in _discovery.builtInSources(normalizedState)) {
        await _book.saveInstruction(source);
      }
      var sources = await _book.sourcesFor(normalizedState);
      if (forceDiscovery ||
          sources.where((s) => s.state == normalizedState).isEmpty ||
          sources.any((s) => s.status == ConstructionSourceState.broken)) {
        for (final candidate in await _discovery.discover(normalizedState)) {
          await _book.saveInstruction(candidate);
        }
        sources = await _book.sourcesFor(normalizedState);
      }
      await _book.setJobStatus(
        runId,
        ConstructionBuildStage.discoverSources,
        'completed',
      );

      if (!await begin(
        ConstructionBuildStage.inspectSources,
        'Inspecting source samples and matching columns…',
      )) {
        throw const _Stopped();
      }
      final usable = <ConstructionSourceInstruction>[];
      for (var source in sources) {
        if (control.isCancelled) throw const _Stopped();
        if (source.format == ConstructionSourceFormat.special) {
          usable.add(source);
          ready++;
          continue;
        }
        try {
          final sample = await _reader.read(
            source,
            control: control,
            maxRecords: 25,
            timeout: const Duration(seconds: 30),
          );
          final inspection = _inspector.inspect(sample.records);
          final sourceState = inspection.confidence >= .66
              ? ConstructionSourceState.ready
              : ConstructionSourceState.needsReview;
          source = source.copyWith(
            mapping: inspection.mapping,
            status: sourceState,
            lastError: inspection.warnings.join(' '),
          );
          await _book.saveInstruction(source);
          if (sourceState == ConstructionSourceState.ready) {
            usable.add(source);
            ready++;
          } else {
            review++;
          }
        } catch (error) {
          errors.add('${source.title}: $error');
          await _book.saveInstruction(
            source.copyWith(
              status: ConstructionSourceState.broken,
              lastError: '$error',
            ),
          );
        }
      }
      await _book.setJobStatus(
        runId,
        ConstructionBuildStage.inspectSources,
        'completed',
      );

      if (!await begin(
        ConstructionBuildStage.importSources,
        'Importing official records…',
      )) {
        throw const _Stopped();
      }
      // Existing WA/NSW adapters remain authoritative where generic parsing is
      // not sufficient. They also import the national state-filtered layer.
      await runSpecialAdapters(control);
      for (final source in usable.where(
        (s) =>
            s.format != ConstructionSourceFormat.special &&
            s.id != 'ga_operating_mines',
      )) {
        if (control.isCancelled) throw const _Stopped();
        if (control.takeSkipSource()) {
          errors.add('${source.title}: skipped by admin');
          continue;
        }
        try {
          await _importGeneric(source, normalizedState, control);
        } catch (error) {
          errors.add('${source.title}: $error');
        }
      }
      await _book.setJobStatus(
        runId,
        ConstructionBuildStage.importSources,
        'completed',
      );

      if (!await begin(
        ConstructionBuildStage.corroborate,
        'Checking operator and contractor evidence…',
      )) {
        throw const _Stopped();
      }
      // Corroboration is performed while generic rows are created and by the
      // existing special adapters. Owner-only rows remain local and unlinked.
      await _book.setJobStatus(
        runId,
        ConstructionBuildStage.corroborate,
        'completed',
      );

      if (!await begin(
        ConstructionBuildStage.enrichContacts,
        'Finding and checking company application contacts…',
      )) {
        throw const _Stopped();
      }
      await enrichContacts(control);
      await _book.setJobStatus(
        runId,
        ConstructionBuildStage.enrichContacts,
        control.isCancelled ? 'cancelled' : 'completed',
      );
      if (control.isCancelled) throw const _Stopped();
    } on _Stopped {
      final after = _metrics(await _stateRows(store, normalizedState));
      final report = ConstructionBuildReport(
        runId: runId,
        state: normalizedState,
        status: 'stopped_saved',
        before: before,
        after: after,
        sourcesReady: ready,
        sourcesNeedingReview: review,
        errors: errors,
        publicationSafe: true,
      );
      await _book.saveReport(report);
      return report;
    } catch (error, stack) {
      debugPrint('Construction state build failed: $error\n$stack');
      errors.add('$error');
    }

    final after = _metrics(await _stateRows(store, normalizedState));
    final safe = _passesSafetyBrake(before, after);
    if (!safe) {
      final pendingAfter = await ConstructionPendingPublishService.instance
          .getPendingIds();
      // Keep the exact pre-run publication queue. Only proposed IDs added by
      // this unsafe run are removed; no source/contact record is deleted.
      await ConstructionPendingPublishService.instance.removePending(
        pendingAfter.difference(pendingBefore),
      );
      errors.add(
        'Safety brake: the result changed too sharply. Existing public data was preserved; review this run before publication.',
      );
    }
    final report = ConstructionBuildReport(
      runId: runId,
      state: normalizedState,
      status: errors.isEmpty
          ? 'completed'
          : (safe ? 'completed_with_warnings' : 'blocked_by_safety_brake'),
      before: before,
      after: after,
      sourcesReady: ready,
      sourcesNeedingReview: review,
      errors: errors,
      publicationSafe: safe,
    );
    await _book.saveReport(report);
    return report;
  }

  Future<void> _importGeneric(
    ConstructionSourceInstruction source,
    String state,
    ConstructionBuildControl control,
  ) async {
    final result = await _reader.read(source, control: control);
    // A skip requested while the network call was in flight takes effect
    // before any records from that source are written.
    if (control.takeSkipSource()) return;
    if (result.fingerprint == source.lastFingerprint) {
      return; // incremental: unchanged source
    }
    final existingByName = <String, List<Map<String, dynamic>>>{};
    for (final existing in await ConstructionSqliteStore.instance.getAll()) {
      if ((existing['state'] ?? '').toString().toUpperCase() != state ||
          !ConstructionDomainRecords.isWorksite(existing)) {
        continue;
      }
      final key = ConstructionDomainRecords.normalizeIdentity(
        (existing['worksite_name'] ?? existing['name'] ?? '').toString(),
      );
      if (key.isNotEmpty) (existingByName[key] ??= []).add(existing);
    }
    final rows = <Map<String, dynamic>>[];
    for (var i = 0; i < result.records.length; i++) {
      if (control.isCancelled) throw const _Stopped();
      final raw = result.records[i];
      final m = source.mapping;
      String value(String role) => (raw[m[role]] ?? '').toString().trim();
      final rowState = value('state').toUpperCase();
      if (rowState.isNotEmpty && rowState != state) continue;
      final name = value('worksite_name');
      if (name.isEmpty) continue;
      final operatorName = value('operator');
      final contractorName = value('contractor');
      final company = operatorName.isNotEmpty ? operatorName : contractorName;
      final role = operatorName.isNotEmpty
          ? 'operator'
          : (contractorName.isNotEmpty ? 'contractor' : '');
      final recordId = value('record_id').isNotEmpty
          ? value('record_id')
          : '$i:${name.hashCode}';
      final id = 'generic_${source.id.hashCode}_${recordId.hashCode}';
      final matches =
          existingByName[ConstructionDomainRecords.normalizeIdentity(name)] ??
          const <Map<String, dynamic>>[];
      Map<String, dynamic>? corroboratingMatch;
      for (final match in matches) {
        final matchSource = (match['source'] ?? '').toString();
        if (matchSource.isNotEmpty && matchSource != source.id) {
          corroboratingMatch = match;
          break;
        }
      }
      final matchedWorksiteId = corroboratingMatch == null
          ? ''
          : ConstructionDomainRecords.worksiteId(corroboratingMatch);
      final corroborated = role.isNotEmpty && matchedWorksiteId.isNotEmpty;
      rows.add({
        'id': id,
        'docId': id,
        'record_type': 'construction_worksite',
        'worksite_id': matchedWorksiteId.isEmpty
            ? 'worksite:$id'
            : matchedWorksiteId,
        'name': company.isEmpty ? name : company,
        'worksite_name': name,
        'state': state,
        'postcode': value('postcode'),
        'latitude': double.tryParse(value('latitude')),
        'longitude': double.tryParse(value('longitude')),
        'company_id': company.isEmpty
            ? ''
            : 'company:${ConstructionDomainRecords.normalizeIdentity(company)}',
        'company_worksite_role': role,
        'link_corroborated': corroborated,
        'company_worksite_evidence': role.isEmpty
            ? ''
            : corroborated
            ? '${source.publisher}: explicit $role field; matched a separate worksite source'
            : '${source.publisher}: explicit $role field; awaiting a second matching worksite source',
        'owner_name': value('owner'),
        'licence_holder_name': value('licence_holder'),
        'source': source.id,
        'source_url': source.catalogueUrl,
        'source_record_id': recordId,
        'source_license': source.license,
        'source_attribution': source.attribution,
        'source_raw_record': raw,
        'place_type': 'construction',
        'marker_kind': 'construction',
      });
    }
    if (rows.isNotEmpty) {
      await MapMarkersService.upsertLocalConstructionCompanies(rows);
    }
    await _book.saveInstruction(
      source.copyWith(
        lastFingerprint: result.fingerprint,
        status: ConstructionSourceState.ready,
        lastError: '',
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _stateRows(
    ConstructionSqliteStore store,
    String state,
  ) async => (await store.getAll())
      .where((r) => (r['state'] ?? '').toString().toUpperCase() == state)
      .toList();
  Map<String, int> _metrics(List<Map<String, dynamic>> rows) {
    final employers = <String>{}, worksites = <String>{}, linked = <String>{};
    for (final row in rows) {
      final c = ConstructionDomainRecords.companyId(row);
      if (c.isNotEmpty) employers.add(c);
      if (ConstructionDomainRecords.isWorksite(row)) {
        final w = ConstructionDomainRecords.worksiteId(row);
        if (w.isNotEmpty) {
          worksites.add(w);
          if (ConstructionDomainRecords.hasCorroboratedHiringLink(row)) {
            linked.add(w);
          }
        }
      }
    }
    return {
      'records': rows.length,
      'employers': employers.length,
      'worksites': worksites.length,
      'linked_worksites': linked.length,
    };
  }

  bool _passesSafetyBrake(Map<String, int> before, Map<String, int> after) {
    for (final key in const ['records', 'employers', 'worksites']) {
      final oldValue = before[key] ?? 0, newValue = after[key] ?? 0;
      if (oldValue >= 20 && newValue < oldValue * .65) return false;
      if (oldValue >= 20 && newValue > oldValue * 3 + 1000) return false;
    }
    return true;
  }
}

class _Stopped implements Exception {
  const _Stopped();
}
