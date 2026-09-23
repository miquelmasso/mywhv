import 'dart:convert';
import 'package:http/http.dart' as http;
import 'construction_source_models.dart';

class ConstructionGovernmentSourceDiscovery {
  ConstructionGovernmentSourceDiscovery({http.Client? client})
    : _client = client ?? http.Client();
  final http.Client _client;

  static const _officialHosts = {
    'services.ga.gov.au',
    'data.gov.au',
    'datasets.seed.nsw.gov.au',
    'spatial.industry.nsw.gov.au',
    'qldspatial.information.qld.gov.au',
    'geoscience.data.qld.gov.au',
    'map.sarig.sa.gov.au',
    'geology.data.vic.gov.au',
    'geovic.vic.gov.au',
    'www.mrt.tas.gov.au',
    'data.nt.gov.au',
    'strike.nt.gov.au',
    'minedex.dmirs.wa.gov.au',
  };

  List<ConstructionSourceInstruction> builtInSources(String state) {
    final sources = <ConstructionSourceInstruction>[
      const ConstructionSourceInstruction(
        id: 'ga_operating_mines',
        state: 'AU',
        title: 'Australian operating mines and deposits',
        publisher: 'Geoscience Australia',
        catalogueUrl:
            'https://services.ga.gov.au/gis/rest/services/AustralianCriticalMineralsOperatingMinesAndDeposits/MapServer/4',
        dataUrl:
            'https://services.ga.gov.au/gis/rest/services/AustralianCriticalMineralsOperatingMinesAndDeposits/MapServer/4',
        format: ConstructionSourceFormat.arcgis,
        license: 'CC BY 4.0',
        attribution: 'Commonwealth of Australia (Geoscience Australia)',
        status: ConstructionSourceState.ready,
      ),
    ];
    if (state == 'WA') {
      sources.add(
        const ConstructionSourceInstruction(
          id: 'wa_minedex',
          state: 'WA',
          title: 'MINEDEX mines and mineral deposits',
          publisher: 'Government of Western Australia',
          catalogueUrl: 'https://minedex.dmirs.wa.gov.au/',
          dataUrl: 'special://wa-minedex',
          format: ConstructionSourceFormat.special,
          license: 'CC BY 4.0',
          attribution: 'Department of Mines, Petroleum and Exploration',
          status: ConstructionSourceState.ready,
        ),
      );
    }
    if (state == 'NSW') {
      for (final entry in const [
        (
          'nsw_major_mines',
          'NSW major operating mines',
          'special://nsw-major-mines',
        ),
        (
          'nsw_coal_producers',
          'NSW coal producers',
          'special://nsw-coal-producers',
        ),
        (
          'nsw_epa_premises',
          'NSW EPA licensed premises',
          'special://nsw-epa-premises',
        ),
        (
          'nsw_minerals_members',
          'NSW Minerals Council members',
          'special://nsw-minerals-members',
        ),
        (
          'nsw_minerals_mines',
          'NSW Minerals Council mines',
          'special://nsw-minerals-mines',
        ),
      ]) {
        sources.add(
          ConstructionSourceInstruction(
            id: entry.$1,
            state: 'NSW',
            title: entry.$2,
            publisher: 'NSW source registry',
            catalogueUrl: 'https://data.nsw.gov.au/',
            dataUrl: entry.$3,
            format: ConstructionSourceFormat.special,
            status: ConstructionSourceState.ready,
          ),
        );
      }
    }
    return sources;
  }

  /// Discovers candidates only in government catalogues. New candidates are
  /// saved as Needs review until sample inspection proves their schema.
  Future<List<ConstructionSourceInstruction>> discover(String state) async {
    final query = Uri.https('data.gov.au', '/data/api/3/action/package_search', {
      'q': '$state operating mines operators contractors extractive industries',
      'rows': '50',
    });
    try {
      final response = await _client
          .get(query)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return const [];
      final decoded = jsonDecode(response.body);
      final results = decoded is Map && decoded['result'] is Map
          ? (decoded['result'] as Map)['results']
          : null;
      if (results is! List) return const [];
      final found = <ConstructionSourceInstruction>[];
      for (final dataset in results.whereType<Map>()) {
        final resources = dataset['resources'];
        if (resources is! List) continue;
        for (final resource in resources.whereType<Map>()) {
          final url = (resource['url'] ?? '').toString();
          final uri = Uri.tryParse(url);
          if (uri == null || !_isOfficial(uri.host)) continue;
          final format = _format((resource['format'] ?? '').toString(), url);
          if (format == null) continue;
          final datasetId = (dataset['id'] ?? dataset['name'] ?? url)
              .toString();
          final resourceId = (resource['id'] ?? url).toString();
          found.add(
            ConstructionSourceInstruction(
              id: 'discovered:${datasetId.hashCode}:${resourceId.hashCode}',
              state: state,
              title:
                  (dataset['title'] ?? resource['name'] ?? 'Government source')
                      .toString(),
              publisher:
                  ((dataset['organization'] is Map
                              ? (dataset['organization'] as Map)['title']
                              : '') ??
                          '')
                      .toString(),
              catalogueUrl:
                  'https://data.gov.au/data/dataset/${dataset['name'] ?? datasetId}',
              dataUrl: url,
              format: format,
              license: (dataset['license_title'] ?? '').toString(),
              status: ConstructionSourceState.needsReview,
            ),
          );
        }
      }
      return found;
    } catch (_) {
      return const [];
    }
  }

  bool _isOfficial(String host) => _officialHosts.any(
    (allowed) => host == allowed || host.endsWith('.$allowed'),
  );
  ConstructionSourceFormat? _format(String raw, String url) {
    final value = '$raw $url'.toLowerCase();
    if (value.contains('arcgis') ||
        value.contains('mapserver') ||
        value.contains('featureserver')) {
      return ConstructionSourceFormat.arcgis;
    }
    if (value.contains('wfs')) return ConstructionSourceFormat.wfs;
    if (value.contains('geojson')) return ConstructionSourceFormat.geoJson;
    if (value.contains('csv')) return ConstructionSourceFormat.csv;
    if (value.contains('json')) return ConstructionSourceFormat.json;
    return null;
  }
}
