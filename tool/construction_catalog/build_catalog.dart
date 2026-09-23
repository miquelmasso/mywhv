import 'dart:convert';
import 'dart:io';

const _manifestPath = 'tool/construction_catalog/sources.json';
const _sourceDirectory = 'work/construction_catalog/sources';
const _reviewOutputPath =
    'work/construction_catalog/construction_catalog_review.json';
const _defaultAusTenderFrom = '2025-01-01T00:00:00Z';
const _defaultAusTenderTo = '2025-02-01T00:00:00Z';

Future<void> main(List<String> arguments) async {
  final fetch = arguments.contains('--fetch');
  final ausTenderFrom = _argumentValue(
    arguments,
    '--austender-from',
    _defaultAusTenderFrom,
  );
  final ausTenderTo = _argumentValue(
    arguments,
    '--austender-to',
    _defaultAusTenderTo,
  );
  final manifestFile = File(_manifestPath);
  if (!manifestFile.existsSync()) {
    stderr.writeln('Missing source manifest: $_manifestPath');
    exitCode = 2;
    return;
  }

  final manifest = jsonDecode(await manifestFile.readAsString());
  if (manifest is! Map<String, dynamic>) {
    throw const FormatException('Source manifest must be a JSON object.');
  }
  final policy = Map<String, dynamic>.from(manifest['policy'] as Map);
  if (policy['allow_html_scraping'] != false ||
      policy['require_explicit_open_licence'] != true ||
      policy['publish_validation_identifiers'] != false) {
    throw StateError('The catalogue safety policy is not strict enough.');
  }

  final sourceDirectory = Directory(_sourceDirectory);
  await sourceDirectory.create(recursive: true);
  final worksites = <Map<String, dynamic>>[];
  final companyEvidence = <String, _CompanyEvidence>{};
  final sourceSummaries = <Map<String, dynamic>>[];
  final rawSources = manifest['sources'];
  if (rawSources is! List) {
    throw const FormatException('Manifest sources must be a list.');
  }

  for (final raw in rawSources.whereType<Map>()) {
    final source = Map<String, dynamic>.from(raw);
    if (source['enabled'] != true) continue;
    _assertSourceMayRun(source);
    final sourceId = source['id'].toString();
    final sourceFile = File('$_sourceDirectory/$sourceId.json');
    if (fetch) {
      final url = sourceId == 'austender_open_contracts'
          ? source['url_template']
                .toString()
                .replaceAll('{from}', ausTenderFrom)
                .replaceAll('{to}', ausTenderTo)
          : source['url'].toString();
      source['_resolved_url'] = url;
      if (sourceId == 'wa_mining_tenements') {
        await _downloadArcGisPages(url, sourceFile);
      } else {
        await _downloadJson(url, sourceFile);
      }
    }
    if (!sourceFile.existsSync()) {
      stderr.writeln('Skipping $sourceId: run with --fetch first.');
      continue;
    }
    final decoded = jsonDecode(await sourceFile.readAsString());
    final imported = source['record_kind'] == 'worksite'
        ? _importGeoJsonWorksites(decoded, source)
        : const <Map<String, dynamic>>[];
    worksites.addAll(imported);
    final evidenceCount = sourceId == 'austender_open_contracts'
        ? _importAusTenderEvidence(decoded, source, companyEvidence)
        : sourceId == 'wa_mining_tenements'
        ? _importWaMiningEvidence(decoded, source, companyEvidence)
        : 0;
    if (source['ephemeral_raw_download'] == true && sourceFile.existsSync()) {
      await sourceFile.delete();
    }
    sourceSummaries.add({
      'source_id': sourceId,
      'records_imported': imported.length + evidenceCount,
      'licence': source['licence'],
      'attribution': source['attribution'],
    });
  }

  worksites.sort((a, b) {
    final state = a['state'].toString().compareTo(b['state'].toString());
    return state != 0
        ? state
        : a['name'].toString().compareTo(b['name'].toString());
  });
  final companies =
      companyEvidence.values.map((evidence) => evidence.toPublicJson()).toList()
        ..sort((a, b) => a['name'].toString().compareTo(b['name'].toString()));
  final output = <String, dynamic>{
    'schema_version': 1,
    'review_status': 'not_approved_for_publication',
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'companies': companies,
    'worksites': worksites,
    'sources': sourceSummaries,
    'excluded_public_fields': const [
      'abn',
      'acn',
      'personal_name',
      'personal_phone',
      'harvested_email',
    ],
  };
  final outputFile = File(_reviewOutputPath);
  await outputFile.parent.create(recursive: true);
  await outputFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(output),
    flush: true,
  );
  stdout.writeln(
    'Review catalogue written: ${worksites.length} worksites, '
    '${companies.length} companies awaiting editorial review.',
  );
}

Future<void> _downloadArcGisPages(String url, File destination) async {
  final allFeatures = <Object?>[];
  var offset = 0;
  while (true) {
    final pageUri = Uri.parse(url).replace(
      queryParameters: {
        ...Uri.parse(url).queryParameters,
        'resultOffset': '$offset',
      },
    );
    final client = HttpClient()
      ..userAgent = 'Workyday open-data catalogue builder';
    try {
      final request = await client.getUrl(pageUri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}', uri: pageUri);
      }
      final decoded = jsonDecode(await utf8.decoder.bind(response).join());
      if (decoded is! Map || decoded['features'] is! List) break;
      final page = decoded['features'] as List;
      allFeatures.addAll(page);
      if (page.isEmpty || decoded['exceededTransferLimit'] != true) break;
      offset += page.length;
    } finally {
      client.close(force: true);
    }
  }
  await destination.writeAsString(
    jsonEncode({'features': allFeatures}),
    flush: true,
  );
}

int _importWaMiningEvidence(
  Object? decoded,
  Map<String, dynamic> source,
  Map<String, _CompanyEvidence> companies,
) {
  if (decoded is! Map || decoded['features'] is! List) return 0;
  var accepted = 0;
  for (final feature in (decoded['features'] as List).whereType<Map>()) {
    if (feature['attributes'] is! Map) continue;
    final attributes = Map<String, dynamic>.from(feature['attributes'] as Map);
    if ((attributes['tenstatus'] ?? '').toString().trim() != 'LIVE') continue;
    for (var index = 1; index <= 9; index++) {
      final name = (attributes['holder$index'] ?? '').toString().trim();
      if (name.isEmpty || _looksLikeIndividual(name)) continue;
      final key = 'name:${_normaliseName(name)}';
      final evidence = companies.putIfAbsent(
        key,
        () => _CompanyEvidence(
          name: name,
          state: 'WA',
          locality: '',
          postcode: '',
          sourceId: source['id'].toString(),
          sourceUrl: source['url'].toString(),
          licence: source['licence'].toString(),
          attribution: source['attribution'].toString(),
        ),
      );
      evidence.categories.add('mining_company');
      evidence.contractIds.add((attributes['tenid'] ?? '').toString().trim());
      accepted++;
    }
  }
  return accepted;
}

String _argumentValue(List<String> arguments, String name, String fallback) {
  final index = arguments.indexOf(name);
  if (index < 0) return fallback;
  if (index + 1 >= arguments.length) {
    throw FormatException('$name requires a value.');
  }
  return arguments[index + 1];
}

void _assertSourceMayRun(Map<String, dynamic> source) {
  final format = source['format'].toString();
  final licence = source['licence'].toString().trim();
  if (source['commercial_reuse_allowed'] != true) {
    throw StateError('${source['id']} does not allow commercial reuse.');
  }
  if (licence.isEmpty || licence.startsWith('pending_')) {
    throw StateError('${source['id']} has no verified open licence.');
  }
  if (!const {
    'geojson_api',
    'json_api',
    'csv',
    'xlsx',
    'xml',
  }.contains(format)) {
    throw StateError('${source['id']} uses a non-approved source format.');
  }
}

int _importAusTenderEvidence(
  Object? decoded,
  Map<String, dynamic> source,
  Map<String, _CompanyEvidence> companies,
) {
  if (decoded is! Map || decoded['releases'] is! List) return 0;
  var accepted = 0;
  for (final rawRelease in (decoded['releases'] as List).whereType<Map>()) {
    final release = Map<String, dynamic>.from(rawRelease);
    final contracts =
        (release['contracts'] as List?)?.whereType<Map>() ??
        const Iterable<Map>.empty();
    final parties =
        (release['parties'] as List?)?.whereType<Map>() ??
        const Iterable<Map>.empty();
    final suppliers = parties.where((party) {
      final roles = party['roles'];
      return roles is List && roles.contains('supplier');
    }).toList();
    if (suppliers.isEmpty) continue;

    for (final contract in contracts) {
      final description = (contract['description'] ?? '').toString().trim();
      final codes = <String>{};
      for (final item
          in (contract['items'] as List? ?? const []).whereType<Map>()) {
        final classification = item['classification'];
        if (classification is Map && classification['scheme'] == 'UNSPSC') {
          final code = (classification['id'] ?? '').toString().split('-').first;
          if (code.isNotEmpty) codes.add(code);
        }
      }
      final categories = _constructionCategories(codes, description);
      if (categories.isEmpty) continue;

      for (final supplier in suppliers) {
        final name = (supplier['name'] ?? '').toString().trim();
        if (name.isEmpty || _looksLikeIndividual(name)) continue;
        final abn = _temporaryAbn(supplier);
        final key = abn == null ? 'name:${_normaliseName(name)}' : 'abn:$abn';
        final address = supplier['address'] is Map
            ? Map<String, dynamic>.from(supplier['address'] as Map)
            : const <String, dynamic>{};
        final country = (address['countryName'] ?? '').toString().toUpperCase();
        final state = (address['region'] ?? '').toString();
        if (country.isNotEmpty && country != 'AUSTRALIA' && country != 'AU') {
          continue;
        }
        if (state.toLowerCase() == 'outside australia') continue;
        final evidence = companies.putIfAbsent(
          key,
          () => _CompanyEvidence(
            name: name,
            state: state,
            locality: (address['locality'] ?? '').toString(),
            postcode: (address['postalCode'] ?? '').toString(),
            sourceId: source['id'].toString(),
            sourceUrl: (source['_resolved_url'] ?? source['url_template'])
                .toString(),
            licence: source['licence'].toString(),
            attribution: source['attribution'].toString(),
          ),
        );
        evidence.categories.addAll(categories);
        evidence.contractIds.add(
          (contract['id'] ?? release['ocid'] ?? '').toString(),
        );
        accepted++;
      }
    }
  }
  return accepted;
}

Set<String> _constructionCategories(Set<String> codes, String description) {
  final text = description.toLowerCase();
  final categories = <String>{};
  final constructionCode = codes.any((code) => code.startsWith('72'));
  final engineeringCode = codes.any(
    (code) => code.startsWith('811015') || code.startsWith('811016'),
  );
  final miningCode = codes.any((code) => code.startsWith('71'));
  final labourCode = codes.any((code) => code.startsWith('801116'));

  bool hasAny(Iterable<String> terms) => terms.any(text.contains);
  final miningTerms = hasAny(const [
    'mining',
    'mine ',
    'mine site',
    'drilling',
    'blasting',
    'ore ',
    'coal ',
    'quarry',
    'mineral',
  ]);
  final oilTerms = hasAny(const [
    'oil and gas',
    'oil & gas',
    'petroleum',
    'natural gas',
    'lng',
    'pipeline',
  ]);
  final renewableTerms = hasAny(const [
    'solar',
    'wind farm',
    'renewable',
    'photovoltaic',
    'battery energy',
    'transmission line',
  ]);
  final infrastructureTerms = hasAny(const [
    'rail',
    'airport',
    'port ',
    'harbour',
    'utility',
    'utilities',
    'telecommunication',
    'water treatment',
    'sewerage',
  ]);
  final civilTerms = hasAny(const [
    'road',
    'bridge',
    'earthwork',
    'drainage',
    'trenching',
    'pavement',
    'civil works',
  ]);
  final buildingTerms = hasAny(const [
    'building',
    'construction',
    'fit-out',
    'fit out',
    'refurbishment',
    'renovation',
    'roofing',
    'demolition',
  ]);

  if (renewableTerms && (constructionCode || engineeringCode)) {
    categories.add('renewables');
  }
  if (oilTerms && (constructionCode || engineeringCode || miningCode)) {
    categories.add('oil_gas_energy');
  }
  if (miningTerms && miningCode) categories.add('mining_contractor');
  if (miningTerms && (constructionCode || engineeringCode)) {
    categories.add('mining_contractor');
  }
  if (infrastructureTerms && (constructionCode || engineeringCode)) {
    categories.add('infrastructure');
  }
  if (civilTerms && (constructionCode || engineeringCode)) {
    categories.add('civil');
  }
  if (engineeringCode) categories.add('engineering_epc');
  if (constructionCode && categories.isEmpty && buildingTerms) {
    categories.add('residential_commercial');
  }
  if (labourCode &&
      (miningTerms ||
          oilTerms ||
          renewableTerms ||
          infrastructureTerms ||
          civilTerms ||
          buildingTerms)) {
    categories.add('labour_hire');
  }
  return categories;
}

String? _temporaryAbn(Map supplier) {
  for (final identifier
      in (supplier['additionalIdentifiers'] as List? ?? const [])
          .whereType<Map>()) {
    if (identifier['scheme'] == 'AU-ABN') {
      final digits = (identifier['id'] ?? '').toString().replaceAll(
        RegExp(r'\D'),
        '',
      );
      if (digits.length == 11) return digits;
    }
  }
  return null;
}

bool _looksLikeIndividual(String name) {
  final lower = name.toLowerCase();
  const organisationMarkers = [
    'pty',
    'limited',
    'ltd',
    'group',
    'services',
    'contracting',
    'construction',
    'engineering',
    'industries',
    'corporation',
    'company',
    'co.',
    'inc',
    'association',
    'council',
    'partners',
    'solutions',
  ];
  return !organisationMarkers.any(lower.contains) &&
      name.trim().split(RegExp(r'\s+')).length <= 3;
}

String _normaliseName(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .replaceAll(RegExp(r'\b(pty|ltd|limited|proprietary)\b'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

class _CompanyEvidence {
  _CompanyEvidence({
    required this.name,
    required this.state,
    required this.locality,
    required this.postcode,
    required this.sourceId,
    required this.sourceUrl,
    required this.licence,
    required this.attribution,
  });

  final String name;
  final String state;
  final String locality;
  final String postcode;
  final String sourceId;
  final String sourceUrl;
  final String licence;
  final String attribution;
  final Set<String> categories = {};
  final Set<String> contractIds = {};

  Map<String, dynamic> toPublicJson() => {
    'id': 'austender:${_normaliseName(name).replaceAll(' ', '-')}',
    'record_kind': 'company',
    'name': name,
    if (state.isNotEmpty) 'state': state,
    if (locality.isNotEmpty) 'locality': locality,
    if (postcode.isNotEmpty) 'postcode': postcode,
    'construction_categories': categories.toList()..sort(),
    'evidence_count': contractIds.length,
    'source_id': sourceId,
    'source_url': sourceUrl,
    'source_licence': licence,
    'source_attribution': attribution,
    'contacts': const <String, dynamic>{},
    'editorial_review_required': true,
  };
}

Future<void> _downloadJson(String url, File destination) async {
  final uri = Uri.parse(url);
  if (uri.scheme != 'https') {
    throw StateError('Only HTTPS sources are allowed.');
  }
  final client = HttpClient()
    ..userAgent = 'Workyday open-data catalogue builder';
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    final temporary = File('${destination.path}.tmp');
    final sink = temporary.openWrite();
    await response.pipe(sink);
    if (destination.existsSync()) await destination.delete();
    await temporary.rename(destination.path);
  } finally {
    client.close(force: true);
  }
}

List<Map<String, dynamic>> _importGeoJsonWorksites(
  Object? decoded,
  Map<String, dynamic> source,
) {
  if (decoded is! Map || decoded['features'] is! List) return const [];
  final allowed =
      (source['publication_fields'] as List?)
          ?.map((field) => field.toString())
          .toSet() ??
      const <String>{};
  final result = <Map<String, dynamic>>[];
  for (final rawFeature in (decoded['features'] as List).whereType<Map>()) {
    final properties = rawFeature['properties'];
    final geometry = rawFeature['geometry'];
    if (properties is! Map || geometry is! Map) continue;
    final name = (properties['name'] ?? '').toString().trim();
    final coordinates = geometry['coordinates'];
    if (name.isEmpty || coordinates is! List || coordinates.length < 2) {
      continue;
    }
    final longitude = coordinates[0];
    final latitude = coordinates[1];
    if (longitude is! num || latitude is! num) continue;
    final candidate = <String, dynamic>{
      'id': '${source['id']}:${properties['objectid']}',
      'record_kind': 'worksite',
      'name': name,
      'state': (properties['state'] ?? '').toString(),
      'latitude': latitude.toDouble(),
      'longitude': longitude.toDouble(),
      'status': (properties['status'] ?? '').toString(),
      'commodity_group': (properties['commodity_group'] ?? '').toString(),
      'construction_category': 'mining_company',
      'source_id': source['id'],
      'source_record_id': properties['objectid'].toString(),
      'source_url': source['url'],
      'source_licence': source['licence'],
      'source_attribution': source['attribution'],
      'operator_company_id': null,
      'verified_operator': false,
    };
    candidate.removeWhere((key, value) {
      const internalFields = {
        'id',
        'record_kind',
        'construction_category',
        'source_id',
        'source_record_id',
        'source_licence',
        'source_attribution',
        'operator_company_id',
        'verified_operator',
      };
      return !internalFields.contains(key) && !allowed.contains(key);
    });
    result.add(candidate);
  }
  return result;
}
