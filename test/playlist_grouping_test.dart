import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zmix/models.dart';
import 'package:zmix/playlist_page.dart';
import 'package:zmix/storage.dart';

import 'golden_fonts.dart';

/// Every title below is invented fixture content (no real playlist data),
/// chosen to exercise: single-season Arabic series, multi-season series,
/// ungrouped films, one very long Arabic title, and one ambiguous
/// multi-marker title that must stay ungrouped.
LibraryPlaylist _fixturePlaylist() {
  LibraryVideo v(String id, String title, [int? secs]) =>
      LibraryVideo(id: id, title: title, thumbUrl: '', durationSeconds: secs);
  return LibraryPlaylist(
    id: 'fixture1',
    name: 'مكتبة تجريبية (بيانات وهمية)',
    url: 'https://example.invalid/playlist',
    author: 'قناة تجريبية',
    thumbUrl: '',
    addedAt: DateTime(2026, 1, 1),
    videos: [
      v('f1', 'فيلم الأرض 1969 - كامل بدقة عالية', 7200),
      v('o1', 'المؤسس عثمان - الحلقة 1', 3600),
      v('o2', 'المؤسس عثمان - الحلقة 2', 3610),
      v('o3', 'المؤسس عثمان - الحلقة 3', 3620),
      v('e1', 'قيامة أرطغرل موسم 1 - الحلقة 4', 3500),
      v('e2', 'قيامة أرطغرل موسم 1 - الحلقة 5', 3505),
      v('e3', 'قيامة أرطغرل موسم 2 - الحلقة 1', 3510),
      v(
        'f2',
        'فيلم الإرهاب والكباب بطولة عادل إمام - نسخة أصلية كاملة بجودة عالية جداً بدون حذف أي مشهد',
        8100,
      ),
      v('a1', 'الحلقة 1 الجزء 2 - مشهد تمثيلي قصير', 900),
    ],
  );
}

void main() {
  setUpAll(loadGoldenFonts);

  // Logical 390x844 portrait phone surface; physicalSize is in physical
  // pixels, so double it at devicePixelRatio 2.
  const surface = Size(780, 1688);

  Future<void> pump(WidgetTester tester, [Size size = surface]) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      goldenHost(PlaylistPage(playlist: _fixturePlaylist(), store: LibraryStore())),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('grouping UI: series sections top', (tester) async {
    await pump(tester);
    // SliverList only builds visible rows; off-screen sections are asserted
    // after scrolling in the second test.
    expect(find.text('المؤسس عثمان · 3 حلقة'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/playlist_grouping_top.png'),
    );
  });

  testWidgets('grouping UI: all sections, tall capture', (tester) async {
    // Taller-than-phone surface so every sliver row is built in one tree:
    // assertions cover the sections a phone viewport only shows after scroll.
    await pump(tester, const Size(780, 2500)); // logical 390x1250
    expect(find.text('المؤسس عثمان · 3 حلقة'), findsOneWidget);
    expect(find.text('قيامة أرطغرل · 3 حلقة'), findsOneWidget);
    expect(find.text('موسم 1'), findsOneWidget);
    expect(find.text('موسم 2'), findsOneWidget);
    // Ambiguous multi-marker title stays ungrouped under the films section.
    expect(find.text('فيديوهات · 3'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/playlist_grouping_scrolled.png'),
    );
  });
}
