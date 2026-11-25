import 'package:flutter_test/flutter_test.dart';
import 'package:zmix/playback_switcher.dart';

// Failure-injection tests for the open/error/retry/rollback state logic.
// Errors are injected exactly where media_kit's async error stream emits
// them (after open() has already returned), and confirmation evidence is
// fed the way mpv's playlist/position streams would deliver it, including
// stale events from a previous stream.
void main() {
  // Drives a full confirmed-playback sequence for the current generation.
  void confirmPlaying(ZmixPlaybackSwitcher s, int gen, String url) {
    s.onMediaLoaded(url, generation: gen);
    expect(
        s.onPlaybackProgress(
            generation: gen, position: Duration.zero, playing: true),
        isFalse,
        reason: 'baseline event only sets the baseline');
    expect(
        s.onPlaybackProgress(
            generation: gen,
            position: const Duration(seconds: 1),
            playing: true),
        isTrue,
        reason: 'advancing position on the loaded media confirms');
  }

  test('initial open fails, nothing ever played -> safe error panel', () {
    final s = ZmixPlaybackSwitcher();
    s.beginOpen('urlA');
    final d = s.onError('urlA');
    expect(d, isA<ShowError>());
    expect((d as ShowError).message, kSafePlaybackError);
    // The safe text must never carry a transport URL or IP.
    expect(d.message.contains('http'), isFalse);
  });

  test('failed quality switch rolls back to the ORIGINAL last-good stream',
      () {
    final s = ZmixPlaybackSwitcher();
    confirmPlaying(s, s.beginOpen('urlA', quality: '360p'), 'urlA');
    // User switches to 1080p; the async error arrives after open returned.
    s.beginOpen('urlB', quality: '1080p');
    final d = s.onError('urlB');
    expect(d, isA<RollbackToLastGood>());
    final r = d as RollbackToLastGood;
    expect(r.url, 'urlA');
    expect(r.quality, '360p');
  });

  test('rollback target failing shows the error panel, no rollback loop', () {
    final s = ZmixPlaybackSwitcher();
    confirmPlaying(s, s.beginOpen('urlA', quality: '360p'), 'urlA');
    s.beginOpen('urlB');
    expect(s.onError('urlB'), isA<RollbackToLastGood>());
    // The rollback open of urlA fails too (network down): panel, not a loop.
    s.beginOpen('urlA');
    final d = s.onError('urlA');
    expect(d, isA<ShowError>());
    // And a third error still does not resurrect a rollback.
    expect(s.onError('urlA'), isA<ShowError>());
  });

  test('a fresh failure after confirmed recovery may roll back again', () {
    final s = ZmixPlaybackSwitcher();
    confirmPlaying(s, s.beginOpen('urlA', quality: '360p'), 'urlA');
    s.beginOpen('urlB');
    expect(s.onError('urlB'), isA<RollbackToLastGood>());
    // Rollback re-opened urlA and got real playback evidence again.
    confirmPlaying(s, s.beginOpen('urlA', quality: '360p'), 'urlA');
    s.beginOpen('urlC');
    expect(s.onError('urlC'), isA<RollbackToLastGood>());
  });

  test('confirmed switch becomes the new rollback target', () {
    final s = ZmixPlaybackSwitcher();
    confirmPlaying(s, s.beginOpen('urlA', quality: '360p'), 'urlA');
    final gen = s.beginOpen('urlB', quality: '720p', needsAudio: true);
    confirmPlaying(s, gen, 'urlB');
    s.beginOpen('urlC');
    final d = s.onError('urlC') as RollbackToLastGood;
    expect(d.url, 'urlB');
    expect(d.needsAudio, isTrue);
  });

  test('error on the currently-playing stream (not a switch) shows panel',
      () {
    final s = ZmixPlaybackSwitcher();
    confirmPlaying(s, s.beginOpen('urlA', quality: '360p'), 'urlA');
    // Mid-playback network drop on the GOOD stream: no other target exists.
    expect(s.onError('urlA'), isA<ShowError>());
  });

  // ── Stale-event guards (review requirement) ────────────────────────────

  test('stale progress burst after a new open must NOT confirm the candidate',
      () {
    final s = ZmixPlaybackSwitcher();
    confirmPlaying(s, s.beginOpen('urlA', quality: '360p'), 'urlA');
    // Switch to B. Before mpv reports B's URI, a stale in-flight position
    // event from stream A arrives (position > 0, player still "playing").
    final genB = s.beginOpen('urlB');
    expect(
        s.onPlaybackProgress(
            generation: genB,
            position: const Duration(minutes: 3),
            playing: true),
        isFalse,
        reason: 'no media-loaded evidence for B yet');
    expect(s.confirmed, isFalse);
    // B fails: the rollback target must still be the original A.
    final d = s.onError('urlB') as RollbackToLastGood;
    expect(d.url, 'urlA');
  });

  test('playlist event with a stale URI does not count as media loaded', () {
    final s = ZmixPlaybackSwitcher();
    confirmPlaying(s, s.beginOpen('urlA', quality: '360p'), 'urlA');
    final genB = s.beginOpen('urlB');
    // mpv re-emits the PREVIOUS stream's playlist entry after the new open.
    s.onMediaLoaded('urlA', generation: genB);
    s.onPlaybackProgress(
        generation: genB, position: Duration.zero, playing: true);
    expect(
        s.onPlaybackProgress(
            generation: genB,
            position: const Duration(seconds: 4),
            playing: true),
        isFalse,
        reason: 'media-loaded was never seen for B');
    expect(s.confirmed, isFalse);
  });

  test('a single progress event never confirms; position must advance', () {
    final s = ZmixPlaybackSwitcher();
    final gen = s.beginOpen('urlA');
    s.onMediaLoaded('urlA', generation: gen);
    expect(
        s.onPlaybackProgress(
            generation: gen,
            position: const Duration(seconds: 5),
            playing: true),
        isFalse,
        reason: 'first event only sets the baseline');
    // Same position again (paused tick / duplicate): still not confirmed.
    expect(
        s.onPlaybackProgress(
            generation: gen,
            position: const Duration(seconds: 5),
            playing: true),
        isFalse);
    expect(s.confirmed, isFalse);
  });

  test('progress while paused does not confirm', () {
    final s = ZmixPlaybackSwitcher();
    final gen = s.beginOpen('urlA');
    s.onMediaLoaded('urlA', generation: gen);
    s.onPlaybackProgress(
        generation: gen, position: Duration.zero, playing: false);
    expect(
        s.onPlaybackProgress(
            generation: gen,
            position: const Duration(seconds: 1),
            playing: false),
        isFalse);
    expect(s.confirmed, isFalse);
  });

  test('evidence from an old generation is ignored', () {
    final s = ZmixPlaybackSwitcher();
    final genA = s.beginOpen('urlA');
    final genB = s.beginOpen('urlB');
    s.onMediaLoaded('urlB', generation: genA); // stale generation tag
    s.onPlaybackProgress(
        generation: genA, position: Duration.zero, playing: true);
    expect(
        s.onPlaybackProgress(
            generation: genA,
            position: const Duration(seconds: 2),
            playing: true),
        isFalse);
    expect(s.confirmed, isFalse);
    expect(genB, greaterThan(genA));
  });

  test('metadata-only confirmation path is gone: duration alone confirms nothing',
      () {
    // Regression guard for the review point "duration>0 may be metadata":
    // the switcher has no duration-based confirmation at all; a candidate
    // whose open fails immediately after mpv parsed metadata must still
    // roll back to the original stream.
    final s = ZmixPlaybackSwitcher();
    confirmPlaying(s, s.beginOpen('urlA'), 'urlA');
    s.beginOpen('urlB');
    // (No evidence calls: only metadata arrived, then the async error.)
    final d = s.onError('urlB') as RollbackToLastGood;
    expect(d.url, 'urlA');
  });
}
