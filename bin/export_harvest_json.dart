import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

const sourceUrl = 'https://www.backpackerjobboard.com.au/harvest/';

int intensityTokenToInt(String t) {
  final s = t.trim().toLowerCase();
  if (s == 'high') return 2;
  if (s == 'med') return 1;
  return 0;
}

String normalizeState(String h2Text) {
  // La pàgina fa H2 com "New South Wales", "Queensland", etc.
  final t = h2Text.trim().toLowerCase();
  return switch (t) {
    'new south wales' => 'NSW',
    'northern territory' => 'NT',
    'queensland' => 'QLD',
    'south australia' => 'SA',
    'tasmania' => 'TAS',
    'victoria' => 'VIC',
    'western australia' => 'WA',
    _ => h2Text.trim(),
  };
}

bool looksLikeRegionHeader(String text) {
  // Exemple: "Ballina (postcode: 2478)" (a vegades sense postcode en algun estat)
  final t = text.toLowerCase();
  return t.contains('(postcode:') || RegExp(r'\([^)]+\)').hasMatch(text);
}

String? extractPostcode(String text) {
  final m = RegExp(r'\(postcode:\s*([0-9]{3,4})\)', caseSensitive: false).firstMatch(text);
  return m?.group(1);
}

String extractRegionName(String text) {
  // Treu "Ballina" de "Ballina (postcode: 2478)"
  final idx = text.indexOf('(');
  if (idx > 0) return text.substring(0, idx).trim();
  return text.trim();
}

List<int> parseMonthsFromLineTokens(List<String> tokens) {
  // A la pàgina, després del nom del cultiu apareixen tokens "med/high" per alguns mesos.
  // Però el text “Crop Jan J Feb F ... Dec D” també està barrejat al DOM segons com.
  // Estratègia robusta:
  // - quedem-nos només amb tokens que siguin "med" o "high"
  // - els posem en ordre i els mapegem a mesos seqüencialment (Jan..Dec) fins a 12
  final levels = tokens
      .map((e) => e.trim().toLowerCase())
      .where((e) => e == 'med' || e == 'high')
      .map(intensityTokenToInt)
      .toList();

  final months = List<int>.filled(12, 0);
  for (var i = 0; i < levels.length && i < 12; i++) {
    months[i] = levels[i];
  }
  return months;
}

Future<void> main() async {
  final res = await http.get(Uri.parse(sourceUrl), headers: {
    'User-Agent': 'mywhv-harvest-export/1.0',
  });

  if (res.statusCode != 200) {
    stderr.writeln('HTTP ${res.statusCode}');
    exit(1);
  }

  final doc = html_parser.parse(res.body);

  // Agafem tots els elements dins del contenidor principal.
  // (Si canvia l’HTML, això continua sent bastant tolerant perquè busquem per patrons.)
  final body = doc.body;
  if (body == null) {
    stderr.writeln('No body found');
    exit(1);
  }

  // Identifica seccions per estat: H2 amb el nom complet.
  final h2s = body.querySelectorAll('h2');
  final statesOut = <Map<String, dynamic>>[];

  for (final h2 in h2s) {
    final stateNameRaw = h2.text.trim();
    if (stateNameRaw.isEmpty) continue;

    final stateCode = normalizeState(stateNameRaw);
    // Només considerem els estats esperats
    const allowed = {'NSW','NT','QLD','SA','TAS','VIC','WA'};
    if (!allowed.contains(stateCode)) continue;

    // Tot el que ve després d’aquest H2 fins al pròxim H2 és el bloc de l’estat.
    final regions = <Map<String, dynamic>>[];

    Element? cursor = h2.nextElementSibling;
    Map<String, dynamic>? currentRegion;

    while (cursor != null && cursor.localName != 'h2') {
      // Busquem links a maps.google.com que contenen "Region (postcode: xxxx)"
      final aTags = cursor.querySelectorAll('a');

      for (final a in aTags) {
        final href = a.attributes['href'] ?? '';
        final text = a.text.trim();

        final isMaps = href.contains('maps.google.com');
        if (isMaps && text.isNotEmpty && looksLikeRegionHeader(text)) {
          // Nova regió
          if (currentRegion != null) {
            regions.add(currentRegion);
          }
          currentRegion = {
            'region_name': extractRegionName(text),
            'postcode': extractPostcode(text) ?? '',
            'map_url': href,
            'crops': <Map<String, dynamic>>[],
          };
          continue;
        }

        // Si ja estem dins una regió, les altres <a> sovint són cultius (Avocados, Citrus, etc.)
        // i el text del voltant conté "med/high".
        if (currentRegion != null && !isMaps && text.isNotEmpty) {
          // Construïm tokens a partir del text del node pare (sol portar els "med/high")
          final parentText = (a.parent?.text ?? '').replaceAll('\n', ' ').trim();
          final tokens = parentText.split(RegExp(r'\s+'));

          // Evita enganxar el header “Crop Jan J ...”
          if (text.toLowerCase() == 'crop') continue;

          final months = parseMonthsFromLineTokens(tokens);

          // Només guarda el cultiu si hi ha algun mes actiu
          if (months.any((v) => v > 0)) {
            (currentRegion['crops'] as List).add({
              'crop': text,
              'months': months,
            });
          }
        }
      }

      cursor = cursor.nextElementSibling;
    }

    if (currentRegion != null) {
      regions.add(currentRegion);
    }

    // Neteja: treu “regions buides” (sense crops)
    final cleaned = regions.where((r) => (r['crops'] as List).isNotEmpty).toList();

    statesOut.add({
      'state': stateCode,
      'regions': cleaned,
    });
  }

  final out = {
    'source_url': sourceUrl,
    'year': 2025,
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'states': statesOut,
  };

  final file = File('harvest_2025.json');
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('OK -> ${file.path}  (states: ${statesOut.length})');
}
