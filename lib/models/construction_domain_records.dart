enum ConstructionCompanyWorksiteRole {
  operator('operator'),
  owner('owner'),
  contractor('contractor');

  const ConstructionCompanyWorksiteRole(this.id);
  final String id;

  static ConstructionCompanyWorksiteRole? fromRow(Map<String, dynamic> row) {
    final raw = (row['company_worksite_role'] ?? row['relationship_role'] ?? '')
        .toString()
        .toLowerCase();
    if (raw.contains('contractor')) return contractor;
    if (raw.contains('operator')) return operator;
    if (raw.contains('owner')) return owner;
    return null;
  }
}

class ConstructionDomainRecords {
  const ConstructionDomainRecords._();

  static String normalizeIdentity(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\b(pty|ltd|limited|australia|australian)\b'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '')
      .trim();

  static String companyId(Map<String, dynamic> row) {
    final explicit = (row['company_id'] ?? '').toString().trim();
    if (explicit.isNotEmpty) return explicit;
    final operatorCode = (row['operator_code'] ?? '').toString().trim();
    if (operatorCode.isNotEmpty) return 'company:wa_operator:$operatorCode';
    if (isWorksite(row) &&
        ConstructionCompanyWorksiteRole.fromRow(row) == null) {
      return '';
    }
    final normalized = normalizeIdentity((row['name'] ?? '').toString());
    return normalized.isEmpty ? '' : 'company:name:$normalized';
  }

  static String worksiteId(Map<String, dynamic> row) {
    final explicit = (row['worksite_id'] ?? '').toString().trim();
    if (explicit.isNotEmpty) return explicit;
    final siteCode = (row['site_code'] ?? '').toString().trim();
    if (siteCode.isNotEmpty) return 'worksite:wa_minedex:$siteCode';
    final sourceId = (row['source_place_id'] ?? row['id'] ?? '')
        .toString()
        .trim();
    if (sourceId.isNotEmpty) return 'worksite:$sourceId';
    final name = normalizeIdentity(
      (row['worksite_name'] ?? row['name'] ?? '').toString(),
    );
    final state = (row['state'] ?? '').toString().trim().toLowerCase();
    return name.isEmpty ? '' : 'worksite:local:$state:$name';
  }

  static bool isWorksite(Map<String, dynamic> row) =>
      (row['worksite_name'] ?? '').toString().trim().isNotEmpty ||
      (row['site_code'] ?? '').toString().trim().isNotEmpty ||
      (row['location_role'] ?? '').toString() == 'worksite' ||
      (row['record_type'] ?? '').toString() == 'construction_worksite' ||
      (row['entity_kind'] ?? '').toString() == 'project_site';

  static bool hasCorroboratedHiringLink(Map<String, dynamic> row) {
    final role = ConstructionCompanyWorksiteRole.fromRow(row);
    final source = (row['source'] ?? '').toString().toLowerCase();
    final classificationSource = (row['classification_source'] ?? '')
        .toString()
        .toLowerCase();
    final isOfficialMinedexLink =
        source.startsWith('wa_minedex') ||
        classificationSource == 'wa_minedex_official_join' ||
        (classificationSource == 'open_data_corroboration' &&
            source.contains('minedex'));
    final corroborated =
        row['link_corroborated'] == true ||
        isOfficialMinedexLink ||
        (row['company_worksite_evidence'] ?? '').toString().trim().isNotEmpty;
    return corroborated &&
        (role == ConstructionCompanyWorksiteRole.operator ||
            role == ConstructionCompanyWorksiteRole.contractor);
  }

  static void attachDerivedIds(Map<String, dynamic> row) {
    final company = companyId(row);
    if (company.isNotEmpty) row['company_id'] = company;
    if (!isWorksite(row)) return;
    final worksite = worksiteId(row);
    if (worksite.isNotEmpty) row['worksite_id'] = worksite;
    final role = ConstructionCompanyWorksiteRole.fromRow(row);
    if (role != null) row['company_worksite_role'] = role.id;
    final source = (row['source'] ?? '').toString().toLowerCase();
    final classificationSource = (row['classification_source'] ?? '')
        .toString()
        .toLowerCase();
    if (source.startsWith('wa_minedex') ||
        classificationSource == 'wa_minedex_official_join') {
      row['link_corroborated'] = true;
      row['company_worksite_evidence'] =
          'Official WA MINEDEX operator-to-worksite record';
    }
  }
}
