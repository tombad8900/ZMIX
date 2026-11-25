import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Outcome of a paginated playlist fetch. [complete] is false when fetching
/// stopped before the last page (cancelled, network failure mid-way, or the
/// protective ceiling); the caller must surface that state, never present a
/// partial import as whole.
class FetchResult {
  FetchResult({
    required this.videos,
    required this.complete,
    this.stopReason,
  });

  final List<LibraryVideo> videos;
  final bool complete;

  /// 'cancelled' | 'network' | 'ceiling' when [complete] is false.
  final String? stopReason;
}

/// ZMIX's own playlist-video fetcher.
///
/// Why this exists: YouTube moved playlist pages (HTML and InnerTube browse)
/// from `playlistVideoRenderer` to `lockupViewModel` entries, which made the
/// upstream Dart extractor yield zero videos (verified 2026-11-25 against
/// several playlists, including YouTube-owned ones). This client talks to the
/// same public InnerTube `browse` endpoint the website itself uses, with no
/// challenge bypassing: it reads exactly what a logged-out browser receives.
class PlaylistFetcher {
  PlaylistFetcher({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static final Uri _browseUrl =
      Uri.https('www.youtube.com', '/youtubei/v1/browse', {'prettyPrint': 'false'});
  static const Map<String, String> _headers = {
    'content-type': 'application/json',
    'user-agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  };

  static const Map<String, dynamic> _context = {
    'client': {'clientName': 'WEB', 'clientVersion': '2.20250219.01.00'},
  };

  /// Protective ceiling only (runaway-page guard), not a UX cap: a playlist
  /// of 2,000+ videos imports in full.
  static const int maxVideos = 20000;

  /// Fetches every video of [playlistId], following continuation pages.
  ///
  /// [onProgress] is called after each page with the cumulative count.
  /// [isCancelled] is polled between pages; when it returns true the fetch
  /// stops and the result is marked incomplete ('cancelled'). A failure after
  /// the first page likewise returns what was fetched, marked incomplete
  /// ('network'); a failure on the first page throws, since there is nothing
  /// usable to show.
  Future<FetchResult> fetchVideos(
    String playlistId, {
    void Function(int fetched)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final videos = <LibraryVideo>[];
    // No deduplication: repeated videos are real playlist positions
    // (verified on a live playlist - same video at positions 23/35/50).
    var firstPage = true;
    Map<String, dynamic> body = {
      'context': _context,
      'browseId': 'VL$playlistId',
    };
    while (true) {
      if (isCancelled?.call() ?? false) {
        return FetchResult(
            videos: videos, complete: false, stopReason: 'cancelled');
      }
      http.Response response;
      dynamic decoded;
      try {
        response = await _client
            .post(_browseUrl, headers: _headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) {
          throw StateError('browse HTTP ${response.statusCode}');
        }
        decoded = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        if (firstPage) rethrow;
        return FetchResult(
            videos: videos, complete: false, stopReason: 'network');
      }
      firstPage = false;
      final lockups = <Map<String, dynamic>>[];
      _findAll(decoded, 'lockupViewModel', lockups);
      var newOnThisPage = 0;
      for (final lockup in lockups) {
        if (lockup['contentType'] != 'LOCKUP_CONTENT_TYPE_VIDEO') continue;
        final id = lockup['contentId'] as String?;
        if (id == null || id.length != 11) continue;
        final video = _parseLockup(lockup, id);
        if (video != null) {
          videos.add(video);
          newOnThisPage++;
        }
      }
      onProgress?.call(videos.length);
      if (videos.length >= maxVideos) {
        return FetchResult(
            videos: videos, complete: false, stopReason: 'ceiling');
      }
      final token = _findContinuation(decoded);
      if (token == null || newOnThisPage == 0) {
        return FetchResult(videos: videos, complete: true);
      }
      body = {'context': _context, 'continuation': token};
      // Gentle pacing between pages, like a user scrolling.
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }

  LibraryVideo? _parseLockup(Map<String, dynamic> lockup, String id) {
    try {
      final metadata =
          lockup['metadata']?['lockupMetadataViewModel'] as Map<String, dynamic>?;
      final title = metadata?['title']?['content'] as String?;
      if (title == null || title.isEmpty) return null;
      final overlays = lockup['contentImage']?['thumbnailViewModel']?['overlays']
          as List<dynamic>?;
      int? durationSeconds;
      if (overlays != null) {
        for (final overlay in overlays) {
          final badges = overlay['thumbnailBottomOverlayViewModel']?['badges']
              as List<dynamic>?;
          final text = badges?.firstOrNull?['thumbnailBadgeViewModel']?['text']
              as String?;
          final parsed = _parseDuration(text);
          if (parsed != null) {
            durationSeconds = parsed;
            break;
          }
        }
      }
      return LibraryVideo(
        id: id,
        title: title,
        thumbUrl: 'https://img.youtube.com/vi/$id/hqdefault.jpg',
        durationSeconds: durationSeconds,
      );
    } catch (_) {
      return null;
    }
  }

  /// '1:16:10' or '45:03' or '3:22' -> seconds
  static int? _parseDuration(String? text) {
    if (text == null) return null;
    final parts = text.split(':');
    if (parts.length < 2 || parts.length > 3) return null;
    final values = <int>[];
    for (final p in parts) {
      final v = int.tryParse(p.trim());
      if (v == null) return null;
      values.add(v);
    }
    var seconds = 0;
    for (final v in values) {
      seconds = seconds * 60 + v;
    }
    return seconds;
  }

  /// The first page can carry more than one continuation token; only the
  /// first one paginates the video list (verified live: the second token
  /// returns an empty payload). Take the first.
  String? _findContinuation(dynamic node) {
    final commands = <Map<String, dynamic>>[];
    _findAll(node, 'continuationCommand', commands);
    for (final command in commands) {
      final token = command['token'] as String?;
      if (token != null && token.isNotEmpty) return token;
    }
    return null;
  }

  void _findAll(dynamic node, String key, List<Map<String, dynamic>> hits) {
    if (node is Map<String, dynamic>) {
      node.forEach((k, v) {
        if (k == key && v is Map<String, dynamic>) hits.add(v);
        _findAll(v, key, hits);
      });
    } else if (node is List<dynamic>) {
      for (final item in node) {
        _findAll(item, key, hits);
      }
    }
  }

  void close() => _client.close();
}
