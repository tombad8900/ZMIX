import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zmix/audio_attach.dart';
import 'package:zmix/diagnostics.dart';

// Characterization of reapplyExternalAudio, extracted from PlayerPage with
// no behavior change. These pin CURRENT behavior, including the swallowed
// attach failure; they do not say it is the desired behavior.
void main() {
  late Directory dir;
  late Diag d;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('audio_seam');
    d = Diag.forTest();
    await d.initWithDir(dir);
    await d.setEnabled(true);
  });
  tearDown(() async {
    d.disposeForTest();
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('video-only + audio url: attaches the external url, logs critical', () async {
    final calls = <String?>[];
    await reapplyExternalAudio(
        currentNeedsAudio: true,
        audioUrl: 'https://rr1.example.com/a?sig=x',
        setAudio: (u) async => calls.add(u),
        attemptId: 'a1',
        diag: d);
    expect(calls, ['https://rr1.example.com/a?sig=x']);
    await d.flush();
    final r = await d.buildReport();
    expect(r, contains('إرفاق مسار الصوت الخارجي'));
    expect(r, contains('host=rr1.example.com'));
    expect(r, isNot(contains('sig=x')));
  });

  test('attach failure is swallowed and logged; caller sees normal completion',
      () async {
    var completed = false;
    await reapplyExternalAudio(
        currentNeedsAudio: true,
        audioUrl: 'https://rr1.example.com/a',
        setAudio: (u) async => throw StateError('boom'),
        attemptId: 'a2',
        diag: d);
    completed = true;
    expect(completed, isTrue); // no throw, no rollback signal
    await d.flush();
    final r = await d.buildReport();
    expect(r, contains('فشل إرفاق مسار الصوت'));
    expect(r, contains('ok=لا'));
  });

  test('muxed (no external audio needed): selects built-in audio (null)',
      () async {
    final calls = <String?>[];
    await reapplyExternalAudio(
        currentNeedsAudio: false,
        audioUrl: 'https://rr1.example.com/a',
        setAudio: (u) async => calls.add(u),
        attemptId: 'a3',
        diag: d);
    expect(calls, [null]);
  });

  test('video-only but audio url unknown: falls back to built-in audio',
      () async {
    final calls = <String?>[];
    await reapplyExternalAudio(
        currentNeedsAudio: true,
        audioUrl: null,
        setAudio: (u) async => calls.add(u),
        attemptId: 'a4',
        diag: d);
    expect(calls, [null]);
  });

  test('built-in audio selection failure is NOT caught (unchanged)', () async {
    await expectLater(
        reapplyExternalAudio(
            currentNeedsAudio: false,
            audioUrl: null,
            setAudio: (u) async => throw StateError('auto failed'),
            attemptId: 'a5',
            diag: d),
        throwsStateError);
  });
}
