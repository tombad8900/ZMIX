import 'package:flutter_test/flutter_test.dart';
import 'package:zmix/youtube_service.dart';

void main() {
  group('buildQualityChoices edge cases', () {
    test('prefers muxed at the same height even when adaptive has higher bitrate', () {
      final choices = YoutubeService.buildQualityChoices(
        hasAudio: true,
        muxed: const [
          (url: 'muxed-720', height: 720, bitrate: 500000, codec: 'avc1.4d401e'),
        ],
        videoOnly: const [
          (url: 'adaptive-720', height: 720, bitrate: 4000000, codec: 'avc1.4d401e'),
        ],
      );

      expect(choices, hasLength(1));
      expect(choices.single.url, 'muxed-720');
      expect(choices.single.videoOnly, isFalse);
    });

    test('hides video-only choices without paired audio', () {
      final choices = YoutubeService.buildQualityChoices(
        hasAudio: false,
        muxed: const [
          (url: 'muxed-360', height: 360, bitrate: 500000, codec: 'avc1.4d401e'),
        ],
        videoOnly: const [
          (url: 'silent-720', height: 720, bitrate: 2000000, codec: 'avc1.4d401e'),
        ],
      );

      expect(choices, hasLength(1));
      expect(choices.single.url, 'muxed-360');
      expect(choices.single.videoOnly, isFalse);
    });

    test('prefers avc1 over a higher-bitrate codec at the same height', () {
      final choices = YoutubeService.buildQualityChoices(
        hasAudio: true,
        muxed: const [],
        videoOnly: const [
          (url: 'vp9-720', height: 720, bitrate: 4000000, codec: 'vp9'),
          (url: 'avc1-720', height: 720, bitrate: 1500000, codec: 'avc1.4d401e'),
        ],
      );

      expect(choices, hasLength(1));
      expect(choices.single.url, 'avc1-720');
      expect(choices.single.codec, startsWith('avc1'));
    });

    test('uses the first candidate when same-height codec and bitrate are equal', () {
      final choices = YoutubeService.buildQualityChoices(
        hasAudio: true,
        muxed: const [],
        videoOnly: const [
          (url: 'first-720', height: 720, bitrate: 2000000, codec: 'avc1.4d401e'),
          (url: 'second-720', height: 720, bitrate: 2000000, codec: 'avc1.4d401e'),
        ],
      );

      expect(choices, hasLength(1));
      expect(choices.single.url, 'first-720');
    });

    test('returns no choices for empty input', () {
      final choices = YoutubeService.buildQualityChoices(
        hasAudio: false,
        muxed: const [],
        videoOnly: const [],
      );

      expect(choices, isEmpty);
    });
  });
}
