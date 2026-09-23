import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mywhv/services/construction_email_domain_verifier.dart';

void main() {
  test(
    'persists active MX and independently enables an official jobs inbox',
    () async {
      final verifier = ConstructionEmailDomainVerifier(
        client: MockClient(
          (_) async => http.Response(
            '{"Status":0,"Answer":[{"name":"mx-test.invalid.","type":15,"data":"10 mail.example"}]}',
            200,
          ),
        ),
      );
      final row = <String, dynamic>{
        'email': 'jobs@mx-test.invalid',
        'website': 'https://mx-test.invalid',
        'email_officially_published': true,
      };

      await verifier.apply(row);

      expect(row['email_domain_status'], 'active_mx');
      expect(row['email_domain_checked_at'], isNotEmpty);
      expect(row['email_public_eligible'], isTrue);
    },
  );

  test('no MX preserves the source email but prevents publication', () async {
    final verifier = ConstructionEmailDomainVerifier(
      client: MockClient((_) async => http.Response('{"Status":0}', 200)),
    );
    final row = <String, dynamic>{
      'email': 'jobs@no-mx-test.invalid',
      'website': 'https://no-mx-test.invalid',
      'email_officially_published': true,
    };

    await verifier.apply(row);

    expect(row['email'], 'jobs@no-mx-test.invalid');
    expect(row['email_domain_status'], 'no_mx');
    expect(row['email_public_eligible'], isFalse);
  });
}
