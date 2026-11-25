import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmix/main.dart';

void main() {
  testWidgets('TrialHome renders', (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ZmixTrialApp());
    await tester.pump();
    await expectLater(
      find.byType(TrialHome),
      matchesGoldenFile('goldens/trial_home.png'),
    );
  });
}
