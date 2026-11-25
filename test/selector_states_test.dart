import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmix/player_chrome.dart';
import 'package:zmix/ui/poster_card.dart';

void main() {
  testWidgets('quality sheet lists qualities and picks the tapped one',
      (tester) async {
    String? picked;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              picked = await showModalBottomSheet<String>(
                context: context,
                builder: (sheetContext) => QualityListSheet(
                  qualities: const ['1080p', '720p', '360p'],
                  activeQuality: '720p',
                  onPick: (q) => Navigator.of(sheetContext).pop(q),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('جودة التشغيل'), findsOneWidget);
    expect(find.text('1080p'), findsOneWidget);
    expect(find.text('720p'), findsOneWidget);
    expect(find.text('360p'), findsOneWidget);
    // Active row carries the accent check mark; exactly one.
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await tester.tap(find.text('360p'));
    await tester.pumpAndSettle();
    expect(picked, '360p');
  });

  test('fit selector cycles contain -> cover -> fill -> contain', () {
    expect(kPlayerFits.map((f) => f.$1).toList(),
        [BoxFit.contain, BoxFit.cover, BoxFit.fill]);
    var index = 0;
    final seen = <BoxFit>[];
    for (var i = 0; i < 4; i++) {
      seen.add(kPlayerFits[index].$1);
      index = nextFitIndex(index);
    }
    expect(seen, [
      BoxFit.contain,
      BoxFit.cover,
      BoxFit.fill,
      BoxFit.contain,
    ]);
  });

  testWidgets('poster grid columns match Zangetsu responsive math',
      (tester) async {
    Future<int> columnsAt(double width) async {
      int? columns;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: Size(width, 800)),
          child: Builder(
            builder: (context) {
              columns = posterGridColumns(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return columns!;
    }

    // Upstream _responsiveColumns(desired=3): 3 columns from phone width up
    // (desired caps the count), fewer only when the screen is too narrow.
    expect(await columnsAt(390), 3);
    expect(await columnsAt(800), 3);
    expect(await columnsAt(2000), 3);
    expect(await columnsAt(320), 2);
  });

  test('poster cell height matches upstream wide-card math', () {
    // Upstream posterCellHeight: art = w*9/16, title = 8 + 2*ceil(13*1.3).
    expect(posterCellHeight(184, wide: true), 146.0); // ceil(103.5 + 8 + 34)
  });
}
