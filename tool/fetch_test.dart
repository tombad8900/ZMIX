import 'package:zmix/playlist_fetcher.dart';

/// Manual probe: full live import of the user's two playlists.
/// Run with: dart run tool/fetch_test.dart
Future<void> main() async {
  final fetcher = PlaylistFetcher();
  for (final id in [
    'PL11111111111111111111111111111111',
    'PL00000000000000000000000000000000',
  ]) {
    try {
      final sw = Stopwatch()..start();
      final result = await fetcher.fetchVideos(id);
      sw.stop();
      final reason =
          result.stopReason != null ? ' reason=${result.stopReason}' : '';
      print(
          '$id -> ${result.videos.length} videos, complete=${result.complete}$reason in ${sw.elapsed.inSeconds}s');
      for (final v in result.videos.take(2)) {
        final short = v.title.length > 50 ? v.title.substring(0, 50) : v.title;
        print('  ${v.id} | $short | ${v.durationLabel}');
      }
      final last = result.videos.lastOrNull;
      if (last != null) {
        final short =
            last.title.length > 50 ? last.title.substring(0, 50) : last.title;
        print('  last: ${last.id} | $short');
      }
    } catch (e) {
      print('$id -> ERROR: $e');
    }
  }
  fetcher.close();
}
