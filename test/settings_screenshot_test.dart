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

  testWidgets('settings diagnostics section renders', (tester) async {
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('diag_golden');
      await Diag.I.initWithDir(tmp);
      await Diag.I.setEnabled(true);
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
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/settings_diag_enabled.png'));
  });
}
