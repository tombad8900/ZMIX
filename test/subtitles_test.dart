import 'package:flutter_test/flutter_test.dart';
import 'package:zmix/subtitles.dart';

void main() {
  group('captionsToSrt', () {
    test('renders numbered cues with comma-millisecond stamps', () {
      final srt = captionsToSrt([
        (
          text: 'أهلاً',
          start: const Duration(seconds: 3, milliseconds: 500),
          end: const Duration(seconds: 5),
        ),
        (
          text: 'second line',
          start: const Duration(minutes: 1, seconds: 2, milliseconds: 40),
          end: const Duration(hours: 1),
        ),
      ]);
      expect(
        srt,
        '1\n00:00:03,500 --> 00:00:05,000\nأهلاً\n\n'
        '2\n00:01:02,040 --> 01:00:00,000\nsecond line\n\n',
      );
    });

    test('drops empty cues and renumbers', () {
      final srt = captionsToSrt([
        (
          text: '   ',
          start: Duration.zero,
          end: const Duration(seconds: 1),
        ),
        (
          text: 'kept',
          start: const Duration(seconds: 2),
          end: const Duration(seconds: 3),
        ),
      ]);
      expect(srt.startsWith('1\n00:00:02,000'), isTrue);
      expect(srt.contains('   \n'), isFalse);
    });

    test('clamps a cue that overlaps the next one', () {
      final srt = captionsToSrt([
        (
          text: '[موسيقى]',
          start: const Duration(seconds: 6),
          end: const Duration(seconds: 20),
        ),
        (
          text: 'كلام',
          start: const Duration(seconds: 9),
          end: const Duration(seconds: 11),
        ),
      ]);
      expect(srt.contains('00:00:06,000 --> 00:00:09,000'), isTrue);
    });

    test('zero-duration cue gets a 2s window', () {
      final srt = captionsToSrt([
        (text: 'x', start: const Duration(seconds: 4), end: const Duration(seconds: 4)),
      ]);
      expect(srt.contains('00:00:04,000 --> 00:00:06,000'), isTrue);
    });

    test('negative durations never produce negative stamps', () {
      final srt = captionsToSrt([
        (
          text: 'x',
          start: const Duration(milliseconds: -5),
          end: const Duration(milliseconds: -1),
        ),
      ]);
      expect(srt.contains('00:00:00,000 --> 00:00:02,000'), isTrue);
    });
  });
}
