import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zmix/diagnostics.dart';
import 'package:zmix/youtube_service.dart';

// End-to-end evidence for the 0.3.6-diag trial ambiguity: when extraction
// FAILS, does the terminal 'فشل استخراج' event actually reach the log file,
// redacted? (The trial report showed starts with no terminals; this test
// proves the instrumented failure path itself works.)
void main() {
  test('extraction failure persists a redacted terminal event', () async {
    final dir = await Directory.systemTemp.createTemp('diag_fail');
    try {
      await Diag.I.initWithDir(dir);
      await Diag.I.setEnabled(true);
      final service = YoutubeService();
      Object? caught;
      try {
        await service
            .resolvePlayable('896cfpFHK4o', attemptId: 'a1')
            .timeout(const Duration(seconds: 30));
      } catch (e) {
        caught = e;
        print('CAUGHT TYPE: ${e.runtimeType}');
        final s = '$e';
        print('CAUGHT TEXT (first 300): ${s.substring(0, s.length > 300 ? 300 : s.length)}');
      } finally {
        service.close();
      }
      expect(caught, isNotNull,
          reason: 'sandbox network is expected to fail extraction');
      await Diag.I.flush();
      final f1 = File('${dir.path}/events-1.log');
      expect(f1.existsSync(), isTrue, reason: 'log file must exist');
      final content = await f1.readAsString();
      print('--- LOG CONTENT ---');
      print(content);
      expect(content, contains('بداية استخراج صيغة مدمجة'));
      expect(content, contains('فشل استخراج الصيغة المدمجة'));
      expect(content, contains('ok=لا'));
      expect(content, isNot(contains('videoplayback?')));
      expect(content, isNot(contains('ip=')));
    } finally {
      Diag.I.disposeForTest();
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
