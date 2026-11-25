import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmix/playback_switcher.dart';
import 'package:zmix/player_hud.dart';

// Route-level evidence for the 0.3.4 device complaint "even pressing Close
// nothing happens; the only escape is exiting the player entirely".
//
// PlayerPage itself cannot be pumped in the VM (its initState constructs a
// media_kit Player, which needs native libmpv), so this harness reproduces
// the exact hit-relevant structure of PlayerPage.build in the error state:
//   Scaffold > Listener > Stack[
//     Row[ ZmixGestureHalf(left), ZmixGestureHalf(right) ]  // opaque,
//                                                           // full-screen
//     PlayerErrorPanel(onBack: Navigator.pop, onRetry: ...) // LAST = topmost
//   ]
// pushed as a real MaterialPageRoute over a home page — the same way
// play_launcher.dart pushes PlayerPage.
class _Probes {
  int gestureTaps = 0;
  int retries = 0;
}

void main() {
  Future<_Probes> pumpApp(WidgetTester tester) async {
    final probes = _Probes();
    await tester.pumpWidget(MaterialApp(home: _HomePage(probes: probes)));
    await tester.tap(find.text('open player'));
    await tester.pumpAndSettle();
    expect(find.text('إغلاق'), findsOneWidget,
        reason: 'player route with error panel is on top');
    return probes;
  }

  testWidgets('tapping the visible Close pops the player route through the '
      'real overlay stack', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('إغلاق'));
    await tester.pumpAndSettle();
    expect(find.text('home page'), findsOneWidget,
        reason: 'Close must pop the player route back to the library');
    expect(find.text('إغلاق'), findsNothing);
  });

  testWidgets('the opaque gesture layer under the panel does not swallow '
      'the Close tap (tap lands on the button, not the layer)', (tester) async {
    final probes = await pumpApp(tester);
    expect(probes.gestureTaps, 0);
    // Tap exactly on the Close button: it must NOT count as a gesture-layer
    // tap, and it must pop.
    await tester.tap(find.text('إغلاق'));
    await tester.pumpAndSettle();
    expect(probes.gestureTaps, 0,
        reason: 'the panel is topmost; the gesture layer must not see taps '
            'meant for its buttons');
    expect(find.text('home page'), findsOneWidget);
  });

  testWidgets('tapping the video area behind the panel does NOT pop '
      '(only the button exits)', (tester) async {
    final probes = await pumpApp(tester);
    // A corner far from the centered panel: hits the gesture layer.
    await tester.tapAt(const Offset(40, 40));
    // The gesture half also recognizes double-tap, so its single-tap
    // callback fires only after the double-tap timeout.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('إغلاق'), findsOneWidget,
        reason: 'a stray tap on the gesture layer must not exit the player');
    expect(probes.gestureTaps, 1,
        reason: 'the gesture layer did receive that tap');
  });

  testWidgets('Retry does not pop the route', (tester) async {
    final probes = await pumpApp(tester);
    await tester.tap(find.text('حاول تاني'));
    await tester.pumpAndSettle();
    expect(probes.retries, 1);
    expect(find.text('إغلاق'), findsOneWidget,
        reason: 'Retry re-opens in place; it never exits the player');
  });
}

class _HomePage extends StatefulWidget {
  const _HomePage({required this.probes});

  final _Probes probes;

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('home page'),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => _PlayerHarnessPage(
                    onGestureTap: () => widget.probes.gestureTaps++,
                    onRetry: () => widget.probes.retries++,
                  ),
                ));
              },
              child: const Text('open player'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mirrors PlayerPage.build's error-state layering, with the real
/// ZmixGestureHalf and PlayerErrorPanel widgets and the same pop wiring
/// (`onBack: () => Navigator.of(context).pop()`).
class _PlayerHarnessPage extends StatelessWidget {
  const _PlayerHarnessPage({
    required this.onGestureTap,
    required this.onRetry,
  });

  final VoidCallback onGestureTap;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Listener(
        onPointerDown: (_) {}, // the pinch-zoom observer, as in PlayerPage
        child: Stack(
          fit: StackFit.expand,
          children: [
            Row(
              children: [
                Expanded(child: _half(isLeft: true)),
                Expanded(child: _half(isLeft: false)),
              ],
            ),
            PlayerErrorPanel(
              errorText: kSafePlaybackError,
              onBack: () => Navigator.of(context).pop(),
              onRetry: onRetry,
            ),
          ],
        ),
      ),
    );
  }

  Widget _half({required bool isLeft}) => ZmixGestureHalf(
        isLeft: isLeft,
        onTap: onGestureTap,
        onDoubleTap: () {},
        onLongPressStart: (_) {},
        onLongPressEnd: (_) {},
        onHorizontalDragStart: (_) {},
        onHorizontalDragUpdate: (_) {},
        onHorizontalDragEnd: (_) {},
        onVerticalDragStart: (_, __) {},
        onVerticalDragUpdate: (_) {},
        onVerticalDragEnd: (_) {},
      );
}
