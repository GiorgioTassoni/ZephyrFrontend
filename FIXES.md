# Zephyr — Fix Registry

**Purpose.** Every non-trivial bug fix gets an entry here. When a bug "comes back", look it up
**before** re-fixing: each entry records the exact symptom, root cause, the fix, and a
*"If it comes back, check"* checklist so the diagnosis starts from history instead of zero.

**Rules for new entries**

1. One entry per distinct bug (not per attempt). ID = next free `F-0XX`.
2. Fill every section — especially *Root cause* (the mechanism, not the symptom) and
   *If it comes back, check* (concrete things to look at: log tags, endpoints, files).
3. If a fix added a unit test, name the test file — it is the regression guard.
4. When a fixed bug reappears, add a row to the **Regression log** at the bottom; do not
   silently rewrite the original entry.
5. Never delete an entry. If the fix was replaced by a better one, note it inside the entry.

**Entry template**

```markdown
## F-0XX <short bug name>
- **Fixed in:** <version> (<date>)
- **Symptom:** what the user sees, including how to reproduce.
- **Root cause:** the actual mechanism.
- **Fix:** files + mechanism.
- **Regression guard:** tests / disabled UI / log tags that prove the fix is active.
- **If it comes back, check:** ordered diagnostic steps.
```

---

## Index

| ID    | Bug                                                         | Area              | Fixed in  |
|-------|-------------------------------------------------------------|-------------------|-----------|
| F-001 | Radio seed fires twice (duplicate radio generations)        | player / radio    | 1.1.2+12  |
| F-002 | Queue screen empty on mobile (self-heals on restart)        | queue / SSE       | 1.1.2+12  |
| F-003 | Double `POST /api/player/next` at track end                 | player (mobile)   | 1.1.2+12  |
| F-004 | Queue sticks to the previous playlist after a switch        | queue policy      | 1.1.2+12  |
| F-005 | First 1–2 seconds of audio missing at stream start          | streaming         | 1.1.2+12  |
| F-006 | Car display (Android Auto) shows no real track duration     | media session     | 1.1.2+12  |
| F-007 | Shuffle pressed in radio mode breaks `/next`                | player / radio    | 1.1.2+12  |
| F-008 | App takes 6–7 s to load songs/playlists on open             | startup / library | 1.1.2+12  |
| F-011 | "Type String is not a subtype of int" — cannot remove a track from a playlist | playlists | 1.1.2+12 |

---

## F-001 Radio seed fires twice

- **Fixed in:** 1.1.2+12 (2026-08-28)
- **Symptom:** backend log shows two radio-seed calls creating two generations ~150 ms apart
  (observed: generations 95/96). The queue can visibly jump or be replaced twice at play time.
- **Root cause:** there are **four independent seed call paths** in `player_provider.dart` —
  scheduled seed (`_scheduleRadioSeed`), background seed (`_seedRadioInBackground`), the inline
  seed fallback inside play, and the remote-command path (`seedOnWire`). None shared idempotency,
  so two paths firing close together both created a generation. The ~150 ms spacing was the
  debounce interval, i.e. two paths raced inside it.
- **Fix:** single dedupe chokepoint in `player_provider.dart`:
  `_radioSeedDedupWindow = 1500ms` with `_isDuplicateRadioSeed` / `_noteRadioSeed`, applied on
  **all four** paths. An inline seed that dedupes **downgrades to a heartbeat** instead of
  re-seeding (tag `radio_seed_deduped_inline`).
- **Regression guard:** log tags `radio_seed_deduped_inline` and the dedupe tags on the other
  paths; no unit test (logic lives in the provider, not a pure function).
- **If it comes back, check:**
  1. `grep -n "seedRadio" packages/zephyr_core/lib/providers/player_provider.dart` — a **fifth**
     seed path that bypasses `_noteRadioSeed` is the prime suspect.
  2. Server-side spacing: if generations are now **>1500 ms** apart, the window is too short for
     the new trigger pattern — widen `_radioSeedDedupWindow` rather than re-adding per-path hacks.

---

## F-002 Queue screen empty on mobile

- **Fixed in:** 1.1.2+12 (2026-08-28)
- **Symptom:** audio plays but the queue screen renders empty; **self-heals after app restart**.
  Mobile-only heisenbug.
- **Root cause:** two stacked issues: (a) an SSE drop left stale bookkeeping, and (b) the
  staleness guard was **direction-blind** — any differing `context_request_id` was treated as
  "older" and latched, so good windows were rejected forever. Some server payload shapes
  (e.g. devices as a bare array) also failed tolerant parsing.
- **Fix:**
  - `zephyr_api.dart`: tolerant devices parsing (bare array or `{devices:[...]}`);
    `_errorCodeMatches` / `_errorField` / `_handleDioError` flatten root+`detail` codes.
  - `queue_policy.dart`: `isStaleContextResolutionGuarded(...)` — a differing request id is stale
    **only when the snapshot is strictly older** (timestamp-ordered via `_contextTrackedUpdatedAt`
    bookkeeping in `player_provider.dart`; explicit null `context_request_id` clears it).
  - Watchdog: `needsQueueWindowResync` + `resyncServerState({reason})` (10 s throttle);
    `queue_screen.dart` triggers a post-frame resync when it is about to render wrongly empty.
- **Regression guard:** 6 tests in `packages/zephyr_core/test/queue_logic_test.dart`
  (`isStaleContextResolutionGuarded`).
- **If it comes back, check:**
  1. In-app log viewer: is SSE connected? Any `resyncServerState` entries firing repeatedly?
  2. If the guard rejects everything again, print both `context_request_id`s **and** both
     `updated_at` values — a `null` snapshot timestamp (backend gap, see Open Items) forces the
     conservative legacy branch.
  3. Confirm the server payload still matches the tolerant parse (bare array vs wrapped).

---

## F-003 Double `POST /api/player/next` at track end

- **Fixed in:** 1.1.2+12 (2026-08-28)
- **Symptom:** two `/next` calls milliseconds apart when a track ends (double-skip; backend log).
  **Mobile only** — desktop was always fine.
- **Root cause:** platform split: desktop uses **audioplayers** (`onPlayerComplete`, fires once;
  `initAudioService()` returns null on desktop) while mobile uses **just_audio + audio_service**,
  whose `processingStateStream` **re-emits**. The first (ID-keyed) guard was defeated because the
  first advance's snapshot swapped `state.currentTrack` before the second engine fire, so the
  ID no longer matched anything.
- **Fix:** `_handlePlaybackComplete()` now uses a **time-window dedupe** (1500 ms,
  ID-independent) and logs `duplicate_completion_ignored` with `previousTrackId`.
- **Regression guard:** log tag `duplicate_completion_ignored` (its *presence* during a normal
  double-fire is the fix working).
- **If it comes back, check:**
  1. Double POST present but **no** `duplicate_completion_ignored` in logs → the second fire
     arrives through a path that doesn't go through `_handlePlaybackComplete` (e.g. an
     audio_service callback) — route it through or guard it too.
  2. Spacing >1500 ms → widen the window.

---

## F-004 Queue sticks to the previous playlist after a switch

- **Fixed in:** 1.1.2+12 (2026-08-28)
- **Symptom:** tap a song in playlist B while playlist A was playing → `/next` keeps playing
  A's queue ("the same queue coming from the last playlist even if i'm listening to a new song").
- **Root cause:** (a) the stale-context guard was direction-blind (any differing
  `context_request_id` = stale → server window for B rejected → A's local queue survives), and
  (b) a latched `isShuffled == true` rejected **radio** windows by design, amplifying stickiness.
- **Fix:** timestamp-ordered staleness (`isStaleContextResolutionGuarded`: differing id is stale
  **only** when the snapshot is strictly older; unknown timestamps keep the conservative legacy
  behavior) + radio snapshots reset `isShuffled: false`. 6 unit tests.
- **Regression guard:** `queue_logic_test.dart` (guarded staleness + `shouldApplyServerQueue`).
- **If it comes back, check:**
  1. Does the server window carry `updated_at`? Backend `user-queue` currently echoes
     `updated_at: null` (Open Items) — with nulls the guard must fall back to the legacy
     branch, which can re-open this bug under SSE drops.
  2. Was the tap routed as a *context* play (server-resolved) or a bare track play?
     Only context plays can switch queues server-side.
- **Contract reference:** `APIs.md` — Exchange 60 (server-resolved contexts: `context_ref`,
  `context_request_id`, 50-track display window, linear/shuffled dual orders).

---

## F-005 First 1–2 seconds of audio missing at stream start

- **Fixed in:** 1.1.2+12 (2026-08-28)
- **Symptom:** a track starts already "into" the song (first seconds skipped). Evidence was a
  track streamed twice (`dz_3559886631`, :07.779 and :11.316, different ports) and a device
  fetching metadata ~7 s after tap.
- **Root cause:** the `track_status` download-upgrade handler **restarted the stream** at
  `state.position` once the upgrade landed — but the ticker position includes silent buffering
  time, so the restart sought past the real audible start.
- **Fix:** restart **only when the stream is actually unhealthy**:
  `streamHealthy = engineActive && enginePos > Duration.zero`, with
  `enginePos = zephyrAudioHandler?.player.position ?? (await _audioPlayer.getCurrentPosition()) ?? Duration.zero`
  (also in the `.catchError` fallback). Healthy streams are left alone.
- **Regression guard:** none (provider logic); watch for restart log lines from the
  `track_status` handler.
- **If it comes back, check:**
  1. Device log: is the track's stream URL requested **twice** (two ports)? → something restarted
     playback; correlate with `track_status`/download events.
  2. A refactor that reintroduces "seek to `state.position` on upgrade" is the classic culprit —
     always gate on `streamHealthy`.

---

## F-006 Car display (Android Auto) shows no real track duration

- **Fixed in:** 1.1.2+12 (2026-08-29)
- **Symptom:** in the car, the track shows unknown/no duration; progress bar dead. (Note: user
  calls it "CarPlay"; it is actually **Android Auto** — `flutter_carplay` is only a stale build
  artifact.)
- **Root cause:** `setTrackMediaItem` pushes `MediaItem(duration: track.duration)` **only at
  track change**. Tracks that start with a null duration (fresh radio / search picks) never got
  a duration update afterwards.
- **Fix:** new `updateMediaItemDuration(Duration)` in `utils/audio_handler.dart` — patches the
  active `MediaItem` in place (**id-guarded + change-guarded**, so a stale patch never lands on
  the next track); `updateDur()` in `player_provider.dart` calls it inside
  `if (dur > Duration.zero)` after the owner guard. Engine-reported duration is the single
  source of truth (deliberately *not* also hydrated from server metadata — avoids conflicts).
- **Regression guard:** none; verify on a head unit / Android Auto emulator.
- **If it comes back, check:**
  1. Does `updateDur` still fire (engine `durationStream` wired)?
  2. Did the patch get rejected by the id/change guard (track switched mid-patch)? That path is
     correct behavior — check whether a *new* media item push overwrote duration back to null.

---

## F-007 Shuffle pressed in radio mode breaks `/next`

- **Fixed in:** 1.1.2+12 (2026-08-29)
- **Symptom:** user hits shuffle during a radio session → subsequent `/next` calls get bugged /
  queue stops flowing.
- **Root cause:** by design `shouldApplyServerQueue` rejects radio snapshots when
  `isShuffled == true` (local shuffle order cannot be mapped onto server dual orders). Local
  shuffle **latched** `isShuffled`, so every later radio window was rejected → queue starved.
  In radio mode the queue is already random; local shuffle is forbidden.
- **Fix:** `toggleShuffle()` early-returns in `queueMode == 'radio'` with a
  "Radio is already shuffled" toast (log `shuffle_disabled_radio_mode`); all shuffle buttons are
  disabled (grey + tooltip) while in radio: `player_screen.dart` (both sizes) and
  `main_layout.dart` mini player. Desktop `S` shortcut is covered by the provider guard.
- **Regression guard:** the disabled buttons + provider guard; no unit test.
- **If it comes back, check:**
  1. `grep -rn "toggleShuffle" packages/zephyr_core apps` — any **new** shuffle entry point
     (queue screen, media session callback, keyboard shortcut in another shell) not covered by
     the guard or the disabled buttons.
  2. Verify radio snapshots still reset `isShuffled: false` (F-004).

---

## F-008 App takes 6–7 s to load songs/playlists on open

- **Fixed in:** 1.1.2+12 (2026-08-29)
- **Symptom:** on open (mobile **and** desktop), all songs/playlists take ~6–7 s to appear.
- **Root cause:** five **sequential** round trips: an auth "validation" call (a redundant
  `getFavorites()`) + `loadLibrary()` awaiting `/api/tracks`, `/api/playlists`, favorites,
  `/api/history` one after another. Nothing was cached locally, so every launch paid the full
  chain.
- **Fix:** three parts, all in `zephyr_core`:
  1. `loadLibrary()` runs the four fetches concurrently (`Future.wait` + `_guard` per request;
     per-request failure tolerance preserved).
  2. **Stale-while-revalidate cache** — `LibraryCache` (versioned payload in SharedPreferences,
     ≤5 MB valve, history capped at 60). Startup hydrates state from cache first (UI renders
     instantly), then refreshes from the network in the background. Added lossless
     `Playlist.toJson` / `HistoryEntry.toJson`.
  3. **Optimistic auth** — `tryAutoLogin()` no longer spends a round trip on validation; the
     stored token is trusted and validated by the first real request (401 → single-flight
     refresh → `forceLogout` path unchanged).
- **Regression guard:** 9 tests in `packages/zephyr_core/test/library_cache_test.dart`
  (round trips, garbage/foreign-version rejection, history cap).
- **If it comes back, check:**
  1. Slow **again on every launch** → the cache is being rejected: log
     `library_cache_skipped_too_large` / "Library cache hydration failed" / payload version bump.
  2. First launch after install/clear is *supposed* to be one cold load (~2 RTTs).
  3. **New bug class to watch** (introduced by this fix): stale or duplicated content after the
     background refresh lands — that would be a hydration-then-replace ordering issue in
     `loadLibrary`; check whether the refresh respects cached state as the base
     (`favorites = state.favorites` fallbacks) instead of clobbering.

---

## F-011 "Type String is not a subtype of int" — cannot remove a track from a playlist

- **Fixed in:** 1.1.2+12 (2026-08-29)
- **Symptom:** tapping remove on a track in the playlist detail screen fails on **both** desktop
  and Android with the toast `Failed to remove: Type String is not a subtype of int`.
- **Root cause:** `playlist_detail_screen._removeTrack` called the **API layer directly** with
  `_playlist!.id` — and `Playlist.id` is **always a String** (`fromJson` stringifies ids, and
  Deezer ids are `'dz_<n>'`). The API method `removeTrackFromPlaylist(int playlistId, ...)`
  declared a hard `int` parameter → implicit dynamic→int downcast threw the TypeError. The
  `library_provider` wrappers (`addTrackToPlaylist` etc.) all normalize ids with
  `is int / int.tryParse` — which is exactly why *adding* a track worked while *removing* did
  not: the screen bypassed the wrapper for removal only.
- **Fix:**
  1. `zephyr_api.dart`: `addTrackToPlaylist` / `removeTrackFromPlaylist` /
     `reorderPlaylistTracks` / `savePlaylist` / `unsavePlaylist` now take `dynamic playlistId`
     and interpolate it into the URL (model ids are strings by design) — the whole bug class is
     dead, not just this call site.
  2. `_removeTrack` routes through `libraryProvider.notifier.removeTrackFromPlaylist(...)` so
     the shared library state refreshes after the mutation (the direct call left it stale).
  3. Defensive: `_fetchPlaylistDetails` ignores degenerate detail responses (e.g. a body with
     only `updated_at`, observed once in device logs as `GET /api/playlists/21 → {updated_at}`)
     instead of blanking an already-loaded screen — see Open Items.
- **Regression guard:** none automated (UI flow); the API-layer signature change is compile-time.
- **If it comes back, check:**
  1. `grep -n "_api\.\(add\|remove\|reorder\|save\|unsave\)" packages/zephyr_core/lib/screens` —
     a screen calling the API layer directly with a model id instead of going through the
     provider wrappers.
  2. Any NEW API method declaring `int playlistId` again.

---

## Platform behavior notes (why some bugs are platform-specific)

- **Mobile** = just_audio + audio_service (Android Auto MediaSession).
  `processingStateStream` **re-emits** → completion/state-driven bugs (F-003) are mobile-only.
- **Desktop** = audioplayers fallback because `initAudioService()` returns null on
  Linux/Windows/macOS; system controls via MPRIS (`MediaControls`).
  `onPlayerComplete` fires **once** → same bugs don't reproduce on desktop.
- Streams go through a local loopback HTTP proxy that injects Authorization.
- In radio mode the server owns randomness: local shuffle must stay off (F-004/F-007).
- Build environment: Flutter SDK + HOME are read-only in the dev sandbox; builds/tests need the
  full-path `dart flutter_tools.snapshot` invocation with elevated file access
  (engine stamps + telemetry writes outside the workspace).

---

## Known open items (flagged, not fixed)

| Item | Detail |
|------|--------|
| `PUT /state` fires late | tap's server-sync awaits full audio prep inside `executePlay`; state lands on the server seconds after playback starts |
| `user-queue` echoes `updated_at: null` | backend contract gap vs "Full player state" (APIs.md); degrades F-002/F-004 timestamp-ordered guard to its conservative legacy branch |
| `GET /api/playlists/{id}` once returned only `{updated_at}` | observed in device logs (2026-08-29 12:55) with a stale timestamp — either a conditional/poll response or a backend contract break; client now guards against blanking (F-011), but the backend contract should be verified |
| AGP 8.6 / Kotlin 2.0.20 deprecation warnings | Flutter will drop support; upgrade AGP ≥ 8.11.1 / Kotlin ≥ 2.2.20 eventually |
| No mobile CI | `release-windows.yml` covers Windows only; mobile builds are manual |

---

## Under investigation (reported, not yet fixed)

| Reported  | Bug (MOBILE)                                                          | Maps to                | Status |
|-----------|------------------------------------------------------------------------|------------------------|--------|
| 2026-08-29 | Missing first 1–2 s of audio at stream start ("start late")          | F-005 (regression)     | partial: log exposed a double `play_url` (85 ms apart) + `Connection aborted` — snapshot replay restarted the tap's play mid-prepare; guarded (skip when `_pendingOwnerTrackId` matches + `isLoading`). Need one dedicated repro to confirm no second mechanism (owner-seek) remains |
| 2026-08-29 | Radio → favorites/playlist keeps the radio queue after switching     | F-004 (regression)     | ROOT CAUSE FOUND in log: owner context plays with `contextRef` never synced the server (FIX A gate `contextRef == null` skipped the upload; success-gated sync skipped by generation checks) → server stayed radio, `/next` advanced radio, `forceTrackTransition` stole playback. Also: local `queueMode` never became 'context' (shuffle button stayed disabled). FIXED: early `context_ref` upload + immediate local queueMode switch. Awaiting device verification |
| 2026-08-29 | Actions wait for the server before showing any visual feedback (like, shuffle play, …) | new (F-009 candidate) | design locked (optimistic UI; shuffle play = instant audio, server queue replaces silently); implementation queued |
| 2026-08-29 | Shuffle state not restored after leaving radio mode                  | new (F-010 candidate)  | discovered the restore machinery ALREADY exists (`_shufflePref` persisted, stamped into `contextRef.order`, restored at playTrack) but was dead code — the broken context path never ran. Revived by the F-004 fix; verify on device |

---

## Regression log (fixed bugs that came back)

| Date | Entry | Symptom seen again | Suspected re-trigger | Resolution |
|------|-------|--------------------|----------------------|------------|
| 2026-08-29 | F-005 | First 1–2 s of audio missing again (mobile) | Double `play_url` (SSE "server says play" replay vs in-flight tap prepare) → `Connection aborted` teardown/re-prepare. Guard added at the replay site; dedicated repro still needed to rule out a second mechanism | fix implemented, awaiting device verification |
| 2026-08-29 | F-004 | Radio → playlist switch keeps radio queue (mobile) | NOT the staleness guard this time: the owner's context upload was gated `contextRef == null`, so server never switched context (log: zero PUTs for the favorites play; `/next` advanced radio gen 127). Early context upload + local queueMode switch implemented | fix implemented, awaiting device verification |
