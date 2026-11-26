import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:zmix/stream_headers.dart';

void main() {
  test('androidSdkless declares a user agent and it is passed through verbatim',
      () {
    final h = streamHeadersFor(YoutubeApiClient.androidSdkless)!;
    expect(h.keys, ['user-agent']);
    expect(h['user-agent'],
        YoutubeApiClient.androidSdkless.payload['context']['client']['userAgent']);
  });

  test('a client that declares no user agent yields no headers (nothing invented)',
      () {
    expect(streamHeadersFor(YoutubeApiClient.androidVr), isNull);
  });

  test('only adaptive opens get headers; muxed opens are unchanged', () {
    const h = {'user-agent': 'x'};
    expect(headersForOpen(needsExternalAudio: true, clientHeaders: h), h);
    expect(headersForOpen(needsExternalAudio: false, clientHeaders: h), isNull);
    expect(headersForOpen(needsExternalAudio: true, clientHeaders: null), isNull);
  });

  test('media_kit Media keeps the headers it is given (what mpv hook reads)', () {
    const url = 'https://h.example.invalid/v?x=1';
    final m = Media(url, httpHeaders: {'user-agent': 'ua-test'});
    expect(m.httpHeaders, {'user-agent': 'ua-test'});
  });

  group('buildOpenMedia (the object mpv reads)', () {
    const ua = {'user-agent': 'ua-test'};
    test('adaptive open carries the headers', () {
      final m = buildOpenMedia('https://h.example.invalid/a?i=1',
          needsExternalAudio: true, clientHeaders: ua);
      expect(m.httpHeaders, ua);
    });

    test('rollback to a muxed URL does not carry them (different URL, no cache hit)',
        () {
      buildOpenMedia('https://h.example.invalid/adaptive?i=1',
          needsExternalAudio: true, clientHeaders: ua);
      final muxed = buildOpenMedia('https://h.example.invalid/muxed?i=2',
          needsExternalAudio: false, clientHeaders: ua);
      expect(muxed.httpHeaders, isNull);
    });

    test('KNOWN media_kit behavior: same URL reopened without headers reuses cached ones',
        () {
      const u = 'https://h.example.invalid/same?i=3';
      buildOpenMedia(u, needsExternalAudio: true, clientHeaders: ua);
      final again = Media(u); // what mpv's on_load hook does: Media(path)
      expect(again.httpHeaders, ua,
          reason: 'headers are keyed by URL in media_kit; our policy is constant per URL');
    });
  });

  group('fetchWithProvenance', () {
    test('first client wins when it returns something', () async {
      final calls = <String>[];
      final r = await fetchWithProvenance<List<int>>((c) async {
        calls.add(c.payload['context']['client']['clientName'] as String);
        return [1];
      }, (m) => m.isEmpty);
      expect(r.client, same(YoutubeApiClient.androidSdkless));
      expect(calls, ['ANDROID']);
    });

    test('empty first result falls back to tv and reports tv', () async {
      final r = await fetchWithProvenance<List<int>>(
          (c) async => identical(c, YoutubeApiClient.androidSdkless) ? [] : [2],
          (m) => m.isEmpty);
      expect(r.client, same(YoutubeApiClient.tv));
      expect(r.manifest, [2]);
    });

    test('exception on first client falls back to tv', () async {
      final r = await fetchWithProvenance<List<int>>((c) async {
        if (identical(c, YoutubeApiClient.androidSdkless)) throw StateError('x');
        return [3];
      }, (m) => m.isEmpty);
      expect(r.client, same(YoutubeApiClient.tv));
    });

    test('tv failure propagates (no silent success)', () async {
      expect(
          fetchWithProvenance<List<int>>(
              (c) async => throw StateError('both'), (m) => m.isEmpty),
          throwsStateError);
    });

    test('headers follow the client that actually served', () async {
      final r = await fetchWithProvenance<List<int>>(
          (c) async => identical(c, YoutubeApiClient.androidSdkless) ? [] : [4],
          (m) => m.isEmpty);
      expect(streamHeadersFor(r.client)!['user-agent'],
          YoutubeApiClient.tv.payload['context']['client']['userAgent']);
    });
  });
}
