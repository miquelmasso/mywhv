import 'dart:convert';
import 'dart:io';

const _reviewPath =
    'work/construction_catalog/construction_catalog_review.json';
const _outputPath = 'export/construction_validated_names.json';

Future<void> main() async {
  final reviewFile = File(_reviewPath);
  if (!reviewFile.existsSync()) {
    throw StateError(
      'Missing $_reviewPath. Build and validate the catalogue first.',
    );
  }
  final decoded = jsonDecode(await reviewFile.readAsString());
  if (decoded is! Map || decoded['companies'] is! List) {
    throw const FormatException('Invalid construction review catalogue.');
  }
  final names =
      (decoded['companies'] as List)
          .whereType<Map>()
          .where(
            (company) =>
                company['validation_status'] == 'validated_active_company',
          )
          .map((company) => (company['name'] ?? '').toString().trim())
          .where(
            (name) =>
                name.isNotEmpty &&
                !RegExp(
                  r'\b(?:ABN|A\.?C\.?N\.?)\s*\d',
                  caseSensitive: false,
                ).hasMatch(name),
          )
          .toSet()
          .toList()
        ..sort();
  final output = {
    'schema_version': 1,
    'source': 'ASIC Company Dataset exact active-company matches',
    'contains_identifiers': false,
    'companies': names,
  };
  final outputFile = File(_outputPath);
  await outputFile.parent.create(recursive: true);
  await outputFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(output),
    flush: true,
  );
  stdout.writeln('Exported ${names.length} validated company names.');
}
