import 'package:flutter_test/flutter_test.dart';
import 'package:reader/main.dart';

void main() {
  testWidgets('app builds home page', (tester) async {
    await tester.pumpWidget(const ReaderApp());
    expect(find.text('Reader'), findsOneWidget);
  });
}
