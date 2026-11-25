import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zmix/player_chrome.dart';

import 'golden_fonts.dart';

PlayerChrome _chrome({
  int seekDelta = 0,
  bool hudVisible = false,
  bool boosting = false,
  String? errorText,
  bool controlsVisible = true,
}) {
  return PlayerChrome(
    title: 'فيلم الاختبار الطويل 2024',
    qualityLabel: '360p',
    position: const Duration(minutes: 1, seconds: 23),
    duration: const Duration(minutes: 45, seconds: 10),
    playing: true,
    rate: 1.0,
    controlsVisible: controlsVisible,
    seekDelta: seekDelta,
    seekForward: true,
    hudVisible: hudVisible,
    hudIsBrightness: false,
    hudValue: 0.65,
    boosting: boosting,
    errorText: errorText,
    onBack: () {},
    onPlayPause: () {},
    onCycleSpeed: () {},
    onScrubChanged: (_) {},
    onScrubEnd: (_) {},
  );
}

void main() {
  setUpAll(loadGoldenFonts);

  // Logical 844x390 landscape phone surface; physicalSize is in physical
  // pixels, so double it at devicePixelRatio 2.
  const surface = Size(1688, 780);

  Future<void> pump(WidgetTester tester, PlayerChrome chrome) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      goldenHost(Scaffold(backgroundColor: Colors.black, body: chrome)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('player chrome controls visible', (tester) async {
    await pump(tester, _chrome());
    expect(find.text('1:23'), findsOneWidget);
    expect(find.text('45:10'), findsOneWidget);
    expect(find.text('360p'), findsOneWidget);
    expect(find.text('1.0x'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/player_chrome_controls.png'),
    );
  });

  testWidgets('player chrome seek indicator and hud and boost', (tester) async {
    await pump(tester, _chrome(seekDelta: 20, hudVisible: true, boosting: true));
    expect(find.text('20 ث'), findsWidgets);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/player_chrome_seek_hud_boost.png'),
    );
  });

  testWidgets('player chrome error banner above bottom controls', (tester) async {
    await pump(tester, _chrome(errorText: 'تعذر حل رابط التشغيل'));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/player_chrome_error.png'),
    );
  });

  testWidgets('fmt renders h:mm:ss and m:ss', (tester) async {
    expect(PlayerChrome.fmt(const Duration(minutes: 1, seconds: 23)), '1:23');
    expect(
      PlayerChrome.fmt(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
    expect(PlayerChrome.fmt(Duration.zero), '0:00');
  });
}
