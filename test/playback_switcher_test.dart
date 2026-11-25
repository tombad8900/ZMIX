import 'package:flutter_test/flutter_test.dart';
import 'package:zmix/playback_switcher.dart';

// Failure-injection tests for the open/error/retry/rollback state logic:
// every sequence below mirrors a real player-page flow, with errors injected
// exactly where media_kit's error stream would emit them.
void main() {
  test('initial open fails, nothing ever played -> safe error panel', () {
    final s = ZmixPlaybackSwitcher();
    final d = s.onError('urlA');
    expect(d, isA<ShowError>());
    expect((d as ShowError).message, kSafePlaybackError);
    // The safe text must never carry a transport URL or IP.
    expect(d.message.contains('http'), isFalse);
  });

  test('failed quality switch rolls back to the last playing stream', () {
    final s = ZmixPlaybackSwitcher();
    s.markPlaying('urlA', quality: '360p');
    // User switches to 1080p; open fails (device evidence: 0.3.4).
    final d = s.onError('urlB');
    expect(d, isA<RollbackToLastGood>());
    final r = d as RollbackToLastGood;
    expect(r.url, 'urlA');
    expect(r.quality, '360p');
  });

  test('rollback target failing shows the error panel, no rollback loop', () {
    final s = ZmixPlaybackSwitcher();
    s.markPlaying('urlA', quality: '360p');
    expect(s.onError('urlB'), isA<RollbackToLastGood>());
    // The rollback open of urlA fails too (network down): panel, not a loop.
    final d = s.onError('urlA');
    expect(d, isA<ShowError>());
    // And a third error still does not resurrect a rollback.
    expect(s.onError('urlA'), isA<ShowError>());
  });

  test('a fresh failure after recovery may roll back again', () {
    final s = ZmixPlaybackSwitcher();
    s.markPlaying('urlA', quality: '360p');
    expect(s.onError('urlB'), isA<RollbackToLastGood>());
    s.markPlaying('urlA', quality: '360p'); // rollback succeeded
    expect(s.onError('urlC'), isA<RollbackToLastGood>());
  });

  test('successful switch becomes the new rollback target', () {
    final s = ZmixPlaybackSwitcher();
    s.markPlaying('urlA', quality: '360p');
    s.markPlaying('urlB', quality: '720p', needsAudio: true);
    final d = s.onError('urlC') as RollbackToLastGood;
    expect(d.url, 'urlB');
    expect(d.needsAudio, isTrue);
  });

  test('error on the currently-playing stream (not a switch) shows panel',
      () {
    final s = ZmixPlaybackSwitcher();
    s.markPlaying('urlA', quality: '360p');
    // Mid-playback network drop on the GOOD stream: no other target exists.
    expect(s.onError('urlA'), isA<ShowError>());
  });
}
