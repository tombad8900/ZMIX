import 'package:flutter_test/flutter_test.dart';
import 'package:http_parser/http_parser.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:zmix/youtube_service.dart';

MuxedStreamInfo _muxed(int tag, int bps, int h) => MuxedStreamInfo(
      VideoId('_8ymBTARneI'),
      tag,
      Uri.parse('https://example.invalid/v$tag'),
      StreamContainer.mp4,
      const FileSize(1000),
      Bitrate(bps),
      'mp4a.40.2',
      'avc1.42001E',
      '${h}p',
      VideoQuality.medium360,
      VideoResolution(h * 16 ~/ 9, h),
      const Framerate(30),
      MediaType('video', 'mp4'),
    );

void main() {
  test('pickBestMuxed works on a real StreamManifest (muxed list)', () {
    final manifest = StreamManifest([
      _muxed(18, 500000, 360),
      _muxed(22, 1500000, 720),
      _muxed(17, 100000, 144),
    ]);
    expect(manifest.muxed.runtimeType.toString(),
        contains('UnmodifiableListView<MuxedStreamInfo>'));
    expect(YoutubeService.pickBestMuxed(manifest).tag, 22);
  });

  test('REGRESSION: extension call on a dynamic receiver throws the '
      'exact device NoSuchMethodError; typed call does not', () {
    final manifest = StreamManifest([_muxed(18, 500000, 360)]);
    // ignore: prefer_typed_declarations
    dynamic untyped = manifest;
    expect(() => untyped.muxed.withHighestBitrate(),
        throwsA(isA<NoSuchMethodError>()));
    expect(manifest.muxed.withHighestBitrate().tag, 18);
  });
}
