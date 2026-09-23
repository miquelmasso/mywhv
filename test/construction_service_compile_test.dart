import 'package:flutter_test/flutter_test.dart';
import 'package:mywhv/services/osm_construction_import_service.dart';
import 'package:mywhv/services/geoscience_australia_mines_import_service.dart';
import 'package:mywhv/screens/add_construction_by_state_page.dart';

void main() {
  test('Construction enrichment service can be created', () {
    expect(OsmConstructionImportService.new, returnsNormally);
    expect(GeoscienceAustraliaMinesImportService.new, returnsNormally);
    expect(const AddConstructionByStatePage(), isNotNull);
  });
}
