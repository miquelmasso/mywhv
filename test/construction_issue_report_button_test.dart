import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mywhv/widgets/map_place_popup.dart';

void main() {
  Widget popup(Map<String, dynamic> data) => MaterialApp(
    home: Scaffold(
      body: Stack(
        children: [
          MapRestaurantPopup(
            data: data,
            workedCount: 0,
            isFavorite: false,
            onClose: () {},
            onWorkedHere: () {},
            onCopyPhone: () {},
            onEmail: () {},
            onFacebook: () {},
            onCareers: () {},
            onInstagram: () {},
            onFavorite: () {},
          ),
        ],
      ),
    ),
  );

  testWidgets('shows a quiet report action for Construction only', (
    tester,
  ) async {
    await tester.pumpWidget(
      popup({'name': 'Example Mining', 'place_type': 'construction'}),
    );
    await tester.pumpAndSettle();
    expect(find.text('Report a problem'), findsOneWidget);

    await tester.pumpWidget(
      popup({'name': 'Example Cafe', 'place_type': 'restaurant'}),
    );
    await tester.pumpAndSettle();
    expect(find.text('Report a problem'), findsNothing);
  });

  testWidgets('opens report form with traceable company name', (tester) async {
    await tester.pumpWidget(
      popup({
        'name': 'Example Mining',
        'place_type': 'construction',
        'company_id': 'company-1',
        'worksite_id': 'worksite-9',
      }),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report a problem'));
    await tester.pumpAndSettle();

    expect(find.text('What is wrong?'), findsOneWidget);
    expect(find.text('Example Mining'), findsWidgets);
    expect(find.text('Save report'), findsOneWidget);
  });
}
