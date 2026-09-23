import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ConstructionImportFailure {
  const ConstructionImportFailure({
    required this.state,
    required this.postcode,
    required this.kind,
    required this.message,
    required this.failedAt,
    required this.attempts,
  });

  final String state;
  final String postcode;
  final String kind;
  final String message;
  final String failedAt;
  final int attempts;

  Map<String, dynamic> toJson() => {
    'state': state,
    'postcode': postcode,
    'kind': kind,
    'message': message,
    'failed_at': failedAt,
    'attempts': attempts,
  };

  factory ConstructionImportFailure.fromJson(Map<String, dynamic> json) =>
      ConstructionImportFailure(
        state: (json['state'] ?? '').toString(),
        postcode: (json['postcode'] ?? '').toString(),
        kind: (json['kind'] ?? 'unknown').toString(),
        message: (json['message'] ?? '').toString(),
        failedAt: (json['failed_at'] ?? '').toString(),
        attempts: int.tryParse((json['attempts'] ?? 1).toString()) ?? 1,
      );
}

class ConstructionImportDiagnosticsService {
  ConstructionImportDiagnosticsService._();

  static final ConstructionImportDiagnosticsService instance =
      ConstructionImportDiagnosticsService._();
  static const _storageKey = 'construction_import_failures_v1';

  Future<List<ConstructionImportFailure>> loadFailures({String? state}) async {
    final all = await _loadAll();
    final values =
        all.values
            .where((failure) => state == null || failure.state == state)
            .toList(growable: false)
          ..sort((a, b) => a.postcode.compareTo(b.postcode));
    return values;
  }

  Future<void> recordFailure({
    required String state,
    required String postcode,
    required Object error,
  }) async {
    final all = await _loadAll();
    final key = _key(state, postcode);
    final previous = all[key];
    final message = error.toString();
    all[key] = ConstructionImportFailure(
      state: state,
      postcode: postcode,
      kind: classifyError(error),
      message: message.length <= 300 ? message : message.substring(0, 300),
      failedAt: DateTime.now().toUtc().toIso8601String(),
      attempts: (previous?.attempts ?? 0) + 1,
    );
    await _save(all);
  }

  Future<void> markSuccessful(String state, String postcode) async {
    final all = await _loadAll();
    if (all.remove(_key(state, postcode)) != null) await _save(all);
  }

  Future<String> exportFailuresJson({String? state}) async {
    final failures = await loadFailures(state: state);
    final directory = await getApplicationDocumentsDirectory();
    final suffix = state == null ? 'all' : state.toLowerCase();
    final file = File(
      '${directory.path}/construction_failed_postcodes_$suffix.json',
    );
    await file.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(failures.map((failure) => failure.toJson()).toList()),
      flush: true,
    );
    return file.path;
  }

  String classifyError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('nominatim')) return 'postcode_lookup';
    if (message.contains('http 429') || message.contains('returned http 429')) {
      return 'rate_limited';
    }
    if (message.contains('timeout')) return 'timeout';
    if (message.contains('overpass')) return 'overpass_unavailable';
    if (message.contains('format') || message.contains('json')) {
      return 'invalid_response';
    }
    return 'unknown';
  }

  Future<Map<String, ConstructionImportFailure>> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return {};
      final failures = decoded
          .whereType<Map>()
          .map(
            (item) => ConstructionImportFailure.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where(
            (failure) =>
                failure.state.isNotEmpty && failure.postcode.isNotEmpty,
          );
      return {
        for (final failure in failures)
          _key(failure.state, failure.postcode): failure,
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _save(Map<String, ConstructionImportFailure> failures) async {
    final prefs = await SharedPreferences.getInstance();
    final values = failures.values.toList()
      ..sort(
        (a, b) =>
            '${a.state}${a.postcode}'.compareTo('${b.state}${b.postcode}'),
      );
    await prefs.setString(
      _storageKey,
      jsonEncode(values.map((failure) => failure.toJson()).toList()),
    );
  }

  static String _key(String state, String postcode) => '$state:$postcode';
}
