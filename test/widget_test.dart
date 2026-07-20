import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';

void main() {
  testWidgets('ZephyrApp loads splash screen initially', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: ZephyrApp(),
      ),
    );

    // Verify that the splash screen text 'ZEPHYR' is displayed
    expect(find.text('ZEPHYR'), findsOneWidget);
  });
}
