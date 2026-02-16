import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/guide_manual/guide_manual.dart';

class GuideManualRepository {
  static String? overrideLocaleCode;

  String _stringsPathForLocale(Locale locale) {
    final lang = locale.languageCode.toLowerCase();
    if (lang.startsWith('es')) return 'assets/data/guide_manual.strings.es.json';
    if (lang.startsWith('fr')) return 'assets/data/guide_manual.strings.fr.json';
    if (lang.startsWith('de')) return 'assets/data/guide_manual.strings.de.json';
    if (lang.startsWith('hi')) return 'assets/data/guide_manual.strings.hi.json';
    return 'assets/data/guide_manual.strings.en.json';
  }

  void _validateKeys(Map<String, dynamic> jsonMap, Map<String, String> strings) {
    if (!kDebugMode) return;
    final found = <String>{};
    final empties = <String>{};
    void collect(dynamic node) {
      if (node is Map) {
        node.forEach((key, value) {
          if (key == 'strings') return;
          collect(value);
        });
      } else if (node is List) {
        for (final v in node) {
          collect(v);
        }
      } else if (node is String && node.startsWith('@')) {
        found.add(node.substring(1));
      }
    }

    collect(jsonMap);
    final missing = found.where((k) => !strings.containsKey(k)).toList()..sort();
    for (final k in found) {
      final v = strings[k];
      if (v != null && v.trim().isEmpty) {
        empties.add(k);
      }
    }
    debugPrint('Guide i18n missing: ${missing.length} | empty: ${empties.length}');
    if (missing.isNotEmpty) debugPrint('Missing keys: ${missing.join(', ')}');
    if (empties.isNotEmpty) debugPrint('Empty keys: ${empties.join(', ')}');
  }

  Future<GuideManual> loadByLocaleCode(String code) async {
    overrideLocaleCode = code;
    return loadFromAssets();
  }

  Future<GuideManual> loadFromAssets() async {
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    final targetLocale = overrideLocaleCode != null ? Locale(overrideLocaleCode!) : locale;
    final stringsPath = _stringsPathForLocale(targetLocale);
    try {
      final structureRaw =
          await rootBundle.loadString('assets/data/guide_manual.structure.json');
      final structure = json.decode(structureRaw) as Map<String, dynamic>;

      final stringsRaw = await rootBundle.loadString(stringsPath);
      final stringsJson = json.decode(stringsRaw) as Map<String, dynamic>;
      final strings = (stringsJson['strings'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          ) ??
          <String, String>{};

      final combined = Map<String, dynamic>.from(structure)
        ..['strings'] = strings
        ..['lang'] = stringsJson['lang'] ?? targetLocale.languageCode;

      final manual = GuideManual.fromJson(combined);
      _validateKeys(combined, manual.strings);
      debugPrint('Guide loaded structure + ${stringsPath} (${manual.strings.length} strings)');
      return manual;
    } catch (_) {
      // Fallback a l’arxiu original si el fitxer per idioma no existeix
      final structureRaw =
          await rootBundle.loadString('assets/data/guide_manual.structure.json');
      final structure = json.decode(structureRaw) as Map<String, dynamic>;
      final stringsRaw =
          await rootBundle.loadString('assets/data/guide_manual.strings.en.json');
      final stringsJson = json.decode(stringsRaw) as Map<String, dynamic>;
      final strings = (stringsJson['strings'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          ) ??
          <String, String>{};
      final combined = Map<String, dynamic>.from(structure)
        ..['strings'] = strings
        ..['lang'] = stringsJson['lang'] ?? 'en';
      final manual = GuideManual.fromJson(combined);
      _validateKeys(combined, manual.strings);
      debugPrint(
          'Guide fallback structure + guide_manual.strings.en.json (${manual.strings.length} strings)');
      return manual;
    }
  }
}
