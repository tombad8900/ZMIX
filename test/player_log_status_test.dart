// Fixtures are SYNTHETIC lines written to match mpv/ffmpeg message shapes.
// They are not captured from YouTube; they prove the classifier's behavior
// (and that it never echoes input), not what a real device emits.
import 'package:flutter_test/flutter_test.dart';
import 'package:zmix/player_log_status.dart';

void main() {
  const secret = 'https://rr1.example.invalid/videoplayback?id=SECRETID&ip=10.1.2.3';

  test('HTTP status is extracted as a number', () {
    final s = PlayerLogStatus.classify(
        'ffmpeg', 'error', 'tcp: HTTP error 403 Forbidden $secret')!;
    expect(s, const PlayerLogStatus('http_status', 403));
    expect(s.label, 'http_status:403');
  });

  test('open failure and external file failure map to fixed kinds', () {
    expect(PlayerLogStatus.classify('cplayer', 'error', 'Failed to open $secret.')!.kind,
        'open_failed');
    expect(
        PlayerLogStatus.classify(
                'cplayer', 'error', 'Can not open external file $secret.')!
            .kind,
        'external_file_failed');
  });

  test('tcp and unknown errors do not carry text', () {
    expect(PlayerLogStatus.classify('ffmpeg', 'error', 'tcp: Connection reset')!.kind,
        'tcp_error');
    expect(PlayerLogStatus.classify('x', 'error', 'something $secret')!.kind,
        'other_error');
  });

  test('non-error levels are ignored', () {
    expect(PlayerLogStatus.classify('ffmpeg', 'info', 'HTTP error 403'), isNull);
  });

  test('label never contains any part of the input text', () {
    for (final line in [
      'HTTP error 403 Forbidden $secret',
      'Failed to open $secret',
      'weird $secret',
    ]) {
      final l = PlayerLogStatus.classify('ffmpeg', 'error', line)!.label;
      expect(l.contains('SECRETID'), isFalse);
      expect(l.contains('10.1.2.3'), isFalse);
      expect(l.contains('example.invalid'), isFalse);
    }
  });
}
