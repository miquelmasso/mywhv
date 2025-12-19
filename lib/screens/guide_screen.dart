import 'package:flutter/material.dart';

import '../models/guide_manual/guide_manual.dart';
import '../repositories/guide_manual_repository.dart';
import 'guide_page_screen.dart';
import 'guide_section_screen.dart';

class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key, this.onNavigateToTab});

  final void Function(int index)? onNavigateToTab;

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  static const Map<String, IconData> _iconMap = {
    // Use broadly available Material icons to avoid SDK version issues.
    'passport': Icons.badge_outlined,
    'flight_takeoff': Icons.flight_takeoff,
    'how_to_reg': Icons.how_to_reg,
    'home': Icons.home,
    'work': Icons.work,
    'agriculture': Icons.agriculture,
    'directions_car': Icons.directions_car,
    'attach_money': Icons.attach_money,
  };

  late Future<GuideManual> _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = GuideManualRepository().loadFromAssets();
  }

  void _openSection(BuildContext context, GuideSection section) {
    // Per a seccions que només tenen una pàgina (ex: visa), salta directament al contingut.
    if (section.id == 'visa_requirements' && section.pages.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GuidePageScreen(
            sectionId: section.id,
            page: section.pages.first,
            onNavigateToTab: widget.onNavigateToTab,
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GuideSectionScreen(
          section: section,
          onNavigateToTab: widget.onNavigateToTab,
        ),
      ),
    );
  }

  List<GuideSection> _filterSections(List<GuideSection> sections) {
    if (_query.trim().isEmpty) return sections;
    final q = _query.toLowerCase();
    return sections
        .where(
          (s) =>
              s.title.toLowerCase().contains(q) ||
              s.description.toLowerCase().contains(q),
        )
        .toList();
  }

  IconData _iconForSection(String iconName) {
    return _iconMap[iconName] ?? Icons.menu_book_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guia Austràlia'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              onChanged: (val) => setState(() => _query = val),
              decoration: InputDecoration(
                hintText: 'Cerca a la guia',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.grey.withOpacity(0.2),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: FutureBuilder<GuideManual>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError || snapshot.data == null) {
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Error carregant la guia.'),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _future = GuideManualRepository().loadFromAssets();
                            });
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    );
                  }
                  final sections = _filterSections(snapshot.data!.sections);
                  if (sections.isEmpty) {
                    return const Center(child: Text('No s’han trobat seccions.'));
                  }
                  return GridView.builder(
                    itemCount: sections.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.35,
                    ),
                    itemBuilder: (context, index) {
                      final section = sections[index];
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _openSection(context, section),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _iconForSection(section.icon),
                                  size: 22,
                                  color: Colors.blue[700],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                section.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
