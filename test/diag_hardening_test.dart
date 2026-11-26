import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zmix/diagnostics.dart';

// Tests for the 0.3.6-diag2 hardening policy (R1-R8): real queue cap with
// per-class drop accounting, bounded write-failure backoff, replay marker,
// dead-disk export snapshot, honest write-health wording, redaction intact.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('diag_hard');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('R1: hard cap actually holds; drops counted per class', () async {
    final d = Diag.forTest();
    await d.initWithDir(dir);
    await d.setEnabled(true);
    await d.flush();
    // Kill the disk so writes stop draining the queue, then overflow it.
    await dir.delete(recursive: true);
    d.outcome('أول فشل', ok: false); // critical; fails to write, requeued
    await d.flush();
    for (var i = 0; i < 305; i++) {
      d.ui('ضغطة $i');
    }
    final s = d.stats();
    // Regression guard: the old code removed from a throwaway list copy, so
    // the queue grew past the cap while counting drops.
    expect(s.pending, 300);
    expect(s.droppedNormal, 7); // marker + 5 oldest taps; critical kept
    // No critical dropped; the snapshot caps at the newest 50 and says so.
    expect(s.droppedCritical, 0);
    final report = await d.buildReport();
    expect(report, contains('(و 250 أحداث أقدم لم تُعرض)'));
    d.disposeForTest();
  });

  test('R1: all-critical overflow drops oldest critical, counted', () async {
    final d = Diag.forTest();
    await d.initWithDir(dir);
    await d.setEnabled(true);
    await d.flush();
    await dir.delete(recursive: true);
    for (var i = 0; i < 301; i++) {
      d.outcome('حرجة $i', ok: false);
    }
    await d.flush();
    final s = d.stats();
    expect(s.pending, 300);
    expect(s.droppedCritical, greaterThan(0));
    final report = await d.buildReport();
    expect(report, contains('حرجة 300')); // newest survives
    d.disposeForTest();
  });

  test('R2: write failure requeues with backoff; no immediate retry storm',
      () async {
    final d = Diag.forTest();
    await d.initWithDir(dir);
    await d.setEnabled(true);
    await d.flush();
    expect(d.stats().writeFailures, 0);
    await dir.delete(recursive: true);
    d.session('اختبار فشل القرص');
    await d.flush();
    final s1 = d.stats();
    expect(s1.writeFailures, greaterThan(0));
    expect(s1.pending, greaterThanOrEqualTo(2)); // marker + event kept
    // Backoff gate: a flush right after the failure must NOT touch the disk.
    await d.flush();
    expect(d.stats().writeFailures, s1.writeFailures);
    // After the backoff window a retry is attempted (and fails again here).
    await Future<void>.delayed(const Duration(milliseconds: 2300));
    await d.flush();
    expect(d.stats().writeFailures, greaterThan(s1.writeFailures));
    d.disposeForTest();
  });

  test('R3+R4: dead-disk export still carries the pending critical line',
      () async {
    final d = Diag.forTest();
    await d.initWithDir(dir);
    await d.setEnabled(true);
    await d.flush();
    await dir.delete(recursive: true);
    d.outcome('فشل استخراج الصيغة المدمجة',
        stage: 'extract', ok: false, detail: 'boom');
    await d.flush(); // fails; event returns to the queue
    final report = await d.buildReport();
    expect(report, contains('أحداث من الذاكرة عند التصدير'));
    expect(report, contains('فشل استخراج الصيغة المدمجة'));
    expect(report, contains('حالة الكتابة: فشل متكرر'));
    expect(report, contains('كتابات فاشلة'));
    d.disposeForTest();
  });

  test('R5: recovery after failure replays with marker and honest health',
      () async {
    final d = Diag.forTest();
    await d.initWithDir(dir);
    await d.setEnabled(true);
    await d.flush();
    await dir.delete(recursive: true);
    d.session('اختبار الاستعادة');
    await d.flush(); // fails, requeued with marker
    expect(d.stats().writeFailures, greaterThan(0));
    // Disk comes back; wait out the backoff, then the retry must succeed.
    await dir.create(recursive: true);
    await Future<void>.delayed(const Duration(milliseconds: 2300));
    await d.flush();
    expect(d.stats().pending, 0);
    final content = await File('${dir.path}/events-1.log').readAsString();
    expect(content, contains('قد تتكرر الأسطر التالية بعد فشل كتابة سابق'));
    expect(content, contains('اختبار الاستعادة'));
    final report = await d.buildReport();
    expect(report, contains('حالة الكتابة: فشلت كتابات سابقة ثم نجحت الكتابة'));
    d.disposeForTest();
  });

  test('R7: launcher-catch style detail persists redacted (host only)',
      () async {
    final d = Diag.forTest();
    await d.initWithDir(dir);
    await d.setEnabled(true);
    d.outcome('فشل إطلاق التشغيل',
        stage: 'launch',
        ok: false,
        detail:
            'Failed to open https://rr4---sn-x.googlevideo.com/videoplayback?expire=1&ip=94.0.0.1&sig=z');
    await d.flush();
    final content = await File('${dir.path}/events-1.log').readAsString();
    expect(content, contains('فشل إطلاق التشغيل'));
    expect(content, contains('ok=لا'));
    expect(content, contains('rr4---sn-x.googlevideo.com'));
    expect(content, isNot(contains('94.0.0.1')));
    expect(content, isNot(contains('ip=')));
    expect(content, isNot(contains('sig=')));
    d.disposeForTest();
  });

  test('R8: health wording - untested before any write, healthy after one',
      () async {
    final d1 = Diag.forTest();
    await d1.initWithDir(dir); // flags absent: diagnostics off
    final report1 = await d1.buildReport();
    expect(report1, contains('حالة الكتابة: لم تُختبر الكتابة بعد'));
    d1.disposeForTest();

    final dir2 = await Directory.systemTemp.createTemp('diag_hard2');
    try {
      final d2 = Diag.forTest();
      await d2.initWithDir(dir2);
      await d2.setEnabled(true);
      await d2.flush();
      final report2 = await d2.buildReport();
      expect(report2, contains('حالة الكتابة: سليمة'));
      d2.disposeForTest();
    } finally {
      if (dir2.existsSync()) await dir2.delete(recursive: true);
    }
  });
}
