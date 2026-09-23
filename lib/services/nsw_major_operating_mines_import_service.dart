import 'dart:convert';

import 'package:http/http.dart' as http;

import 'map_markers_service.dart';

class NswMajorOperatingMinesImportResult {
  const NswMajorOperatingMinesImportResult({
    required this.worksites,
    required this.added,
    required this.updated,
  });

  final int worksites;
  final int added;
  final int updated;
}

/// Imports the official NSW layer as worksites only. Its published schema has
/// no operator, owner or contractor, so this importer never invents a link.
class NswMajorOperatingMinesImportService {
  NswMajorOperatingMinesImportService({http.Client? client})
    : _client = client ?? http.Client();

  static const sourceUrl =
      'https://public-gs.geoscience.nsw.gov.au/geoserver/ows';
  static const featureType =
      'mineral-occurrence:mineral_occurrence_operating_mines';

  final http.Client _client;

  Future<NswMajorOperatingMinesImportResult> importLocal() async {
    final uri = Uri.parse(sourceUrl).replace(
      queryParameters: {
        'service': 'WFS',
        'version': '2.0.0',
        'request': 'GetFeature',
        'typeNames': featureType,
        'outputFormat': 'application/json',
        'srsName': 'EPSG:4326',
      },
    );
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) {
      throw StateError(
        'NSW Major Operating Mines returned HTTP ${response.statusCode}.',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid NSW Major Operating Mines GeoJSON.');
    }
    final rows = recordsFromGeoJson(decoded);
    final write = await MapMarkersService.upsertLocalConstructionCompanies(
      rows,
    );
    return NswMajorOperatingMinesImportResult(
      worksites: rows.length,
      added: write.added,
      updated: write.updated,
    );
  }

  static List<Map<String, dynamic>> recordsFromGeoJson(
    Map<String, dynamic> decoded,
  ) {
    final features = decoded['features'];
    if (features is! List) {
      throw const FormatException('Invalid NSW Major Operating Mines GeoJSON.');
    }
    final rows = <Map<String, dynamic>>[];
    for (final rawFeature in features) {
      if (rawFeature is! Map) continue;
      final feature = Map<String, dynamic>.from(rawFeature);
      final rawProperties = feature['properties'];
      final rawGeometry = feature['geometry'];
      if (rawProperties is! Map || rawGeometry is! Map) continue;
      final properties = Map<String, dynamic>.from(rawProperties);
      final geometry = Map<String, dynamic>.from(rawGeometry);
      final coordinates = geometry['coordinates'];
      if (coordinates is! List || coordinates.length < 2) continue;
      final longitude = _asDouble(coordinates[0]);
      final latitude = _asDouble(coordinates[1]);
      final occurrenceId = (properties['occurrence_id'] ?? '')
          .toString()
          .trim();
      final operation = (properties['operation'] ?? '').toString().trim();
      if (occurrenceId.isEmpty ||
          operation.isEmpty ||
          latitude == null ||
          longitude == null) {
        continue;
      }
      final sourceId = 'nsw:major_operating_mine:$occurrenceId';
      rows.add({
        'id': 'nsw_major_operating_mine_$occurrenceId',
        'docId': 'nsw_major_operating_mine_$occurrenceId',
        'worksite_id': 'worksite:$sourceId',
        'record_type': 'construction_worksite',
        'name': operation,
        'worksite_name': operation,
        'state': 'NSW',
        'latitude': latitude,
        'longitude': longitude,
        'worksite_stage': (properties['operation_state'] ?? '').toString(),
        'commodities': (properties['comm_type'] ?? '').toString(),
        'deposit_name': (properties['deposit_name'] ?? '').toString().trim(),
        'number_of_mines': properties['number_of_mines'],
        'entity_kind': 'project_site',
        'company_id': '',
        'company_worksite_role': '',
        'link_corroborated': false,
        'source': 'nsw_major_operating_mines',
        'source_place_id': sourceId,
        'source_url': sourceUrl,
        'source_license': 'CC BY 4.0',
        'source_attribution':
            'Geological Survey of NSW, NSW Major Operating Mines',
        'place_type': 'construction',
        'marker_kind': 'construction',
        'contact_enrichment_status': 'not_applicable_unlinked_worksite',
      });
    }
    return rows;
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}
