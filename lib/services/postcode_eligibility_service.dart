import 'package:cloud_firestore/cloud_firestore.dart';

enum PostcodeVisaType { regional, remote, notEligible }

class PostcodeEligibilityResult {
  const PostcodeEligibilityResult({
    required this.postcode,
    required this.type,
    required this.allowsFarm,
    required this.allowsHospitality,
    this.error,
  });

  final String postcode;
  final PostcodeVisaType type;
  final bool allowsFarm;
  final bool allowsHospitality;
  final String? error;

  bool get isValid => error == null;
  bool get isEligible => type != PostcodeVisaType.notEligible;

  factory PostcodeEligibilityResult.invalid(String message, String postcode) {
    return PostcodeEligibilityResult(
      postcode: postcode,
      type: PostcodeVisaType.notEligible,
      allowsFarm: false,
      allowsHospitality: false,
      error: message,
    );
  }
}

/// Centralitza la lògica de validació de postcodes utilitzada a restaurants/farms.
class PostcodeEligibilityService {
  PostcodeEligibilityService._();

  static final PostcodeEligibilityService instance = PostcodeEligibilityService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  QuerySnapshot<Map<String, dynamic>>? _cache;

  Future<QuerySnapshot<Map<String, dynamic>>> _loadVisaPostcodes() async {
    _cache ??= await _firestore.collection('visa_postcodes').get();
    return _cache!;
  }

  String _normalize(String raw) => raw.padLeft(4, '0');

  bool _isNorthernTerritory(String normalized, int number) {
    return normalized.startsWith('08') || (number >= 800 && number <= 999);
  }

  bool _containsPostcode(List<dynamic> postcodes, String normalized, int number) {
    for (final pc in postcodes) {
      final normalizedPc = pc.toString().padLeft(4, '0');
      if (normalizedPc == normalized || pc == number) return true;
    }
    return false;
  }

  Future<PostcodeEligibilityResult> check(String raw) async {
    final trimmed = raw.trim();
    final normalized = _normalize(trimmed);
    if (trimmed.isEmpty) {
      return PostcodeEligibilityResult.invalid('Introdueix un codi postal.', normalized);
    }
    final number = int.tryParse(normalized);
    if (number == null || normalized.length != 4) {
      return PostcodeEligibilityResult.invalid('Escriu un postcode de 4 dígits.', normalized);
    }

    final snapshot = await _loadVisaPostcodes();
    bool isRegional = false;
    bool isHospitality = _isNorthernTerritory(normalized, number); // Mateixa lògica que restaurants.
    bool matched = isHospitality;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final List<dynamic> postcodes = data['postcodes'] ?? [];
      if (!_containsPostcode(postcodes, normalized, number)) continue;

      matched = true;
      final industry = (data['industry'] ?? doc.id ?? '').toString().toLowerCase();
      if (industry.contains('hospitality')) {
        isHospitality = true;
      }
      if (industry.contains('regional australia')) {
        isRegional = true;
      }
    }

    if (!matched) {
      return PostcodeEligibilityResult(
        postcode: normalized,
        type: PostcodeVisaType.notEligible,
        allowsFarm: false,
        allowsHospitality: false,
      );
    }

    final type = isHospitality
        ? PostcodeVisaType.remote
        : (isRegional ? PostcodeVisaType.regional : PostcodeVisaType.notEligible);

    return PostcodeEligibilityResult(
      postcode: normalized,
      type: type,
      allowsFarm: isRegional,
      allowsHospitality: isHospitality,
    );
  }
}
