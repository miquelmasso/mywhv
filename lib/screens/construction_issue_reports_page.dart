import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/construction_issue_report_store.dart';

class ConstructionIssueReportsPage extends StatefulWidget {
  const ConstructionIssueReportsPage({super.key});

  @override
  State<ConstructionIssueReportsPage> createState() =>
      _ConstructionIssueReportsPageState();
}

class _ConstructionIssueReportsPageState
    extends State<ConstructionIssueReportsPage> {
  late Future<List<Map<String, dynamic>>> _reports;

  @override
  void initState() {
    super.initState();
    _reports = ConstructionIssueReportStore.instance.getAll();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reported Construction problems')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _reports,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final reports = snapshot.data!;
          if (reports.isEmpty) {
            return const Center(child: Text('No problems reported.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: reports.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (context, index) {
              final report = reports[index];
              final companyId = report['company_id'].toString();
              final worksiteId = report['worksite_id'].toString();
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  report['company_name'].toString(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  [
                    report['issue_type'],
                    if (report['note'].toString().isNotEmpty) report['note'],
                    if (companyId.isNotEmpty) 'Company ID: $companyId',
                    if (worksiteId.isNotEmpty) 'Worksite ID: $worksiteId',
                    report['created_at'],
                  ].join('\n'),
                ),
                trailing: IconButton(
                  tooltip: 'Copy full report',
                  icon: const Icon(Icons.copy_outlined, size: 20),
                  onPressed: () async {
                    final snapshot = jsonDecode(
                      report['snapshot_json'].toString(),
                    );
                    await Clipboard.setData(
                      ClipboardData(
                        text: const JsonEncoder.withIndent(
                          '  ',
                        ).convert({...report, 'snapshot': snapshot}),
                      ),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Full report copied.')),
                      );
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
