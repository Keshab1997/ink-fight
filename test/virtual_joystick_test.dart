import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inkfight/widgets/virtual_joystick.dart';

/// The pad on its own: dead zone, axis passthrough, release, and the
/// edge-triggered jump. Drag math: the default pad travels 30 dp, so the
/// .10 dead zone is the middle 3 dp.
void main() {
  Future<List<double>> pumpPad(WidgetTester tester, VoidCallback onJump) async {
    final axes = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: VirtualJoystick(onAxisChanged: axes.add, onJump: onJump),
          ),
        ),
      ),
    );
    return axes;
  }

  testWidgets('a nudge inside the dead zone stays silent', (tester) async {
    final axes = await pumpPad(tester, () {});

    final centre = tester.getCenter(find.byType(VirtualJoystick));
    final gesture = await tester.startGesture(centre);
    // 2 dp of 30 is inside the .10 zone: the fighter must not drift.
    await gesture.moveBy(const Offset(2, 0));
    await tester.pump();
    expect(axes, isEmpty);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 150));
    expect(axes, [0.0], reason: 'release always reports 0');
  });

  testWidgets('a nudge past the dead zone reports its axis', (tester) async {
    final axes = await pumpPad(tester, () {});

    final centre = tester.getCenter(find.byType(VirtualJoystick));
    final gesture = await tester.startGesture(centre);
    // 4 dp of 30 is past the .10 zone: reported raw, unscaled.
    await gesture.moveBy(const Offset(4, 0));
    await tester.pump();
    expect(axes, hasLength(1));
    expect(axes.last, closeTo(4 / 30, .001));

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 150));
    expect(axes.last, 0);
  });

  testWidgets('a full drag saturates and the release recentres', (
    tester,
  ) async {
    final axes = await pumpPad(tester, () {});

    final centre = tester.getCenter(find.byType(VirtualJoystick));
    final gesture = await tester.startGesture(centre);
    await gesture.moveBy(const Offset(-60, 0));
    await tester.pump();
    expect(axes.last, closeTo(-1, .01));

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 150));
    expect(axes.last, 0);
  });

  testWidgets('the jump edge and its rearm are unchanged', (tester) async {
    var jumps = 0;
    final axes = await pumpPad(tester, () => jumps++);

    final centre = tester.getCenter(find.byType(VirtualJoystick));
    final gesture = await tester.startGesture(centre);
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    expect(jumps, 1);
    expect(
      axes.where((axis) => axis != 0),
      isEmpty,
      reason: 'vertical input never moves the fighter',
    );

    // Still held up: no refire while the edge stays crossed.
    await gesture.moveBy(const Offset(0, -10));
    await tester.pump();
    expect(jumps, 1);

    // Home and flick again: fires once more.
    await gesture.moveBy(const Offset(0, 50));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    expect(jumps, 2);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 150));
  });
}
