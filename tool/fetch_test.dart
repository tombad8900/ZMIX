import 'package:zmix/playlist_fetcher.dart';

Future<void> main() async {
  final fetcher = PlaylistFetcher();
  for (final id in ['PL11111111111111111111111111111111', 'PL00000000000000000000000000000000']) {
    try {
      final videos = await fetcher.fetchVideos(id);
      print('$id -> ${videos.length} videos');
      for (final v in videos.take(3)) {
        print('  ${v.id} | ${v.title.length > 50 ? v.title.substring(0, 50) : v.title} | ${v.durationLabel} | ${v.thumbUrl}');
      }
    } catch (e) {
      print('$id -> ERROR: $e');
    }
  }
  fetcher.close();
}
