import 'package:flutter/material.dart';

import '../models/guide_manual/guide_manual.dart';
import '../utils/guide_section_theme.dart';
import '../widgets/guide_back_button.dart';
import 'guide_page_screen.dart';

class VisaTypeSelectionScreen extends StatelessWidget {
  const VisaTypeSelectionScreen({
    super.key,
    required this.sectionId,
    required this.whvPage,
    required this.initialStrings,
    this.onNavigateToTab,
  });

  final String sectionId;
  final GuidePage whvPage;
  final Map<String, String> initialStrings;
  final void Function(int index)? onNavigateToTab;

  static const List<String> _whvBullets = [
    'Travel and work full-time',
    'Change employers freely',
    'Explore Australia while saving',
    'Valid for adventure and work',
    'Good for short-term plans',
  ];

  static const List<String> _studentBullets = [
    'Study at schools, TAFE or uni',
    'Work limited hours',
    'Build a longer-term future',
    'Improve English or skills',
    'Best for study-based plans',
  ];

  @override
  Widget build(BuildContext context) {
    final sectionTheme = GuideSectionTheme.forSection(sectionId);
    return Scaffold(
      backgroundColor: sectionTheme.pageBackground,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
              child: Row(
                children: [
                  GuideBackButton(onTap: () => Navigator.of(context).pop()),
                  const Expanded(
                    child: Text(
                      'Visa & requirements',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF151922),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 34, 24, 28),
                children: [
                  const Text(
                    'Types of visa',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF151922),
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 44),
                  _VisaTypeCard(
                    title: 'Work and Holiday Visa',
                    bullets: _whvBullets,
                    icon: Icons.travel_explore_outlined,
                    accentColor: const Color(0xFFE8847A),
                    onTap: () => _openPage(context, whvPage),
                  ),
                  const SizedBox(height: 18),
                  _VisaTypeCard(
                    title: 'Student Visa',
                    bullets: _studentBullets,
                    icon: Icons.school_outlined,
                    accentColor: const Color(0xFF78A8E5),
                    onTap: () => _openPage(context, _studentVisaPage),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openPage(BuildContext context, GuidePage page) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GuidePageScreen(
          sectionId: sectionId,
          page: page,
          onNavigateToTab: onNavigateToTab,
          initialStrings: initialStrings,
        ),
      ),
    );
  }

  static final GuidePage _studentVisaPage = GuidePage(
    id: 'visa_overview',
    title: 'Student Visa',
    summary: 'Study in Australia while working limited hours.',
    blocks: const [],
    sections: [
      GuidePageSection(
        id: 'requirements_tab',
        title: 'Requirements',
        blocks: [
          GuideBlock(
            type: 'card',
            title: 'What is a Student Visa?',
            items: [
              'Designed for people enrolled in an eligible course in Australia.',
              'Allows study at schools, TAFE, universities or other approved providers.',
              'Lets students work limited hours while studying.',
            ],
          ),
          GuideBlock(
            type: 'card',
            title: 'Estimated approval time',
            content:
                'Processing times vary depending on your course, country, documents and application quality.',
          ),
          GuideBlock(
            type: 'card',
            title: 'Student Visa requirements',
            items: [
              'Valid passport',
              'Confirmation of Enrolment from an approved provider',
              'Evidence of funds for course fees, travel and living costs',
              'Health insurance for overseas students',
              'English level or education documents if required',
            ],
            ordered: true,
            buttonLabel: 'Recommended insurance',
            buttonUrl: 'action:travel_insurance',
          ),
          GuideBlock(
            type: 'callout',
            title: 'Important',
            content:
                'Student visa rules and work conditions can change. Always verify the latest requirements on the official Australian Government website before applying.',
            variant: 'warning',
          ),
        ],
      ),
      GuidePageSection(
        id: 'apply_steps_tab',
        title: 'How to apply',
        blocks: [
          GuideBlock(
            type: 'card',
            title: 'Application steps',
            items: [
              'Choose an eligible course and education provider.',
              'Receive your Confirmation of Enrolment.',
              'Prepare documents, funds evidence and health insurance.',
              'Apply online through ImmiAccount.',
              'Wait for the visa decision before making final plans.',
            ],
            ordered: true,
          ),
          GuideBlock(
            type: 'card',
            title: 'Work and study balance',
            content:
                'Plan your budget around study first. Work rights are limited and should not be treated as the only way to fund your stay.',
          ),
          GuideBlock(
            type: 'card',
            title: 'Student visa support',
            content:
                'If you need help applying for a student visa or finding schools and study centres in Australia, we recommend contacting YouTooProject.',
            buttonLabel: 'YouTooProject',
            buttonUrl: 'https://youtooproject.com/contacto/?ref=miquelmasso',
          ),
          GuideBlock(
            type: 'card',
            title: 'Official information',
            buttonLabel: 'Check Student Visa details',
            buttonUrl:
                'https://immi.homeaffairs.gov.au/visas/getting-a-visa/visa-listing/student-500',
          ),
        ],
      ),
    ],
    checklist: const [],
    cta: GuideCtaLink(forumTag: 'visa'),
  );
}

class _VisaTypeCard extends StatelessWidget {
  const _VisaTypeCard({
    required this.title,
    required this.bullets,
    required this.icon,
    required this.accentColor,
    required this.onTap,
  });

  final String title;
  final List<String> bullets;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.045),
                blurRadius: 18,
                spreadRadius: -6,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accentColor, size: 25),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF151922),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...bullets.map(
                      (bullet) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 7),
                              child: Container(
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: accentColor.withValues(alpha: 0.78),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                bullet,
                                style: const TextStyle(
                                  color: Color(0xFF3E3A39),
                                  fontSize: 13.5,
                                  height: 1.28,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Color(0xFF8E8A86)),
            ],
          ),
        ),
      ),
    );
  }
}
