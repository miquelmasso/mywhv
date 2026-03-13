import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReportServiceResult {
  const ReportServiceResult({
    required this.success,
    required this.message,
    this.statusCode,
    this.reportId,
  });

  final bool success;
  final String message;
  final int? statusCode;
  final String? reportId;
}

class ReportService {
  const ReportService();

  static const int _minMessageLength = 5;
  static const int _maxMessageLength = 2000;
  static const int _maxReportsPerDay = 3;
  static const String _clientIdPrefsKey = 'report_client_id';
  static const String _reportTimestampsPrefsKey = 'report_send_timestamps';
  static final Random _random = _createRandom();

  Future<ReportServiceResult> sendReport(String message) async {
    final trimmedMessage = message.trim();
    if (trimmedMessage.length < _minMessageLength ||
        trimmedMessage.length > _maxMessageLength) {
      return const ReportServiceResult(
        success: false,
        message: 'The message must be between 5 and 2000 characters.',
        statusCode: 400,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final recentReportTimestamps = _readRecentReportTimestamps(prefs);
    if (recentReportTimestamps.length >= _maxReportsPerDay) {
      return const ReportServiceResult(
        success: false,
        message: 'You have reached the daily limit.',
        statusCode: 429,
      );
    }

    final clientId = await _getOrCreateClientId(prefs);
    final now = DateTime.now();

    try {
      final document = await FirebaseFirestore.instance
          .collection('reports')
          .add({
            'userId': clientId,
            'message': trimmedMessage,
            'platform': _platformName,
            'source': 'app',
            'status': 'new',
            'createdAt': FieldValue.serverTimestamp(),
            'clientCreatedAt': Timestamp.fromDate(now.toUtc()),
          });
      await _storeReportTimestamp(prefs, now, recentReportTimestamps);

      return ReportServiceResult(
        success: true,
        message: 'Report sent successfully.',
        statusCode: 200,
        reportId: document.id,
      );
    } on FirebaseException catch (error) {
      debugPrint(
        'ReportService Firestore error (${error.code}): ${error.message}',
      );
    } catch (error) {
      debugPrint('ReportService unexpected error saving report: $error');
    }

    return const ReportServiceResult(
      success: false,
      message: 'Could not send the report.',
    );
  }

  Future<String> _getOrCreateClientId([
    SharedPreferences? providedPrefs,
  ]) async {
    final prefs = providedPrefs ?? await SharedPreferences.getInstance();
    final existing = prefs.getString(_clientIdPrefsKey)?.trim() ?? '';
    if (existing.isNotEmpty) {
      return existing;
    }

    final created = _generateClientId();
    await prefs.setString(_clientIdPrefsKey, created);
    return created;
  }

  String _generateClientId() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final parts = List<String>.generate(
      3,
      (_) => _random.nextInt(0x7fffffff).toRadixString(36),
      growable: false,
    );
    return 'wd-$now-${parts.join()}';
  }

  static Random _createRandom() {
    try {
      return Random.secure();
    } catch (_) {
      return Random();
    }
  }

  List<DateTime> _readRecentReportTimestamps(SharedPreferences prefs) {
    final rawValues =
        prefs.getStringList(_reportTimestampsPrefsKey) ?? const [];
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(hours: 24));
    final values = <DateTime>[];

    for (final rawValue in rawValues) {
      final milliseconds = int.tryParse(rawValue);
      if (milliseconds == null) {
        continue;
      }

      final timestamp = DateTime.fromMillisecondsSinceEpoch(milliseconds);
      if (timestamp.isAfter(cutoff)) {
        values.add(timestamp);
      }
    }

    return values;
  }

  Future<void> _storeReportTimestamp(
    SharedPreferences prefs,
    DateTime timestamp,
    List<DateTime> recentTimestamps,
  ) async {
    final updated = <String>[
      ...recentTimestamps.map(
        (value) => value.millisecondsSinceEpoch.toString(),
      ),
      timestamp.millisecondsSinceEpoch.toString(),
    ];
    await prefs.setStringList(_reportTimestampsPrefsKey, updated);
  }

  String get _platformName {
    if (kIsWeb) {
      return 'web';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }
}
