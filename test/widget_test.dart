import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';
import 'package:frontend/providers/player_provider.dart';

void main() {
  test('backend queue mode does not activate repeat mode', () {
    final state = ZephyrPlayerState();

    expect(state.repeatMode, 'off');
    expect(ZephyrPlayerState(repeatMode: null).repeatMode, 'off');
    expect(ZephyrPlayerState(repeatMode: null).copyWith().repeatMode, 'off');
    expect(state.copyWith(queueMode: 'radio').repeatMode, 'off');
    expect(state.copyWith(queueMode: 'context').repeatMode, 'off');
  });

  testWidgets('ZephyrApp loads splash screen initially', (
    WidgetTester tester,
  ) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: ZephyrApp()));

    // Verify that the splash screen text 'ZEPHYR' is displayed
    expect(find.text('ZEPHYR'), findsOneWidget);
  });
}
