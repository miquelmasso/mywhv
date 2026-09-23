import 'dart:convert';
import 'dart:io';

const _catalogPath =
    'work/construction_catalog/construction_catalog_review.json';
const _asicResourceId = '5c3914e6-413e-4a2c-b890-bf8efe3eabf2';
const _endpoint = 'https://data.gov.au/data/api/action/datastore_search_sql';

Future<void> main() async {
  final file = File(_catalogPath);
  if (!file.existsSync()) {
    throw StateError('Run build_catalog.dart before ASIC validation.');
  }
  final catalog = Map<String, dynamic>.from(
    jsonDecode(await file.readAsString()) as Map,
  );
  final companies = (catalog['companies'] as List)
      .whereType<Map>()
      .map(Map<String, dynamic>.from)
      .toList();
  final byExactName = <String, List<Map<String, dynamic>>>{};
  for (final company in companies) {
    final name = company['name'].toString().trim().toUpperCase();
    byExactName.putIfAbsent(name, () => []).add(company);
  }

  final names = byExactName.keys.toList()..sort();
  final matches = <String, Map<String, dynamic>>{};
  const batchSize = 100;
  for (var offset = 0; offset < names.length; offset += batchSize) {
    final chunk = names.skip(offset).take(batchSize);
    final quoted = chunk.map((name) => "'${name.replaceAll("'", "''")}'");
    final sql =
        '''
SELECT "Company Name", "Status", "Current Name Indicator", "Date of Deregistration"
FROM "$_asicResourceId"
WHERE upper("Company Name") IN (${quoted.join(',')})
''';
    final uri = Uri.parse(_endpoint).replace(queryParameters: {'sql': sql});
    final records = await _fetchRecordsWithRetry(uri);
    for (final record in records) {
      final name = (record['Company Name'] ?? '').toString().toUpperCase();
      if (name.isNotEmpty) matches[name] = record;
    }
    stdout.writeln(
      'ASIC batch ${offset ~/ batchSize + 1}/'
      '${(names.length + batchSize - 1) ~/ batchSize}',
    );
  }

  var validated = 0;
  var needsReview = 0;
  var notFound = 0;
  for (final entry in byExactName.entries) {
    final match = matches[entry.key];
    for (final company in entry.value) {
      if (match == null) {
        company['validation_status'] = 'not_found_in_asic_exact_match';
        company['editorial_review_required'] = true;
        notFound++;
        continue;
      }
      final status = (match['Status'] ?? '').toString();
      final current = (match['Current Name Indicator'] ?? '').toString() == 'Y';
      final deregistered = (match['Date of Deregistration'] ?? '')
          .toString()
          .trim()
          .isNotEmpty;
      if (status == 'REGD' && current && !deregistered) {
        company['validation_status'] = 'validated_active_company';
        company['editorial_review_required'] = false;
        validated++;
      } else {
        company['validation_status'] = 'asic_match_needs_review';
        company['editorial_review_required'] = true;
        needsReview++;
      }
      company['validation_source'] = 'asic_companies';
    }
  }

  catalog['companies'] = companies;
  catalog['validation_summary'] = {
    'source': 'ASIC Company Dataset',
    'licence': 'CC BY 3.0 AU',
    'method': 'exact company-name match; no ABN or ACN requested or stored',
    'validated_active': validated,
    'matched_needs_review': needsReview,
    'not_found_exactly': notFound,
  };
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(catalog),
    flush: true,
  );
  stdout.writeln(
    'ASIC validation complete: $validated active, $needsReview review, '
    '$notFound not found.',
  );
}

Future<List<Map<String, dynamic>>> _fetchRecordsWithRetry(Uri uri) async {
  Object? lastError;
  for (var attempt = 1; attempt <= 6; attempt++) {
    final client = HttpClient()
      ..userAgent = 'Workyday ASIC open-data validator'
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final response = await (await client.getUrl(uri)).close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('ASIC API HTTP ${response.statusCode}', uri: uri);
      }
      final decoded = jsonDecode(await utf8.decoder.bind(response).join());
      if (decoded is! Map || decoded['success'] != true) {
        throw StateError('ASIC API returned an invalid response.');
      }
      final result = decoded['result'];
      if (result is! Map || result['records'] is! List) return const [];
      return (result['records'] as List)
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();
    } catch (error) {
      lastError = error;
      if (attempt < 6) {
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
    } finally {
      client.close(force: true);
    }
  }
  throw StateError('ASIC API failed after retries: $lastError');
}
