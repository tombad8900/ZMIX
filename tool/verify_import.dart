// End-to-end production verification: real PlaylistFetcher against the user's
// real playlist, then a LibraryPlaylist JSON persistence round-trip.
import 'package:zmix/models.dart';
import 'package:zmix/playlist_fetcher.dart';

Future<void> main() async {
  final fetcher = PlaylistFetcher();
  final result = await fetcher.fetchVideos('PL00000000000000000000000000000000');
  fetcher.close();

  final playlist = LibraryPlaylist(
    id: 'PL00000000000000000000000000000000',
    name: 'verify',
    url: 'https://www.youtube.com/playlist?list=PL00000000000000000000000000000000',
    author: '',
    thumbUrl: '',
    videos: result.videos,
    addedAt: DateTime.now(),
    importComplete: result.complete,
    totalCountHint: 625,
    hiddenUntitledCount: result.hiddenUntitled,
    hiddenTitledCount: result.hiddenTitled,
  );
  // Persistence round-trip.
  final restored = LibraryPlaylist.fromJson(playlist.toJson());

  final visible = restored.videos.where((v) => v.visibility == 'visible').length;
  final untitled = restored.videos.where((v) => v.visibility == 'hiddenUntitled').length;
  final titledHidden = restored.videos.where((v) => v.visibility == 'hiddenTitled').length;
  final dups = restored.videos.length - restored.videos.map((v) => v.id).toSet().length;

  print('complete=${result.complete} stopReason=${result.stopReason}');
  print('fetched=${result.videos.length} restored=${restored.videos.length}');
  print('visible=$visible hiddenTitled=$titledHidden hiddenUntitled=$untitled');
  print('countsFields=${restored.hiddenTitledCount}/${restored.hiddenUntitledCount}');
  print('duplicatePositionsPreserved=$dups');
  print('first=${restored.videos.first.id} vis=${restored.videos.first.visibility}');
  print('last=${restored.videos.last.id} vis=${restored.videos.last.visibility}');
  // Spot-check order stability across the round-trip.
  var orderOk = true;
  for (var i = 0; i < result.videos.length; i++) {
    if (result.videos[i].id != restored.videos[i].id ||
        result.videos[i].visibility != restored.videos[i].visibility) {
      orderOk = false;
      print('ORDER MISMATCH at $i');
      break;
    }
  }
  print('orderRoundTrip=$orderOk');
}
