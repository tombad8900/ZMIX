import 'package:flutter_test/flutter_test.dart';
import 'package:http_parser/http_parser.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:zmix/youtube_service.dart';

const _videoId = 'abcdefghijk';

Uri _url(String name) => Uri.parse('https://example.invalid/$name');

VideoQuality _qualityFor(int height) => switch (height) {
      360 => VideoQuality.medium360,
      720 => VideoQuality.high720,
      1080 => VideoQuality.high1080,
      _ => VideoQuality.unknown,
    };

MuxedStreamInfo _muxed({
  required String name,
  required int height,
  int bitrate = 500000,
  String videoCodec = 'avc1.4d401e',
}) =>
    MuxedStreamInfo(
      VideoId(_videoId),
      18 + height,
      _url(name),
      StreamContainer.mp4,
      const FileSize(1),
      Bitrate(bitrate),
      'mp4a.40.2',
      videoCodec,
      '${height}p',
      _qualityFor(height),
      VideoResolution(height * 16 ~/ 9, height),
      const Framerate(30),
      MediaType('video', 'mp4'),
    );

VideoOnlyStreamInfo _videoOnly({
  required String name,
  required int height,
  int bitrate = 2000000,
  String videoCodec = 'avc1.4d401e',
}) =>
    VideoOnlyStreamInfo(
      VideoId(_videoId),
      100 + height,
      _url(name),
      StreamContainer.mp4,
      const FileSize(1),
      Bitrate(bitrate),
      videoCodec,
      '${height}p',
      _qualityFor(height),
      VideoResolution(height * 16 ~/ 9, height),
      const Framerate(30),
      const [],
      MediaType('video', 'mp4'),
    );

AudioOnlyStreamInfo _audioOnly({
  required String name,
  required String mime,
  required int bitrate,
}) =>
    AudioOnlyStreamInfo(
      VideoId(_videoId),
      200,
      _url(name),
      StreamContainer.mp4,
      const FileSize(1),
      Bitrate(bitrate),
      'mp4a.40.2',
      'medium',
      const [],
      MediaType.parse(mime),
      null,
    );

String _userAgentFor(YoutubeApiClient client) =>
    client.payload['context']['client']['userAgent'] as String;

void main() {
  group('resolveStreamChoices with manifestFetcher', () {
    test('classifies manifest streams and returns the serving client headers',
        () async {
      final calls = <({String videoId, YoutubeApiClient client})>[];
      final service = YoutubeService(
        manifestFetcher: (videoId, client) async {
          calls.add((videoId: videoId, client: client));
          return StreamManifest([
            _muxed(name: 'muxed-360', height: 360),
            _videoOnly(name: 'video-720', height: 720),
            _audioOnly(name: 'audio-webm', mime: 'audio/webm', bitrate: 160000),
            _audioOnly(name: 'audio-m4a', mime: 'audio/mp4', bitrate: 128000),
          ]);
        },
      );
      addTearDown(service.close);

      final choices = await service.resolveStreamChoices(_videoId);

      expect(calls, hasLength(1));
      expect(calls.single.videoId, _videoId);
      expect(calls.single.client, same(YoutubeApiClient.androidSdkless));
      expect(choices.qualities.map((q) => q.quality).toList(), ['720p', '360p']);
      expect(choices.qualities.map((q) => q.url).toList(), [
        'https://example.invalid/video-720',
        'https://example.invalid/muxed-360',
      ]);
      expect(choices.qualities.map((q) => q.videoOnly).toList(), [true, false]);
      expect(choices.audioUrl, 'https://example.invalid/audio-m4a');
      expect(choices.httpHeaders, {
        'user-agent': _userAgentFor(YoutubeApiClient.androidSdkless),
      });
    });

    test('tries tv after an empty first manifest and uses tv provenance', () async {
      final clients = <YoutubeApiClient>[];
      final service = YoutubeService(
        manifestFetcher: (_, client) async {
          clients.add(client);
          if (identical(client, YoutubeApiClient.androidSdkless)) {
            return StreamManifest(const <StreamInfo>[]);
          }
          return StreamManifest([
            _videoOnly(name: 'tv-video-720', height: 720),
            _audioOnly(name: 'tv-audio', mime: 'audio/mp4', bitrate: 128000),
          ]);
        },
      );
      addTearDown(service.close);

      final choices = await service.resolveStreamChoices(_videoId);

      expect(clients, hasLength(2));
      expect(clients[0], same(YoutubeApiClient.androidSdkless));
      expect(clients[1], same(YoutubeApiClient.tv));
      expect(choices.qualities.map((q) => q.quality).toList(), ['720p']);
      expect(choices.qualities.single.videoOnly, isTrue);
      expect(choices.httpHeaders, {
        'user-agent': _userAgentFor(YoutubeApiClient.tv),
      });
      expect(
        choices.httpHeaders!['user-agent'],
        isNot(_userAgentFor(YoutubeApiClient.androidSdkless)),
      );
    });

    test('tries tv after the first fetch throws', () async {
      final clients = <YoutubeApiClient>[];
      final service = YoutubeService(
        manifestFetcher: (_, client) async {
          clients.add(client);
          if (identical(client, YoutubeApiClient.androidSdkless)) {
            throw StateError('synthetic first-client failure');
          }
          return StreamManifest([_muxed(name: 'tv-muxed-360', height: 360)]);
        },
      );
      addTearDown(service.close);

      final choices = await service.resolveStreamChoices(_videoId);

      expect(clients, hasLength(2));
      expect(clients[0], same(YoutubeApiClient.androidSdkless));
      expect(clients[1], same(YoutubeApiClient.tv));
      expect(choices.qualities.single.url, 'https://example.invalid/tv-muxed-360');
      expect(choices.httpHeaders, {
        'user-agent': _userAgentFor(YoutubeApiClient.tv),
      });
    });

    test('rethrows when both client fetches throw', () async {
      var calls = 0;
      final service = YoutubeService(
        manifestFetcher: (_, __) async {
          calls++;
          throw StateError('synthetic fetch failure');
        },
      );
      addTearDown(service.close);

      await expectLater(
        service.resolveStreamChoices(_videoId),
        throwsA(isA<StateError>()),
      );
      expect(calls, 2);
    });

    test('throws when both clients return empty manifests', () async {
      var calls = 0;
      final service = YoutubeService(
        manifestFetcher: (_, __) async {
          calls++;
          return StreamManifest(const <StreamInfo>[]);
        },
      );
      addTearDown(service.close);

      await expectLater(
        service.resolveStreamChoices(_videoId),
        throwsA(isA<FormatException>()),
      );
      expect(calls, 2);
    });

    test('does not treat an audio-only manifest as a playable video quality',
        () async {
      final service = YoutubeService(
        manifestFetcher: (_, __) async => StreamManifest([
          _audioOnly(name: 'audio-only', mime: 'audio/mp4', bitrate: 128000),
        ]),
      );
      addTearDown(service.close);

      await expectLater(
        service.resolveStreamChoices(_videoId),
        throwsA(isA<FormatException>()),
      );
    });

    test('drops adaptive qualities without paired audio and keeps muxed fallback',
        () async {
      final service = YoutubeService(
        manifestFetcher: (_, __) async => StreamManifest([
          _muxed(name: 'muxed-360', height: 360),
          _videoOnly(name: 'silent-720', height: 720),
        ]),
      );
      addTearDown(service.close);

      final choices = await service.resolveStreamChoices(_videoId);

      expect(choices.audioUrl, isNull);
      expect(choices.qualities.map((q) => q.url).toList(), [
        'https://example.invalid/muxed-360',
      ]);
      expect(choices.qualities.single.videoOnly, isFalse);
    });
  });
}
