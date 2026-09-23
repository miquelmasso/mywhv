import 'package:flutter/material.dart';

import '../services/construction_issue_report_store.dart';

const _constructionIssueTypes = <String>[
  'Email bounced',
  'Wrong email or contact',
  'Website does not work',
  'Wrong location',
  'Company closed or not operating',
  'Other',
];

Future<void> showConstructionIssueReportSheet(
  BuildContext context,
  Map<String, dynamic> company,
) async {
  var issueType = _constructionIssueTypes.first;
  final noteController = TextEditingController();
  final submitted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setModalState) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          18 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Report a problem',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              (company['name'] ?? 'Construction company').toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: issueType,
              decoration: const InputDecoration(
                labelText: 'What is wrong?',
                border: OutlineInputBorder(),
              ),
              items: _constructionIssueTypes
                  .map(
                    (type) => DropdownMenuItem(value: type, child: Text(type)),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) setModalState(() => issueType = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Extra details (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  await ConstructionIssueReportStore.instance.add(
                    company: company,
                    issueType: issueType,
                    note: noteController.text,
                  );
                  if (sheetContext.mounted) Navigator.pop(sheetContext, true);
                },
                child: const Text('Save report'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  noteController.dispose();
  if (submitted == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Problem report saved locally. Thank you.')),
    );
  }
}
