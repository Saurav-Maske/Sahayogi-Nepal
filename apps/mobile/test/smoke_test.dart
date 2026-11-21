import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('placeholder — Person 1/4 add widget tests', () => expect(1 + 1, 2));

  test('splash logo is bundled', () async {
    final data = await rootBundle.load('assets/images/SahayogiNepalLogo.png');
    expect(data.lengthInBytes, greaterThan(0));
  });
}
