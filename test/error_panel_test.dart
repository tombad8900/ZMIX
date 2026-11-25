import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmix/playback_switcher.dart';
import 'package:zmix/player_hud.dart';

// Widget-level evidence for the 0.3.4 device complaint "Close does
// nothing": the actual error-panel buttons must fire their callbacks, and
// the text on screen must be the sanitized message, never a transport URL.
void main() {
  testWidgets('tapping Close fires onBack (exit the player)', (tester) async {
    var closed = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlayerErrorPanel(
          errorText: kSafePlaybackError,
          onBack: () => closed = true,
          onRetry: () {},
        ),
      ),
    ));
    await tester.tap(find.text('إغلاق'));
    expect(closed, isTrue);
  });

  testWidgets('tapping Retry fires onRetry', (tester) async {
    var retried = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlayerErrorPanel(
          errorText: kSafePlaybackError,
          onBack: () {},
          onRetry: () => retried = true,
        ),
      ),
    ));
    await tester.tap(find.text('حاول تاني'));
    expect(retried, isTrue);
  });

  testWidgets('panel never renders a raw URL or IP', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: PlayerErrorPanel(
          errorText: kSafePlaybackError,
          onBack: _noop,
          onRetry: _noop,
        ),
      ),
    ));
    final text =
        tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').join('\n');
    expect(text.contains('http'), isFalse);
    expect(text.contains('googlevideo'), isFalse);
    expect(RegExp(r'\d{1,3}(\.\d{1,3}){3}').hasMatch(text), isFalse,
        reason: 'no IPv4 literal may reach the panel');
  });
}

void _noop() {}
