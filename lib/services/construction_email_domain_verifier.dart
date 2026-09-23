import 'dart:convert';

import 'package:http/http.dart' as http;

import 'construction_application_contact_classifier.dart';

class ConstructionEmailDomainVerifier {
  ConstructionEmailDomainVerifier({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;
  static final Map<String, Future<String>> _cache = {};

  Future<void> apply(Map<String, dynamic> company) async {
    final email = (company['email'] ?? '').toString().trim().toLowerCase();
    if (!ConstructionApplicationContactClassifier.isSemanticallyValidEmail(
      email,
    )) {
      company['email_domain_status'] = email.isEmpty
          ? 'not_applicable'
          : 'invalid_email';
      company['email_domain_checked_at'] = DateTime.now()
          .toUtc()
          .toIso8601String();
      ConstructionApplicationContactClassifier.applyDerivedFields(company);
      return;
    }

    final domain = email.substring(email.lastIndexOf('@') + 1);
    final status = await _cache.putIfAbsent(domain, () => _lookupMx(domain));
    company['email_domain_status'] = status;
    company['email_domain_checked_at'] = DateTime.now()
        .toUtc()
        .toIso8601String();
    company['email_domain_check_source'] = 'google_public_dns_mx';
    ConstructionApplicationContactClassifier.applyDerivedFields(company);
  }

  Future<String> _lookupMx(String domain) async {
    try {
      final uri = Uri.https('dns.google', '/resolve', {
        'name': domain,
        'type': 'MX',
      });
      final response = await _client
          .get(uri, headers: const {'accept': 'application/dns-json'})
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return 'check_failed';
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return 'check_failed';
      final answers = decoded['Answer'];
      if (answers is List &&
          answers.any(
            (answer) =>
                answer is Map &&
                (answer['type'] == 15 || answer['type'].toString() == '15'),
          )) {
        return 'active_mx';
      }
      return decoded['Status'] == 0 ? 'no_mx' : 'dns_error';
    } catch (_) {
      // A temporary verifier outage must not turn otherwise successful
      // company enrichment into retry_later.
      return 'check_failed';
    }
  }
}
