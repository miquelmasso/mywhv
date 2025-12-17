import 'package:flutter/material.dart';

class MainTabsController {
  static String? lastMapCategory;
  static String? lastForumTag;

  static void goToTab(
    BuildContext context,
    int index, {
    String? mapCategory,
    String? forumTag,
    void Function(int index)? onNavigateToTab,
  }) {
    lastMapCategory = mapCategory;
    lastForumTag = forumTag;

    if (onNavigateToTab != null) {
      onNavigateToTab(index);
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }
}
