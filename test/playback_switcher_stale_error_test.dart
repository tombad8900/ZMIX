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
  identityTests();
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

// Identity ambiguity: the guard may fail to ignore a stale error, but must
// never ignore an error that could belong to the current open.
void identityTests() {
  const base = 'https://h1.example/videoplayback';
  ZmixPlaybackSwitcher twoOpens(String cur, String old) {
    final s = ZmixPlaybackSwitcher();
    s.beginOpen(old, quality: '720p');
    s.beginOpen(cur, quality: '480p');
    return s;
  }

  test('same itag/id/mime, different signature: treated as current', () {
    final old = '$base?itag=136&id=A&mime=video%2Fmp4&sig=OLD&expire=1';
    final cur = '$base?itag=136&id=A&mime=video%2Fmp4&sig=NEW&expire=2';
    final s = twoOpens(cur, old);
    expect(s.onPlayerError('Failed to open $old', cur), isA<ShowError>());
  });

  test('same host, different itag: distinct streams', () {
    final old = '$base?itag=136&id=A&mime=video%2Fmp4&sig=1';
    final cur = '$base?itag=135&id=A&mime=video%2Fmp4&sig=2';
    final s = twoOpens(cur, old);
    expect(s.onPlayerError('Failed to open $old', cur), isA<IgnoreStaleError>());
  });

  test('same itag, different video id: distinct streams', () {
    final old = '$base?itag=136&id=A&mime=video%2Fmp4';
    final cur = '$base?itag=136&id=B&mime=video%2Fmp4';
    final s = twoOpens(cur, old);
    expect(s.onPlayerError('Failed to open $old', cur), isA<IgnoreStaleError>());
  });

  test('encoded vs unencoded mime give the same key', () {
    expect(streamKey('$base?itag=1&id=A&mime=video%2Fmp4'),
        streamKey('$base?itag=1&id=A&mime=video/mp4'));
  });

  test('missing id falls back to the whole URL (no cross-video collision)', () {
    final old = '$base?itag=136&sig=1';
    final cur = '$base?itag=136&sig=2';
    final s = twoOpens(cur, old);
    expect(streamKey(old), isNot(streamKey(cur)));
    expect(s.onPlayerError('Failed to open $old', cur), isA<IgnoreStaleError>());
    // the identical URL is the current one: handled normally
    expect(s.onPlayerError('Failed to open $cur', cur), isA<ShowError>());
  });

  test('stale URL plus an unknown URL is not ignored (Pally review)', () {
    final old = '$base?itag=136&id=A&mime=video%2Fmp4&sig=1';
    final cur = '$base?itag=135&id=A&mime=video%2Fmp4&sig=2';
    final s = twoOpens(cur, old);
    expect(
        s.onPlayerError('open $old via https://x.example/other', cur),
        isA<ShowError>());
  });

  test('truncated URL that names no known stream is not ignored', () {
    final old = '$base?itag=136&id=A&mime=video%2Fmp4&sig=1';
    final cur = '$base?itag=135&id=A&mime=video%2Fmp4&sig=2';
    final s = twoOpens(cur, old);
    expect(s.onPlayerError('Failed to open $base?ita', cur), isA<ShowError>());
  });

  test('text naming both a stale and the current stream is not ignored', () {
    final old = '$base?itag=136&id=A&mime=video%2Fmp4&sig=1';
    final cur = '$base?itag=135&id=A&mime=video%2Fmp4&sig=2';
    final s = twoOpens(cur, old);
    expect(s.onPlayerError('open $old then $cur failed', cur), isA<ShowError>());
  });

  test('non-http / unknown formats fall back to previous behavior', () {
    final s = twoOpens('https://h/x?itag=1&id=A', 'https://h/x?itag=2&id=A');
    expect(s.onPlayerError('ffmpeg: tcp: Connection reset', 'u'),
        isA<ShowError>());
    expect(s.onPlayerError('Failed to open file:///x/y.mp4', 'u'),
        isA<ShowError>());
  });
}
