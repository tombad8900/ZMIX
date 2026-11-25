import 'dart:io';
import 'package:zmix/grouper.dart';
import 'package:zmix/playlist_fetcher.dart';

/// What would the grouper do with the user's real playlists?
Future<void> main(List<String> args) async {
  final fetcher = PlaylistFetcher();
  if (args.isEmpty) {
    stderr.writeln('usage: dart run this tool <playlistId>...');
    exitCode = 2;
    return;
  }
  for (final id in args) {
    final result = await fetcher.fetchVideos(id);
    final g = groupPlaylist(result.videos);
    print('$id: ${result.videos.length} entries -> '
        '${g.series.length} groups, ${g.ungrouped.length} ungrouped');
    for (final s in g.series.take(12)) {
      print('  GROUP "${s.title}" (${s.totalEpisodes} eps, '
          'seasons: ${s.sortedSeasons})');
      for (final e in s.episodes.take(3)) {
        print('     ${e.title.length > 60 ? e.title.substring(0, 60) : e.title}');
      }
    }
  }
  fetcher.close();
}
