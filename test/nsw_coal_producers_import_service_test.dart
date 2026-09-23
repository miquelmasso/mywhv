import 'package:flutter_test/flutter_test.dart';
import 'package:mywhv/models/construction_domain_records.dart';
import 'package:mywhv/services/nsw_coal_producers_import_service.dart';

void main() {
  const fixture = '''
  <div class="accordion__item">
    <span class="accordion__label">BHP Group Limited</span>
    <div class="accordion__body">
      <p>171 Collins Street<br>Phone: <a href="tel:+61396093333">+61 3 9609 3333</a><br>
      Website: <a href="https://www.bhp.com/">www.bhp.com</a></p>
      <p><strong>Mt Arthur Coal</strong><br>Open cut mine<br>
      Contact: <a href="https://www.bhp.com/contact-us">Contact</a></p>
    </div>
  </div>
  <div class="accordion__item">
    <span class="accordion__label">GM3</span>
    <div class="accordion__body">
      <p>Brisbane<br><a href="https://www.gm-3.com.au">Website</a></p>
      <p><strong>Appin</strong><br>Underground mine<br>
      <a href="mailto:jobs@example.com">Email</a></p>
    </div>
  </div>
  <div class="accordion__item">
    <span class="accordion__label">Idemitsu Australia Resources Pty Ltd</span>
    <div class="accordion__body">
      <p><a href="https://www.idemitsu.com.au/">Website</a></p>
      <p><strong>Boggabri Coal Operations Pty Ltd</strong><br>Boggabri<br>
      Open cut mine</p>
    </div>
  </div>
  ''';

  test('parses producer, mine, website and subsidiary operator', () {
    final entries = NswCoalProducersImportService.parseDirectoryHtml(fixture);

    expect(entries, hasLength(3));
    expect(entries[0].producerName, 'BHP Group Limited');
    expect(entries[0].mineName, 'Mt Arthur Coal');
    expect(entries[0].website, 'https://www.bhp.com/');
    expect(entries[0].contactUrl, 'https://www.bhp.com/contact-us');
    expect(entries[1].email, 'jobs@example.com');
    expect(entries[2].mineName, 'Boggabri');
    expect(entries[2].operatorName, 'Boggabri Coal Operations Pty Ltd');
  });

  test('creates only unique corroborated employer-worksite links', () {
    final entries = NswCoalProducersImportService.parseDirectoryHtml(fixture);
    final rows = NswCoalProducersImportService.buildCorroboratedRows(entries, [
      {
        'name': 'Appin underground mine',
        'worksite_name': 'Appin underground mine',
        'worksite_id': 'worksite:nsw:major_operating_mine:220017',
        'source_place_id': 'nsw:major_operating_mine:220017',
        'source': 'nsw_major_operating_mines',
        'state': 'NSW',
        'latitude': -34.2111,
        'longitude': 150.7925,
      },
      {
        'name': 'Unmatched mine',
        'worksite_name': 'Unmatched mine',
        'worksite_id': 'worksite:nsw:major_operating_mine:99',
        'source_place_id': 'nsw:major_operating_mine:99',
        'source': 'nsw_major_operating_mines',
        'state': 'NSW',
      },
    ]);

    expect(rows, hasLength(1));
    expect(rows.single['name'], 'GM3');
    expect(rows.single['company_worksite_role'], 'operator');
    expect(rows.single['link_corroborated'], isTrue);
    expect(
      ConstructionDomainRecords.hasCorroboratedHiringLink(rows.single),
      isTrue,
    );
  });

  test('matches safe NSW spelling and mine-type variants', () {
    const entries = [
      NswCoalProducerEntry(
        producerName: 'BHP Group Limited',
        operatorName: 'BHP Group Limited',
        mineName: 'Mt Arthur Coal',
      ),
      NswCoalProducerEntry(
        producerName: 'Bloomfield Group',
        operatorName: 'Bloomfield Group',
        mineName: 'Rix’s Creek',
      ),
    ];
    final rows = NswCoalProducersImportService.buildCorroboratedRows(entries, [
      {
        'worksite_name': 'Mount Arthur open cut mine',
        'worksite_id': 'worksite:nsw:major_operating_mine:1',
        'source_place_id': 'nsw:major_operating_mine:1',
      },
      {
        'worksite_name': 'Rixs Creek open cut mine',
        'worksite_id': 'worksite:nsw:major_operating_mine:2',
        'source_place_id': 'nsw:major_operating_mine:2',
      },
    ]);

    expect(rows.map((row) => row['worksite_name']).toSet(), {
      'Mount Arthur open cut mine',
      'Rixs Creek open cut mine',
    });
  });
}
