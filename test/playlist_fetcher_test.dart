import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zmix/models.dart';
import 'package:zmix/playlist_fetcher.dart';

/// Builds one InnerTube browse page with lockupViewModel video entries.
/// [ids] are titled entries; [untitledIds] are served with metadata but no
/// title, the way YouTube serves deleted/private videos in its own
/// "show unavailable videos" view.
String _page(List<String> ids, {String? nextToken, List<String> untitledIds = const []}) {
  Map<String, dynamic> lockup(String id, {bool untitled = false}) => {
        'lockupViewModel': {
          'contentId': id,
          'contentType': 'LOCKUP_CONTENT_TYPE_VIDEO',
          'metadata': {
            'lockupMetadataViewModel': {
              'title': {'content': untitled ? '' : 'Video $id'}
            }
          },
          'contentImage': {
            'thumbnailViewModel': {
              'overlays': [
                {
                  'thumbnailBottomOverlayViewModel': {
                    'badges': [
                      {
                        'thumbnailBadgeViewModel': {'text': '10:00'}
                      }
                    ]
                  }
                }
              ]
            }
          }
        }
      };
  final map = <String, dynamic>{
    'contents': [
      ...ids.map((id) => lockup(id)),
      ...untitledIds.map((id) => lockup(id, untitled: true)),
    ],
  };
  if (nextToken != null) {
    map['onResponseReceivedActions'] = [
      {
        'continuationCommand': {'token': nextToken}
      }
    ];
  }
  return jsonEncode(map);
}

void main() {
  test('imports 2000 videos across 20 continuation pages, complete', () async {
    String id(int n) => 'v${n.toString().padLeft(10, '0')}'; // 11 chars
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      int start;
      if (body.containsKey('continuation')) {
        start = int.parse((body['continuation'] as String).substring(4));
      } else {
        expect(body['browseId'], 'VLfixture');
        start = 0;
      }
      final ids = List.generate(100, (i) => id(start + i));
      final next = start + 100;
      return http.Response(
          _page(ids, nextToken: next < 2000 ? 'tok-$next' : null), 200);
    });
    final fetcher = PlaylistFetcher(client: client);
    final progress = <int>[];
    final result = await fetcher.fetchVideos(
      'fixture',
      onProgress: progress.add,
    );
    expect(result.complete, isTrue);
    expect(result.videos.length, 2000);
    expect(result.videos.first.id, id(0));
    expect(result.videos.last.id, id(1999));
    expect(result.videos.first.title, 'Video ${id(0)}');
    expect(result.videos.first.durationSeconds, 600);
    expect(progress.last, 2000);
    fetcher.close();
  });

  test('cancel mid-pagination keeps partial and marks incomplete', () async {
    String id(int n) => 'v${n.toString().padLeft(10, '0')}';
    var pages = 0;
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final start =
          body.containsKey('continuation') ? int.parse((body['continuation'] as String).substring(4)) : 0;
      pages++;
      final ids = List.generate(100, (i) => id(start + i));
      return http.Response(_page(ids, nextToken: 'tok-${start + 100}'), 200);
    });
    final fetcher = PlaylistFetcher(client: client);
    final result = await fetcher.fetchVideos(
      'fixture',
      isCancelled: () => pages >= 3,
    );
    expect(result.complete, isFalse);
    expect(result.stopReason, 'cancelled');
    expect(result.videos.length, 300);
    fetcher.close();
  });

  test('network failure after first page keeps partial, marks incomplete',
      () async {
    String id(int n) => 'v${n.toString().padLeft(10, '0')}';
    var pages = 0;
    final client = MockClient((request) async {
      pages++;
      if (pages == 1) {
        return http.Response(
            _page(List.generate(100, (i) => id(i)), nextToken: 'tok-100'), 200);
      }
      return http.Response('server error', 500);
    });
    final fetcher = PlaylistFetcher(client: client);
    final result = await fetcher.fetchVideos('fixture');
    expect(result.complete, isFalse);
    expect(result.stopReason, 'network');
    expect(result.videos.length, 100);
    fetcher.close();
  });

  test('first-page failure throws (nothing usable to show)', () async {
    final client = MockClient((request) async => http.Response('down', 503));
    final fetcher = PlaylistFetcher(client: client);
    expect(() => fetcher.fetchVideos('fixture'), throwsA(anything));
    fetcher.close();
  });

  test('classifies hidden entries from the show-unavailable view', () async {
    // Phase A (default view): 3 titled entries, one duplicated position.
    // Phase B (params = show unavailable): same 3 + a titled hidden entry +
    // an untitled hidden entry, order and duplicates preserved.
    String id(String n) => n.padRight(11, 'x');
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body.containsKey('params')) {
        expect(body['params'], PlaylistFetcher.showUnavailableParams);
        return http.Response(
            _page([id('a'), id('b'), id('a'), id('hidden1')],
                untitledIds: [id('gone1')]),
            200);
      }
      return http.Response(_page([id('a'), id('b'), id('a')]), 200);
    });
    final fetcher = PlaylistFetcher(client: client);
    final result = await fetcher.fetchVideos('fixture');
    expect(result.complete, isTrue);
    expect(result.videos.map((v) => v.id).toList(),
        [id('a'), id('b'), id('a'), id('hidden1'), id('gone1')]);
    expect(result.videos.map((v) => v.visibility).toList(),
        ['visible', 'visible', 'visible', 'hiddenTitled', 'hiddenUntitled']);
    expect(result.hiddenTitled, 1);
    expect(result.hiddenUntitled, 1);
    fetcher.close();
  });

  test('show-unavailable pass failure falls back to the default import',
      () async {
    String id(String n) => n.padRight(11, 'x');
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body.containsKey('params')) {
        return http.Response('server error', 500);
      }
      return http.Response(_page([id('a'), id('b')]), 200);
    });
    final fetcher = PlaylistFetcher(client: client);
    final result = await fetcher.fetchVideos('fixture');
    expect(result.complete, isFalse);
    expect(result.stopReason, 'network');
    expect(result.videos.length, 2);
    expect(result.videos.every((v) => v.visibility == 'visible'), isTrue);
    fetcher.close();
  });

  test('model round-trip keeps visibility and hidden counts', () {
    // through LibraryPlaylist JSON persistence
    final video = LibraryVideo(
        id: 'abcdefghijk', title: '', thumbUrl: '', visibility: 'hiddenUntitled');
    expect(video.isSourceUntitled, isTrue);
    final back = LibraryVideo.fromJson(video.toJson());
    expect(back.visibility, 'hiddenUntitled');
    expect(back.isSourceUntitled, isTrue);
    final legacy = LibraryVideo.fromJson({
      'id': 'abcdefghijk',
      'title': 't',
      'thumbUrl': '',
    });
    expect(legacy.visibility, 'visible');
  });
}
