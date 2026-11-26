import 'package:flutter_test/flutter_test.dart';
import 'package:zmix/models.dart';
import 'package:zmix/player_queue.dart';

LibraryVideo v(String id, String title) =>
    LibraryVideo(id: id, title: title, thumbUrl: '');

void main() {
  test('Arabic-Indic episode numbers sort numerically in the player queue', () {
    final playlist = [
      v('episode-5', 'مسلسل المدار الحلقة ٥'),
      v('episode-11', 'مسلسل المدار الحلقة ١١'),
      v('episode-2', 'مسلسل المدار الحلقة ٢'),
    ];

    final queue = playerQueueFor(playlist, playlist.first);

    expect(
      [for (final episode in queue.videos) episode.id],
      ['episode-2', 'episode-5', 'episode-11'],
    );
    expect(queue.index, 1);
  });

  test('seasonless episodes precede explicitly numbered seasons', () {
    final playlist = [
      v('season-2-episode-1', 'مسلسل النور موسم ٢ الحلقة ١'),
      v('no-season-episode-2', 'مسلسل النور الحلقة ٢'),
      v('season-1-episode-1', 'مسلسل النور موسم ١ الحلقة ١'),
      v('no-season-episode-1', 'مسلسل النور الحلقة ١'),
    ];

    final queue = playerQueueFor(playlist, playlist.first);

    expect(
      [for (final episode in queue.videos) episode.id],
      [
        'no-season-episode-1',
        'no-season-episode-2',
        'season-1-episode-1',
        'season-2-episode-1',
      ],
    );
    expect(queue.index, 3);
  });

  test('a title with episode and part markers stays out of inferred series queue', () {
    final playlist = [
      v('episode-2', 'مسلسل الضي الحلقة ٢'),
      v('ambiguous', 'مسلسل الضي الحلقة ٣ الجزء ١'),
      v('episode-1', 'مسلسل الضي الحلقة ١'),
    ];

    final queue = playerQueueFor(playlist, playlist[1]);

    // A title with two different markers is ambiguous under the grouper
    // contract. Keep the original playlist order instead of guessing.
    expect(queue.videos, same(playlist));
    expect(queue.index, 1);
  });
}
