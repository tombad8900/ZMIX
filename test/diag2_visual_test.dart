import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmix/diagnostics.dart';
import 'package:zmix/settings_page.dart';
import 'package:zmix/storage.dart';

import 'golden_fonts.dart';

void main() {
  setUpAll(() async {
    await loadGoldenFonts();
  });

  testWidgets('settings tile shows write-failure and pending counters', (tester) async {
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('diag2vis1');
      await Diag.I.initWithDir(tmp);
      await Diag.I.setEnabled(true);
      await Diag.I.flush();
      await tmp.delete(recursive: true);
      Diag.I.session('اختبار فشل القرص');
      await Diag.I.flush();
    });
    addTearDown(Diag.I.disposeForTest);
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(goldenHost(SettingsPage(store: LibraryStore())));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(milliseconds: 200));
    final list = find.byType(Scrollable).first;
    await tester.drag(list, const Offset(0, -700));
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/diag2_settings_counters.png'));
  });

  testWidgets('report header shows honest write state and memory snapshot', (tester) async {
    var report = '';
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('diag2vis2');
      await Diag.I.initWithDir(tmp);
      await Diag.I.setEnabled(true);
      await Diag.I.flush();
      Diag.I.outcome('بداية استخراج صيغة مدمجة', stage: 'extract', attemptId: 'a1');
      await tmp.delete(recursive: true);
      Diag.I.outcome('فشل استخراج الصيغة المدمجة', stage: 'extract', ok: false, detail: 'SocketException: Failed host lookup www.youtube.com', attemptId: 'a1');
      await Diag.I.flush();
      report = await Diag.I.buildReport();
      // Freeze clock/random inputs so the golden is deterministic.
      report = report
          .replaceAll(RegExp(r'\d{4}-\d{2}-\d{2}T[\d:.]+'), '2026-01-01T00:00:00.000000')
          .replaceAll(RegExp(r's:[0-9a-f]{6}'), 's:aaaaaa')
          .replaceAll(RegExp(r'الجلسة الحالية: [0-9a-f]{6} · تقرير: [0-9a-f]{6}'),
              'الجلسة الحالية: aaaaaa · تقرير: bbbbbb')
          .replaceAll(RegExp(r'كل \d+ ث'), 'كل 1 ث')
          // The header prints the host OS name and kernel version, which differ
          // between a dev box and a CI runner. Freeze that line (the only
          // environment-dependent text in this golden).
          .replaceAll(RegExp(r'النظام: [^\n]*'), 'النظام: linux test-os');
    });
    addTearDown(Diag.I.disposeForTest);
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(goldenHost(Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: SelectableText(report, style: const TextStyle(fontSize: 13, height: 1.5)),
        ),
      ),
    )));
    await tester.pump(const Duration(milliseconds: 200));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/diag2_report_header.png'));
  });
}
