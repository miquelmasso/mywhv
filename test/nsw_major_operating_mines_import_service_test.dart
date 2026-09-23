import 'package:flutter_test/flutter_test.dart';
import 'package:mywhv/services/nsw_major_operating_mines_import_service.dart';

void main() {
  test('maps the official NSW feature to an unlinked local worksite', () {
    final rows = NswMajorOperatingMinesImportService.recordsFromGeoJson({
      'type': 'FeatureCollection',
      'features': [
        {
          'geometry': {
            'type': 'Point',
            'coordinates': [150.7925, -34.2111],
          },
          'properties': {
            'occurrence_id': 220017,
            'comm_type': 'COAL',
            'operation': 'Appin underground mine',
            'deposit_name': 'Appin Mine, Westcliff Mine',
            'operation_state': 'Operating',
            'number_of_mines': 2,
          },
        },
      ],
    });

    expect(rows, hasLength(1));
    expect(rows.single['worksite_name'], 'Appin underground mine');
    expect(rows.single['state'], 'NSW');
    expect(rows.single['latitude'], -34.2111);
    expect(rows.single['longitude'], 150.7925);
    expect(rows.single['company_id'], isEmpty);
    expect(rows.single['company_worksite_role'], isEmpty);
    expect(rows.single['link_corroborated'], isFalse);
    expect(
      rows.single['contact_enrichment_status'],
      'not_applicable_unlinked_worksite',
    );
  });

  test('skips malformed features without erasing valid records', () {
    final rows = NswMajorOperatingMinesImportService.recordsFromGeoJson({
      'features': [
        {
          'geometry': {
            'coordinates': [151.0, -33.0],
          },
          'properties': {'occurrence_id': 1, 'operation': ''},
        },
        {
          'geometry': {
            'coordinates': [151.1, -33.1],
          },
          'properties': {'occurrence_id': 2, 'operation': 'Valid mine'},
        },
      ],
    });

    expect(rows.map((row) => row['worksite_name']), ['Valid mine']);
  });
}
