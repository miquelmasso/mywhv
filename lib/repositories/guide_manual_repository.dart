import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/guide_manual/guide_manual.dart';

class GuideManualRepository {
  Future<GuideManual> loadFromAssets() async {
    final raw = await rootBundle.loadString('assets/data/guide_manual.json');
    final decoded = json.decode(raw) as Map<String, dynamic>;
    return GuideManual.fromJson(decoded);
  }
}
