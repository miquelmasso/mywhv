enum ConstructionApplicationContactType {
  directApplication('direct_application'),
  askAboutJobs('ask_about_jobs'),
  generalCompanyContact('general_company_contact'),
  unsuitable('unsuitable'),
  none('none');

  const ConstructionApplicationContactType(this.id);
  final String id;
}

class ConstructionApplicationContactClassification {
  const ConstructionApplicationContactClassification({
    required this.type,
    required this.confidence,
    required this.evidence,
  });

  final ConstructionApplicationContactType type;
  final int confidence;
  final List<String> evidence;

  bool get isSuitableForPublicMap =>
      type == ConstructionApplicationContactType.directApplication ||
      type == ConstructionApplicationContactType.askAboutJobs;
}

class ConstructionApplicationContactClassifier {
  const ConstructionApplicationContactClassifier._();

  static ConstructionApplicationContactClassification classify(
    Map<String, dynamic> company,
  ) {
    final careers = (company['careers_page'] ?? '').toString().trim();
    final website = (company['website'] ?? '').toString().trim();
    final email = (company['email'] ?? '').toString().trim().toLowerCase();
    final phone = (company['phone'] ?? '').toString().trim();

    final directUrls = <String>[
      if (_isJobsUrl(careers)) careers,
      if (_isJobsUrl(website)) website,
    ];
    if (directUrls.isNotEmpty) {
      return ConstructionApplicationContactClassification(
        type: ConstructionApplicationContactType.directApplication,
        confidence: careers.isNotEmpty ? 98 : 92,
        evidence: directUrls.map((url) => 'verified_jobs_page:$url').toList(),
      );
    }

    final localPart = _emailLocalPart(email);
    if (localPart.isNotEmpty && _isBlockedMailbox(localPart)) {
      return ConstructionApplicationContactClassification(
        type: ConstructionApplicationContactType.unsuitable,
        confidence: 99,
        evidence: ['non_recruitment_mailbox:$email'],
      );
    }
    if (localPart.isNotEmpty && _matchesMailbox(localPart, _recruitmentTerms)) {
      return ConstructionApplicationContactClassification(
        type: ConstructionApplicationContactType.directApplication,
        confidence: 96,
        evidence: ['recruitment_email:$email'],
      );
    }
    if (localPart.isNotEmpty && _matchesMailbox(localPart, _genericTerms)) {
      return ConstructionApplicationContactClassification(
        type: ConstructionApplicationContactType.askAboutJobs,
        confidence: 86,
        evidence: ['generic_corporate_email:$email'],
      );
    }
    if (localPart.isNotEmpty) {
      final unsuitableReason = _unsuitableEmailReason(localPart);
      return ConstructionApplicationContactClassification(
        type: ConstructionApplicationContactType.unsuitable,
        confidence: unsuitableReason == 'named_personal_email' ? 82 : 94,
        evidence: ['$unsuitableReason:$email'],
      );
    }
    if (phone.isNotEmpty) {
      return ConstructionApplicationContactClassification(
        type: ConstructionApplicationContactType.generalCompanyContact,
        confidence: 75,
        evidence: ['corporate_switchboard:$phone'],
      );
    }
    return const ConstructionApplicationContactClassification(
      type: ConstructionApplicationContactType.none,
      confidence: 100,
      evidence: ['no_application_contact'],
    );
  }

  static void applyDerivedFields(Map<String, dynamic> company) {
    final result = classify(company);
    company['application_contact_type'] = result.type.id;
    company['application_contact_confidence'] = result.confidence;
    company['application_contact_evidence'] = result.evidence;
    _applyPerChannelFields(company);
  }

  static void _applyPerChannelFields(Map<String, dynamic> company) {
    final email = (company['email'] ?? '').toString().trim().toLowerCase();
    final careers = (company['careers_page'] ?? '').toString().trim();
    final phone = (company['phone'] ?? '').toString().trim();

    final emailSemanticValid = isSemanticallyValidEmail(email);
    final emailResult = emailSemanticValid
        ? classify(<String, dynamic>{'email': email})
        : const ConstructionApplicationContactClassification(
            type: ConstructionApplicationContactType.unsuitable,
            confidence: 100,
            evidence: ['malformed_or_extraction_garbage'],
          );
    company['email_contact_type'] = email.isEmpty
        ? ConstructionApplicationContactType.none.id
        : emailResult.type.id;
    company['email_contact_confidence'] = emailResult.confidence;
    company['email_contact_evidence'] = emailResult.evidence;
    company['email_format_valid'] = email.isNotEmpty && _hasEmailShape(email);
    company['email_semantic_valid'] = emailSemanticValid;

    final identityStatus = _emailIdentityStatus(company, email);
    company['email_identity_status'] = identityStatus;
    final mailStatus = (company['email_domain_status'] ?? 'not_checked')
        .toString();
    final verificationStatus = (company['email_verification_status'] ?? '')
        .toString();
    final officiallyPublished =
        company['email_officially_published'] == true ||
        verificationStatus == 'officially_published';
    final isLegacyUnchecked =
        mailStatus == 'not_checked' && verificationStatus.isEmpty;
    final mailDomainIsNotKnownBad = !const {
      'no_mx',
      'invalid_email',
      'dns_error',
    }.contains(mailStatus);
    company['email_public_eligible'] =
        emailResult.isSuitableForPublicMap &&
        emailSemanticValid &&
        mailDomainIsNotKnownBad &&
        (officiallyPublished || isLegacyUnchecked) &&
        identityStatus != 'unverified_domain_mismatch';

    final careersVerificationStatus =
        (company['careers_verification_status'] ?? '').toString();
    final careersVerified =
        _isJobsUrl(careers) &&
        careersVerificationStatus != 'rejected' &&
        careersVerificationStatus != 'invalid';
    company['careers_contact_type'] = careersVerified
        ? ConstructionApplicationContactType.directApplication.id
        : ConstructionApplicationContactType.none.id;
    company['careers_contact_confidence'] = careersVerified ? 98 : 0;
    company['careers_contact_evidence'] = careersVerified
        ? <String>['verified_jobs_page:$careers']
        : <String>[];
    company['careers_public_eligible'] = careersVerified;

    company['phone_contact_type'] = phone.isEmpty
        ? ConstructionApplicationContactType.none.id
        : ConstructionApplicationContactType.generalCompanyContact.id;
    company['phone_public_job_enquiry_eligible'] =
        phone.isNotEmpty && company['phone_verification_status'] != 'invalid';
  }

  /// Rejects strings which merely resemble an address because they were cut
  /// from an image filename, URL, CSS selector, or neighbouring page text.
  static bool isSemanticallyValidEmail(String value) {
    final email = value.trim().toLowerCase();
    if (!_hasEmailShape(email)) return false;
    const forbiddenEndings = <String>{
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.svg',
      '.webp',
      '.css',
      '.js',
      '.contact',
      '.email',
      '.image',
      '.icon',
    };
    if (forbiddenEndings.any(email.endsWith)) return false;
    if (email.contains('mailto:') ||
        email.contains('://') ||
        email.contains('%40') ||
        RegExp(r'@[0-9]+x\.[a-z]+$').hasMatch(email)) {
      return false;
    }
    return true;
  }

  static bool _hasEmailShape(String email) => RegExp(
    r"^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$",
    caseSensitive: false,
  ).hasMatch(email);

  static String _emailIdentityStatus(
    Map<String, dynamic> company,
    String email,
  ) {
    if (!isSemanticallyValidEmail(email)) return 'invalid';
    final emailDomain = email.substring(email.lastIndexOf('@') + 1);
    if (_publicMailboxDomains.contains(emailDomain)) {
      return 'public_mail_provider';
    }
    final websiteHost = Uri.tryParse(
      (company['website'] ?? '').toString(),
    )?.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    if (websiteHost == null || websiteHost.isEmpty) {
      return 'no_verified_website';
    }
    if (websiteHost == emailDomain ||
        websiteHost.endsWith('.$emailDomain') ||
        emailDomain.endsWith('.$websiteHost')) {
      return 'matches_website';
    }
    if (company['email_domain_relationship_corroborated'] == true) {
      return 'corroborated_related_domain';
    }
    return 'unverified_domain_mismatch';
  }

  static bool _isJobsUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
    final text = '${uri.path} ${uri.query}'.toLowerCase();
    final normalized = text.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    final tokens = normalized.split(RegExp(r'\s+')).toSet();
    return tokens.intersection(_jobsUrlTerms).isNotEmpty ||
        text.contains('work-with-us') ||
        text.contains('join-us');
  }

  static String _emailLocalPart(String email) {
    final at = email.lastIndexOf('@');
    return at > 0 && at < email.length - 1 ? email.substring(0, at) : '';
  }

  static bool _matchesMailbox(String localPart, Set<String> terms) {
    final tokens = localPart.split(RegExp(r'[._+\-]'));
    return tokens.any(terms.contains) || terms.contains(localPart);
  }

  static bool _isBlockedMailbox(String localPart) {
    final compact = localPart.replaceAll(RegExp(r'[^a-z0-9]+'), '');
    return _blockedMailboxNames.any(
      (name) => compact == name || compact.startsWith(name),
    );
  }

  static String _unsuitableEmailReason(String localPart) {
    if (_matchesMailbox(localPart, _executiveTerms)) return 'executive_email';
    if (_matchesMailbox(localPart, _specialistTerms)) return 'specialist_email';
    return 'named_personal_email';
  }

  static const _recruitmentTerms = {
    'career',
    'careers',
    'job',
    'jobs',
    'recruit',
    'recruitment',
    'recruiting',
    'hr',
    'people',
    'talent',
    'employment',
    'vacancies',
  };
  static const _jobsUrlTerms = {
    'career',
    'careers',
    'job',
    'jobs',
    'vacancy',
    'vacancies',
    'employment',
    'opportunities',
  };
  static const _genericTerms = {
    'info',
    'reception',
    'admin',
    'contact',
    'enquiry',
    'enquiries',
  };
  static const _executiveTerms = {'ceo', 'director', 'managingdirector', 'md'};
  static const _specialistTerms = {
    'licensing',
    'licence',
    'environment',
    'environmental',
    'accounts',
    'accounting',
    'finance',
    'supply',
    'procurement',
    'media',
    'press',
    'investor',
    'investors',
    'ir',
    'legal',
    'privacy',
    'security',
    'cybersecurity',
    'communications',
    'sales',
    'support',
    'customerservice',
  };
  static const _blockedMailboxNames = {
    'noreply',
    'donotreply',
    'apsupport',
    'accountspayable',
    'generalcounsel',
    'corporateservices',
    'chemprodsteward',
    'cybersecurity',
    'customerservice',
  };
  static const _publicMailboxDomains = {
    'gmail.com',
    'hotmail.com',
    'outlook.com',
    'icloud.com',
    'live.com.au',
    'bigpond.com',
    'westnet.com.au',
    'iinet.net.au',
  };
}
