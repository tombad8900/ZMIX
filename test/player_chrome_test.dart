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
  bool locked = false,
  bool hasPrev = true,
  bool hasNext = true,
}) {
  return PlayerChrome(
    title: 'فيلم الاختبار الطويل 2024',
    secondaryText: '360p',
    position: const Duration(minutes: 1, seconds: 23),
    duration: const Duration(minutes: 45, seconds: 10),
    playing: true,
    rate: 1.0,
    controlsVisible: controlsVisible,
    locked: locked,
    fitLabel: 'ملاءمة',
    hasPrev: hasPrev,
    hasNext: hasNext,
    seekDelta: seekDelta,
    seekForward: true,
    hudVisible: hudVisible,
    hudIsBrightness: false,
    hudValue: 0.65,
    boosting: boosting,
    errorText: errorText,
    onBack: () {},
    onPlayPause: () {},
    onPrev: () {},
    onNext: () {},
    onCycleSpeed: () {},
    onQuality: () {},
    onCycleFit: () {},
    onToggleLock: () {},
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
    // Render the chrome over a stand-in for video artwork (bright, busy
    // gradient) instead of a black frame: Zangetsu's scrims were designed
    // over real poster art, so legibility must be judged over that.
    await tester.pumpWidget(
      goldenHost(
        Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: [0.0, 0.45, 0.7, 1.0],
                colors: [
                  Color(0xFF3A5DA8),
                  Color(0xFFD9D2C4),
                  Color(0xFF8C3A2F),
                  Color(0xFF1B2B1E),
                ],
              ),
            ),
            child: chrome,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('player chrome: Zangetsu-layout controls', (tester) async {
    await pump(tester, _chrome());
    expect(find.text('1:23'), findsOneWidget);
    expect(find.text('45:10'), findsOneWidget);
    expect(find.text('360p'), findsOneWidget);
    expect(find.text('1.0x'), findsOneWidget);
    expect(find.text('ملاءمة'), findsOneWidget);
    expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
    expect(find.byIcon(Icons.hd_rounded), findsOneWidget);
    expect(find.byIcon(Icons.aspect_ratio_rounded), findsOneWidget);
    expect(find.byIcon(Icons.lock_open_rounded), findsOneWidget);
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

  testWidgets('player chrome locked: only the lock affordance', (tester) async {
    await pump(tester, _chrome(locked: true, controlsVisible: false));
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    expect(find.byIcon(Icons.hd_rounded), findsNothing);
    expect(find.byIcon(Icons.skip_next_rounded), findsNothing);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/player_chrome_locked.png'),
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
