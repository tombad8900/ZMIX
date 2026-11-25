import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zmix/player/player_controls_config.dart';
import 'package:zmix/player/player_controls_overlay.dart';
import 'package:zmix/player_hud.dart';

import 'golden_fonts.dart';

/// VM-test surface: a real media_kit Player needs native libmpv and cannot
/// exist in a widget test, so the ported overlay is exercised through the
/// same [ZmixPlayerSurface] seam the production page wires with
/// [MediaKitPlayerSurface].
class FakePlayerSurface implements ZmixPlayerSurface {
  FakePlayerSurface({
    ZmixPlayerSnapshot snapshot = const ZmixPlayerSnapshot(
      position: Duration(minutes: 1, seconds: 23),
      duration: Duration(minutes: 45, seconds: 10),
      playing: true,
      width: 1280,
      height: 720,
    ),
  }) : _snapshot = snapshot;

  ZmixPlayerSnapshot _snapshot;

  @override
  ZmixPlayerSnapshot get state => _snapshot;

  Stream<T> _once<T>(T v) => Stream.value(v).asBroadcastStream();

  @override
  Stream<Duration> get positionStream => _once(_snapshot.position);
  @override
  Stream<Duration> get bufferStream => _once(_snapshot.position);
  @override
  Stream<Duration> get durationStream => _once(_snapshot.duration);
  @override
  Stream<int?> get widthStream => _once(_snapshot.width);
  @override
  Stream<bool> get bufferingStream => _once(_snapshot.buffering);
  @override
  Stream<bool> get playingStream => _once(_snapshot.playing);
}

Widget _overlay({
  ZmixPlayerSurface? surface,
  bool visible = true,
  bool multiEpisode = true,
  bool hasNext = true,
  bool hasQualityChoices = true,
}) {
  return PlayerControlsOverlay(
    player: surface ?? FakePlayerSurface(),
    episodeNumber: 3,
    episodeTitle: 'فيلم الاختبار الطويل 2024',
    multiEpisode: multiEpisode,
    hasNext: hasNext,
    hasQualityChoices: hasQualityChoices,
    activeQualityLabel: '360p',
    onTogglePlay: () {},
    onSeek: (_) {},
    onNext: () {},
    onPrev: () {},
    showTitle: 'قائمة الاختبار',
    duration: const Duration(minutes: 45, seconds: 10),
    onDurationChanged: (_) {},
    onInteract: () {},
    onBack: () {},
    onSpeed: () {},
    onQuality: () {},
    onLock: () {},
    onRotate: null,
    portraitMode: false,
    barConfig: PlayerControlsConfig.defaults,
    onZoom: () {},
    zoomLabel: 'ملاءمة',
    showQuality: true,
    visible: visible,
  );
}

void main() {
  setUpAll(loadGoldenFonts);

  // Logical 844x390 landscape phone surface; physicalSize is in physical
  // pixels, so double it at devicePixelRatio 2.
  const surface = Size(1688, 780);

  Future<void> pump(WidgetTester tester, Widget child,
      {bool dark = false}) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    // Render over a stand-in for video artwork (bright, busy gradient)
    // instead of a black frame: the ported scrims were designed over real
    // frames, so legibility must be judged over that.
    await tester.pumpWidget(
      goldenHost(
        Scaffold(
          backgroundColor: dark ? Colors.black : null,
          body: Container(
            decoration: dark
                ? null
                : const BoxDecoration(
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
            child: child,
          ),
        ),
      ),
    );
    // Let the one-shot streams land, the first-frame latch flip, and the
    // fade-in finish.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('ported overlay: bars, transport, seek row', (tester) async {
    await pump(tester, _overlay());
    expect(find.textContaining('1:23'), findsWidgets);
    expect(find.textContaining('45:10'), findsWidgets);
    expect(find.textContaining('360p'), findsWidgets);
    expect(find.text('قائمة الاختبار'), findsOneWidget);
    expect(find.textContaining('فيلم الاختبار الطويل 2024'), findsOneWidget);
    expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
    expect(find.byIcon(Icons.high_quality_rounded), findsOneWidget);
    expect(find.byIcon(Icons.fit_screen_rounded), findsOneWidget);
    expect(find.byIcon(Icons.lock_open_rounded), findsOneWidget);
    expect(find.byIcon(Icons.speed_rounded), findsOneWidget);
    // 'more' drops out while its panel has no rows.
    expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/player_overlay_controls.png'),
    );
  });

  testWidgets('ported overlay + ZMIX extras: seek, hud, boost', (tester) async {
    await pump(
      tester,
      Stack(
        fit: StackFit.expand,
        children: [
          _overlay(),
          const SeekIndicator(delta: 20, forward: true),
          const PlayerHud(isBrightness: false, value: 0.65),
          const BoostBadge(),
        ],
      ),
    );
    expect(find.text('20 ث'), findsOneWidget);
    expect(find.text('2×'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/player_overlay_seek_hud_boost.png'),
    );
  });

  testWidgets('locked: only the lock affordance', (tester) async {
    await pump(tester, LockOverlay(onUnlock: () {}), dark: true);
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    expect(find.byIcon(Icons.high_quality_rounded), findsNothing);
    expect(find.byIcon(Icons.skip_next_rounded), findsNothing);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/player_overlay_locked.png'),
    );
  });

  testWidgets('error panel over the overlay', (tester) async {
    await pump(
      tester,
      Stack(
        fit: StackFit.expand,
        children: [
          _overlay(),
          PlayerErrorPanel(
            errorText: 'تعذر حل رابط التشغيل',
            onBack: () {},
            onRetry: () {},
          ),
        ],
      ),
    );
    expect(find.text('حاول تاني'), findsOneWidget);
    expect(find.text('إغلاق'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/player_overlay_error.png'),
    );
  });

  testWidgets('error panel on a dark frame', (tester) async {
    await pump(
      tester,
      PlayerErrorPanel(
        errorText: 'تعذر حل رابط التشغيل',
        onBack: () {},
        onRetry: () {},
      ),
      dark: true,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/player_overlay_error_dark.png'),
    );
  });

  testWidgets('single video: lone play button, no episode arrows',
      (tester) async {
    await pump(tester, _overlay(multiEpisode: false, hasNext: false));
    expect(find.byIcon(Icons.skip_previous_rounded), findsNothing);
    expect(find.byIcon(Icons.skip_next_rounded), findsNothing);
  });

  testWidgets('no second quality: quality button drops out', (tester) async {
    await pump(tester, _overlay(hasQualityChoices: false));
    expect(find.byIcon(Icons.high_quality_rounded), findsNothing);
  });

  testWidgets('hidden controls: bottom block slides away', (tester) async {
    await pump(tester, _overlay(visible: false));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/player_overlay_hidden.png'),
    );
  });
}
