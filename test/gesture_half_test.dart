import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmix/player_hud.dart';

// Reproduces the 0.3.1 device bug: vertical drag read localPosition.dx,
// which is relative to the half-width detector, so every drag routed to
// brightness and volume-by-gesture never fired. These tests pin the
// production routing: right half -> volume (isLeft=false), left -> brightness.
void main() {
  Widget host(void Function(bool side) onSide) {
    Widget half(bool isLeft) => ZmixGestureHalf(
          isLeft: isLeft,
          onTap: () {},
          onDoubleTap: () {},
          onLongPressStart: (_) {},
          onLongPressEnd: (_) {},
          onHorizontalDragStart: (_) {},
          onHorizontalDragUpdate: (_) {},
          onHorizontalDragEnd: (_) {},
          onVerticalDragStart: (_, side) => onSide(side),
          onVerticalDragUpdate: (_) {},
          onVerticalDragEnd: (_) {},
        );
    return Directionality(
      textDirection: TextDirection.rtl, // production is RTL
      child: SizedBox(
        width: 800,
        height: 400,
        child: Row(
          children: [
            Expanded(child: half(true)),
            Expanded(child: half(false)),
          ],
        ),
      ),
    );
  }

  testWidgets('vertical drag on the right half routes as volume',
      (tester) async {
    final sides = <bool>[];
    await tester.pumpWidget(host(sides.add));
    await tester.drag(
        find.byType(ZmixGestureHalf).at(1), const Offset(0, -60));
    // Drain the double-tap recognizer's 40ms countdown timer.
    await tester.pump(const Duration(milliseconds: 100));
    expect(sides, [false]);
  });

  testWidgets('vertical drag on the left half routes as brightness',
      (tester) async {
    final sides = <bool>[];
    await tester.pumpWidget(host(sides.add));
    await tester.drag(
        find.byType(ZmixGestureHalf).at(0), const Offset(0, -60));
    await tester.pump(const Duration(milliseconds: 100));
    expect(sides, [true]);
  });
}
