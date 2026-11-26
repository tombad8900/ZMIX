// Titles are invented fixtures.
import 'package:flutter_test/flutter_test.dart';
import 'package:zmix/models.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:zmix/player/player_episodes_panel.dart';
import 'package:zmix/player_queue.dart';

import 'golden_fonts.dart';

LibraryVideo v(String id, String title) =>
    LibraryVideo(id: id, title: title, thumbUrl: '');

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadGoldenFonts();
  });
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

  group('series boundaries and conservative cases', () {
    test('seasons are walked in order across the boundary (S1 end -> S2 start)', () {
      final pl = [
        v('s2e1', 'مسلسل النهر الموسم 2 الحلقة 1'),
        v('s1e2', 'مسلسل النهر الموسم 1 الحلقة 2'),
        v('s1e1', 'مسلسل النهر الموسم 1 الحلقة 1'),
        v('s2e2', 'مسلسل النهر الموسم 2 الحلقة 2'),
      ];
      final q = playerQueueFor(pl, pl[1]);
      expect([for (final x in q.videos) x.id], ['s1e1', 's1e2', 's2e1', 's2e2']);
      expect(q.index, 1);
    });

    test('two series stay separate: the queue is the selected series only', () {
      final pl = [
        v('a1', 'مسلسل النهر الحلقة 1'),
        v('b1', 'مسلسل الجبل الحلقة 1'),
        v('a2', 'مسلسل النهر الحلقة 2'),
        v('b2', 'مسلسل الجبل الحلقة 2'),
      ];
      final q = playerQueueFor(pl, pl[3]);
      expect([for (final x in q.videos) x.id], ['b1', 'b2']);
      expect(q.index, 1);
    });

    test('duplicate episode numbers keep playlist order (deterministic)', () {
      final pl = [
        v('d1', 'مسلسل الريح الحلقة 2'),
        v('d0', 'مسلسل الريح الحلقة 1'),
        v('d2', 'مسلسل الريح الحلقة 2'),
        v('d3', 'مسلسل الريح الحلقة 2'),
      ];
      final q = playerQueueFor(pl, pl[0]);
      expect([for (final x in q.videos) x.id], ['d0', 'd1', 'd2', 'd3']);
    });

    test('the same id listed twice: first occurrence is selected, nothing crashes', () {
      final pl = [
        v('z', 'مسلسل الشمس الحلقة 2'),
        v('y', 'مسلسل الشمس الحلقة 1'),
        v('z', 'مسلسل الشمس الحلقة 2'),
      ];
      final q = playerQueueFor(pl, pl[2]);
      expect(q.videos[q.index].id, 'z');
    });

    test('a very large playlist keeps full order', () {
      final pl = [
        for (var i = 2000; i >= 1; i--) v('big$i', 'مسلسل الطويل الحلقة $i'),
      ];
      final q = playerQueueFor(pl, pl.first);
      expect(q.videos.length, 2000);
      expect(q.videos.first.id, 'big1');
      expect(q.videos[q.index].id, 'big2000');
    });
  });

  group('panel and stale-result guard', () {
    test('panel rows come from the same queue, row i = queue[i]', () {
      final q = playerQueueFor(playlist, playlist[1]);
      final rows = panelEpisodesFor(q.videos);
      expect(rows.length, q.videos.length);
      for (var i = 0; i < rows.length; i++) {
        expect(rows[i].title, q.videos[i].title);
        expect(rows[i].number, i + 1);
      }
    });

    test('a result for the previous episode is stale after next/prev', () {
      expect(isStaleForCurrent('e1', 'e2'), isTrue);
      expect(isStaleForCurrent('e2', 'e2'), isFalse);
    });
  });

  testWidgets('RENDERED episodes panel shows the series in episode order, current marked',
      (tester) async {
    final q = playerQueueFor(playlist, playlist[1]); // playing episode 3
    tester.view.physicalSize = const Size(1600, 720);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: goldenHost(Scaffold(
        body: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: ZmixEpisodesPanel(
            episodes: panelEpisodesFor(q.videos),
            currentIndex: q.index,
            onSelect: (_) {},
          ),
        ),
      )),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    final order = [
      for (final t in ['الحلقة 1', 'الحلقة 2', 'الحلقة 3'])
        tester.getTopLeft(find.textContaining(t).first).dy,
    ];
    expect(order[0] < order[1] && order[1] < order[2], isTrue,
        reason: 'rows must appear top-to-bottom in episode order: $order');
    final out = Platform.environment['ZMIX_EVIDENCE_DIR'];
    if (out != null) {
      await tester.runAsync(() async {
        final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final img = await b.toImage(pixelRatio: 1.0);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$out/episodes_panel.png').writeAsBytesSync(data!.buffer.asUint8List());
      });
    }
  });
}
