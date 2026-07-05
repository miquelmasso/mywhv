class OsmImportConfig {
  OsmImportConfig._();

  static const String nominatimBaseUrl = 'https://nominatim.openstreetmap.org';
  static const List<String> overpassEndpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];

  static const double searchRadiusMeters = 20000;
  static const int overpassTimeoutSeconds = 45;
  static const int scanCooldownDays = 30;
  static const int postcodeCenterCacheDays = 365;
  static const int maxResultsPerPostcode = 250;

  // Enrichment is deliberately conservative: it does not use web search APIs.
  // It can use OSM tags, Wikidata entity data, known brand websites, and
  // directly-tested probable domains.
  static const bool enrichWebContactsByDefault = true;
  static const int enrichmentConcurrency = 4;
  static const bool discoverMissingWebsitesByDefault = true;
  static const int websiteDiscoveryMaxCandidatesPerBusiness = 4;
  static const int websiteDiscoveryTimeoutSeconds = 8;
  static const int restaurantContactEnrichmentTimeoutSeconds = 180;
}
