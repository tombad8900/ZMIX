import 'package:flutter_test/flutter_test.dart';
import 'package:zmix/playback_switcher.dart';

const _good = 'https://h1.example/videoplayback?itag=18&id=A&mime=video%2Fmp4&sig=1';
const _v720 = 'https://h1.example/videoplayback?itag=136&id=A&mime=video%2Fmp4&sig=2';
const _a = 'https://h2.example/videoplayback?itag=140&id=A&mime=audio%2Fmp4&sig=3';
const _v480 = 'https://h1.example/videoplayback?itag=135&id=A&mime=video%2Fmp4&sig=4';

void confirm(ZmixPlaybackSwitcher s, int g, String url) {
  s.onMediaLoaded(url, generation: g);
  s.onPlaybackProgress(generation: g, position: Duration.zero, playing: true);
  s.onPlaybackProgress(
      generation: g, position: const Duration(seconds: 1), playing: true);
}

void main() {
  test('diag4 sequence: late audio error of the failed candidate is stale', () {
    final s = ZmixPlaybackSwitcher();
    confirm(s, s.beginOpen(_good, quality: '360p'), _good);
    s.beginOpen(_v720, quality: '720p', needsAudio: true, audioUrl: _a);
    expect(s.onPlayerError('Failed to open $_v720.', _v720),
        isA<RollbackToLastGood>());
    s.beginOpen(_good, quality: '360p'); // rollback reopen
    expect(s.onPlayerError('Can not open external file $_a.', _good),
        isA<IgnoreStaleError>());
  });

  test('B then C then late B failure does not cancel C', () {
    final s = ZmixPlaybackSwitcher();
    confirm(s, s.beginOpen(_good, quality: '360p'), _good);
    s.beginOpen(_v720, quality: '720p', needsAudio: true, audioUrl: _a);
    s.beginOpen(_v480, quality: '480p', needsAudio: true, audioUrl: _a);
    expect(s.onPlayerError('Failed to open $_v720', _v480),
        isA<IgnoreStaleError>());
  });

  test('genuine failure of the CURRENT open is still handled', () {
    final s = ZmixPlaybackSwitcher();
    confirm(s, s.beginOpen(_good, quality: '360p'), _good);
    s.beginOpen(_v720, quality: '720p', needsAudio: true, audioUrl: _a);
    expect(s.onPlayerError('Failed to open $_v720', _v720),
        isA<RollbackToLastGood>());
    // an error naming the current external audio of the current open
    final s2 = ZmixPlaybackSwitcher();
    confirm(s2, s2.beginOpen(_good, quality: '360p'), _good);
    s2.beginOpen(_v720, quality: '720p', needsAudio: true, audioUrl: _a);
    expect(s2.onPlayerError('Can not open external file $_a', _v720),
        isA<RollbackToLastGood>());
  });

  test('error text without a URL keeps the previous behavior', () {
    final s = ZmixPlaybackSwitcher();
    confirm(s, s.beginOpen(_good, quality: '360p'), _good);
    s.beginOpen(_v720, quality: '720p', needsAudio: true, audioUrl: _a);
    expect(s.onPlayerError('tcp: connection timed out', _v720),
        isA<RollbackToLastGood>());
    final s2 = ZmixPlaybackSwitcher();
    s2.beginOpen(_good);
    expect(s2.onPlayerError('Failed to open', _good), isA<ShowError>());
  });

  test('unknown URL in text is not treated as stale', () {
    final s = ZmixPlaybackSwitcher();
    s.beginOpen(_good);
    expect(s.onPlayerError('Failed to open https://x.example/other', _good),
        isA<ShowError>());
  });

  test('same stream reopened (retry) stays attributable to current', () {
    final s = ZmixPlaybackSwitcher();
    s.beginOpen(_v720, needsAudio: true, audioUrl: _a);
    s.beginOpen(_good);
    s.beginOpen(_v720, needsAudio: true, audioUrl: _a);
    expect(s.onPlayerError('Failed to open $_v720', _v720), isA<ShowError>());
  });
}
