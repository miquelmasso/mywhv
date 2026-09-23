import '../models/construction_category.dart';
import 'construction_publication_policy.dart';
import 'construction_sqlite_store.dart';
import 'construction_validation_catalog_service.dart';
import 'map_markers_service.dart';

class ConstructionCatalogueReviewResult {
  const ConstructionCatalogueReviewResult({
    required this.total,
    required this.employers,
    required this.projectSites,
    required this.suppliersExcluded,
    required this.needsReview,
    required this.mapReady,
    required this.withoutPublicContact,
    required this.operatorsLinked,
    required this.operatorCompaniesCreated,
    required this.worksitesCorroborated,
    this.operatorCompanyIds = const <String>[],
  });

  final int total;
  final int employers;
  final int projectSites;
  final int suppliersExcluded;
  final int needsReview;
  final int mapReady;
  final int withoutPublicContact;
  final int operatorsLinked;
  final int operatorCompaniesCreated;
  final int worksitesCorroborated;
  final List<String> operatorCompanyIds;
}

class ConstructionCatalogueReviewService {
  ConstructionCatalogueReviewService._();

  static final ConstructionCatalogueReviewService instance =
      ConstructionCatalogueReviewService._();

  Future<ConstructionCatalogueReviewResult> reviewAndLinkOperators() async {
    await MapMarkersService.reclassifyLocalConstructionCompanies();
    final store = ConstructionSqliteStore.instance;
    await store.init();
    final rows = await store.getAll();
    final operatorCompanies = <String, Map<String, dynamic>>{};
    var operatorsLinked = 0;
    var worksitesCorroborated = 0;

    for (final row in rows) {
      if ((row['entity_kind'] ?? '').toString() != 'project_site') continue;
      final worksiteEvidence = await ConstructionValidationCatalogService
          .instance
          .findOpenDataWorksiteEvidence(
            (row['name'] ?? '').toString(),
            state: (row['state'] ?? '').toString(),
          );
      if (worksiteEvidence != null) {
        final worksiteSource = (worksiteEvidence['source_id'] ?? '').toString();
        final sources = <String>{
          ...(row['catalog_sources'] is List
              ? (row['catalog_sources'] as List).map(
                  (value) => value.toString(),
                )
              : const <String>[]),
          'osm',
          if (worksiteSource.isNotEmpty) worksiteSource,
        };
        row['catalog_sources'] = sources.toList()..sort();
        row['worksite_validation_status'] = 'corroborated';
        row['worksite_status'] = worksiteEvidence['status'] ?? '';
        row['commodity_group'] = worksiteEvidence['commodity_group'] ?? '';
        worksitesCorroborated++;
      }
      var operatorName = _firstText(row, const ['osm_operator', 'operator']);
      if (operatorName.isEmpty &&
          worksiteEvidence?['operator_verified'] == true) {
        operatorName = (worksiteEvidence?['operator_name'] ?? '')
            .toString()
            .trim();
      }
      if (operatorName.isEmpty) continue;
      row['operator_name'] = operatorName;
      final evidence = await ConstructionValidationCatalogService.instance
          .findOpenDataEvidence(operatorName);
      if (evidence == null) {
        row['operator_validation_status'] = 'unverified';
        continue;
      }

      final normalized =
          ConstructionValidationCatalogService.normalizeCompanyName(
            operatorName,
          );
      if (normalized.isEmpty) continue;
      final operatorId = 'open_data_operator_${_safeId(normalized)}';
      final categories = evidence['construction_categories'];
      final category = categories is List && categories.isNotEmpty
          ? ConstructionCategory.fromId(categories.first)
          : ConstructionCategory.fromId(row['construction_category']);
      final sourceId = (evidence['source_id'] ?? '').toString();
      final siteName = (row['name'] ?? '').toString().trim();
      final existing = operatorCompanies[operatorId];
      final sites = <String>{
        ...(existing?['operated_project_names'] is List
            ? (existing!['operated_project_names'] as List).map(
                (value) => value.toString(),
              )
            : const <String>[]),
        if (siteName.isNotEmpty) siteName,
      };
      operatorCompanies[operatorId] = <String, dynamic>{
        ...?existing,
        'id': operatorId,
        'docId': operatorId,
        'name': operatorName,
        'address': row['address'] ?? '',
        'postcode': row['postcode'] ?? '',
        'postcode_display': row['postcode_display'] ?? row['postcode'] ?? '',
        'state': row['state'] ?? evidence['state'] ?? '',
        'latitude': row['latitude'] ?? row['lat'],
        'longitude': row['longitude'] ?? row['lng'],
        'phone': _prefer(existing?['phone'], row['phone']),
        'email': _prefer(existing?['email'], row['email']),
        'website': _prefer(existing?['website'], row['website']),
        'careers_page': _prefer(existing?['careers_page'], row['careers_page']),
        'facebook_url': _prefer(existing?['facebook_url'], row['facebook_url']),
        'instagram_url': _prefer(
          existing?['instagram_url'],
          row['instagram_url'],
        ),
        'construction_category': category.id,
        'construction_category_label': category.label,
        'entity_kind': 'employer',
        'classification_confidence': 95,
        'classification_reason':
            'OSM project operator corroborated by an open-data company source',
        'classification_source': 'open_data_corroboration',
        'review_status': 'ready_for_map',
        'company_validation_status': 'validated_active_company',
        'company_validation_source': 'asic_companies',
        'catalog_sources': <String>[
          'osm',
          'asic_companies',
          if (sourceId.isNotEmpty) sourceId,
        ],
        'source': 'open_data_operator_link',
        'source_place_id': operatorId,
        'location_role': 'operated_project_site',
        'operated_project_names': sites.toList()..sort(),
        'place_type': 'construction',
        'marker_kind': 'construction',
        'blocked': false,
      };
      row['operator_company_id'] = operatorId;
      row['operator_validation_status'] = 'corroborated';
      operatorsLinked++;
    }

    await MapMarkersService.replaceLocalConstructionCompanies(rows);
    if (operatorCompanies.isNotEmpty) {
      await MapMarkersService.upsertLocalConstructionCompanies(
        operatorCompanies.values.toList(growable: false),
      );
    }
    final reviewed =
        await MapMarkersService.reclassifyLocalConstructionCompanies();
    return _summarize(
      reviewed,
      operatorsLinked: operatorsLinked,
      operatorCompaniesCreated: operatorCompanies.length,
      operatorCompanyIds: operatorCompanies.keys.toList(growable: false),
      worksitesCorroborated: worksitesCorroborated,
    );
  }

  Future<ConstructionCatalogueReviewResult> summarize() async {
    final rows = await MapMarkersService.reclassifyLocalConstructionCompanies();
    return _summarize(
      rows,
      operatorsLinked: rows
          .where(
            (row) =>
                (row['operator_validation_status'] ?? '').toString() ==
                'corroborated',
          )
          .length,
      operatorCompaniesCreated: rows
          .where(
            (row) =>
                (row['source'] ?? '').toString() == 'open_data_operator_link',
          )
          .length,
      operatorCompanyIds: const <String>[],
      worksitesCorroborated: rows
          .where(
            (row) =>
                (row['worksite_validation_status'] ?? '').toString() ==
                'corroborated',
          )
          .length,
    );
  }

  ConstructionCatalogueReviewResult _summarize(
    List<Map<String, dynamic>> rows, {
    required int operatorsLinked,
    required int operatorCompaniesCreated,
    required int worksitesCorroborated,
    List<String> operatorCompanyIds = const <String>[],
  }) {
    var employers = 0;
    var sites = 0;
    var suppliers = 0;
    var review = 0;
    var mapReady = 0;
    var noContact = 0;
    for (final row in rows) {
      switch ((row['entity_kind'] ?? '').toString()) {
        case 'employer':
          employers++;
          break;
        case 'project_site':
          sites++;
          break;
        case 'supplier_retail':
          suppliers++;
          break;
        default:
          review++;
      }
      if (!ConstructionPublicationPolicy.hasPublicContact(row)) noContact++;
      if (ConstructionPublicationPolicy.canAppearOnMap(row)) mapReady++;
    }
    return ConstructionCatalogueReviewResult(
      total: rows.length,
      employers: employers,
      projectSites: sites,
      suppliersExcluded: suppliers,
      needsReview: review,
      mapReady: mapReady,
      withoutPublicContact: noContact,
      operatorsLinked: operatorsLinked,
      operatorCompaniesCreated: operatorCompaniesCreated,
      worksitesCorroborated: worksitesCorroborated,
      operatorCompanyIds: operatorCompanyIds,
    );
  }

  String _firstText(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = (row[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _safeId(String value) => value
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  Object? _prefer(Object? current, Object? incoming) {
    final currentText = (current ?? '').toString().trim();
    return currentText.isNotEmpty ? current : incoming;
  }
}
