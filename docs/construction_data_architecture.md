# Construction data architecture

This file is the durable project context for Construction work. It records
decisions previously spread across Codex tasks so future changes do not regress
them.

## Non-negotiable data rules

- Preserve source rows and every existing local contact.
- Construction data remains local until the existing explicit publication flow.
- Do not write Construction enrichment/import results to Firebase implicitly.
- Do not change Hospitality while changing Construction.
- A contact channel is not evidence of a current vacancy.
- Contact classification is an internal publication rule, not a visible badge.

## Domain model

- `ConstructionCompany`: one reusable company identity and its contacts.
- `ConstructionWorksite`: a mine, project, or job site with coordinates.
- `CompanyWorksiteLink`: company/worksite relationship with `operator`, `owner`,
  or `contractor` role and corroborating evidence.
- Owners are not assumed to hire site workers.
- Only corroborated operators and contractors with useful application contact
  channels can make a worksite public.
- Unlinked worksites remain in the local/admin catalogue.
- Public rows are currently a backwards-compatible flattened projection of the
  linked company and worksite; normalized SQLite tables are authoritative for
  identity, link, and metrics work going forward.

## Website discovery priority

1. Official website supplied by a government source.
2. Domain from an official corporate email.
3. Website already verified for the same company identity at another location.
4. Legal name, trading name, parent, subsidiary, operator, and known aliases.
5. Wikidata/OSM as discovery hints.
6. Generated domain candidates as a final fallback.

Candidate verification considers name/alias matches, corporate information,
Australian presence, matching official email/phone, and structured
`Organization`/`Corporation`/`LocalBusiness` data. Multiple similarly plausible
domains must be sent to manual review.

## Official-source order

1. Geoscience Australia national operating-mines layer (CC BY 4.0).
2. WA MINEDEX remains the detailed WA source.
3. NSW Major Operating Mines and Queensland government spatial sources.
4. SA SARIG, Victoria GeoVic, Mineral Resources Tasmania, and NT STRIKE.

National/state mine layers create worksites only unless the source explicitly
corroborates a company relationship. Never infer an employer from a project or
mine name.

## Regional-work wording

Use `Likely eligible regional area`, never a guarantee. The map must explain
that eligibility depends on the worksite postcode, industry, eligible work, and
current visa rules, and link to current Department of Home Affairs guidance.

## Enrichment behavior

- Resume processes only `pending` and `retry_later`; it does not scan OSM.
- Completed companies remain untouched.
- Enrich a company identity once and reuse its verified contacts across linked
  worksites.
- Skip/Stop must remain responsive and must discard late results.
- Optional contact/careers/social failures do not invalidate a verified homepage.
- Persist timeout stages and transient failure categories.
