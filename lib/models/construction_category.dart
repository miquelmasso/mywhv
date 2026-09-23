import 'package:flutter/material.dart';

enum ConstructionEntityKind { employer, projectSite, supplierRetail, unknown }

class ConstructionClassification {
  const ConstructionClassification({
    required this.category,
    required this.entityKind,
    required this.confidence,
    required this.reason,
  });

  final ConstructionCategory category;
  final ConstructionEntityKind entityKind;
  final int confidence;
  final String reason;

  bool get isEmployer => entityKind == ConstructionEntityKind.employer;

  String get entityKindId => switch (entityKind) {
    ConstructionEntityKind.employer => 'employer',
    ConstructionEntityKind.projectSite => 'project_site',
    ConstructionEntityKind.supplierRetail => 'supplier_retail',
    ConstructionEntityKind.unknown => 'needs_review',
  };
}

class ConstructionCategory {
  const ConstructionCategory({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String id;
  final String label;
  final IconData icon;
  final Color color;

  static const residentialCommercial = ConstructionCategory(
    id: 'residential_commercial',
    label: 'Residential & commercial',
    icon: Icons.apartment_rounded,
    color: Color(0xFF4E79A7),
  );
  static const civil = ConstructionCategory(
    id: 'civil_construction',
    label: 'Civil construction',
    icon: Icons.add_road_rounded,
    color: Color(0xFFF28E2B),
  );
  static const infrastructure = ConstructionCategory(
    id: 'infrastructure',
    label: 'Infrastructure',
    icon: Icons.account_balance_rounded,
    color: Color(0xFF59A14F),
  );
  static const miningCompany = ConstructionCategory(
    id: 'mining_company',
    label: 'Mining companies',
    icon: Icons.landscape_rounded,
    color: Color(0xFF8B6F47),
  );
  static const miningContractor = ConstructionCategory(
    id: 'mining_contractor',
    label: 'Mining contractors',
    icon: Icons.precision_manufacturing_rounded,
    color: Color(0xFFE15759),
  );
  static const engineeringEpc = ConstructionCategory(
    id: 'engineering_epc',
    label: 'Engineering & EPC',
    icon: Icons.architecture_rounded,
    color: Color(0xFFB07AA1),
  );
  static const oilGasEnergy = ConstructionCategory(
    id: 'oil_gas_energy',
    label: 'Oil, gas & energy',
    icon: Icons.local_fire_department_rounded,
    color: Color(0xFFEDC948),
  );
  static const renewables = ConstructionCategory(
    id: 'renewables',
    label: 'Renewables',
    icon: Icons.energy_savings_leaf_rounded,
    color: Color(0xFF76B7B2),
  );
  static const labourHire = ConstructionCategory(
    id: 'labour_hire',
    label: 'Labour hire & contracting',
    icon: Icons.groups_rounded,
    color: Color(0xFFFF9DA7),
  );
  static const other = ConstructionCategory(
    id: 'other_construction',
    label: 'Other construction',
    icon: Icons.construction_rounded,
    color: Color(0xFF8FAEA6),
  );

  static const values = <ConstructionCategory>[
    residentialCommercial,
    civil,
    infrastructure,
    miningCompany,
    miningContractor,
    engineeringEpc,
    oilGasEnergy,
    renewables,
    labourHire,
    other,
  ];

  static ConstructionCategory fromId(Object? raw) {
    final id = (raw ?? '').toString().trim().toLowerCase();
    const aliases = <String, String>{
      'contractor': 'residential_commercial',
      'construction_company': 'residential_commercial',
      'professional_service': 'engineering_epc',
      'supplier_or_retail': 'other_construction',
      'other': 'other_construction',
    };
    final normalized = aliases[id] ?? id;
    return values.firstWhere(
      (category) => category.id == normalized,
      orElse: () => other,
    );
  }

  static ConstructionClassification classifyDetailed({
    required Map tags,
    String name = '',
  }) {
    final text = <Object?>[
      name,
      tags['name'],
      tags['description'],
      tags['operator'],
      tags['brand'],
      tags['craft'],
      tags['office'],
      tags['industrial'],
      tags['landuse'],
      tags['man_made'],
      tags['power'],
      tags['plant:source'],
      tags['generator:source'],
      tags['service'],
      tags['services'],
      tags['product'],
      tags['company'],
      tags['industry'],
      tags['osm_office'],
      tags['osm_craft'],
      tags['osm_shop'],
      tags['osm_industrial'],
      tags['osm_description'],
      tags['osm_operator'],
      tags['osm_company'],
      tags['osm_service'],
      tags['osm_product'],
      tags['osm_industry'],
      tags['osm_landuse'],
      tags['osm_man_made'],
      tags['osm_power'],
    ].whereType<Object>().join(' ').toLowerCase();
    bool hasAny(Iterable<String> terms) => terms.any(text.contains);

    final shop = (tags['shop'] ?? tags['osm_shop'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (shop.isNotEmpty) {
      return ConstructionClassification(
        category: other,
        entityKind: ConstructionEntityKind.supplierRetail,
        confidence: 100,
        reason:
            'OSM shop=$shop identifies a retailer/supplier, not an employer',
      );
    }

    ConstructionCategory category;
    String reason;

    if (hasAny(const ['solar', 'wind farm', 'wind power', 'renewable'])) {
      category = renewables;
      reason = 'matched renewable-energy terms';
    } else if (hasAny(const [
      'labour hire',
      'labor hire',
      'recruitment',
      'employment agency',
      'employment_agency',
      'staffing',
    ])) {
      category = labourHire;
      reason = 'matched labour-hire or recruitment terms';
    } else if (hasAny(const [
      'drilling',
      'blasting',
      'underground mining',
      'mine maintenance',
      'mining services',
    ])) {
      category = miningContractor;
      reason = 'matched mining-contractor services';
    } else if (hasAny(const [
      'oil',
      'petroleum',
      'natural gas',
      'lng',
      'energy',
    ])) {
      category = oilGasEnergy;
      reason = 'matched oil, gas or energy terms';
    } else if (hasAny(const [
      'mine',
      'mining',
      'quarry',
      'iron ore',
      'coal',
      'lithium',
      'copper',
      'gold',
    ])) {
      category = miningCompany;
      reason = 'matched mining or commodity terms';
    } else if (hasAny(const [
      'rail',
      'airport',
      'port',
      'utility',
      'utilities',
      'telecommunication',
      'water infrastructure',
      'transmission',
    ])) {
      category = infrastructure;
      reason = 'matched infrastructure terms';
    } else if (hasAny(const [
      'civil',
      'earthwork',
      'excavat',
      'road construction',
      'drainage',
      'bridge',
    ])) {
      category = civil;
      reason = 'matched civil-construction services';
    } else if (hasAny(const ['engineer', 'engineering', 'epc', 'surveyor'])) {
      category = engineeringEpc;
      reason = 'matched engineering, EPC or surveying terms';
    } else if (hasAny(const [
      'builder',
      'building',
      'construction',
      'carpenter',
      'electrician',
      'plumber',
      'roofer',
      'fit-out',
      'fitout',
      'developer',
    ])) {
      category = residentialCommercial;
      reason = 'matched building or trade services';
    } else {
      category = other;
      reason = 'insufficient evidence to identify an employer category';
    }

    final industrial = (tags['industrial'] ?? tags['osm_industrial'] ?? '')
        .toString()
        .toLowerCase();
    final landuse = (tags['landuse'] ?? tags['osm_landuse'] ?? '')
        .toString()
        .toLowerCase();
    final manMade = (tags['man_made'] ?? tags['osm_man_made'] ?? '')
        .toString()
        .toLowerCase();
    final power = (tags['power'] ?? tags['osm_power'] ?? '')
        .toString()
        .toLowerCase();
    final office = (tags['office'] ?? tags['osm_office'] ?? '')
        .toString()
        .toLowerCase();
    final craft = (tags['craft'] ?? tags['osm_craft'] ?? '')
        .toString()
        .toLowerCase();
    final isPhysicalSite =
        const {'mine', 'oil', 'gas'}.contains(industrial) ||
        landuse == 'quarry' ||
        manMade == 'mineshaft' ||
        const {'plant', 'generator'}.contains(power);
    final hasEmployerTag =
        office.isNotEmpty ||
        craft.isNotEmpty ||
        office == 'employment_agency' ||
        hasAny(const ['contractor', 'services', 'labour hire', 'labor hire']);
    if (isPhysicalSite && !hasEmployerTag) {
      return ConstructionClassification(
        category: category,
        entityKind: ConstructionEntityKind.projectSite,
        confidence: 95,
        reason:
            'OSM tags identify a physical project/site; operator unverified',
      );
    }
    if (category == other) {
      return ConstructionClassification(
        category: category,
        entityKind: ConstructionEntityKind.unknown,
        confidence: 30,
        reason: reason,
      );
    }
    return ConstructionClassification(
      category: category,
      entityKind: ConstructionEntityKind.employer,
      confidence: hasEmployerTag ? 90 : 78,
      reason: hasEmployerTag
          ? '$reason; supported by an OSM office, craft or service tag'
          : '$reason; supported by the business name and OSM context',
    );
  }

  static ConstructionCategory classify({required Map tags, String name = ''}) =>
      classifyDetailed(tags: tags, name: name).category;

  static ConstructionCategory classifyRow(Map<String, dynamic> row) {
    return classifyRowDetailed(row).category;
  }

  static ConstructionClassification classifyRowDetailed(
    Map<String, dynamic> row,
  ) {
    final detailed = classifyDetailed(
      tags: row,
      name: (row['name'] ?? '').toString(),
    );
    final explicit = (row['construction_category'] ?? '').toString();
    final source = (row['classification_source'] ?? '').toString();
    final storedKind = (row['entity_kind'] ?? '').toString();
    final isOfficialEmployerSource =
        source == 'open_data_corroboration' ||
        source == 'wa_minedex_official_join';
    if (explicit.isNotEmpty &&
        (isOfficialEmployerSource || detailed.category == other)) {
      return ConstructionClassification(
        category: fromId(explicit),
        entityKind:
            isOfficialEmployerSource &&
                storedKind != 'supplier_retail' &&
                storedKind != 'project_site'
            ? ConstructionEntityKind.employer
            : detailed.entityKind,
        confidence: isOfficialEmployerSource
            ? (source == 'wa_minedex_official_join'
                  ? 100
                  : (detailed.confidence < 85 ? 85 : detailed.confidence))
            : detailed.confidence,
        reason: isOfficialEmployerSource
            ? (row['classification_reason'] ??
                      'category corroborated by an open-data company source')
                  .toString()
            : detailed.reason,
      );
    }
    return detailed;
  }
}
