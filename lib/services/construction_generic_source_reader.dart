import 'dart:convert';
import 'package:http/http.dart' as http;
import 'construction_source_models.dart';

class ConstructionSourceReadResult {
  const ConstructionSourceReadResult(this.records, this.fingerprint);
  final List<Map<String, dynamic>> records;
  final String fingerprint;
}

class ConstructionGenericSourceReader {
  ConstructionGenericSourceReader({http.Client? client})
    : _client = client ?? http.Client();
  final http.Client _client;

  Future<ConstructionSourceReadResult> read(
    ConstructionSourceInstruction source, {
    ConstructionBuildControl? control,
    int maxRecords = 10000,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (control?.isCancelled == true) throw const _Cancelled();
    if (source.format == ConstructionSourceFormat.special) {
      throw UnsupportedError(
        'Special sources must use their registered adapter.',
      );
    }
    var uri = Uri.parse(source.dataUrl);
    if (source.format == ConstructionSourceFormat.arcgis) {
      final path = uri.path.endsWith('/query') ? uri.path : '${uri.path}/query';
      uri = uri.replace(
        path: path,
        queryParameters: {
          'where': '1=1',
          'outFields': '*',
          'returnGeometry': 'true',
          'outSR': '4326',
          'f': 'geojson',
          'resultRecordCount': '$maxRecords',
        },
      );
    } else if (source.format == ConstructionSourceFormat.wfs) {
      uri = uri.replace(
        queryParameters: {
          ...uri.queryParameters,
          'service': 'WFS',
          'request': 'GetFeature',
          'version': '2.0.0',
          'outputFormat': 'application/json',
          'count': '$maxRecords',
        },
      );
    }
    final response = await _client
        .get(
          uri,
          headers: const {
            'Accept':
                'application/geo+json, application/json, text/csv;q=0.9, */*;q=0.5',
            'User-Agent': 'WorkyDay-Construction-Admin/1.0',
          },
        )
        .timeout(timeout);
    if (control?.isCancelled == true) throw const _Cancelled();
    if (response.statusCode != 200) {
      throw StateError('HTTP ${response.statusCode}');
    }
    final body = response.body;
    if (body.length > 40 * 1024 * 1024) {
      throw const FormatException(
        'Source is larger than the safe 40 MB limit.',
      );
    }
    final records = source.format == ConstructionSourceFormat.csv
        ? _readCsv(body)
        : _readJson(body);
    final bounded = records.take(maxRecords).toList(growable: false);
    return ConstructionSourceReadResult(bounded, _fingerprint(body));
  }

  List<Map<String, dynamic>> _readJson(String body) {
    final decoded = jsonDecode(body);
    dynamic list = decoded;
    if (decoded is Map) {
      list =
          decoded['features'] ??
          decoded['records'] ??
          decoded['results'] ??
          decoded['data'];
    }
    if (list is! List) {
      throw const FormatException('No record list found in JSON source.');
    }
    return list
        .whereType<Map>()
        .map((item) {
          final row = <String, dynamic>{};
          final properties = item['properties'];
          if (properties is Map) {
            row.addAll(properties.map((k, v) => MapEntry(k.toString(), v)));
          }
          row.addAll(item.map((k, v) => MapEntry(k.toString(), v)));
          final geometry = item['geometry'];
          if (geometry is Map && geometry['coordinates'] is List) {
            final c = geometry['coordinates'] as List;
            if (c.length >= 2) {
              row['_longitude'] = c[0];
              row['_latitude'] = c[1];
            }
          }
          return row;
        })
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _readCsv(String body) {
    final rows = _csvRows(body);
    if (rows.isEmpty) return const [];
    final headers = rows.first.map((v) => v.trim()).toList();
    return rows
        .skip(1)
        .where((r) => r.any((v) => v.trim().isNotEmpty))
        .map((r) {
          final result = <String, dynamic>{};
          for (var i = 0; i < headers.length; i++) {
            result[headers[i]] = i < r.length ? r[i].trim() : '';
          }
          return result;
        })
        .toList(growable: false);
  }

  List<List<String>> _csvRows(String value) {
    final result = <List<String>>[];
    var row = <String>[];
    var field = StringBuffer();
    var quoted = false;
    for (var i = 0; i < value.length; i++) {
      final c = value[i];
      if (c == '"') {
        if (quoted && i + 1 < value.length && value[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (c == ',' && !quoted) {
        row.add(field.toString());
        field = StringBuffer();
      } else if ((c == '\n' || c == '\r') && !quoted) {
        if (c == '\r' && i + 1 < value.length && value[i + 1] == '\n') i++;
        row.add(field.toString());
        result.add(row);
        row = <String>[];
        field = StringBuffer();
      } else {
        field.write(c);
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      result.add(row);
    }
    return result;
  }

  String _fingerprint(String body) {
    var hash = 0x811c9dc5;
    for (final unit in body.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return '${body.length}:${hash.toRadixString(16)}';
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}
