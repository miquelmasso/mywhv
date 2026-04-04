const String osmVectorStyleAssetPath = 'assets/osm_vector_style.json';

const String osmVectorTilesUrlTemplate = String.fromEnvironment(
  'OSM_VECTOR_TILES_URL_TEMPLATE',
  defaultValue: '',
);

bool get hasOsmVectorTilesUrlTemplate =>
    osmVectorTilesUrlTemplate.trim().isNotEmpty;

String get osmVectorTilesUrlTemplateOrEmpty => osmVectorTilesUrlTemplate.trim();
