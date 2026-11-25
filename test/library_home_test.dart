import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zmix/library_page.dart';
import 'package:zmix/models.dart';
import 'package:zmix/storage.dart';

import 'golden_fonts.dart';

/// Invented fixture content (no real playlist data): two playlists, enough
/// videos to prove the horizontal shelf scrolls past the viewport.
LibraryPlaylist _playlist(String id, String name, int count) {
  return LibraryPlaylist(
    id: id,
    name: name,
    url: 'https://example.invalid/$id',
    author: 'قناة تجريبية',
    thumbUrl: '',
    addedAt: DateTime(2026, 1, 1),
    videos: [
      for (var i = 1; i <= count; i++)
        LibraryVideo(
          id: '$id-$i',
          title: '$name - الحلقة $i',
          thumbUrl: '',
          durationSeconds: 2400 + i * 7,
        ),
    ],
  );
}

void main() {
  setUpAll(loadGoldenFonts);

  const surface = Size(780, 1688); // logical 390x844 at dpr 2

  testWidgets('home: per-playlist sections with horizontal poster shelves',
      (tester) async {
    final store = LibraryStore()
      ..playlists.addAll([
        _playlist('p1', 'المؤسس عثمان', 14),
        _playlist('p2', 'قيامة أرطغرل', 8),
      ]);
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(goldenHost(LibraryPage(store: store)));
    await tester.pump(const Duration(milliseconds: 100));

    // Section headers: name, count, chevron affordance.
    expect(find.text('المؤسس عثمان'), findsOneWidget);
    expect(find.text('14 فيديو'), findsOneWidget);
    expect(find.text('قيامة أرطغرل'), findsOneWidget);
    // Shelf cards carry titles below the art and duration badges.
    expect(find.text('المؤسس عثمان - الحلقة 1'), findsOneWidget);
    expect(find.text('40:07'), findsWidgets);
    // Old giant playlist cards are gone: no card shows the playlist thumb.
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/library_home_shelves.png'),
    );
  });
}
