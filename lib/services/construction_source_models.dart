import 'dart:convert';

enum ConstructionSourceFormat { arcgis, wfs, geoJson, csv, json, special }

enum ConstructionSourceState { ready, needsReview, broken, disabled }

enum ConstructionBuildStage {
  snapshot,
  discoverSources,
  inspectSources,
  importSources,
  corroborate,
  enrichContacts,
  qualityReport,
  complete,
}

class ConstructionSourceInstruction {
  const ConstructionSourceInstruction({
    required this.id,
    required this.state,
    required this.title,
    required this.publisher,
    required this.catalogueUrl,
    required this.dataUrl,
    required this.format,
    this.license = '',
    this.attribution = '',
    this.mapping = const {},
    this.status = ConstructionSourceState.needsReview,
    this.isGovernment = true,
    this.lastFingerprint = '',
    this.lastError = '',
  });

  final String id, state, title, publisher, catalogueUrl, dataUrl;
  final ConstructionSourceFormat format;
  final String license, attribution, lastFingerprint, lastError;
  final Map<String, String> mapping;
  final ConstructionSourceState status;
  final bool isGovernment;

  Map<String, Object?> toMap() => {
    'id': id,
    'state': state,
    'title': title,
    'publisher': publisher,
    'catalogue_url': catalogueUrl,
    'data_url': dataUrl,
    'format': format.name,
    'license': license,
    'attribution': attribution,
    'mapping_json': jsonEncode(mapping),
    'status': status.name,
    'is_government': isGovernment ? 1 : 0,
    'last_fingerprint': lastFingerprint,
    'last_error': lastError,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };

  factory ConstructionSourceInstruction.fromMap(Map<String, Object?> row) {
    final mappingRaw = row['mapping_json']?.toString() ?? '{}';
    final decoded = jsonDecode(mappingRaw);
    return ConstructionSourceInstruction(
      id: row['id'].toString(),
      state: row['state'].toString(),
      title: row['title'].toString(),
      publisher: row['publisher'].toString(),
      catalogueUrl: row['catalogue_url'].toString(),
      dataUrl: row['data_url'].toString(),
      format: ConstructionSourceFormat.values.firstWhere(
        (v) => v.name == row['format'],
        orElse: () => ConstructionSourceFormat.json,
      ),
      license: row['license']?.toString() ?? '',
      attribution: row['attribution']?.toString() ?? '',
      mapping: decoded is Map
          ? decoded.map((k, v) => MapEntry(k.toString(), v.toString()))
          : const {},
      status: ConstructionSourceState.values.firstWhere(
        (v) => v.name == row['status'],
        orElse: () => ConstructionSourceState.needsReview,
      ),
      isGovernment: row['is_government'] == 1,
      lastFingerprint: row['last_fingerprint']?.toString() ?? '',
      lastError: row['last_error']?.toString() ?? '',
    );
  }

  ConstructionSourceInstruction copyWith({
    Map<String, String>? mapping,
    ConstructionSourceState? status,
    String? dataUrl,
    String? lastFingerprint,
    String? lastError,
  }) => ConstructionSourceInstruction(
    id: id,
    state: state,
    title: title,
    publisher: publisher,
    catalogueUrl: catalogueUrl,
    dataUrl: dataUrl ?? this.dataUrl,
    format: format,
    license: license,
    attribution: attribution,
    mapping: mapping ?? this.mapping,
    status: status ?? this.status,
    isGovernment: isGovernment,
    lastFingerprint: lastFingerprint ?? this.lastFingerprint,
    lastError: lastError ?? this.lastError,
  );
}

class ConstructionBuildControl {
  bool _cancelled = false;
  bool _skipSource = false;
  bool _skipCompany = false;
  bool _skipPostcode = false;

  bool get isCancelled => _cancelled;
  void stopAndSave() => _cancelled = true;
  void skipSource() => _skipSource = true;
  void skipCompany() => _skipCompany = true;
  void skipPostcode() => _skipPostcode = true;
  bool takeSkipSource() {
    final value = _skipSource;
    _skipSource = false;
    return value;
  }

  bool takeSkipCompany() {
    final value = _skipCompany;
    _skipCompany = false;
    return value;
  }

  bool takeSkipPostcode() {
    final value = _skipPostcode;
    _skipPostcode = false;
    return value;
  }
}

class ConstructionBuildReport {
  const ConstructionBuildReport({
    required this.runId,
    required this.state,
    required this.status,
    required this.before,
    required this.after,
    required this.sourcesReady,
    required this.sourcesNeedingReview,
    required this.errors,
    required this.publicationSafe,
  });
  final String runId, state, status;
  final Map<String, int> before, after;
  final int sourcesReady, sourcesNeedingReview;
  final List<String> errors;
  final bool publicationSafe;
}
