import 'dart:convert';

import 'package:http/http.dart' as http;

import 'map_markers_service.dart';

class GeoscienceAustraliaMinesImportResult {
  const GeoscienceAustraliaMinesImportResult({
    required this.state,
    required this.worksites,
    required this.added,
    required this.updated,
  });

  final String state;
  final int worksites;
  final int added;
  final int updated;
}

/// Imports official national operating-mine points as worksites only.
/// The source has no verified operator relationship, so this service never
/// invents a company or makes a worksite public by itself.
class GeoscienceAustraliaMinesImportService {
  GeoscienceAustraliaMinesImportService({http.Client? client})
    : _client = client ?? http.Client();

  static const layerUrl =
      'https://services.ga.gov.au/gis/rest/services/'
      'AustralianCriticalMineralsOperatingMinesAndDeposits/MapServer/4';

  final http.Client _client;

  Future<GeoscienceAustraliaMinesImportResult> importState(
    String rawState,
  ) async {
    final state = rawState.trim().toUpperCase();
    final uri = Uri.parse('$layerUrl/query').replace(
      queryParameters: {
        'where': "state='$state'",
        'outFields': '*',
        'returnGeometry': 'true',
        'outSR': '4326',
        'f': 'geojson',
      },
    );
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) {
      throw StateError(
        'Geoscience Australia returned HTTP ${response.statusCode}.',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['features'] is! List) {
      throw const FormatException('Invalid Geoscience Australia GeoJSON.');
    }
    final rows = <Map<String, dynamic>>[];
    for (final feature in (decoded['features'] as List).whereType<Map>()) {
      final properties = feature['properties'];
      final geometry = feature['geometry'];
      if (properties is! Map || geometry is! Map) continue;
      final coordinates = geometry['coordinates'];
      if (coordinates is! List || coordinates.length < 2) continue;
      final objectId = (properties['objectid'] ?? '').toString();
      final projectName = (properties['projectname'] ?? '').toString().trim();
      if (objectId.isEmpty || projectName.isEmpty) continue;
      rows.add({
        'id': 'ga_operating_mine_$objectId',
        'docId': 'ga_operating_mine_$objectId',
        'worksite_id': 'worksite:ga_operating_mine:$objectId',
        'record_type': 'construction_worksite',
        'name': projectName,
        'worksite_name': projectName,
        'state': (properties['state'] ?? state).toString().toUpperCase(),
        'latitude': coordinates[1],
        'longitude': coordinates[0],
        'worksite_stage': (properties['status'] ?? '').toString(),
        'commodities': (properties['commodities'] ?? '').toString(),
        'entity_kind': 'project_site',
        'company_id': '',
        'company_worksite_role': '',
        'link_corroborated': false,
        'source': 'geoscience_australia_operating_mines',
        'source_place_id': 'ga:operating_mine:$objectId',
        'source_url': layerUrl,
        'source_license': 'CC BY 4.0',
        'source_attribution':
            '© Commonwealth of Australia (Geoscience Australia) 2026',
        'source_record_url': (properties['source'] ?? '').toString(),
        'place_type': 'construction',
        'marker_kind': 'construction',
        'contact_enrichment_status': 'not_applicable_unlinked_worksite',
      });
    }
    final write = await MapMarkersService.upsertLocalConstructionCompanies(
      rows,
    );
    return GeoscienceAustraliaMinesImportResult(
      state: state,
      worksites: rows.length,
      added: write.added,
      updated: write.updated,
    );
  }
}
