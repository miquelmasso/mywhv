import 'package:flutter_test/flutter_test.dart';
import 'package:mywhv/services/nsw_epa_licensed_premises_import_service.dart';

void main() {
  test('parses an official premises polygon and derives its map point', () {
    final records = NswEpaLicensedPremisesImportService.recordsFromArcGis({
      'features': [
        {
          'attributes': {
            'EPL': 11583,
            'APName': 'PEAK GOLD MINES PTY LTD',
            'TradingName': 'PEAK',
            'LocationName': 'MT BOPPY GOLD MINE',
            'Address': 'Gilgunnia-Canbelego Road',
            'Suburb': 'CANBELEGO',
            'Postcode': '2835',
            'PrimaryFeebasedActivity': 'Mining for minerals',
            'VerDate': 1761523200000,
          },
          'geometry': {
            'rings': [
              [
                [146.0, -32.0],
                [148.0, -32.0],
                [148.0, -30.0],
                [146.0, -30.0],
                [146.0, -32.0],
              ],
            ],
          },
        },
      ],
    });

    expect(records, hasLength(1));
    expect(records.single.licenceNumber, '11583');
    expect(records.single.latitude, closeTo(-31, 0.0001));
    expect(records.single.longitude, closeTo(147, 0.0001));
    expect(records.single.postcode, '2835');
  });

  test(
    'creates corporate operator links and retains other holders locally',
    () {
      const premises = <NswEpaLicensedPremise>[
        NswEpaLicensedPremise(
          licenceNumber: '1',
          holderName: 'EXAMPLE CIVIL PTY LTD',
          tradingName: 'Example Civil',
          locationName: 'Regional road project',
          activity: 'Road construction',
          address: '1 Example Road',
          suburb: 'ORANGE',
          postcode: '2800',
          latitude: -33.28,
          longitude: 149.1,
        ),
        NswEpaLicensedPremise(
          licenceNumber: '2',
          holderName: 'EXAMPLE REGIONAL COUNCIL',
          locationName: 'Council concrete works',
          activity: 'Concrete works',
          address: '2 Example Road',
          suburb: 'ORANGE',
          postcode: '2800',
          latitude: -33.29,
          longitude: 149.11,
        ),
      ];

      final rows = NswEpaLicensedPremisesImportService.buildRows(premises, [
        {
          'name': 'EXAMPLE CIVIL PTY LTD',
          'company_id': 'company:name:examplecivil',
          'company_identity_aliases': ['Example Materials Group'],
          'website': 'https://example.test',
          'careers_page': 'https://example.test/careers',
          'contact_enrichment_status': 'completed',
        },
      ]);

      expect(rows, hasLength(2));
      expect(rows.first['company_worksite_role'], 'operator');
      expect(rows.first['link_corroborated'], isTrue);
      expect(rows.first['website'], 'https://example.test');
      expect(
        rows.first['company_identity_aliases'],
        containsAll(['EXAMPLE CIVIL PTY LTD', 'Example Civil']),
      );
      expect(
        rows.first['company_identity_aliases'],
        isNot(contains('Example Materials Group')),
      );
      expect(rows.first['contact_enrichment_status'], 'completed');
      expect(rows.last['company_id'], isEmpty);
      expect(rows.last['entity_kind'], 'project_site');
      expect(
        rows.last['contact_enrichment_status'],
        'not_applicable_unlinked_worksite',
      );
    },
  );

  test('ignores activities outside the selected construction scope', () {
    final records = NswEpaLicensedPremisesImportService.recordsFromArcGis({
      'features': [
        {
          'attributes': {
            'EPL': 3,
            'APName': 'EXAMPLE WASTE PTY LTD',
            'PrimaryFeebasedActivity': 'Waste storage - other types of waste',
          },
          'geometry': null,
        },
      ],
    });

    expect(records, isEmpty);
  });
}
