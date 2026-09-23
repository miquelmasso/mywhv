import 'package:flutter/material.dart';

import '../services/construction_pending_publish_service.dart';
import '../services/construction_issue_report_store.dart';
import 'add_construction_manual_page.dart';
import 'add_construction_by_postcode_page.dart';
import 'add_construction_by_state_page.dart';
import 'construction_issue_reports_page.dart';
import 'construction_sources_admin_page.dart';

class ConstructionManagementPage extends StatefulWidget {
  const ConstructionManagementPage({super.key});

  @override
  State<ConstructionManagementPage> createState() =>
      _ConstructionManagementPageState();
}

class _ConstructionManagementPageState
    extends State<ConstructionManagementPage> {
  bool _isGeneratingJson = false;
  bool _didChange = false;

  Future<void> _openPostcodeImport() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddConstructionByPostcodePage()),
    );
    if (changed == true) _didChange = true;
  }

  Future<void> _openStateImport() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddConstructionByStatePage()),
    );
    if (changed == true) _didChange = true;
  }

  Future<void> _openManualAdd() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddConstructionManualPage()),
    );
    if (changed == true) _didChange = true;
  }

  Future<void> _openIssueReports() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const ConstructionIssueReportsPage()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openSources() => Navigator.push<void>(
    context,
    MaterialPageRoute(builder: (_) => const ConstructionSourcesAdminPage()),
  );

  Future<void> _generateJson() async {
    if (_isGeneratingJson) return;
    final pending = await ConstructionPendingPublishService.instance
        .getPublishablePendingIds();
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Final construction publication?'),
        content: Text(
          'This will upload ${pending.length} ready records to Firebase and generate construction_companies.json. Use it once all states are complete.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Publish all'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isGeneratingJson = true);
    try {
      final result = await ConstructionPendingPublishService.instance
          .publishPendingAndExportJson();
      if (!mounted) return;
      _didChange = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.uploaded} empreses publicades. JSON generat amb ${result.jsonCount} empreses.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No s’ha pogut generar construction_companies.json.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isGeneratingJson = false);
    }
  }

  void _close() => Navigator.pop(context, _didChange);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Construction management',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _close,
          ),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0.5,
        ),
        backgroundColor: Colors.white,
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Com vols afegir construcció?',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _openPostcodeImport,
                icon: const Icon(Icons.location_on),
                label: const Text('Add by postcode'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: _openManualAdd,
                icon: const Icon(Icons.add_business_outlined),
                label: const Text('Add manually'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  backgroundColor: Colors.teal.shade700,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: _openStateImport,
                icon: const Icon(Icons.map),
                label: const Text('Add by state'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  backgroundColor: Colors.blueGrey.shade700,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: _isGeneratingJson ? null : _generateJson,
                icon: _isGeneratingJson
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : const Icon(Icons.download_for_offline_outlined),
                label: Text(
                  _isGeneratingJson
                      ? 'Publishing and generating JSON...'
                      : 'Publish all + generate construction_companies.json',
                ),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  backgroundColor: Colors.orange.shade700,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              FutureBuilder<int>(
                future: ConstructionIssueReportStore.instance.count(),
                builder: (context, snapshot) => TextButton.icon(
                  onPressed: _openIssueReports,
                  icon: const Icon(Icons.flag_outlined, size: 18),
                  label: Text(
                    'Reported problems${snapshot.hasData ? ' (${snapshot.data})' : ''}',
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _openSources,
                icon: const Icon(Icons.rule_folder_outlined, size: 18),
                label: const Text('Sources & quality reports'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Publicació final única quan tots els estats estiguin completats.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
