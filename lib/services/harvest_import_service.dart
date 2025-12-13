import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

class HarvestImportProgress {
  final int regionsParsed;
  final int docsWritten;
  final int errors;
  final String message;

  const HarvestImportProgress({
    required this.regionsParsed,
    required this.docsWritten,
    required this.errors,
    required this.message,
  });

  HarvestImportProgress copyWith({
    int? regionsParsed,
    int? docsWritten,
    int? errors,
    String? message,
  }) {
    return HarvestImportProgress(
      regionsParsed: regionsParsed ?? this.regionsParsed,
      docsWritten: docsWritten ?? this.docsWritten,
      errors: errors ?? this.errors,
      message: message ?? this.message,
    );
  }
}

class HarvestImportResult {
  final int regions;
  final int docs;
  final int errors;
  final int? httpStatus;
  final int? bodyLength;
  final String? finalUrl;
  final String? snippet;
  final String? exception;
  const HarvestImportResult({
    required this.regions,
    required this.docs,
    required this.errors,
    this.httpStatus,
    this.bodyLength,
    this.finalUrl,
    this.snippet,
    this.exception,
  });
}

class HarvestImportService {
  static const _url = 'https://www.backpackerjobboard.com.au/harvest/';
  static const _keywords = [
    'harvest',
    'postcode',
    'post code',
    'region',
    'calendar',
    'month',
    'jan',
    'feb',
    'nsw',
    'qld',
    'vic',
    'tas',
    'sa',
    'wa',
    'nt',
    'act',
  ];

  Future<HarvestImportResult> importHarvest({
    required void Function(HarvestImportProgress) onProgress,
  }) async {
    try {
      onProgress(const HarvestImportProgress(
        regionsParsed: 0,
        docsWritten: 0,
        errors: 0,
        message: 'Descarregant...',
      ));

      final resp = await _fetchHtml();
      final status = resp.statusCode;
      final finalUrl = resp.request?.url.toString() ?? _url;
      final bodyText = utf8.decode(resp.bodyBytes);
      final bodyLen = bodyText.length;
      final snippet =
          bodyText.substring(0, bodyText.length > 500 ? 500 : bodyText.length);

      if (status != 200) {
        final msg = 'HTTP $status\nURL: $finalUrl\nBody length: $bodyLen\nSnippet: $snippet';
        onProgress(HarvestImportProgress(
          regionsParsed: 0,
          docsWritten: 0,
          errors: 1,
          message: msg,
        ));
        return HarvestImportResult(
          regions: 0,
          docs: 0,
          errors: 1,
          httpStatus: status,
          bodyLength: bodyLen,
          finalUrl: finalUrl,
          snippet: snippet,
        );
      }

      if (status == 403 || status == 429 || bodyLen < 5000) {
        final msg =
            'The site might block direct HTTP scraping. Try WebView extraction fallback.\nHTTP $status\nURL: $finalUrl\nBody length: $bodyLen\nSnippet: $snippet';
        onProgress(HarvestImportProgress(
          regionsParsed: 0,
          docsWritten: 0,
          errors: 1,
          message: msg,
        ));
        return HarvestImportResult(
          regions: 0,
          docs: 0,
          errors: 1,
          httpStatus: status,
          bodyLength: bodyLen,
          finalUrl: finalUrl,
          snippet: snippet,
        );
      }

      final diag = _diagnose(bodyText);
      final document = html.parse(bodyText);
      final parsedRegionsList = _parseFromScripts(document) ??
          _parseFromTables(document) ??
          _parseFromHeadings(document);
      int parsed = 0;
      int written = 0;
      int errors = 0;

      final firestore = FirebaseFirestore.instance;
      WriteBatch batch = firestore.batch();
      int batchCount = 0;

      Future<void> commitBatch() async {
        if (batchCount == 0) return;
        await batch.commit();
        batch = firestore.batch();
        batchCount = 0;
      }

      final regions = parsedRegionsList ?? [];

      for (final region in regions) {
        final docId = _buildId(region.state, region.postcode, region.regionName);
        final data = {
          'state': region.state,
          'region_name': region.regionName,
          'postcode': region.postcode,
          'map_url': region.mapUrl,
          'crops': region.crops,
          'timestamp': FieldValue.serverTimestamp(),
          'source_url': _url,
          if (region.latLng != null) 'latitude': region.latLng!.$1,
          if (region.latLng != null) 'longitude': region.latLng!.$2,
        };

        batch.set(
          firestore.collection('harvest_calendar').doc(docId),
          data,
          SetOptions(merge: true),
        );
        batchCount++;
        parsed++;
        written++;

        if (batchCount >= 450) {
          await commitBatch();
        }

        onProgress(HarvestImportProgress(
          regionsParsed: parsed,
          docsWritten: written,
          errors: errors,
          message: 'Processant ${region.regionName} (${region.state})...',
        ));
      }

      await commitBatch();

      if (parsed == 0) {
        final msg =
            'HTML parsed 0 regions; selectors changed or blocked.\nBody length: $bodyLen\nSnippet: $snippet';
        onProgress(HarvestImportProgress(
          regionsParsed: 0,
          docsWritten: 0,
          errors: errors + 1,
          message: msg,
        ));
        await firestore.collection('harvest_import_debug').doc('last').set({
          'httpStatus': status,
          'bodyLength': bodyLen,
          'url': finalUrl,
          'first1000Chars': bodyText.substring(0, bodyText.length > 1000 ? 1000 : bodyText.length),
          'diagnostic': diag.toJson(),
          'timestamp': FieldValue.serverTimestamp(),
        });
        return HarvestImportResult(
          regions: 0,
          docs: 0,
          errors: errors + 1,
          httpStatus: status,
          bodyLength: bodyLen,
          finalUrl: finalUrl,
          snippet: snippet,
        );
      }

      onProgress(HarvestImportProgress(
        regionsParsed: parsed,
        docsWritten: written,
        errors: errors,
        message: 'Completat',
      ));

      return HarvestImportResult(
        regions: parsed,
        docs: written,
        errors: errors,
        httpStatus: status,
        bodyLength: bodyLen,
        finalUrl: finalUrl,
        snippet: snippet,
      );
    } catch (e, st) {
      onProgress(HarvestImportProgress(
        regionsParsed: 0,
        docsWritten: 0,
        errors: 1,
        message: 'Exception: $e',
      ));
      // ignore: avoid_print
      print('Harvest import error: $e\n$st');
      return HarvestImportResult(
        regions: 0,
        docs: 0,
        errors: 1,
        exception: e.toString(),
      );
    }
  }

  Future<http.Response> _fetchHtml() {
    return http.get(
      Uri.parse(_url),
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile',
        'Accept': 'text/html,application/xhtml+xml',
        'Accept-Language': 'en-AU,en;q=0.9',
        'Cache-Control': 'no-cache',
      },
    );
  }

  _HarvestDiagnostic _diagnose(String body) {
    final matches = <String, List<String>>{};
    for (final key in _keywords) {
      final re = RegExp(key, caseSensitive: false);
      final all = re.allMatches(body).toList();
      if (all.isEmpty) continue;
      matches[key] = all.take(3).map((m) {
        final start = (m.start - 300).clamp(0, body.length);
        final end = (m.end + 300).clamp(0, body.length);
        return body.substring(start, end);
      }).toList();
    }
    return _HarvestDiagnostic(matches: matches);
  }

  List<_HarvestRegion>? _parseFromScripts(dynamic document) {
    final scripts = document.querySelectorAll('script');
    for (final s in scripts) {
      final type = s.attributes['type'] ?? '';
      final content = s.text;
      if (type.contains('ld+json')) {
        final regions = _parseJsonAny(content);
        if (regions != null && regions.isNotEmpty) return regions;
      } else if (content.contains('{') && content.contains('}')) {
        final regions = _parseJsonFromScript(content);
        if (regions != null && regions.isNotEmpty) return regions;
      }
    }
    return null;
  }

  List<_HarvestRegion>? _parseFromTables(dynamic document) {
    final tables = document.querySelectorAll('table');
    final regions = <_HarvestRegion>[];
    for (final table in tables) {
      final headers = table.querySelectorAll('th').map((e) => e.text.toLowerCase()).toList();
      final hasMonths = headers.any((h) => h.contains('jan')) || headers.length >= 12;
      if (!hasMonths && !headers.any((h) => h.contains('postcode') || h.contains('post code'))) {
        continue;
      }
      final rows = table.querySelectorAll('tr');
      if (rows.length < 2) continue;
      final headerCells = rows.first.querySelectorAll('th');
      final monthIndexes = <int>[];
      for (var i = 0; i < headerCells.length; i++) {
        final t = headerCells[i].text.toLowerCase();
        if (t.contains('jan') ||
            t.contains('feb') ||
            t.contains('mar') ||
            t.contains('apr') ||
            t.contains('may') ||
            t.contains('jun') ||
            t.contains('jul') ||
            t.contains('aug') ||
            t.contains('sep') ||
            t.contains('oct') ||
            t.contains('nov') ||
            t.contains('dec')) {
          monthIndexes.add(i);
        }
      }
      for (final row in rows.skip(1)) {
        final cells = row.querySelectorAll('td');
        if (cells.length < 2) continue;
        final name = cells.first.text.trim();
        if (name.isEmpty) continue;
        final postcode = _extractPostcode(row.text) ?? '';
        final months = <int>[];
        if (monthIndexes.isNotEmpty) {
          for (final idx in monthIndexes.take(12)) {
            if (idx < cells.length) {
              months.add(_monthValue(cells[idx].text));
            }
          }
        } else if (cells.length >= 13) {
          months.addAll(cells.skip(1).take(12).map((c) => _monthValue(c.text)));
        }
        regions.add(_HarvestRegion(
          state: '',
          regionName: name,
          postcode: postcode,
          mapUrl: '',
          crops: [
            {'crop': name, 'months': months.isEmpty ? List.filled(12, 0) : months}
          ],
          latLng: null,
        ));
      }
    }
    return regions.isEmpty ? null : regions;
  }

  List<_HarvestRegion>? _parseFromHeadings(dynamic document) {
    final headings = document.querySelectorAll('h2, h3');
    final stateHeadings = headings
        .where((h) => _isStateHeading(h.text))
        .toList();
    final regions = <_HarvestRegion>[];
    for (final h in stateHeadings) {
      final state = h.text.trim().split(' ').first.toUpperCase();
      var el = h.nextElementSibling;
      while (el != null && !(el.localName == 'h2' || el.localName == 'h3')) {
        final text = el.text;
        final postcode = _extractPostcode(text) ?? '';
        if (postcode.isNotEmpty || text.toLowerCase().contains('postcode')) {
          final regionName = text.split('\n').first.trim();
          regions.add(_HarvestRegion(
            state: state,
            regionName: regionName,
            postcode: postcode,
            mapUrl: '',
            crops: const [],
            latLng: null,
          ));
        }
        el = el.nextElementSibling;
      }
    }
    return regions.isEmpty ? null : regions;
  }

  List<_HarvestRegion>? _parseJsonAny(String content) {
    try {
      final data = jsonDecode(content);
      if (data is List) {
        return _regionsFromJsonList(data);
      } else if (data is Map<String, dynamic>) {
        return _regionsFromJson(data);
      }
    } catch (_) {}
    return null;
  }

  List<_HarvestRegion>? _parseJsonFromScript(String content) {
    final re = RegExp(r'=\s*({.*});', dotAll: true);
    final match = re.firstMatch(content);
    if (match != null) {
      final jsonStr = match.group(1);
      if (jsonStr != null) {
        return _parseJsonAny(jsonStr);
      }
    }
    return null;
  }

  List<_HarvestRegion>? _regionsFromJsonList(List data) {
    final regions = <_HarvestRegion>[];
    for (final item in data) {
      if (item is Map<String, dynamic>) {
        final region = _regionFromMap(item);
        if (region != null) regions.add(region);
      }
    }
    return regions.isEmpty ? null : regions;
  }

  List<_HarvestRegion>? _regionsFromJson(Map<String, dynamic> data) {
    final regions = <_HarvestRegion>[];
    for (final entry in data.entries) {
      final val = entry.value;
      if (val is List) {
        final parsed = _regionsFromJsonList(val);
        if (parsed != null) regions.addAll(parsed);
      } else if (val is Map<String, dynamic>) {
        final region = _regionFromMap(val);
        if (region != null) regions.add(region);
      }
    }
    return regions.isEmpty ? null : regions;
  }

  _HarvestRegion? _regionFromMap(Map<String, dynamic> map) {
    final name = map['region'] ?? map['name'] ?? '';
    if (name.toString().isEmpty) return null;
    final postcode = map['postcode']?.toString() ?? '';
    final state = (map['state'] ?? '').toString().toUpperCase();
    final mapUrl = map['map_url']?.toString() ?? '';
    final cropsRaw = map['crops'];
    final crops = <Map<String, dynamic>>[];
    if (cropsRaw is List) {
      for (final c in cropsRaw) {
        if (c is Map<String, dynamic>) {
          final cropName = c['crop']?.toString() ?? '';
          final months = (c['months'] as List?)?.map((e) => _parseInt(e)).toList() ??
              List.filled(12, 0);
          crops.add({'crop': cropName, 'months': months});
        }
      }
    }
    return _HarvestRegion(
      state: state,
      regionName: name.toString(),
      postcode: postcode,
      mapUrl: mapUrl,
      crops: crops,
      latLng: null,
    );
  }

  bool _isStateHeading(String text) {
    final t = text.toUpperCase().trim();
    return ['NSW', 'QLD', 'VIC', 'TAS', 'SA', 'WA', 'NT', 'ACT'].any(t.contains);
  }

  int _parseInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;

  String _buildId(String state, String postcode, String region) {
    final safeRegion = region
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim()
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final pc = postcode.isEmpty ? 'nopc' : postcode;
    return '${state}_${pc}_$safeRegion';
  }

  String? _extractPostcode(String text) {
    final re = RegExp(r'\b(\d{4})\b');
    final m = re.firstMatch(text);
    return m?.group(1);
  }

  (double, double)? _extractLatLng(String url) {
    try {
      final uri = Uri.parse(url);
      final query = uri.queryParameters['q'] ?? uri.queryParameters['query'];
      final target = query ?? uri.pathSegments.join(',');
      final re = RegExp(r'(-?\d{1,3}\.\d+)[, ]+(-?\d{1,3}\.\d+)');
      final m = re.firstMatch(target);
      if (m != null) {
        final lat = double.parse(m.group(1)!);
        final lng = double.parse(m.group(2)!);
        return (lat, lng);
      }
    } catch (_) {}
    return null;
  }

  int _monthValue(String raw) {
    final l = raw.toLowerCase();
    if (l.contains('high')) return 2;
    if (l.contains('med')) return 1;
    return 0;
  }
}

class _HarvestRegion {
  final String state;
  final String regionName;
  final String postcode;
  final String mapUrl;
  final List<Map<String, dynamic>> crops;
  final (double, double)? latLng;

  _HarvestRegion({
    required this.state,
    required this.regionName,
    required this.postcode,
    required this.mapUrl,
    required this.crops,
    required this.latLng,
  });
}

class _HarvestDiagnostic {
  final Map<String, List<String>> matches;
  _HarvestDiagnostic({required this.matches});

  Map<String, dynamic> toJson() => {
        'matches': matches.map((k, v) => MapEntry(k, v)),
      };
}
