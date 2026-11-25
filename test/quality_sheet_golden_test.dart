import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zmix/player_chrome.dart';

import 'golden_fonts.dart';

void main() {
  setUpAll(loadGoldenFonts);

  testWidgets('quality sheet golden', (tester) async {
    tester.view.physicalSize = const Size(780, 1000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      goldenHost(
        const Scaffold(
          body: Center(
            child: QualityListSheet(
              qualities: ['1080p', '720p', '360p'],
              activeQuality: '720p',
              onPick: _noop,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/quality_sheet.png'),
    );
  });
}

void _noop(String _) {}
