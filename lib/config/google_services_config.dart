class GoogleServicesConfig {
  GoogleServicesConfig._();

  // Temporary kill switches for Google services.
  // Keep the implementation in the app, but prevent outgoing Google API calls.
  static const bool enableGooglePlaces = false;
  static const bool enableGoogleGeocoding = false;
  static const bool enableGoogleMapsSdk = false;
  static const bool enableExternalGoogleMapsLinks = false;
  static const bool enableLegacyGoogleImports = false;
}
