import 'package:flutter_test/flutter_test.dart';
import 'package:zmix/youtube_service.dart';

void main() {
  group('buildQualityChoices', () {
    test('one entry per height, best first, muxed beats video-only', () {
      final out = YoutubeService.buildQualityChoices(
        hasAudio: true,
        muxed: [
          (url: 'm360', height: 360, bitrate: 500, codec: 'avc1.4d'),
        ],
        videoOnly: [
          (url: 'v360', height: 360, bitrate: 900, codec: 'vp9'),
          (url: 'v720vp9', height: 720, bitrate: 2000, codec: 'vp9'),
          (url: 'v720avc', height: 720, bitrate: 1500, codec: 'avc1.64'),
          (url: 'v1080', height: 1080, bitrate: 4000, codec: 'avc1.64'),
        ],
      );
      expect(out.map((o) => o.quality).toList(), ['1080p', '720p', '360p']);
      // avc1 wins at 720p despite the lower bitrate (hardware decode).
      expect(out[1].url, 'v720avc');
      // The muxed 360p wins over the higher-bitrate video-only 360p.
      expect(out[2].url, 'm360');
      expect(out[2].videoOnly, isFalse);
      expect(out[0].videoOnly, isTrue);
    });

    test('labels come from resolution height, 4K included honestly', () {
      final out = YoutubeService.buildQualityChoices(
        hasAudio: true,
        muxed: const [],
        videoOnly: [
          (url: 'v2160', height: 2160, bitrate: 20000, codec: 'vp9'),
        ],
      );
      expect(out.single.quality, '2160p');
    });

    test('REGRESSION: no paired audio -> video-only entries never offered',
        () {
      final out = YoutubeService.buildQualityChoices(
        hasAudio: false,
        muxed: [
          (url: 'm360', height: 360, bitrate: 500, codec: 'avc1.4d'),
        ],
        videoOnly: [
          (url: 'v720', height: 720, bitrate: 2000, codec: 'vp9'),
          (url: 'v1080', height: 1080, bitrate: 4000, codec: 'avc1.64'),
        ],
      );
      // Silent playback is never offered: only the muxed fallback remains.
      expect(out.map((o) => o.quality).toList(), ['360p']);
      expect(out.every((o) => !o.videoOnly), isTrue);
    });

    test('no audio and no muxed -> empty list, not a silent offer', () {
      final out = YoutubeService.buildQualityChoices(
        hasAudio: false,
        muxed: const [],
        videoOnly: [
          (url: 'v720', height: 720, bitrate: 2000, codec: 'vp9'),
        ],
      );
      expect(out, isEmpty);
    });
  });

  group('pickAudioUrl', () {
    test('prefers highest-bitrate mp4 audio', () {
      final url = YoutubeService.pickAudioUrl([
        (url: 'a_webm', bitrate: 160, mime: 'audio/webm'),
        (url: 'a_m4a_low', bitrate: 96, mime: 'audio/mp4'),
        (url: 'a_m4a_high', bitrate: 128, mime: 'audio/mp4'),
      ]);
      expect(url, 'a_m4a_high');
    });

    test('falls back to highest overall when no mp4', () {
      final url = YoutubeService.pickAudioUrl([
        (url: 'a1', bitrate: 50, mime: 'audio/webm'),
        (url: 'a2', bitrate: 90, mime: 'audio/webm'),
      ]);
      expect(url, 'a2');
    });

    test('null when no audio streams', () {
      expect(YoutubeService.pickAudioUrl(const []), isNull);
    });
  });
}
