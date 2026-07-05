# OpenStreetMap restaurant import

The admin postcode screen can import hospitality venues without Google:

1. Nominatim resolves the postcode to an approximate centre.
2. Overpass searches inside the postcode bounding box returned by Nominatim.
   A 20 km radius is used only if no bounding box is available.
3. It finds `restaurant`, `cafe`, `bar`, `pub`, `fast_food`, `food_court`,
   `biergarten`, and `ice_cream` features.
4. Results are normalized to the existing restaurant schema.
5. Existing OSM IDs and existing name/postcode combinations are deduplicated.
6. The merged dataset is written to SQLite and the map cache.

## Required local setup

Add a monitored contact email to `.env`:

```env
OSM_IMPORT_CONTACT_EMAIL=admin@example.com
```

No API key or billing account is required.

## Operational limits

- Use the postcode import manually and avoid unattended state-wide scans
  against public endpoints.
- A successfully scanned postcode is cached for 30 days.
- Postcode coordinates are cached for 365 days.
- The importer retries through two public Overpass endpoints.
- Web contact enrichment is disabled by default because it can make many HTTP
  requests and take significantly longer.

For large recurring imports, run a private Overpass instance or use a hosted
OSM provider with an explicit service agreement.

OpenStreetMap-derived records must retain appropriate OpenStreetMap attribution
in any published dataset or user-facing product.

## Configuration

Defaults are in `lib/config/osm_import_config.dart`:

- search radius: 20 km
- maximum imported results: 250
- scan cooldown: 30 days
- postcode centre cache: 365 days
- enrichment concurrency: 2
