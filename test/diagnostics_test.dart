import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zmix/diagnostics.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('diag_test');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  group('redaction', () {
    test('redact reduces any URL to its host, stripping query/IP/signature', () {
      const raw =
          'Failed to open https://rr4---sn-example.googlevideo.com/videoplayback?expire=123&ip=94.0.0.1&itag=137&sig=abc نهاية';
      final out = Diag.redact(raw);
      expect(out, contains('rr4---sn-example.googlevideo.com'));
      expect(out, isNot(contains('videoplayback')));
      expect(out, isNot(contains('ip=')));
      expect(out, isNot(contains('94.0.0.1')));
      expect(out, isNot(contains('sig=')));
      expect(out, isNot(contains('itag=')));
    });

    test('hostOf keeps only the host; unparseable input is masked', () {
      expect(Diag.hostOf('https://www.googlevideo.com/videoplayback?ip=1'),
          'www.googlevideo.com');
      expect(Diag.hostOf('not a url'), '[رابط]');
    });
  });

  group('restart semantics', () {
    test('enabled flag persists across launches; events before enabling are not recorded',
        () async {
      final d1 = Diag.forTest();
      await d1.initWithDir(dir);
      expect(d1.enabled, isFalse);
      d1.outcome('حدث قبل التفعيل'); // must be dropped: off by default
      await d1.flush();
      await d1.setEnabled(true);
      d1.disposeForTest();

      final d2 = Diag.forTest();
      await d2.initWithDir(dir);
      expect(d2.enabled, isTrue, reason: 'toggle persists across launches');
      final report = await d2.buildReport();
      expect(report, isNot(contains('حدث قبل التفعيل')));
      d2.disposeForTest();
    });

    test('previous session without a clean-exit marker is labeled abnormal with unknown cause',
        () async {
      final d1 = Diag.forTest();
      await d1.initWithDir(dir);
      await d1.setEnabled(true);
      d1.outcome('خطأ من المشغّل', ok: false, stage: 'open');
      await d1.flush();
      d1.disposeForTest(); // no markCleanExit: simulate kill/crash

      final d2 = Diag.forTest();
      await d2.initWithDir(dir);
      final report = await d2.buildReport();
      expect(report, contains('الجلسة السابقة انتهت من غير إنهاء نظيف'));
      expect(report, contains('سبب غير معروف'));
      d2.disposeForTest();
    });

    test('a clean exit leaves no abnormal label on the next launch', () async {
      final d1 = Diag.forTest();
      await d1.initWithDir(dir);
      await d1.setEnabled(true);
      await d1.markCleanExit();
      d1.disposeForTest();

      final d2 = Diag.forTest();
      await d2.initWithDir(dir);
      final report = await d2.buildReport();
      expect(report, isNot(contains('انتهت من غير إنهاء نظيف')));
      d2.disposeForTest();
    });
  });

  group('bounds and report', () {
    test('write queue is bounded and counts drops under pressure', () async {
      final d = Diag.forTest();
      await d.initWithDir(dir);
      await d.setEnabled(true);
      for (var i = 0; i < 500; i++) {
        d.ui('ضغطة رقم $i');
      }
      await d.flush();
      expect(d.stats().droppedNormal + d.stats().droppedCritical,
          greaterThan(0));
      d.disposeForTest();
    });

    test('exported report carries a header and host-only URLs', () async {
      final d = Diag.forTest();
      await d.initWithDir(dir);
      await d.setEnabled(true);
      d.outcome('خطأ من المشغّل',
          ok: false,
          stage: 'open',
          detail:
              'Failed to open https://rr9---sn-x.googlevideo.com/videoplayback?ip=203.0.113.7&expire=999');
      final report = await d.buildReport();
      expect(report, contains('تقرير تشخيص ZMIX'));
      expect(report, contains('إصدار التطبيق'));
      expect(report, contains('rr9---sn-x.googlevideo.com'));
      expect(report, isNot(contains('203.0.113.7')));
      expect(report, isNot(contains('videoplayback')));
      d.disposeForTest();
    });

    test('log files stay bounded by rotation', () async {
      final d = Diag.forTest();
      await d.initWithDir(dir);
      await d.setEnabled(true);
      final filler = 'x' * 2000;
      for (var i = 0; i < 600; i++) {
        d.ui('سطر $i', detail: filler);
        if (i % 50 == 0) await d.flush();
      }
      await d.flush();
      final s = d.stats();
      // Two files capped at ~900KB each.
      expect(s.bytes, lessThan(2 * 1024 * 1024));
      d.disposeForTest();
    });
  });
}
