import 'package:flutter/material.dart';

import '../models/guide_manual/guide_manual.dart';
import '../utils/app_i18n.dart';
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

  @override
  Widget build(BuildContext context) {
    final sectionTheme = GuideSectionTheme.forSection(sectionId);
    return FutureBuilder<Map<String, String>>(
      future: AppI18n.load(),
      initialData: AppI18n.forCode('en'),
      builder: (context, snapshot) {
        final strings = snapshot.data ?? AppI18n.forCode('en');
        String t(String key) => AppI18n.t(strings, key);
        final whvBullets = [
          t('visa.whv.b1'),
          t('visa.whv.b2'),
          t('visa.whv.b3'),
          t('visa.whv.b4'),
          t('visa.whv.b5'),
        ];
        final studentBullets = [
          t('visa.student.b1'),
          t('visa.student.b2'),
          t('visa.student.b3'),
          t('visa.student.b4'),
          t('visa.student.b5'),
        ];

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
                      Expanded(
                        child: Text(
                          t('visa.types.title'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
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
                      Text(
                        t('visa.types.heading'),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF151922),
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 44),
                      _VisaTypeCard(
                        title: t('visa.types.whv'),
                        bullets: whvBullets,
                        icon: Icons.travel_explore_outlined,
                        accentColor: const Color(0xFFE8847A),
                        onTap: () => _openPage(context, whvPage),
                      ),
                      const SizedBox(height: 18),
                      _VisaTypeCard(
                        title: t('visa.types.student'),
                        bullets: studentBullets,
                        icon: Icons.school_outlined,
                        accentColor: const Color(0xFF78A8E5),
                        onTap: () => _openPage(context, _studentVisaPage(t)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  GuidePage _studentVisaPage(String Function(String key) t) {
    return GuidePage(
      id: 'visa_overview',
      title: t('student.title'),
      summary: 'Study in Australia while working limited hours.',
      blocks: const [],
      sections: [
        GuidePageSection(
          id: 'requirements_tab',
          title: t('student.requirements_tab'),
          blocks: [
            GuideBlock(
              type: 'card',
              title: t('student.what_title'),
              items: [
                t('student.what_1'),
                t('student.what_2'),
                t('student.what_3'),
              ],
            ),
            GuideBlock(
              type: 'card',
              title: t('student.approval_title'),
              content: t('student.approval_body'),
            ),
            GuideBlock(
              type: 'card',
              title: t('student.requirements_title'),
              items: [
                t('student.req_1'),
                t('student.req_2'),
                t('student.req_3'),
                t('student.req_4'),
                t('student.req_5'),
              ],
              ordered: true,
              buttonLabel: t('insurance.recommended'),
              buttonUrl: 'action:travel_insurance',
            ),
            GuideBlock(
              type: 'callout',
              title: t('student.important_title'),
              content: t('student.important_body'),
              variant: 'warning',
            ),
          ],
        ),
        GuidePageSection(
          id: 'apply_steps_tab',
          title: t('student.apply_tab'),
          blocks: [
            GuideBlock(
              type: 'card',
              title: t('student.steps_title'),
              items: [
                t('student.step_1'),
                t('student.step_2'),
                t('student.step_3'),
                t('student.step_4'),
                t('student.step_5'),
              ],
              ordered: true,
            ),
            GuideBlock(
              type: 'card',
              title: t('student.balance_title'),
              content: t('student.balance_body'),
            ),
            GuideBlock(
              type: 'card',
              title: t('student.support_title'),
              content: t('student.support_body'),
              buttonLabel: t('student.support_button'),
              buttonUrl: 'https://youtooproject.com/contacto/?ref=miquelmasso',
            ),
            GuideBlock(
              type: 'card',
              title: t('student.official_title'),
              buttonLabel: t('student.official_button'),
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
