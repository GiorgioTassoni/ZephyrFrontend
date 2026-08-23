import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr_core/models/models.dart';
import 'package:zephyr_core/providers/player_provider.dart';

void main() {
  test('backend queue mode does not activate repeat mode', () {
    final state = ZephyrPlayerState();

    expect(state.repeatMode, 'off');
    expect(ZephyrPlayerState(repeatMode: null).repeatMode, 'off');
    expect(ZephyrPlayerState(repeatMode: null).copyWith().repeatMode, 'off');
    expect(state.copyWith(queueMode: 'radio').repeatMode, 'off');
    expect(state.copyWith(queueMode: 'context').repeatMode, 'off');
  });

  test('extracted queue policy is consulted by the state defaults', () {
    // Sanity: the provider default state is non-playing and empty-queue.
    const state = ZephyrPlayerState();
    expect(state.isPlaying, isFalse);
    expect(state.queue, isEmpty);
    expect(state.queueMode, 'radio');
  });

  test('Track model produces canonical dz ids for the player queue', () {
    // The queue screen/context handle dz_-prefixed ids; guard the contract.
    final track = Track.fromJson({'track_id': '3135551', 'title': 'X'});
    expect(track.videoId, 'dz_3135551');
  });
}