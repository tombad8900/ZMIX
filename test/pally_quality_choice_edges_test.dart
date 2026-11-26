import 'package:flutter_test/flutter_test.dart';
import 'package:zmix/youtube_service.dart';

void main() {
  group('buildQualityChoices edge cases', () {
    test('muxed stream wins over adaptive at the same height', () {
      final choices = YoutubeService.buildQualityChoices(
        hasAudio: true,
        muxed: [
          (url: 'muxed-360', height: 360, bitrate: 500000, codec: 'avc1.4d401e'),
        ],
        videoOnly: [
          (url: 'adaptive-360', height: 360, bitrate: 9000000, codec: 'avc1.4d401e'),
        ],
      );

      expect(choices, hasLength(1));
      expect(choices.single.url, 'muxed-360');
      expect(choices.single.videoOnly, isFalse);
    });

    test('video-only streams are hidden when no audio URL is available', () {
      final choices = YoutubeService.buildQualityChoices(
        hasAudio: false,
        muxed: [
          (url: 'muxed-360', height: 360, bitrate: 500000, codec: 'avc1.4d401e'),
        ],
        videoOnly: [
          (url: 'video-720', height: 720, bitrate: 2000000, codec: 'avc1.4d401e'),
        ],
      );

      expect(choices.map((q) => q.url).toList(), ['muxed-360']);
      expect(choices.single.videoOnly, isFalse);
    });

    test('avc1 is preferred over a higher-bitrate codec at the same height', () {
      final choices = YoutubeService.buildQualityChoices(
        hasAudio: true,
        muxed: const [],
        videoOnly: [
          (url: 'vp9-720', height: 720, bitrate: 4000000, codec: 'vp9'),
          (url: 'avc1-720', height: 720, bitrate: 2000000, codec: 'avc1.4d401e'),
        ],
      );

      expect(choices, hasLength(1));
      expect(choices.single.url, 'avc1-720');
    });

    test('equal-bitrate candidates with the same codec keep the first entry', () {
      final choices = YoutubeService.buildQualityChoices(
        hasAudio: true,
        muxed: const [],
        videoOnly: [
          (url: 'first-720', height: 720, bitrate: 2000000, codec: 'avc1.4d401e'),
          (url: 'second-720', height: 720, bitrate: 2000000, codec: 'avc1.4d401e'),
        ],
      );

      expect(choices, hasLength(1));
      expect(choices.single.url, 'first-720');
    });

    test('empty stream lists yield no quality choices', () {
      final choices = YoutubeService.buildQualityChoices(
        hasAudio: false,
        muxed: const [],
        videoOnly: const [],
      );

      expect(choices, isEmpty);
    });
  });
}
