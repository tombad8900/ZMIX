// Titles are invented fixtures.
import 'package:flutter_test/flutter_test.dart';
import 'package:zmix/models.dart';
import 'package:zmix/player_queue.dart';

LibraryVideo v(String id, String title) =>
    LibraryVideo(id: id, title: title, thumbUrl: '');

void main() {
  // Playlist order is scrambled on purpose.
  final playlist = [
    v('m1', 'فيلم الأرض 1969 - كامل'),
    v('e3', 'مسلسل الواحة الحلقة 3'),
    v('e1', 'مسلسل الواحة الحلقة 1'),
    v('x1', 'مقطع بدون أي علامة'),
    v('e2', 'مسلسل الواحة الحلقة 2'),
  ];

  test('a recognized series plays in episode order, not playlist order', () {
    final q = playerQueueFor(playlist, playlist[1]); // episode 3
    expect([for (final x in q.videos) x.id], ['e1', 'e2', 'e3']);
    expect(q.index, 2);
  });

  test('next/previous walk the same order the panel shows', () {
    final q = playerQueueFor(playlist, playlist[2]); // episode 1
    expect(q.index, 0);
    expect(q.videos[q.index + 1].id, 'e2');
    expect(q.videos[q.index + 2].id, 'e3');
  });

  test('a video with no clear marker keeps the original playlist order', () {
    final q = playerQueueFor(playlist, playlist[3]);
    expect(q.videos, same(playlist));
    expect(q.index, 3);
  });

  test('a movie stays in the original order too', () {
    final q = playerQueueFor(playlist, playlist[0]);
    expect(q.videos, same(playlist));
    expect(q.index, 0);
  });

  test('a lone episode is not a series: original order', () {
    final lone = [v('a', 'مسلسل الغريب الحلقة 4'), v('b', 'شيء آخر')];
    final q = playerQueueFor(lone, lone[0]);
    expect(q.videos, same(lone));
  });

  test('a video not in the playlist gives index -1', () {
    final q = playerQueueFor(playlist, v('zz', 'غير موجود'));
    expect(q.index, -1);
  });

  group('currentVideoId (episode-ID mismatch fix)', () {
    final queue = [v('e1', 't'), v('e2', 't'), v('e3', 't')];
    test('after navigating, the queue position wins over the creation-time id',
        () {
      expect(
          currentVideoId(initialVideoId: 'e1', queue: queue, index: 2), 'e3');
    });
    test('at start it is the same video', () {
      expect(
          currentVideoId(initialVideoId: 'e1', queue: queue, index: 0), 'e1');
    });
    test('falls back to the creation-time id when the queue cannot name it', () {
      expect(currentVideoId(initialVideoId: 'q', queue: queue, index: -1), 'q');
      expect(currentVideoId(initialVideoId: 'q', queue: null, index: 0), 'q');
      expect(currentVideoId(initialVideoId: null, queue: queue, index: 9), isNull);
    });
  });
}
