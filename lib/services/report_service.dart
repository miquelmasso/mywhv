import 'dart:convert';
import 'dart:math';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
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
  static const String _clientIdPrefsKey = 'report_client_id';
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

    final endpoint = _resolveEndpoint();
    if (endpoint == null) {
      return const ReportServiceResult(
        success: false,
        message:
            'REPORT_BACKEND_URL is missing on the client. Add the real reports backend URL.',
      );
    }

    final parsedUri = Uri.tryParse(endpoint);
    if (parsedUri == null) {
      return const ReportServiceResult(
        success: false,
        message: 'The reports backend URL is invalid.',
      );
    }

    final candidateUris = _candidateUrisForRuntime(parsedUri);

    final clientId = await _getOrCreateClientId();

    http.Response? response;
    for (final uri in candidateUris) {
      try {
        response = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'userId': clientId,
                'message': trimmedMessage,
                'platform': _platformName,
              }),
            )
            .timeout(const Duration(seconds: 6));
        break;
      } on TimeoutException {
        continue;
      } catch (_) {
        continue;
      }
    }

    if (response == null) {
      return const ReportServiceResult(
        success: false,
        message: 'Could not contact the reports server.',
      );
    }

    final payload = _decodeJsonBody(response.body);
    if (response.statusCode == 200 && payload['success'] == true) {
      final reportId = payload['reportId'] is String
          ? payload['reportId'] as String
          : null;
      return ReportServiceResult(
        success: true,
        message: 'Report sent successfully.',
        statusCode: response.statusCode,
        reportId: reportId,
      );
    }

    if (response.statusCode == 429) {
      return const ReportServiceResult(
        success: false,
        message: 'You have reached the daily limit.',
        statusCode: 429,
      );
    }

    final serverError = payload['error'] is String
        ? (payload['error'] as String).trim()
        : '';
    return ReportServiceResult(
      success: false,
      message: serverError.isNotEmpty
          ? serverError
          : 'Could not send the report.',
      statusCode: response.statusCode,
    );
  }

  String? _resolveEndpoint() {
    const compileTimeUrl = String.fromEnvironment('REPORT_BACKEND_URL');
    if (compileTimeUrl.trim().isNotEmpty) {
      return compileTimeUrl.trim();
    }

    final envUrl = dotenv.env['REPORT_BACKEND_URL']?.trim() ?? '';
    if (envUrl.isNotEmpty) {
      return envUrl;
    }

    final legacyEnvUrl = dotenv.env['SEND_REPORT_URL']?.trim() ?? '';
    if (legacyEnvUrl.isNotEmpty) {
      return legacyEnvUrl;
    }

    return null;
  }

  Future<String> _getOrCreateClientId() async {
    final prefs = await SharedPreferences.getInstance();
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

  Map<String, dynamic> _decodeJsonBody(String body) {
    if (body.trim().isEmpty) {
      return const <String, dynamic>{};
    }

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // Ignore invalid JSON and fall back to an empty payload.
    }

    return const <String, dynamic>{};
  }

  static Random _createRandom() {
    try {
      return Random.secure();
    } catch (_) {
      return Random();
    }
  }

  List<Uri> _candidateUrisForRuntime(Uri uri) {
    if (kIsWeb) {
      return [uri];
    }

    final host = uri.host.toLowerCase();
    final isLoopbackHost = host == 'localhost' || host == '127.0.0.1';

    if (!isLoopbackHost) {
      return [uri];
    }

    final candidates = <Uri>[];
    void addCandidate(Uri value) {
      if (!candidates.contains(value)) {
        candidates.add(value);
      }
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      addCandidate(uri.replace(host: '10.0.2.2'));
      addCandidate(uri.replace(host: '10.0.3.2'));
      addCandidate(uri.replace(host: '127.0.0.1'));
      addCandidate(uri.replace(host: 'localhost'));
      return candidates;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      addCandidate(uri.replace(host: 'localhost'));
      addCandidate(uri.replace(host: '127.0.0.1'));
      return candidates;
    }

    addCandidate(uri);
    if (host != 'localhost') {
      addCandidate(uri.replace(host: 'localhost'));
    }
    if (host != '127.0.0.1') {
      addCandidate(uri.replace(host: '127.0.0.1'));
    }
    return candidates;
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
