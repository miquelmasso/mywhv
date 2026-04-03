import 'google_places_service.dart';
import 'visa_postcodes_sqlite_store.dart';

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
  final GooglePlacesService _placesService = GooglePlacesService();
  final VisaPostcodesSqliteStore _store = VisaPostcodesSqliteStore.instance;
  List<Map<String, dynamic>>? _visaPostcodesCache;

  Future<List<Map<String, dynamic>>> _loadVisaPostcodes() async {
    await _store.init();
    _visaPostcodesCache ??= await _store.getAll();
    return _visaPostcodesCache!;
  }

  String _normalize(String raw) => raw.padLeft(4, '0');

  bool _isNorthernTerritory(String normalized, int number) {
    return normalized.startsWith('08') || (number >= 800 && number <= 999);
  }

  bool _isAllowedWithSnapshot(
    String normalized,
    int number,
    List<Map<String, dynamic>> snapshot,
  ) {
    // Només considerem codis de Tourism & Hospitality (Remote & Very Remote Australia).
    // Els codis de "Regional Australia" NO s’utilitzen per a hospitality.
    if (_isNorthernTerritory(normalized, number)) return true;

    for (final data in snapshot) {
      final List<dynamic> postcodes = data['postcodes'] ?? [];
      final String industry = (data['industry'] ?? '').toString();
      final lowerIndustry = industry.toLowerCase();
      final bool isTourism = lowerIndustry.contains('hospitality');
      if (!isTourism) continue;
      if (postcodes.contains(number) || postcodes.contains(normalized)) {
        return true;
      }
    }
    return false;
  }

  Future<ImportResult> importRestaurantsForPostcode(
    String postcodeStr, {
    List<Map<String, dynamic>>? visaSnapshot,
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

    final list = await _placesService.saveTwoRestaurantsForPostcode(number);
    return ImportResult(
      postcode: normalized,
      valid: true,
      allowed: true,
      addedCount: list.length,
    );
  }

  Future<bool> isRemoteTourismPostcode(String postcodeStr) async {
    final normalized = _normalize(postcodeStr.trim());
    final number = int.tryParse(normalized);
    if (number == null) return false;
    final snapshot = await _loadVisaPostcodes();
    return _isAllowedWithSnapshot(normalized, number, snapshot);
  }

  Future<int> importAllRestaurantsForPostcode(String postcodeStr) async {
    final normalized = _normalize(postcodeStr.trim());
    final postcodeNum = int.tryParse(normalized);
    if (postcodeNum == null) return 0;

    final snapshot = await _loadVisaPostcodes();
    final allowed = _isAllowedWithSnapshot(normalized, postcodeNum, snapshot);
    if (!allowed) return 0;

    // 🔹 Importa tots els restaurants disponibles per aquest codi (sense límit)
    final list = await _placesService.saveTwoRestaurantsForPostcode(
      postcodeNum,
      maxToSave: 0, // sense límit: volem tots els del codi en una sola passada
    );

    // El servei ja desarà els restaurants; retornem el recompte per coherència
    return list.length;
  }
}
