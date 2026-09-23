import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/construction_source_models.dart';
import '../services/construction_state_builder_store.dart';

class ConstructionSourcesAdminPage extends StatefulWidget {
  const ConstructionSourcesAdminPage({super.key});
  @override
  State<ConstructionSourcesAdminPage> createState() =>
      _ConstructionSourcesAdminPageState();
}

class _ConstructionSourcesAdminPageState
    extends State<ConstructionSourcesAdminPage> {
  late Future<_SourcePageData> _data;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _data = _load();
  Future<_SourcePageData> _load() async => _SourcePageData(
    await ConstructionStateBuilderStore.instance.allSources(),
    await ConstructionStateBuilderStore.instance.reports(),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Construction sources & quality'),
      actions: [
        IconButton(
          onPressed: () => setState(_reload),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<_SourcePageData>(
      future: _data,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Source instruction book',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Green sources can be imported automatically. Yellow sources need schema review. Red sources failed but their earlier local records were kept.',
            ),
            const SizedBox(height: 12),
            for (final source in data.sources) _sourceCard(source),
            const SizedBox(height: 24),
            const Text(
              'Build quality reports',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (data.reports.isEmpty)
              const Text('No state-builder run has finished yet.'),
            for (final report in data.reports) _reportCard(report),
          ],
        );
      },
    ),
  );

  Widget _sourceCard(ConstructionSourceInstruction s) {
    final color = switch (s.status) {
      ConstructionSourceState.ready => Colors.green,
      ConstructionSourceState.needsReview => Colors.orange,
      ConstructionSourceState.broken => Colors.red,
      ConstructionSourceState.disabled => Colors.grey,
    };
    return Card(
      child: ListTile(
        leading: Icon(Icons.circle, size: 14, color: color),
        title: Text('${s.state} · ${s.title}'),
        subtitle: Text(
          '${s.publisher}\n${s.format.name} · ${s.status.name}${s.lastError.isEmpty ? '' : '\n${s.lastError}'}',
        ),
        isThreeLine: true,
      ),
    );
  }

  Widget _reportCard(Map<String, Object?> r) {
    Map<String, dynamic> decode(String key) {
      final value = jsonDecode(r[key]?.toString() ?? '{}');
      return value is Map ? Map<String, dynamic>.from(value) : {};
    }

    final after = decode('after_json');
    final safe = r['publication_safe'] == 1;
    return Card(
      child: ListTile(
        leading: Icon(
          safe ? Icons.verified_outlined : Icons.warning_amber_rounded,
          color: safe ? Colors.green : Colors.red,
        ),
        title: Text('${r['state']} · ${r['status']}'),
        subtitle: Text(
          'Employers ${after['employers'] ?? 0} · worksites ${after['worksites'] ?? 0} · linked ${after['linked_worksites'] ?? 0}\nReady sources ${r['sources_ready']} · review ${r['sources_review']}',
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _SourcePageData {
  const _SourcePageData(this.sources, this.reports);
  final List<ConstructionSourceInstruction> sources;
  final List<Map<String, Object?>> reports;
}
