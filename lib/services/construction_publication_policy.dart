import '../models/construction_category.dart';
import '../models/construction_domain_records.dart';
import 'construction_application_contact_classifier.dart';

class ConstructionPublicationPolicy {
  const ConstructionPublicationPolicy._();

  static bool hasPublicContact(Map<String, dynamic> company) {
    const fields = [
      'website',
      'phone',
      'email',
      'careers_page',
      'facebook_url',
      'instagram_url',
    ];
    return fields.any(
      (field) => (company[field] ?? '').toString().trim().isNotEmpty,
    );
  }

  static bool hasMapCoordinates(Map<String, dynamic> company) {
    final latitude = company['latitude'] ?? company['lat'];
    final longitude = company['longitude'] ?? company['lng'];
    return _asDouble(latitude) != null && _asDouble(longitude) != null;
  }

  static bool isRelevantEmployer(Map<String, dynamic> company) {
    final classification = ConstructionCategory.classifyRowDetailed(company);
    final storedKind = (company['entity_kind'] ?? '').toString();
    final confidence =
        int.tryParse((company['classification_confidence'] ?? '').toString()) ??
        classification.confidence;
    final isEmployer = storedKind.isEmpty
        ? classification.isEmployer
        : storedKind == 'employer';
    return isEmployer && confidence >= 70;
  }

  /// Accepts verified standalone employers and any employer linked to a
  /// worksite as a corroborated operator or contractor. This keeps enrichment
  /// state-agnostic instead of hard-coding WA or NSW source identifiers.
  static bool isVerifiedEnrichmentCandidate(Map<String, dynamic> company) {
    if (!isRelevantEmployer(company)) return false;
    final classificationSource = (company['classification_source'] ?? '')
        .toString();
    if (classificationSource == 'wa_minedex_official_join' ||
        classificationSource == 'open_data_corroboration') {
      return true;
    }
    return ConstructionDomainRecords.hasCorroboratedHiringLink(company);
  }

  /// Contact details inherited only because two mining records were nearby are
  /// retained locally, but cannot be published as belonging to the company.
  /// Physical proximity corroborates a worksite, not corporate identity.
  static bool hasReliableContactAssociation(Map<String, dynamic> company) {
    final evidence = (company['known_company_website_evidence'] ?? '')
        .toString()
        .toLowerCase();
    if (evidence.startsWith('verified_nearby_mining_worksite:')) return false;
    if (evidence.startsWith('verified_other_location:') &&
        !_websiteHostMatchesSourceIdentity(company)) {
      return false;
    }
    return true;
  }

  static bool _websiteHostMatchesSourceIdentity(Map<String, dynamic> company) {
    final host = Uri.tryParse(
      (company['website'] ?? '').toString(),
    )?.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    if (host == null || host.isEmpty) return false;
    const ignored = <String>{
      'australia',
      'australian',
      'company',
      'construction',
      'contractor',
      'group',
      'holding',
      'holdings',
      'limited',
      'mineral',
      'minerals',
      'mining',
      'operations',
      'resources',
      'services',
    };
    final names = <String>{
      (company['name'] ?? '').toString(),
      (company['trading_name'] ?? '').toString(),
    };
    final tokens = names
        .expand(
          (name) => name
              .toLowerCase()
              .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
              .split(RegExp(r'\s+')),
        )
        .where((token) => token.length >= 5 && !ignored.contains(token));
    return tokens.any(host.contains);
  }

  static bool canAppearOnMap(Map<String, dynamic> company) =>
      isRelevantEmployer(company) &&
      hasReliableContactAssociation(company) &&
      (!ConstructionDomainRecords.isWorksite(company) ||
          ConstructionDomainRecords.hasCorroboratedHiringLink(company)) &&
      hasVerifiedPublicApplicationChannel(company) &&
      hasMapCoordinates(company);

  static bool hasVerifiedPublicApplicationChannel(
    Map<String, dynamic> company,
  ) {
    final evaluated = Map<String, dynamic>.from(company);
    ConstructionApplicationContactClassifier.applyDerivedFields(evaluated);
    return evaluated['careers_public_eligible'] == true ||
        evaluated['email_public_eligible'] == true ||
        evaluated['phone_public_job_enquiry_eligible'] == true;
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString());
  }
}
