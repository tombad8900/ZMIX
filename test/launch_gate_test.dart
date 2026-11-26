import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zmix/diagnostics.dart';
import 'package:zmix/launch_gate.dart';
import 'package:zmix/playback_switcher.dart';

void main() {
  gateRunTests();
  test('gate: second tap refused while first launch in flight, counted', () {
    final g = LaunchGate();
    expect(g.tryEnter(), isTrue);
    expect(g.tryEnter(), isFalse);
    expect(g.tryEnter(), isFalse);
    expect(g.ignored, 2);
    g.leave();
    expect(g.tryEnter(), isTrue);
  });

  test('gate: four rapid taps start exactly one launch, even when it throws',
      () async {
    final g = LaunchGate();
    var started = 0;
    Future<void> launch({bool fail = false}) async {
      if (!g.tryEnter()) return;
      var held = true;
      try {
        started++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (fail) throw StateError('resolve failed');
      } catch (_) {
      } finally {
        if (held) {
          held = false;
          g.leave();
        }
      }
    }

    await Future.wait([launch(fail: true), launch(), launch(), launch()]);
    expect(started, 1);
    expect(g.busy, isFalse, reason: 'released in finally after the throw');
    await launch();
    expect(started, 2);
  });

  test('late release by an old launch cannot free a newer launch\'s hold', () {
    final g = LaunchGate();
    // Launch 1: enter, release early (route pushed), keep stale release fn.
    expect(g.tryEnter(), isTrue);
    var held1 = true;
    void release1() {
      if (held1) {
        held1 = false;
        g.leave();
      }
    }

    release1();
    // Launch 2 takes the gate while launch 1 is still awaiting pop.
    expect(g.tryEnter(), isTrue);
    release1(); // launch 1's finally runs late: must be a no-op
    expect(g.busy, isTrue);
  });

  group('first-play log edge', () {
    test('onFirstPlaybackConfirmation is true once per open, not per tick', () {
      final s = ZmixPlaybackSwitcher();
      final gen = s.beginOpen('urlA', quality: '360p');
      s.onMediaLoaded('urlA', generation: gen);
      var trues = 0;
      var progressTrues = 0;
      for (var i = 0; i < 50; i++) {
        final p = Duration(milliseconds: 40 * i);
        if (s.onFirstPlaybackConfirmation(
            generation: gen, position: p, playing: true)) {
          trues++;
        }
      }
      // Contrast: raw onPlaybackProgress is true on every advancing tick.
      final r = ZmixPlaybackSwitcher();
      final g3 = r.beginOpen('urlC', quality: '360p');
      r.onMediaLoaded('urlC', generation: g3);
      for (var i = 0; i < 50; i++) {
        if (r.onPlaybackProgress(
            generation: g3,
            position: Duration(milliseconds: 40 * i),
            playing: true)) {
          progressTrues++;
        }
      }
      expect(trues, 1);
      expect(progressTrues, greaterThan(10));
      // A new open re-arms the edge.
      final gen2 = s.beginOpen('urlB', quality: '720p');
      s.onMediaLoaded('urlB', generation: gen2);
      expect(
          s.onFirstPlaybackConfirmation(
              generation: gen2, position: Duration.zero, playing: true),
          isFalse);
      expect(
          s.onFirstPlaybackConfirmation(
              generation: gen2,
              position: const Duration(milliseconds: 40),
              playing: true),
          isTrue);
    });
  });
}

// Concurrent async launch through the real LaunchGate.run, with counters for
// "extraction" and "player open" standing in for the network/push.
void gateRunTests() {
  group('LaunchGate.run concurrency', () {
    test('four simultaneous taps: one extraction, one open, one release',
        () async {
      final g = LaunchGate();
      var extractions = 0, opens = 0;
      Future<bool> tap() => g.run((release) async {
            extractions++;
            await Future<void>.delayed(const Duration(milliseconds: 30));
            opens++;
            release(); // route pushed
            await Future<void>.delayed(const Duration(milliseconds: 10));
          });
      final r = await Future.wait([tap(), tap(), tap(), tap()]);
      expect(r.where((x) => x).length, 1);
      expect(extractions, 1);
      expect(opens, 1);
      expect(g.ignored, 3);
      expect(g.busy, isFalse);
    });

    test('released after a throw, after unmounted early return, and a newer '
        'launch is not freed by an older launch\'s late finally', () async {
      final g = LaunchGate();
      await expectLater(
          g.run((_) async => throw StateError('resolve failed')),
          throwsStateError);
      expect(g.busy, isFalse);
      expect(await g.run((_) async {/* !context.mounted -> return */}), isTrue);
      expect(g.busy, isFalse);

      // Older launch releases early, then lingers (awaiting route pop).
      late void Function() oldRelease;
      final popped = Completer<void>();
      final old = g.run((release) async {
        oldRelease = release;
        release();
        await popped.future;
      });
      await Future<void>.delayed(Duration.zero);
      // Newer launch takes the gate while the old route is still open.
      final newer = Completer<void>();
      final newerRun = g.run((_) => newer.future);
      await Future<void>.delayed(Duration.zero);
      expect(g.busy, isTrue);
      oldRelease(); // stale call: no-op
      popped.complete(); // old finally runs: must not free the newer hold
      await old;
      expect(g.busy, isTrue);
      newer.complete();
      await newerRun;
      expect(g.busy, isFalse);
    });
  });

  test('quality events are critical: survive a flood of normal taps',
      () async {
    final dir = await Directory.systemTemp.createTemp('diag_q');
    final d = Diag.forTest();
    await d.initWithDir(dir);
    await d.setEnabled(true);
    await d.flush();
    await dir.delete(recursive: true); // dead disk: queue holds, caps apply
    d.ui('اختيار جودة 720p', detail: 'منفصلة', attemptId: 'a1', critical: true);
    d.outcome('رجوع لآخر جودة شغالة',
        stage: 'open', attemptId: 'a1', critical: true);
    for (var i = 0; i < 400; i++) {
      d.ui('ضغطة $i');
    }
    final s = d.stats();
    // Overflow dropped only normal taps; the two critical quality lines were
    // kept (they are the oldest, so any critical drop would hit them first).
    expect(s.pending, 300);
    expect(s.droppedNormal, greaterThan(0));
    expect(s.droppedCritical, 0);
    d.disposeForTest();
  });
}
