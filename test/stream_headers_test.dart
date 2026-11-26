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
}
