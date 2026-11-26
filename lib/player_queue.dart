import 'grouper.dart';
import 'models.dart';

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
