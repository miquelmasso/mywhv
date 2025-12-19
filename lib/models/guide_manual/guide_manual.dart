class GuideManual {
  final String version;
  final String lang;
  final String updatedAt;
  final List<GuideSection> sections;

  GuideManual({
    required this.version,
    required this.lang,
    required this.updatedAt,
    required this.sections,
  });

  factory GuideManual.fromJson(Map<String, dynamic> json) {
    final sectionsJson = json['sections'] as List? ?? [];
    return GuideManual(
      version: (json['version'] ?? '').toString(),
      lang: (json['lang'] ?? '').toString(),
      updatedAt: (json['updated_at'] ?? '').toString(),
      sections: sectionsJson
          .whereType<Map<String, dynamic>>()
          .map(GuideSection.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'lang': lang,
        'updated_at': updatedAt,
        'sections': sections.map((s) => s.toJson()).toList(),
      };
}

class GuideSection {
  final String id;
  final String title;
  final String description;
  final String icon;
  final List<GuidePage> pages;

  GuideSection({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.pages,
  });

  factory GuideSection.fromJson(Map<String, dynamic> json) {
    final pagesJson = json['pages'] as List? ?? [];
    return GuideSection(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      icon: (json['icon'] ?? '').toString(),
      pages: pagesJson
          .whereType<Map<String, dynamic>>()
          .map(GuidePage.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'icon': icon,
        'pages': pages.map((p) => p.toJson()).toList(),
      };
}

class GuidePage {
  final String id;
  final String title;
  final String summary;
  final List<GuideBlock> blocks;
  final List<GuidePageSection> sections;
  final List<ChecklistItem> checklist;
  final GuideCtaLink? cta;

  GuidePage({
    required this.id,
    required this.title,
    required this.summary,
    required this.blocks,
    this.sections = const [],
    required this.checklist,
    this.cta,
  });

  factory GuidePage.fromJson(Map<String, dynamic> json) {
    final blocksJson = json['blocks'] as List? ?? [];
    final checklistJson = json['checklist'] as List? ?? [];
    final sectionsJson = json['sections'] as List? ?? [];
    return GuidePage(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      summary: (json['summary'] ?? '').toString(),
      blocks: blocksJson
          .whereType<Map<String, dynamic>>()
          .map(GuideBlock.fromJson)
          .toList(),
      sections: sectionsJson
          .whereType<Map<String, dynamic>>()
          .map(GuidePageSection.fromJson)
          .toList(),
      checklist: checklistJson
          .whereType<Map<String, dynamic>>()
          .map(ChecklistItem.fromJson)
          .toList(),
      cta: json['cta'] is Map<String, dynamic>
          ? GuideCtaLink.fromJson(json['cta'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'summary': summary,
        'blocks': blocks.map((b) => b.toJson()).toList(),
        if (sections.isNotEmpty) 'sections': sections.map((s) => s.toJson()).toList(),
        'checklist': checklist.map((c) => c.toJson()).toList(),
        if (cta != null) 'cta': cta!.toJson(),
      };
}

class GuideBlock {
  final String type; // text | bullets | steps | warning | tip
  final String? title;
  final String? content;
  final List<String> items;
  final String? buttonLabel;
  final String? buttonUrl;

  GuideBlock({
    required this.type,
    this.title,
    this.content,
    this.items = const [],
    this.buttonLabel,
    this.buttonUrl,
  });

  factory GuideBlock.fromJson(Map<String, dynamic> json) {
    final rawContent = json['content'];
    final items = <String>[];
    String? contentStr;
    String? buttonLabel;
    String? buttonUrl;

    if (rawContent is List) {
      items.addAll(rawContent.whereType<String>());
    } else if (rawContent is String) {
      contentStr = rawContent;
    } else if (json['text'] is String) {
      contentStr = json['text'] as String;
    }

    if (json['button'] is Map<String, dynamic>) {
      final btn = json['button'] as Map<String, dynamic>;
      buttonLabel = btn['label']?.toString();
      buttonUrl = btn['url']?.toString();
    }

    return GuideBlock(
      type: (json['type'] ?? 'text').toString(),
      title: json['title']?.toString(),
      content: contentStr,
      items: items,
      buttonLabel: buttonLabel,
      buttonUrl: buttonUrl,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        if (title != null) 'title': title,
        if (content != null) 'content': content,
        if (items.isNotEmpty) 'content': items,
        if (buttonLabel != null || buttonUrl != null)
          'button': {
            if (buttonLabel != null) 'label': buttonLabel,
            if (buttonUrl != null) 'url': buttonUrl,
          },
      };
}

class ChecklistItem {
  final String id;
  final String text;
  final bool done;

  ChecklistItem({
    required this.id,
    required this.text,
    required this.done,
  });

  factory ChecklistItem.fromJson(Map<String, dynamic> json) => ChecklistItem(
        id: (json['id'] ?? '').toString(),
        text: (json['text'] ?? '').toString(),
        done: json['done'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'done': done,
      };
}

class GuideCtaLink {
  final String? mapCategory;
  final String? forumTag;
  final List<String> externalLinks;

  GuideCtaLink({
    this.mapCategory,
    this.forumTag,
    this.externalLinks = const [],
  });

  factory GuideCtaLink.fromJson(Map<String, dynamic> json) {
    final links = (json['externalLinks'] as List? ?? [])
        .whereType<String>()
        .toList();
    return GuideCtaLink(
      mapCategory: json['mapCategory']?.toString(),
      forumTag: json['forumTag']?.toString(),
      externalLinks: links,
    );
  }

  Map<String, dynamic> toJson() => {
        if (mapCategory != null) 'mapCategory': mapCategory,
        if (forumTag != null) 'forumTag': forumTag,
        if (externalLinks.isNotEmpty) 'externalLinks': externalLinks,
      };
}

class GuidePageSection {
  final String id;
  final String title;
  final String? subtitle;
  final String? icon;
  final List<GuideBlock> blocks;

  GuidePageSection({
    required this.id,
    required this.title,
    this.subtitle,
    this.icon,
    this.blocks = const [],
  });

  factory GuidePageSection.fromJson(Map<String, dynamic> json) {
    final blocksJson = json['blocks'] as List? ?? [];
    return GuidePageSection(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      subtitle: json['subtitle']?.toString(),
      icon: json['icon']?.toString(),
      blocks: blocksJson
          .whereType<Map<String, dynamic>>()
          .map(GuideBlock.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (subtitle != null) 'subtitle': subtitle,
        if (icon != null) 'icon': icon,
        'blocks': blocks.map((b) => b.toJson()).toList(),
      };
}
