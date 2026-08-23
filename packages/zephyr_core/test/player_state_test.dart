import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr_core/providers/player_provider.dart';

void main() {
  group('ZephyrPlayerState context fields', () {
    test('new context fields default to null', () {
      const state = ZephyrPlayerState();
      expect(state.contextRef, isNull);
      expect(state.contextTotal, isNull);
      expect(state.contextCursor, isNull);
      expect(state.queueCount, isNull);
      expect(state.contextRequestId, isNull);
      expect(state.contextStatus, isNull);
    });

    test('copyWith sets the new fields', () {
      const state = ZephyrPlayerState();
      final updated = state.copyWith(
        contextRef: {'type': 'playlist', 'id': 'pl-1'},
        contextTotal: 94,
        contextCursor: 0,
        queueCount: 94,
        contextRequestId: 'ctx-1',
        contextStatus: 'ready',
      );
      expect(updated.contextRef?['id'], 'pl-1');
      expect(updated.contextTotal, 94);
      expect(updated.contextCursor, 0);
      expect(updated.queueCount, 94);
      expect(updated.contextRequestId, 'ctx-1');
      expect(updated.contextStatus, 'ready');
    });

    test('copyWith(null) preserves existing values (stale-snapshot path)', () {
      final state = ZephyrPlayerState().copyWith(
        contextRef: {'type': 'playlist', 'id': 'pl-B'},
        contextRequestId: 'ctx-B',
        contextTotal: 94,
        queueCount: 94,
        contextStatus: 'ready',
      );
      // A stale snapshot passes null for every context field; copyWith must
      // keep the newer B values untouched (the F1 guard relies on this).
      final preserved = state.copyWith(
        contextRef: null,
        contextTotal: null,
        contextCursor: null,
        queueCount: null,
        contextOrderActive: null,
        contextStatus: null,
        contextRequestId: null,
      );
      expect(preserved.contextRef?['id'], 'pl-B');
      expect(preserved.contextRequestId, 'ctx-B');
      expect(preserved.contextTotal, 94);
      expect(preserved.queueCount, 94);
      expect(preserved.contextStatus, 'ready');
    });

    test('clearContextMetadata wipes the count/order/status fields (incl. new ones)', () {
      final state = ZephyrPlayerState().copyWith(
        contextRef: {'type': 'playlist', 'id': 'pl-1'},
        contextTotal: 94,
        contextCursor: 2,
        queueCount: 94,
        contextOrderActive: 'linear',
        contextStatus: 'ready',
        contextRequestId: 'ctx-1',
      );
      // clearContextMetadata clears the metadata group but NOT contextRef
      // itself (that is clearContextRef's job).
      final cleared = state.copyWith(clearContextMetadata: true);
      expect(cleared.contextRef?['id'], 'pl-1');
      expect(cleared.contextTotal, isNull);
      expect(cleared.contextCursor, isNull);
      expect(cleared.queueCount, isNull);
      expect(cleared.contextOrderActive, isNull);
      expect(cleared.contextStatus, isNull);
      expect(cleared.contextRequestId, isNull);
    });

    test('clearContextRef wipes only the reference', () {
      final state = ZephyrPlayerState().copyWith(
        contextRef: {'type': 'playlist', 'id': 'pl-1'},
        contextTotal: 94,
        contextRequestId: 'ctx-1',
      );
      final withMeta = state.copyWith(clearContextRef: true);
      expect(withMeta.contextRef, isNull);
      expect(withMeta.contextTotal, 94);
      expect(withMeta.contextRequestId, 'ctx-1');
    });
  });
}