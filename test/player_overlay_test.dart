import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zmix/player/player_controls_config.dart';
import 'package:zmix/player/player_controls_overlay.dart';
import 'package:zmix/player/player_episodes_panel.dart';
import 'package:zmix/player_chrome.dart';
import 'package:zmix/player_hud.dart';
import 'package:zmix/player_page.dart';

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
  bool transportHidden = false,
  bool withEpisodes = false,
  bool withSubtitles = false,
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
    transportHidden: transportHidden,
    onEpisodes: withEpisodes ? () {} : null,
    onSubtitles: withSubtitles ? () {} : null,
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
    // Production wiring (PlayerPage): while seek feedback is up the center
    // transport is suppressed so the centered pill never overlaps it.
    await pump(
      tester,
      Stack(
        fit: StackFit.expand,
        children: [
          _overlay(transportHidden: true),
          const SeekIndicator(delta: 20, forward: true),
          const PlayerHud(isBrightness: false, value: 0.65),
          const BoostBadge(),
        ],
      ),
    );
    expect(find.text('20 ث'), findsOneWidget);
    expect(find.text('2×'), findsOneWidget);
    expect(find.byIcon(Icons.skip_next_rounded), findsNothing);
    expect(find.byIcon(Icons.pause_rounded), findsNothing);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/player_overlay_seek_hud_boost.png'),
    );
  });

  testWidgets('locked: only the lock affordance, artwork stays visible',
      (tester) async {
    var unlocked = false;
    await pump(tester, LockOverlay(onUnlock: () => unlocked = true));
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    expect(find.byIcon(Icons.high_quality_rounded), findsNothing);
    expect(find.byIcon(Icons.skip_next_rounded), findsNothing);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/player_overlay_locked.png'),
    );
    await tester.tap(find.byIcon(Icons.lock_rounded));
    expect(unlocked, isTrue);
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

  testWidgets('episodes button shows only with the panel callback',
      (tester) async {
    await pump(tester, _overlay(withEpisodes: true));
    expect(find.byIcon(Icons.video_library_outlined), findsOneWidget);
  });

  testWidgets('subtitles button shows only with the callback',
      (tester) async {
    await pump(tester, _overlay());
    expect(find.byIcon(Icons.subtitles_rounded), findsNothing);
    await pump(tester, _overlay(withSubtitles: true));
    expect(find.byIcon(Icons.subtitles_rounded), findsOneWidget);
  });

  testWidgets('subtitle sheet: off row, language rows, auto marker, pick',
      (tester) async {
    int? picked = -2; // non-pick sentinel
    var tapped = false;
    await pump(
      tester,
      Scaffold(
        backgroundColor: const Color(0xFF16161C),
        body: SubtitleListSheet(
          rows: const [
            (code: 'ar', name: '', autoGenerated: true),
            (code: 'en-US', name: '', autoGenerated: false),
          ],
          activeCode: 'ar',
          onPick: (i) {
            tapped = true;
            picked = i;
          },
        ),
      ),
    );
    expect(find.text('الترجمة'), findsOneWidget);
    expect(find.text('إيقاف'), findsOneWidget);
    expect(find.text('العربية'), findsOneWidget);
    expect(find.text('الإنجليزية (أمريكي)'), findsOneWidget);
    expect(find.text('تلقائية'), findsOneWidget); // auto-generated marker
    expect(find.byIcon(Icons.check_rounded), findsOneWidget); // active row
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/player_subtitle_sheet.png'),
    );
    await tester.tap(find.text('إيقاف'));
    expect(tapped, isTrue);
    expect(picked, isNull); // Off picks null
  });

  testWidgets('episodes panel: rows, current highlight, untitled label, select',
      (tester) async {
    var selected = -1;
    await pump(
      tester,
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: ZmixEpisodesPanel(
          episodes: const [
            ZmixPanelEpisode(
              number: 1,
              title: 'الحلقة الأولى',
              runtimeSeconds: 1320,
            ),
            ZmixPanelEpisode(number: 2, title: 'Episode 2 - المطاردة'),
            ZmixPanelEpisode(number: 3, title: 'بلا عنوان'),
            ZmixPanelEpisode(number: 4, title: 'الحلقة الرابعة'),
            ZmixPanelEpisode(number: 5, title: 'الحلقة الخامسة'),
          ],
          currentIndex: 1,
          onSelect: (i) => selected = i,
        ),
      ),
    );
    expect(find.text('الحلقات'), findsOneWidget);
    expect(find.text('E1'), findsOneWidget);
    expect(find.text('E3'), findsOneWidget);
    expect(find.text('بلا عنوان'), findsOneWidget);
    // The generic "Episode 2 - " prefix is stripped on display.
    expect(find.text('المطاردة'), findsOneWidget);
    expect(find.text('22 د'), findsOneWidget); // 1320s -> 22m
    expect(find.text('يُعرض الآن'), findsOneWidget); // current row
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/player_episodes_panel.png'),
    );
    await tester.tap(find.text('الحلقة الرابعة'));
    expect(selected, 3);
  });

  testWidgets(
      'component fixture: visible=false only slides the bottom block '
      '(production hiding is the gate, tested below)', (tester) async {
    await pump(tester, _overlay(visible: false));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/player_overlay_hidden.png'),
    );
  });

  testWidgets('production gate: hidden controls are gone and take no taps',
      (tester) async {
    var playTapped = false;
    await pump(
      tester,
      ControlsGate(
        visible: false,
        child: PlayerControlsOverlay(
          player: FakePlayerSurface(),
          episodeNumber: 3,
          episodeTitle: 'فيلم الاختبار الطويل 2024',
          multiEpisode: true,
          hasNext: true,
          hasQualityChoices: true,
          activeQualityLabel: '360p',
          onTogglePlay: () => playTapped = true,
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
          visible: false,
        ),
      ),
    );
    // Golden proves the composite hides the controls over representative
    // artwork; only the artwork may be visible.
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/player_gate_hidden.png'),
    );
    // IgnorePointer: taps in the center (where pause sits) reach nothing.
    await tester.tapAt(const Offset(422, 195)); // logical center
    expect(playTapped, isFalse);
  });

  testWidgets('production gate: visible again after toggling back',
      (tester) async {
    await pump(
      tester,
      ControlsGate(visible: true, child: _overlay()),
    );
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/player_gate_visible.png'),
    );
  });
}
