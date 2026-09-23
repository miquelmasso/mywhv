import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mywhv/screens/construction_edit_page.dart';

void main() {
  const company = <String, dynamic>{
    'id': 'company-exact-1',
    'docId': 'company-exact-1',
    'name': 'Exact Construction Company',
    'address': '1 Local Road, Perth WA 6000',
    'postcode': '6000',
    'postcode_display': '6000',
    'state': 'WA',
    'latitude': -31.95,
    'longitude': 115.86,
    'construction_category': 'general_construction',
    'contact_enrichment_status': 'needs_review',
  };

  testWidgets('opens the exact local review row without name search', (
    tester,
  ) async {
    await tester.pumpWidget(const _ReviewHarness(company: company));

    await tester.tap(find.text('Open review'));
    await tester.pumpAndSettle();

    expect(find.text('Edit construction'), findsOneWidget);
    expect(find.text('Exact Construction Company'), findsOneWidget);
    expect(find.text('Search construction companies'), findsNothing);
    expect(find.text('Delete company'), findsNothing);
  });

  testWidgets('cancelling review returns no changed result', (tester) async {
    await tester.pumpWidget(const _ReviewHarness(company: company));

    await tester.tap(find.text('Open review'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Result: unchanged'), findsOneWidget);
  });

  testWidgets('successful local save returns the changed review result', (
    tester,
  ) async {
    String? savedId;
    Map<String, dynamic>? savedUpdates;
    await tester.pumpWidget(
      _ReviewHarness(
        company: company,
        saver: (companyId, updates) async {
          savedId = companyId;
          savedUpdates = Map<String, dynamic>.from(updates);
        },
      ),
    );

    await tester.tap(find.text('Open review'));
    await tester.pumpAndSettle();
    final save = find.text('Save changes');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(savedId, 'company-exact-1');
    expect(savedUpdates?['contact_enrichment_status'], 'completed');
    expect(find.text('Result: needs_review → completed'), findsOneWidget);
  });
}

class _ReviewHarness extends StatefulWidget {
  const _ReviewHarness({required this.company, this.saver});

  final Map<String, dynamic> company;
  final ConstructionCompanySaver? saver;

  @override
  State<_ReviewHarness> createState() => _ReviewHarnessState();
}

class _ReviewHarnessState extends State<_ReviewHarness> {
  ConstructionEditResult? _result;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                onPressed: () async {
                  final result = await Navigator.of(context)
                      .push<ConstructionEditResult>(
                        MaterialPageRoute(
                          builder: (_) => ConstructionEditPage(
                            companyId: (widget.company['docId'] ?? '')
                                .toString(),
                            initialCompany: Map<String, dynamic>.from(
                              widget.company,
                            ),
                            saveCompany: widget.saver,
                          ),
                        ),
                      );
                  if (mounted) setState(() => _result = result);
                },
                child: const Text('Open review'),
              ),
              Text(
                _result == null
                    ? 'Result: unchanged'
                    : 'Result: ${_result!.previousStatus} → ${_result!.newStatus}',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
