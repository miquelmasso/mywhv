import 'package:cloud_firestore/cloud_firestore.dart';
import 'google_places_service.dart';
import 'postcode_state_helper.dart';

class ImportResult {
  final String postcode;
  final bool valid;
  final bool allowed;
  final int addedCount;

  const ImportResult({
    required this.postcode,
    required this.valid,
    required this.allowed,
    required this.addedCount,
  });
}

class RestaurantImportService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GooglePlacesService _placesService = GooglePlacesService();
  QuerySnapshot<Map<String, dynamic>>? _visaPostcodesCache;

  Future<QuerySnapshot<Map<String, dynamic>>> _loadVisaPostcodes() async {
    _visaPostcodesCache ??= await _firestore.collection('visa_postcodes').get();
    return _visaPostcodesCache!;
  }

  String _normalize(String raw) => raw.padLeft(4, '0');

  bool _isNorthernTerritory(String normalized, int number) {
    return normalized.startsWith('08') || (number >= 800 && number <= 999);
  }

  bool _isAllowedWithSnapshot(
    String normalized,
    int number,
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    if (_isNorthernTerritory(normalized, number)) return true;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final List<dynamic> postcodes = data['postcodes'] ?? [];
      final String industry = (data['industry'] ?? '').toString();
      final lowerIndustry = industry.toLowerCase();
      final bool isTourism = lowerIndustry.contains('hospitality');
      final bool isRegional = lowerIndustry.contains('regional');
      if (!isTourism && !isRegional) continue;
      if (postcodes.contains(number) || postcodes.contains(normalized)) {
        return true;
      }
    }
    return false;
  }

  Future<ImportResult> importRestaurantsForPostcode(
    String postcodeStr, {
    QuerySnapshot<Map<String, dynamic>>? visaSnapshot,
  }) async {
    final normalized = _normalize(postcodeStr.trim());
    final number = int.tryParse(normalized);
    if (number == null) {
      return ImportResult(
        postcode: normalized,
        valid: false,
        allowed: false,
        addedCount: 0,
      );
    }

    final snapshot = visaSnapshot ?? await _loadVisaPostcodes();
    final allowed = _isAllowedWithSnapshot(normalized, number, snapshot);
    if (!allowed) {
      return ImportResult(
        postcode: normalized,
        valid: true,
        allowed: false,
        addedCount: 0,
      );
    }

    final list = await _placesService.SaveTwoRestaurantsForPostcode(number);
    return ImportResult(
      postcode: normalized,
      valid: true,
      allowed: true,
      addedCount: list.length,
    );
  }

  Future<int> importAllRestaurantsForPostcode(String postcodeStr) async {
    final normalized = _normalize(postcodeStr.trim());
    final postcodeNum = int.tryParse(normalized);
    if (postcodeNum == null) return 0;

    final snapshot = await _loadVisaPostcodes();
    final allowed = _isAllowedWithSnapshot(normalized, postcodeNum, snapshot);
    if (!allowed) return 0;

    final computedState = getStateFromPostcode(normalized);

    int totalAdded = 0;
    while (true) {
      final list = await _placesService.SaveTwoRestaurantsForPostcode(
        postcodeNum,
      );

      if (list.isEmpty) break;

      for (final restaurant in list) {
        final name = restaurant['name'] ?? 'Nom desconegut';
        final lat = restaurant['lat'];
        final lng = restaurant['lng'];
        final phone = restaurant['phone'] ?? 'Sense telèfon';

        final exists = await _firestore
            .collection('restaurants')
            .where('name', isEqualTo: name)
            .limit(1)
            .get();

        final blocked = await _firestore
            .collection('restaurants')
            .where('name', isEqualTo: name)
            .where('blocked', isEqualTo: true)
            .get();

        if (blocked.docs.isNotEmpty) continue;

        if (exists.docs.isNotEmpty) {
          final data = exists.docs.first.data();
          if (data['blocked'] == true) {
            continue;
          }
        }

        if (exists.docs.isNotEmpty) {
          continue;
        }

        await _firestore.collection('restaurants').add({
          'name': name,
          'postcode': normalized,
          'lat': lat,
          'lng': lng,
          'latitude': lat,
          'longitude': lng,
          'phone': phone,
          'timestamp': FieldValue.serverTimestamp(),
          'worked_here_count': 0,
          'state': computedState,
        });

        totalAdded++;
      }

      await Future.delayed(const Duration(seconds: 1));
    }

    return totalAdded;
  }
}
