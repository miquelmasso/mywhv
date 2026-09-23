import 'dart:convert';
import 'dart:io';

const _reviewPath =
    'work/construction_catalog/construction_catalog_review.json';
const _outputPath = 'export/construction_open_data_snapshot.json';

Future<void> main() async {
  final review = jsonDecode(await File(_reviewPath).readAsString());
  if (review is! Map || review['companies'] is! List) {
    throw const FormatException('Invalid construction review catalogue.');
  }

  final companies = <Map<String, dynamic>>[];
  for (final raw in (review['companies'] as List).whereType<Map>()) {
    if (raw['validation_status'] != 'validated_active_company') continue;
    final name = (raw['name'] ?? '').toString().trim();
    if (name.isEmpty || _containsIdentifierName(name)) continue;
    companies.add({
      'name': name,
      if ((raw['state'] ?? '').toString().trim().isNotEmpty)
        'state': raw['state'].toString(),
      'construction_categories':
          (raw['construction_categories'] as List? ?? const [])
              .map((value) => value.toString())
              .toSet()
              .toList(),
      'source_id': (raw['source_id'] ?? '').toString(),
      'validation_status': 'validated_active_company',
    });
  }
  companies.sort(
    (a, b) => a['name'].toString().compareTo(b['name'].toString()),
  );

  final worksites = <Map<String, dynamic>>[];
  for (final raw
      in (review['worksites'] as List? ?? const []).whereType<Map>()) {
    if (raw['verified_operator'] == true) continue;
    worksites.add({
      'name': (raw['name'] ?? '').toString(),
      'state': (raw['state'] ?? '').toString(),
      'latitude': raw['latitude'],
      'longitude': raw['longitude'],
      'status': (raw['status'] ?? '').toString(),
      'commodity_group': (raw['commodity_group'] ?? '').toString(),
      'source_id': (raw['source_id'] ?? '').toString(),
      'operator_verified': false,
      'map_as_company': false,
    });
  }

  final output = {
    'schema_version': 1,
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'privacy': {
      'contains_abn': false,
      'contains_acn': false,
      'contains_contacts': false,
      'contains_personal_names': false,
    },
    'companies': companies,
    'unlinked_worksites': worksites,
  };
  final file = File(_outputPath);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(output),
    flush: true,
  );
  stdout.writeln(
    'Runtime snapshot: ${companies.length} validated companies, '
    '${worksites.length} unlinked worksites.',
  );
}

bool _containsIdentifierName(String name) =>
    RegExp(r'\b(?:ABN|A\.?C\.?N\.?)\s*\d', caseSensitive: false).hasMatch(name);
