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
  // Public OSM services are free, shared infrastructure. Keep state imports
  // deliberately slow and retry only transient failures.
  static const int overpassMinimumRequestGapMilliseconds = 1500;
  static const int overpassMaximumAttempts = 4;
  static const int nominatimMinimumRequestGapMilliseconds = 1100;
  static const int stateImportRetryPauseSeconds = 8;

  // Enrichment is deliberately conservative: it does not use web search APIs.
  // It can use OSM tags, Wikidata entity data, known brand websites, and
  // directly-tested probable domains.
  static const bool enrichWebContactsByDefault = true;
  static const int enrichmentConcurrency = 4;
  // Construction enrichment probes several pages per company. Keep Resume
  // below the broader importer concurrency to reduce website rate limiting.
  static const int constructionEnrichmentConcurrency = 2;
  static const bool discoverMissingWebsitesByDefault = true;
  // Construction legal names often differ from their public trading or parent
  // company domain. Check a small, ordered set of useful variants rather than
  // only the first four literal-name domains.
  static const int websiteDiscoveryMaxCandidatesPerBusiness = 12;
  static const int websiteDiscoveryTimeoutSeconds = 8;
  static const int constructionContactEnrichmentTimeoutSeconds = 180;
  static const int restaurantContactEnrichmentTimeoutSeconds = 180;
}
