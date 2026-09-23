import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mywhv/services/nsw_minerals_council_mines_import_service.dart';

void main() {
  test('keeps only operating mines with operators and coordinates', () {
    final source = jsonEncode([
      {
        'id': '1',
        'store': 'Example Gold Mine',
        'subtitle': 'Example Resources',
        'lat': '-32.1',
        'lng': '149.2',
        'status': 'Operating',
        'address': 'Example NSW 2840',
        'type': 'Gold',
      },
      {
        'id': '2',
        'store': 'Future Project',
        'subtitle': 'Future Resources',
        'lat': '-31.1',
        'lng': '148.2',
        'status': 'Proposed Mine',
      },
    ]);

    final mines = NswMineralsCouncilMinesImportService.recordsFromJson(source);

    expect(mines, hasLength(1));
    expect(mines.single.name, 'Example Gold Mine');
    expect(mines.single.operatorName, 'Example Resources');
    expect(mines.single.postcode, '2840');
  });

  test('creates a corroborated operator link and reuses official worksite', () {
    const mines = <NswMineralsCouncilMine>[
      NswMineralsCouncilMine(
        id: '15',
        name: 'Example Gold Mine',
        operatorName: 'Example Resources',
        latitude: -32.1,
        longitude: 149.2,
        status: 'Operating',
      ),
    ];
    final existing = <Map<String, dynamic>>[
      {
        'source': 'nsw_major_operating_mines',
        'state': 'NSW',
        'name': 'Example Gold Operation',
        'worksite_name': 'Example Gold Operation',
        'worksite_id': 'worksite:official:15',
        'latitude': -32.2,
        'longitude': 149.3,
      },
      {
        'company_id': 'company:name:exampleresources',
        'name': 'Example Resources',
        'website': 'https://example.test/',
        'careers_page': 'https://example.test/careers',
        'contact_enrichment_status': 'completed',
      },
    ];

    final rows = NswMineralsCouncilMinesImportService.buildCorroboratedRows(
      mines,
      existing,
    );

    expect(rows, hasLength(1));
    expect(rows.single['worksite_id'], 'worksite:official:15');
    expect(rows.single['company_worksite_role'], 'operator');
    expect(rows.single['link_corroborated'], isTrue);
    expect(rows.single['website'], 'https://example.test/');
    expect(rows.single['latitude'], -32.2);
  });
}
