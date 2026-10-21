import 'package:flutter_test/flutter_test.dart';
import 'package:reader/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('app builds home page', (tester) async {
    await tester.pumpWidget(const ReaderApp());
    await tester.pump();
    expect(find.text('Reader'), findsOneWidget);
  });
}
