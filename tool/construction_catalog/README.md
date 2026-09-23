# Workyday construction catalogue builder

This is a one-off, local-first catalogue pipeline. It never writes to Firebase.

## Safety rules

- A source is rejected unless `commercial_reuse_allowed` is `true`, it has an
  explicit open licence, and its format is a download or API.
- HTML scraping is disabled.
- ABN and ACN may be used temporarily for identity validation but are never
  included in public output.
- Personal names, personal phone numbers and harvested emails are not public
  output fields.
- Contact details are denied by default. A connector must explicitly prove
  that each contact field is licensed for republication.
- Mine and project names are worksites, not companies. They cannot become a
  company record until an open source identifies an operator.

## Run

```bash
dart run tool/construction_catalog/build_catalog.dart --fetch
```

The initial AusTender window is deliberately limited to one month so the
classification can be reviewed before a larger national extraction. Override
it with ISO-8601 values when ready:

```bash
dart run tool/construction_catalog/build_catalog.dart --fetch \
  --austender-from 2025-01-01T00:00:00Z \
  --austender-to 2025-02-01T00:00:00Z
```

The command downloads only enabled, openly licensed API sources into
`work/construction_catalog/sources/` and writes the review draft to
`work/construction_catalog/construction_catalog_review.json`.

Validate candidate company names against the official ASIC open-data API:

```bash
dart run tool/construction_catalog/validate_asic.dart
```

The validator requests only company name, registration status, current-name
indicator and deregistration date. It neither requests nor stores ABN/ACN.

The review file is deliberately not the production asset. Publication to
`export/construction_companies.json` and Firebase remains a separate manual
step inside the app.

AusTender supplier `contactPoint` values are procurement-agency contacts, not
verified supplier contacts, and are therefore always discarded. Supplier ABNs
are held only in memory as deduplication keys and are never serialized. The raw
AusTender response is deleted immediately after import so those discarded
fields do not remain in the local catalogue cache either.

## Agreed rollout sequence

1. REMP projects and operators.
2. WA and NSW mining-title holders.
3. ASIC and ABR validation/deduplication (identifiers never published).
4. A small WA or NSW review run.
5. Editorial review of false positives, duplicates and categories.
6. Only then, build the full Australian publication candidate.

## Runtime pipeline

`export_runtime_snapshot.dart` creates the identifier-free asset consumed by
the app's `ConstructionCatalogPipelineService`. The Admin action combines that
snapshot with the configured national OSM postcode scan, reconciles exact
normalized company names, deduplicates through the local construction store,
and marks map eligibility. It never writes to Firebase.

Unlinked Geoscience worksites remain reference records and cannot become
company markers until an open source verifies their operator. Companies without
a public business contact or coordinates remain local but are excluded from the
map and publication JSON.
