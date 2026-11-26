import 'package:flutter_test/flutter_test.dart';
import 'package:zmix/youtube_service.dart';

void main() {
  group('synthetic quality pipeline', () {
    test('pairs selected audio with adaptive qualities and keeps muxed fallback', () {
      final audioUrl = YoutubeService.pickAudioUrl([
        (url: 'audio-webm', bitrate: 160, mime: 'audio/webm'),
        (url: 'audio-mp4-high', bitrate: 128, mime: 'audio/mp4'),
      ]);
      final choices = YoutubeService.buildQualityChoices(
        hasAudio: audioUrl != null,
        muxed: [
          (url: 'muxed-360', height: 360, bitrate: 500, codec: 'avc1.4d'),
        ],
        videoOnly: [
          (url: 'video-720', height: 720, bitrate: 2000, codec: 'avc1.64'),
          (url: 'video-1080', height: 1080, bitrate: 4000, codec: 'vp9'),
        ],
      );

      expect(audioUrl, 'audio-mp4-high');
      expect(choices.map((q) => q.quality).toList(), ['1080p', '720p', '360p']);
      expect(choices.map((q) => q.url).toList(), ['video-1080', 'video-720', 'muxed-360']);
      expect(choices.map((q) => q.videoOnly).toList(), [true, true, false]);
    });

    test('without a selected audio track, only muxed qualities remain', () {
      final audioUrl = YoutubeService.pickAudioUrl(const []);
      final choices = YoutubeService.buildQualityChoices(
        hasAudio: audioUrl != null,
        muxed: [
          (url: 'muxed-360', height: 360, bitrate: 500, codec: 'avc1.4d'),
        ],
        videoOnly: [
          (url: 'video-720', height: 720, bitrate: 2000, codec: 'avc1.64'),
        ],
      );

      expect(audioUrl, isNull);
      expect(choices.map((q) => q.quality).toList(), ['360p']);
      expect(choices.single.videoOnly, isFalse);
    });

    test('empty synthetic stream lists yield no quality rows', () {
      final choices = YoutubeService.buildQualityChoices(
        hasAudio: false,
        muxed: const [],
        videoOnly: const [],
      );

      expect(choices, isEmpty);
    });
  });
}
