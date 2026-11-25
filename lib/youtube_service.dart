import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'models.dart';
import 'playlist_fetcher.dart';

/// Thin wrapper over youtube_explode_dart for the library flows.
class YoutubeService {
  YoutubeService() : _yt = YoutubeExplode();

  final YoutubeExplode _yt;

  /// Fetches a playlist's real metadata and video list from YouTube.
  /// Throws [FormatException] when the link is not a playlist link.
  Future<LibraryPlaylist> fetchPlaylist(
    String input, {
    String? nickname,
    void Function(int fetched)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final parsed = PlaylistId.parsePlaylistId(input.trim());
    if (parsed == null) {
      throw const FormatException('مش قادر أفهم الرابط ده كقائمة تشغيل يوتيوب');
    }
    final playlist = await _yt.playlists.get(PlaylistId(parsed));
    // youtube_explode's getVideos yields nothing since YouTube moved playlist
    // pages to lockupViewModel (verified 2026-11-25); ZMIX fetches the list
    // itself from the same public endpoint the website uses.
    final fetcher = PlaylistFetcher();
    final FetchResult result;
    try {
      result = await fetcher.fetchVideos(
        playlist.id.value,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
    } finally {
      fetcher.close();
    }
    final videos = result.videos;
    // Honest count handling: even a fully paginated import can come back
    // short of YouTube's declared videoCount (deleted/private/duplicated
    // entries are counted in the header but never served). Surface that as
    // its own state instead of implying the library holds every video.
    final declared = playlist.videoCount;
    var complete = result.complete;
    String? note = result.stopReason;
    if (result.complete &&
        declared != null &&
        videos.length < declared &&
        (declared - videos.length) > 2) {
      complete = false;
      note = 'short_of_declared';
    }
    final name = (nickname != null && nickname.trim().isNotEmpty)
        ? nickname.trim()
        : playlist.title;
    return LibraryPlaylist(
      id: playlist.id.value,
      name: name,
      url: playlist.url,
      author: playlist.author,
      thumbUrl: videos.isNotEmpty
          ? videos.first.thumbUrl
          : playlist.thumbnails.highResUrl,
      videos: videos,
      addedAt: DateTime.now(),
      importComplete: complete,
      totalCountHint: playlist.videoCount,
      importNote: note,
    );
  }

  /// Resolves a playable muxed stream URL for a video.
  Future<({String url, String quality})> resolvePlayable(String videoId) async {
    final manifest = await _yt.videos.streamsClient.getManifest(VideoId(videoId));
    if (manifest.muxed.isEmpty) {
      throw const FormatException('مفيش صيغة تشغيل مدمجة متاحة للفيديو ده');
    }
    final stream = manifest.muxed.withHighestBitrate();
    return (url: stream.url.toString(), quality: _qualityLabel(stream.videoQuality.name));
  }

  /// 'medium360' -> '360p'
  static String _qualityLabel(String raw) {
    final match = RegExp(r'(\d+)').firstMatch(raw);
    return match == null ? raw : '${match.group(1)}p';
  }

  void close() => _yt.close();
}
