class ConstructionSourceInspection {
  const ConstructionSourceInspection(
    this.mapping,
    this.confidence,
    this.warnings,
  );
  final Map<String, String> mapping;
  final double confidence;
  final List<String> warnings;
}

class ConstructionSourceInspector {
  static const _candidates = <String, List<String>>{
    'worksite_name': [
      'site name',
      'mine name',
      'project name',
      'facility name',
      'operation name',
      'worksite',
    ],
    'operator': [
      'operator',
      'operator name',
      'operating company',
      'mine operator',
    ],
    'contractor': ['contractor', 'principal contractor', 'mining contractor'],
    'owner': ['owner', 'ownership', 'parent company'],
    'licence_holder': [
      'licence holder',
      'licensee',
      'title holder',
      'tenement holder',
    ],
    'status': ['status', 'operating status', 'stage'],
    'state': ['state', 'jurisdiction'],
    'postcode': ['postcode', 'postal code'],
    'latitude': ['latitude', 'lat', '_latitude'],
    'longitude': ['longitude', 'lon', 'lng', 'long', '_longitude'],
    'record_id': ['objectid', 'id', 'record id', 'site id', 'mine id'],
  };

  ConstructionSourceInspection inspect(List<Map<String, dynamic>> records) {
    if (records.isEmpty) {
      return const ConstructionSourceInspection({}, 0, [
        'The source returned no sample records.',
      ]);
    }
    final keys = <String>{};
    for (final row in records.take(25)) {
      keys.addAll(row.keys);
    }
    String normal(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[_\-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final mapping = <String, String>{};
    for (final role in _candidates.entries) {
      for (final wanted in role.value) {
        final match = keys.where((k) => normal(k) == wanted).firstOrNull;
        if (match != null) {
          mapping[role.key] = match;
          break;
        }
      }
    }
    final warnings = <String>[];
    if (!mapping.containsKey('worksite_name')) {
      warnings.add('No reliable worksite-name field was found.');
    }
    if (!mapping.containsKey('operator') && !mapping.containsKey('contractor')) {
      warnings.add(
        'No explicit operator or contractor field was found; owners and licence holders will not be treated as employers.',
      );
    }
    if (!mapping.containsKey('latitude') || !mapping.containsKey('longitude')) {
      warnings.add('Coordinates were not recognised.');
    }
    final essential = ['worksite_name', 'latitude', 'longitude'];
    final score =
        essential.where(mapping.containsKey).length / essential.length;
    return ConstructionSourceInspection(mapping, score, warnings);
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
