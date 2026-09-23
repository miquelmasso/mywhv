import 'dart:convert';

import 'package:flutter/services.dart';

class ConstructionValidationCatalogService {
  ConstructionValidationCatalogService._();

  static final ConstructionValidationCatalogService instance =
      ConstructionValidationCatalogService._();
  static const _assetPath = 'export/construction_validated_names.json';
  static const _openDataAssetPath =
      'export/construction_open_data_snapshot.json';

  Set<String>? _validatedNames;
  Map<String, Map<String, dynamic>>? _openDataCompanies;
  List<Map<String, dynamic>>? _openDataWorksites;

  Future<bool> isValidatedCompanyName(String name) async {
    final names = await _loadNames();
    return names.contains(normalizeCompanyName(name));
  }

  Future<Map<String, dynamic>?> findOpenDataEvidence(String name) async {
    final companies = await _loadOpenDataCompanies();
    final match = companies[normalizeCompanyName(name)];
    return match == null ? null : Map<String, dynamic>.from(match);
  }

  Future<Map<String, dynamic>?> findOpenDataWorksiteEvidence(
    String name, {
    String? state,
  }) async {
    await _loadOpenDataCompanies();
    final normalizedName = normalizeCompanyName(name);
    if (normalizedName.isEmpty) return null;
    final normalizedState = (state ?? '').trim().toUpperCase();
    for (final worksite in _openDataWorksites ?? const []) {
      if (normalizeCompanyName((worksite['name'] ?? '').toString()) !=
          normalizedName) {
        continue;
      }
      final worksiteState = (worksite['state'] ?? '')
          .toString()
          .trim()
          .toUpperCase();
      if (normalizedState.isNotEmpty &&
          worksiteState.isNotEmpty &&
          normalizedState != worksiteState) {
        continue;
      }
      return Map<String, dynamic>.from(worksite);
    }
    return null;
  }

  Future<Map<String, Map<String, dynamic>>> _loadOpenDataCompanies() async {
    final cached = _openDataCompanies;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString(_openDataAssetPath);
    final decoded = jsonDecode(raw);
    final values = decoded is Map ? decoded['companies'] : null;
    final companies = <String, Map<String, dynamic>>{};
    if (values is List) {
      for (final value in values.whereType<Map>()) {
        final row = Map<String, dynamic>.from(value);
        final key = normalizeCompanyName((row['name'] ?? '').toString());
        if (key.isNotEmpty) companies[key] = row;
      }
    }
    final rawWorksites = decoded is Map ? decoded['unlinked_worksites'] : null;
    _openDataWorksites = rawWorksites is List
        ? rawWorksites
              .whereType<Map>()
              .map((value) => Map<String, dynamic>.from(value))
              .toList(growable: false)
        : <Map<String, dynamic>>[];
    _openDataCompanies = companies;
    return companies;
  }

  Future<Set<String>> _loadNames() async {
    final cached = _validatedNames;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString(_assetPath);
    final decoded = jsonDecode(raw);
    final values = decoded is Map ? decoded['companies'] : null;
    final names = values is List
        ? values
              .map((value) => normalizeCompanyName(value.toString()))
              .where((value) => value.isNotEmpty)
              .toSet()
        : <String>{};
    _validatedNames = names;
    return names;
  }

  static String normalizeCompanyName(String value) => value
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(
        RegExp(r'\b(proprietary|pty|limited|ltd|australia|aust)\b'),
        '',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
