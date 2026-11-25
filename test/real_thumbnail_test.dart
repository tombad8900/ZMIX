import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zmix/ui/poster_card.dart';

import 'golden_fonts.dart';

/// Real YouTube thumbnail (hqdefault 480x360, Big Buck Bunny - used purely
/// as representative video-still content) to verify PosterCard crop,
/// readability, and the production CachedNetworkImage loading path with
/// real content rather than synthetic gradients.
const _stillUrl = 'https://i.ytimg.com/vi/aqz-KE-bpKQ/hqdefault.jpg';

Uint8List get _stillBytes =>
    File('test/fixtures/youtube_hqdefault.jpg').readAsBytesSync();

class _StillHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _StillClient();
}

class _StillClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _StillRequest(_stillBytes);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _StillRequest implements HttpClientRequest {
  _StillRequest(this.bytes);
  final Uint8List bytes;
  @override
  Future<HttpClientResponse> close() async => _StillResponse(bytes);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _StillResponse extends Stream<List<int>> implements HttpClientResponse {
  _StillResponse(this.bytes);
  final Uint8List bytes;
  @override
  int get statusCode => 200;
  @override
  int get contentLength => bytes.length;
  @override
  HttpHeaders get headers => _StillHeaders();
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.fromIterable([bytes]).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _StillHeaders implements HttpHeaders {
  @override
  List<String>? operator [](String name) =>
      name.toLowerCase() == 'content-type' ? ['image/jpeg'] : null;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('zmix_cache_probe');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
    HttpOverrides.global = _StillHttpOverrides();
    await loadGoldenFonts();
  });

  testWidgets('poster card with real video still - crop and readability',
      (tester) async {
    tester.view.physicalSize = const Size(1104, 760); // logical 552x380
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    PosterCard.debugImageProvider = (_) => MemoryImage(_stillBytes);
    addTearDown(() => PosterCard.debugImageProvider = null);
    await tester.pumpWidget(
      goldenHost(
        const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: SizedBox(
              width: 184,
              // Production shelf cell: posterCellHeight(184, wide: true).
              height: 146,
              child: PosterCard(
                title: 'Big Buck Bunny - فيديو تجريبي بدقة عالية من يوتيوب',
                imageUrl: _stillUrl,
                tags: ['10:34'],
                cellWidth: 184,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() => Future.delayed(const Duration(seconds: 1)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/poster_card_real_still.png'),
    );
  });
}
