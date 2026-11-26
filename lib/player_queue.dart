import 'grouper.dart';
import 'models.dart';
import 'player/player_episodes_panel.dart';

/// The list the player's episodes panel and next/previous walk, plus where
/// the playing video sits in it.
class PlayerQueue {
  const PlayerQueue(this.videos, this.index);
  final List<LibraryVideo> videos;

  /// Index of the playing video in [videos], or -1 when it is not there.
  final int index;
}

/// Picks the queue for starting playback of [current] from [playlist].
///
/// - When [current] belongs to a series the title grouper recognized (clear
///   episode/part markers only), the queue is that series in season/episode
///   order, so the panel, next and previous agree with the order the library
///   shows. Nothing is invented: only [groupPlaylist]'s own decision is used.
/// - Otherwise (movie, unclear title, lone episode) the queue is the original
///   playlist order, exactly as before.
PlayerQueue playerQueueFor(List<LibraryVideo> playlist, LibraryVideo current) {
  final grouped = groupPlaylist(playlist);
  for (final s in grouped.series) {
    final eps = s.episodes;
    final i = eps.indexWhere((v) => v.id == current.id);
    if (i >= 0) return PlayerQueue(eps, i);
  }
  return PlayerQueue(playlist, playlist.indexWhere((v) => v.id == current.id));
}

/// The id of the video that is playing now. Once the user moves between
/// episodes, the queue position is the truth; the id the page was created
/// with is only a fallback when the queue cannot name the video. (Preferring
/// the creation-time id after navigation made quality and subtitle loading
/// target the FIRST episode.)
String? currentVideoId({
  required String? initialVideoId,
  required List<LibraryVideo>? queue,
  required int index,
}) {
  if (queue != null && index >= 0 && index < queue.length) {
    return queue[index].id;
  }
  return initialVideoId;
}

/// The episodes panel's rows, built from the SAME queue the player walks with
/// next/previous (never from the raw playlist). Row i is queue[i].
List<ZmixPanelEpisode> panelEpisodesFor(List<LibraryVideo> queue) => [
      for (var i = 0; i < queue.length; i++)
        ZmixPanelEpisode(
          number: i + 1,
          // Untitled (source-hidden) entries keep the library's neutral
          // label: no title is not evidence of unavailability.
          title: queue[i].isSourceUntitled ? 'بلا عنوان' : queue[i].title,
          thumbnail: queue[i].thumbUrl.isNotEmpty ? queue[i].thumbUrl : null,
          runtimeSeconds: queue[i].durationSeconds,
        ),
    ];

/// True when an async result (qualities, captions) that was requested for
/// [requestedId] must be dropped because the player has since moved on.
bool isStaleForCurrent(String requestedId, String? currentId) =>
    requestedId != currentId;

/// Runs [fetch] for [requestedId] and returns its result only if the page is
/// still mounted and still playing [requestedId] when it completes; otherwise
/// null (result dropped). [currentId] is read AFTER the await, so an episode
/// switch that happens while the fetch is in flight is caught. Errors from
/// [fetch] propagate to the caller. This is the single place the page's async
/// loaders (qualities, captions) decide "still relevant".
Future<T?> fetchIfStillCurrent<T>({
  required String requestedId,
  required String? Function() currentId,
  required bool Function() isMounted,
  required Future<T> Function() fetch,
}) async {
  final result = await fetch();
  if (!isMounted()) return null;
  if (isStaleForCurrent(requestedId, currentId())) return null;
  return result;
}
