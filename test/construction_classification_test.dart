import 'package:flutter_test/flutter_test.dart';
import 'package:mywhv/models/construction_category.dart';
import 'package:mywhv/models/construction_domain_records.dart';
import 'package:mywhv/services/construction_application_contact_classifier.dart';
import 'package:mywhv/services/construction_company_identity_matcher.dart';
import 'package:mywhv/services/construction_publication_policy.dart';

void main() {
  test('official MINEDEX operator/worksite join is a verified employer', () {
    final row = <String, dynamic>{
      'name': 'Example Resources Pty Ltd',
      'construction_category': 'mining_company',
      'entity_kind': 'employer',
      'classification_confidence': 100,
      'classification_source': 'wa_minedex_official_join',
      'classification_reason': 'Current official worksite operator',
      'latitude': -28.1,
      'longitude': 121.3,
      'email': 'recruitment@example.com.au',
      'website': 'https://example.com.au',
      'email_domain_status': 'active_mx',
      'email_officially_published': true,
    };

    final result = ConstructionCategory.classifyRowDetailed(row);

    expect(result.category, ConstructionCategory.miningCompany);
    expect(result.entityKind, ConstructionEntityKind.employer);
    expect(result.confidence, 100);
    expect(ConstructionPublicationPolicy.canAppearOnMap(row), isTrue);
  });

  test('corroborated NSW coal operator enters the enrichment queue', () {
    final row = <String, dynamic>{
      'name': 'GM3',
      'worksite_name': 'Appin underground mine',
      'entity_kind': 'employer',
      'construction_category': 'mining_company',
      'classification_confidence': 95,
      'classification_source': 'nsw_coal_services_official_join',
      'company_worksite_role': 'operator',
      'link_corroborated': true,
      'company_worksite_evidence':
          'Coal Services NSW Black Coal Producers Directory',
      'state': 'NSW',
    };

    expect(
      ConstructionPublicationPolicy.isVerifiedEnrichmentCandidate(row),
      isTrue,
    );
  });

  group('construction employer classification', () {
    test('hardware shops are suppliers and cannot appear on the map', () {
      final company = <String, dynamic>{
        'name': 'Example Hardware',
        'osm_shop': 'hardware',
        'latitude': -31.95,
        'longitude': 115.86,
        'careers_page': 'https://example.com/careers',
        'careers_verification_status': 'verified',
      };

      final result = ConstructionCategory.classifyRowDetailed(company);

      expect(result.entityKind, ConstructionEntityKind.supplierRetail);
      expect(ConstructionPublicationPolicy.canAppearOnMap(company), isFalse);
    });

    test('a civil contractor with public contact can appear on the map', () {
      final company = <String, dynamic>{
        'name': 'Example Civil Contractors',
        'osm_office': 'construction',
        'osm_service': 'earthworks drainage roads',
        'latitude': -31.95,
        'longitude': 115.86,
        'careers_page': 'https://example.com/careers',
        'careers_verification_status': 'verified',
      };

      final result = ConstructionCategory.classifyRowDetailed(company);

      expect(result.category, ConstructionCategory.civil);
      expect(result.entityKind, ConstructionEntityKind.employer);
      expect(ConstructionPublicationPolicy.canAppearOnMap(company), isTrue);
    });

    test(
      'a clearly named construction employer is not rejected for sparse tags',
      () {
        final company = <String, dynamic>{
          'name': 'Example Regional Construction',
          'latitude': -31.95,
          'longitude': 115.86,
          'email': 'info@example.com.au',
          'website': 'https://example.com.au',
          'email_domain_status': 'active_mx',
          'email_officially_published': true,
        };

        final result = ConstructionCategory.classifyRowDetailed(company);

        expect(result.entityKind, ConstructionEntityKind.employer);
        expect(result.confidence, greaterThanOrEqualTo(70));
        expect(ConstructionPublicationPolicy.canAppearOnMap(company), isTrue);
      },
    );

    test('an unverified mine is a project site, not an employer', () {
      final company = <String, dynamic>{
        'name': 'Example Gold Mine',
        'osm_industrial': 'mine',
        'latitude': -28.0,
        'longitude': 121.0,
        'website': 'https://example.com',
      };

      final result = ConstructionCategory.classifyRowDetailed(company);

      expect(result.entityKind, ConstructionEntityKind.projectSite);
      expect(ConstructionPublicationPolicy.canAppearOnMap(company), isFalse);
    });

    test('low-confidence unknown places stay in review', () {
      final company = <String, dynamic>{
        'name': 'Example Place',
        'latitude': -31.95,
        'longitude': 115.86,
        'phone': '08 0000 0000',
      };

      final result = ConstructionCategory.classifyRowDetailed(company);

      expect(result.entityKind, ConstructionEntityKind.unknown);
      expect(ConstructionPublicationPolicy.canAppearOnMap(company), isFalse);
    });
  });

  group('construction application-contact classification', () {
    test('recruitment mailboxes and verified jobs pages are direct', () {
      for (final row in [
        {'email': 'talent@example.com.au'},
        {'careers_page': 'https://example.com/work-with-us'},
      ]) {
        final result = ConstructionApplicationContactClassifier.classify(row);
        expect(
          result.type,
          ConstructionApplicationContactType.directApplication,
        );
      }
    });

    test(
      'generic inboxes are job enquiries and switchboards are general only',
      () {
        expect(
          ConstructionApplicationContactClassifier.classify({
            'email': 'reception@example.com.au',
          }).type,
          ConstructionApplicationContactType.askAboutJobs,
        );
        expect(
          ConstructionApplicationContactClassifier.classify({
            'phone': '08 9000 0000',
          }).type,
          ConstructionApplicationContactType.generalCompanyContact,
        );
      },
    );

    test(
      'personal and specialist contacts are unsuitable without recruitment evidence',
      () {
        for (final email in [
          'jane.smith@example.com.au',
          'director@example.com.au',
          'licensing@example.com.au',
          'accounts@example.com.au',
          'media@example.com.au',
          'investors@example.com.au',
        ]) {
          expect(
            ConstructionApplicationContactClassifier.classify({
              'email': email,
            }).type,
            ConstructionApplicationContactType.unsuitable,
          );
        }
      },
    );

    test('non-recruitment operational mailboxes are never applications', () {
      for (final email in [
        'no-reply@example.com.au',
        'apsupport@example.com.au',
        'generalcounsel@example.com.au',
        'corporate.services@example.com.au',
        'cybersecurity@example.com.au',
        'ChemProdSteward@example.com.au',
      ]) {
        expect(
          ConstructionApplicationContactClassifier.classify({
            'email': email,
          }).type,
          ConstructionApplicationContactType.unsuitable,
        );
      }
    });

    test('careers and an unsuitable email receive independent verdicts', () {
      final row = <String, dynamic>{
        'email': 'ceo@example.com.au',
        'careers_page': 'https://example.com/jobs',
        'careers_verification_status': 'verified',
      };
      ConstructionApplicationContactClassifier.applyDerivedFields(row);
      expect(row['careers_public_eligible'], isTrue);
      expect(row['email_contact_type'], 'unsuitable');
      expect(row['email_public_eligible'], isFalse);
    });

    test('rejects image filenames and polluted extraction suffixes', () {
      for (final email in [
        'About-US_At-CITIC-Pacific@4x.png',
        'shades@weathersafe.com.au.Contact',
      ]) {
        expect(
          ConstructionApplicationContactClassifier.isSemanticallyValidEmail(
            email,
          ),
          isFalse,
        );
      }
    });

    test('dead and uncorroborated email channels remain private', () {
      final dead = <String, dynamic>{
        'email': 'jobs@example.com.au',
        'website': 'https://example.com.au',
        'email_domain_status': 'no_mx',
        'email_officially_published': true,
      };
      final mismatch = <String, dynamic>{
        'email': 'jobs@parent.example',
        'website': 'https://subsidiary.example',
        'email_domain_status': 'active_mx',
        'email_officially_published': true,
      };
      ConstructionApplicationContactClassifier.applyDerivedFields(dead);
      ConstructionApplicationContactClassifier.applyDerivedFields(mismatch);
      expect(dead['email_public_eligible'], isFalse);
      expect(mismatch['email_public_eligible'], isFalse);
    });

    test(
      'legacy unchecked contacts do not become failures during migration',
      () {
        final row = <String, dynamic>{
          'email': 'info@example.com.au',
          'website': 'https://example.com.au',
        };
        ConstructionApplicationContactClassifier.applyDerivedFields(row);
        expect(row['email_domain_status'], isNull);
        expect(row['email_public_eligible'], isTrue);
      },
    );

    test('a switchboard remains useful when the email is confirmed dead', () {
      final row = <String, dynamic>{
        'email': 'jobs@example.com.au',
        'email_domain_status': 'no_mx',
        'email_officially_published': true,
        'phone': '08 9000 0000',
      };
      ConstructionApplicationContactClassifier.applyDerivedFields(row);
      expect(row['email_public_eligible'], isFalse);
      expect(row['phone_public_job_enquiry_eligible'], isTrue);
    });
  });

  group('construction website identity', () {
    test('rejects partial-name companies from unrelated domains', () {
      expect(
        ConstructionCompanyIdentityMatcher.matchesWebsite(
          html: '<title>Aeris IoT</title><p>Aeris resources and support</p>',
          url: 'https://aeris.com',
          businessName: 'Aeris Resources Ltd',
          aliases: const ['Aeris'],
        ),
        isFalse,
      );
      expect(
        ConstructionCompanyIdentityMatcher.matchesWebsite(
          html: '<title>Hill Defence</title>',
          url: 'https://hill.com.au',
          businessName: 'Mineral Hill Pty Ltd',
        ),
        isFalse,
      );
    });

    test('accepts the complete company identity', () {
      expect(
        ConstructionCompanyIdentityMatcher.matchesWebsite(
          html: '<title>Aeris Resources</title>',
          url: 'https://aerisresources.com.au',
          businessName: 'Aeris Resources Ltd',
        ),
        isTrue,
      );
      expect(
        ConstructionCompanyIdentityMatcher.matchesWebsite(
          html: '<title>The Bloomfield Group</title>',
          url: 'https://bloomcoll.com.au',
          businessName: 'Bloomfield Group',
        ),
        isTrue,
      );
      expect(
        ConstructionCompanyIdentityMatcher.matchesWebsite(
          html: '<title>Heidelberg Materials Australia</title>',
          url: 'https://heidelbergmaterials.com.au',
          businessName: 'Heidelberg Materials Australia Pty Ltd',
        ),
        isTrue,
      );
    });
  });

  group('construction company/worksite publication', () {
    Map<String, dynamic> worksite(String role, {bool corroborated = true}) => {
      'name': 'Example Mine Operator',
      'worksite_name': 'Example Mine',
      'record_type': 'construction_worksite',
      'entity_kind': 'employer',
      'classification_confidence': 100,
      'company_worksite_role': role,
      'link_corroborated': corroborated,
      'email': 'jobs@example.com.au',
      'website': 'https://example.com.au',
      'email_domain_status': 'active_mx',
      'email_officially_published': true,
      'latitude': -30.0,
      'longitude': 145.0,
    };

    test('corroborated operators and contractors can publish', () {
      expect(
        ConstructionPublicationPolicy.canAppearOnMap(worksite('operator')),
        isTrue,
      );
      expect(
        ConstructionPublicationPolicy.canAppearOnMap(worksite('contractor')),
        isTrue,
      );
    });

    test('owners and unlinked worksites remain local only', () {
      expect(
        ConstructionPublicationPolicy.canAppearOnMap(worksite('owner')),
        isFalse,
      );
      expect(
        ConstructionPublicationPolicy.canAppearOnMap(
          worksite('operator', corroborated: false),
        ),
        isFalse,
      );
      final unlinked = <String, dynamic>{
        'name': 'Unlinked Mine',
        'record_type': 'construction_worksite',
        'entity_kind': 'project_site',
      };
      ConstructionDomainRecords.attachDerivedIds(unlinked);
      expect(unlinked['company_id'], isNull);
      expect(unlinked['worksite_id'], isNotEmpty);
    });

    test('proximity-derived contacts stay local until identity is proven', () {
      final row = worksite('operator')
        ..addAll({
          'website': 'https://centennialcoal.com.au',
          'known_company_website_evidence':
              'verified_nearby_mining_worksite:another-record',
        });

      expect(
        ConstructionPublicationPolicy.hasReliableContactAssociation(row),
        isFalse,
      );
      expect(ConstructionPublicationPolicy.canAppearOnMap(row), isFalse);
    });

    test('sibling contact reuse requires the source identity to match', () {
      final contaminated = worksite('operator')
        ..addAll({
          'name': 'HEIDELBERG MATERIALS AUSTRALIA PTY LTD',
          'website': 'https://centennialcoal.com.au',
          'known_company_website_evidence':
              'verified_other_location:another-record',
        });
      final corroborated = worksite('operator')
        ..addAll({
          'name': 'Centennial Airly Pty Ltd',
          'website': 'https://centennialcoal.com.au',
          'known_company_website_evidence':
              'verified_other_location:another-record',
        });

      expect(
        ConstructionPublicationPolicy.hasReliableContactAssociation(
          contaminated,
        ),
        isFalse,
      );
      expect(
        ConstructionPublicationPolicy.hasReliableContactAssociation(
          corroborated,
        ),
        isTrue,
      );
    });
  });
}
