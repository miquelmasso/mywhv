import 'package:cloud_firestore/cloud_firestore.dart';
import 'farm_places_service.dart';

class FarmImportResult {
  final String postcode;
  final bool valid;
  final bool allowed;
  final int addedCount;

  const FarmImportResult({
    required this.postcode,
    required this.valid,
    required this.allowed,
    required this.addedCount,
  });
}

class FarmImportService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FarmPlacesService _placesService = FarmPlacesService();
  QuerySnapshot<Map<String, dynamic>>? _visaPostcodesCache;

  Future<QuerySnapshot<Map<String, dynamic>>> _loadVisaPostcodes() async {
    _visaPostcodesCache ??= await _firestore.collection('visa_postcodes').get();
    return _visaPostcodesCache!;
  }

  String _normalize(String raw) => raw.padLeft(4, '0');

  bool _isRegionalWithSnapshot(
    String normalized,
    int number,
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final List<dynamic> postcodes = data['postcodes'] ?? [];
      final String industry = (data['industry'] ?? '').toString();
      final lowerIndustry = industry.toLowerCase();
      final bool isRegional = lowerIndustry.contains('regional australia');
      if (!isRegional) continue;
      if (postcodes.contains(number) || postcodes.contains(normalized)) {
        return true;
      }
    }
    return false;
  }

  Future<FarmImportResult> importFarmsForPostcode(
    String postcodeStr, {
    QuerySnapshot<Map<String, dynamic>>? visaSnapshot,
  }) async {
    final normalized = _normalize(postcodeStr.trim());
    final number = int.tryParse(normalized);
    if (number == null) {
      return FarmImportResult(
        postcode: normalized,
        valid: false,
        allowed: false,
        addedCount: 0,
      );
    }

    final snapshot = visaSnapshot ?? await _loadVisaPostcodes();
    final allowed = _isRegionalWithSnapshot(normalized, number, snapshot);
    if (!allowed) {
      return FarmImportResult(
        postcode: normalized,
        valid: true,
        allowed: false,
        addedCount: 0,
      );
    }

    final list = await _placesService.saveFarmsForPostcode(
      number,
      maxToSave: 0,
      isRemote462: true,
    );
    return FarmImportResult(
      postcode: normalized,
      valid: true,
      allowed: true,
      addedCount: list.length,
    );
  }

  /// Importa totes les farms d'un estat utilitzant pivots rurals + llista regional.
  Future<int> importFarmsForState(String stateCode) async {
    final snapshot = await _loadVisaPostcodes();
    final allowedPostcodes = <String>{};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final String industry = (data['industry'] ?? '').toString();
      if (!industry.toLowerCase().contains('regional australia')) continue;
      final List<dynamic> postcodes = data['postcodes'] ?? [];
      for (final pc in postcodes) {
        final pcStr = pc.toString().padLeft(4, '0');
        allowedPostcodes.add(pcStr);
      }
    }

    final list = await _placesService.saveFarmsForState(
      stateCode,
      allowedPostcodes: allowedPostcodes,
    );
    return list.length;
  }
}
