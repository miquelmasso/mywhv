import 'package:flutter/material.dart';

class GuideSectionTheme {
  const GuideSectionTheme({
    required this.pageBackground,
    required this.accent,
    required this.softAccent,
    required this.buttonBackground,
    required this.buttonText,
    required this.calloutBackground,
    required this.warningIcon,
  });

  final Color pageBackground;
  final Color accent;
  final Color softAccent;
  final Color buttonBackground;
  final Color buttonText;
  final Color calloutBackground;
  final Color warningIcon;

  static const fallback = GuideSectionTheme(
    pageBackground: Color(0xFFFFF8F7),
    accent: Color(0xFF9F5A4D),
    softAccent: Color(0xFFF8EDEA),
    buttonBackground: Color(0xFFEBCBC3),
    buttonText: Color(0xFF8A4A3A),
    calloutBackground: Color(0xFFFFF3D9),
    warningIcon: Color(0xFFFF8A00),
  );

  static GuideSectionTheme forSection(String sectionId) {
    switch (sectionId) {
      case 'visa_requirements':
        return const GuideSectionTheme(
          pageBackground: Color(0xFFFFF6F4),
          accent: Color(0xFFE8847A),
          softAccent: Color(0xFFFFE7E4),
          buttonBackground: Color(0xFFFFE7E4),
          buttonText: Color(0xFFB65F54),
          calloutBackground: Color(0xFFFFF0E8),
          warningIcon: Color(0xFFE8847A),
        );
      case 'before_arrival':
        return const GuideSectionTheme(
          pageBackground: Color(0xFFFFFAF1),
          accent: Color(0xFFE9B34F),
          softAccent: Color(0xFFFFF0D4),
          buttonBackground: Color(0xFFFFD686),
          buttonText: Color(0xFFAF7316),
          calloutBackground: Color(0xFFFFF4D9),
          warningIcon: Color(0xFFE9A93D),
        );
      case 'arrival_steps':
        return const GuideSectionTheme(
          pageBackground: Color(0xFFFCF7FF),
          accent: Color(0xFFB985D8),
          softAccent: Color(0xFFF0E4FA),
          buttonBackground: Color(0xFFD9B9EF),
          buttonText: Color(0xFF8250A3),
          calloutBackground: Color(0xFFF6ECFF),
          warningIcon: Color(0xFFB985D8),
        );
      case 'housing':
        return const GuideSectionTheme(
          pageBackground: Color(0xFFF5FCFB),
          accent: Color(0xFFA6D7D2),
          softAccent: Color(0xFFE4F5F3),
          buttonBackground: Color(0xFFC1E5E0),
          buttonText: Color(0xFF4B8C86),
          calloutBackground: Color(0xFFEFFFFD),
          warningIcon: Color(0xFF7FBFB8),
        );
      case 'work':
        return const GuideSectionTheme(
          pageBackground: Color(0xFFF5FAFF),
          accent: Color(0xFF78A8E5),
          softAccent: Color(0xFFE4F0FF),
          buttonBackground: Color(0xFFC8DFFF),
          buttonText: Color(0xFF4376B2),
          calloutBackground: Color(0xFFEEF6FF),
          warningIcon: Color(0xFF78A8E5),
        );
      case 'regional_and_extension':
        return const GuideSectionTheme(
          pageBackground: Color(0xFFFAFCF5),
          accent: Color(0xFF98A76B),
          softAccent: Color(0xFFEAF0DA),
          buttonBackground: Color(0xFFCBD9A5),
          buttonText: Color(0xFF667A3C),
          calloutBackground: Color(0xFFF2F6E5),
          warningIcon: Color(0xFF98A76B),
        );
      case 'transport':
        return const GuideSectionTheme(
          pageBackground: Color(0xFFF3FBFD),
          accent: Color(0xFF63B3C1),
          softAccent: Color(0xFFDFF3F7),
          buttonBackground: Color(0xFFB7E4EC),
          buttonText: Color(0xFF357F8F),
          calloutBackground: Color(0xFFEAF9FC),
          warningIcon: Color(0xFF63B3C1),
        );
      case 'money_taxes':
        return const GuideSectionTheme(
          pageBackground: Color(0xFFFCF8F5),
          accent: Color(0xFF9B8172),
          softAccent: Color(0xFFEDE3DC),
          buttonBackground: Color(0xFFD7C0B1),
          buttonText: Color(0xFF735749),
          calloutBackground: Color(0xFFF7EFE9),
          warningIcon: Color(0xFF9B8172),
        );
    }
    return fallback;
  }
}
