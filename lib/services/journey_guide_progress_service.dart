import 'package:shared_preferences/shared_preferences.dart';

class JourneyGuideProgressService {
  JourneyGuideProgressService._();

  static final JourneyGuideProgressService instance =
      JourneyGuideProgressService._();

  static const String _completedStepsKey = 'journey_guide_completed_steps';
  static const String _finishedKey = 'journey_guide_finished';
  static const String _checklistPrefix = 'journey_guide_checklist_';

  Future<Set<String>> loadCompletedSteps() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_completedStepsKey) ?? const <String>[])
        .toSet();
  }

  Future<bool> isJourneyFinished() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_finishedKey) ?? false;
  }

  Future<Set<String>> markStepCompleted(
    String stepId, {
    required int totalSteps,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final completed =
        (prefs.getStringList(_completedStepsKey) ?? <String>[]).toSet()
          ..add(stepId);
    await prefs.setStringList(_completedStepsKey, completed.toList());
    if (completed.length >= totalSteps) {
      await prefs.setBool(_finishedKey, true);
    }
    return completed;
  }

  Future<Map<String, Set<String>>> loadChecklistItems(
    Iterable<String> stepIds,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    return {
      for (final stepId in stepIds)
        stepId:
            (prefs.getStringList('$_checklistPrefix$stepId') ??
                    const <String>[])
                .toSet(),
    };
  }

  Future<Set<String>> setChecklistItem({
    required String stepId,
    required String item,
    required bool checked,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_checklistPrefix$stepId';
    final items = (prefs.getStringList(key) ?? <String>[]).toSet();
    if (checked) {
      items.add(item);
    } else {
      items.remove(item);
    }
    await prefs.setStringList(key, items.toList());
    return items;
  }
}
