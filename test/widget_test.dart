import 'package:flutter_test/flutter_test.dart';

import 'package:mywhv/main.dart';

void main() {
  test('MyApp can be created with an initial index', () {
    const app = MyApp(initialHomeIndex: 1);

    expect(app.initialHomeIndex, 1);
  });
}
