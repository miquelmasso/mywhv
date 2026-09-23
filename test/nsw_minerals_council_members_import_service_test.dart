import 'package:flutter_test/flutter_test.dart';
import 'package:mywhv/services/nsw_minerals_council_members_import_service.dart';

void main() {
  test('parses full members and excludes associate members', () {
    const html = '''
      <section id="section1" class="logos-grid">
        <div class="logo-h"><div class="text">No Link Mining</div></div>
        <a class="logo-h" href="https://operator.example/">
          <div class="text">Operator Resources Ltd</div>
        </a>
      </section>
      <section id="section2" class="logos-grid">
        <a class="logo-h" href="https://lawyer.example/">
          <div class="text">Example Lawyers</div>
        </a>
      </section>
    ''';

    final members = NswMineralsCouncilMembersImportService.parseMembersHtml(
      html,
    );

    expect(members, hasLength(2));
    expect(
      members.map((member) => member.name),
      containsAll(<String>['No Link Mining', 'Operator Resources Ltd']),
    );
    expect(
      members
          .singleWhere((member) => member.name.startsWith('Operator'))
          .website,
      'https://operator.example/',
    );
    expect(
      members.map((member) => member.name),
      isNot(contains('Example Lawyers')),
    );
  });
}
