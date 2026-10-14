import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inkfight/game/bot/bot_strategy.dart';
import 'package:inkfight/game/ink_fight_battle_game.dart';
import 'package:inkfight/game/rules/match_rules.dart';
import 'package:inkfight/screens/bot_fight_screen.dart';
import 'package:inkfight/widgets/virtual_joystick.dart';

/// Screen-level coverage for the live HUD and the decided-match card.
/// The headless view/controller behaviour lives in `bot_fight_game_test.dart`.
void main() {
  testWidgets('a decided match shows the outcome card and rematch resets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 720);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    // Image decoding is real async, so the whole mount has to happen inside
    // `runAsync`: in a fake-async zone the game's `onLoad` never finishes
    // loading its frames and the widget never hands back a mounted game.
    //
    // Do not wait on `game.loaded` here - that is the *component* lifecycle
    // future, and it only completes once GameWidget's loader has mounted the
    // game. Awaiting it from the test zone waits forever. Flame's own hook for
    // exactly this situation is `toBeLoaded()` (see
    // flame/test/game/game_widget/game_widget_test.dart), and `ready()` then
    // flushes the component tree so both fighters exist before we tick.
    late final InkFightBattleGame game;
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(home: BotFightScreen()));
      game =
          tester
                  .widget<GameWidget<FlameGame>>(
                    find.byWidgetPredicate((w) => w is GameWidget<FlameGame>),
                  )
                  .game!
              as InkFightBattleGame;
      await game.toBeLoaded();
      await game.ready();
    });
    await tester.pump();

    // An idle player loses to the practice bot; simulate it headlessly.
    for (var i = 0; i < 4200 && !game.match.isFinished; i++) {
      game.update(1 / 60);
    }
    expect(game.match.isFinished, isTrue);
    await tester.pump();

    // The HUD reads the controller, not a placeholder.
    final health = game.match.stateOf(FighterId.player).health;
    expect(
      find.text('${(health / game.match.rules.health * 100).round()}%'),
      findsOneWidget,
    );
    expect(find.text('END'), findsOneWidget);

    // The knockout blow plays its cinema before the card may stamp in
    // (GAME_FEEL §5): 350 ms of slow motion, then a 250 ms frozen beat.
    expect(health, 0, reason: 'the normal bot finishes an idle player');
    expect(game.roundEndCardVisible, isFalse);
    expect(find.text('REMATCH'), findsNothing);
    var guard = 0;
    while (!game.roundEndCardVisible && guard++ < 90) {
      await tester.pump(const Duration(milliseconds: 17));
    }
    expect(game.roundEndCardVisible, isTrue);
    expect(guard, greaterThanOrEqualTo(35), reason: '~600 ms of cinema');

    expect(find.text('REMATCH'), findsOneWidget);
    expect(
      find.text(
        game.match.outcome == MatchOutcome.playerWin
            ? 'YOU WIN'
            : 'CRIMSON RIVAL WINS',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('REMATCH'));
    await tester.pump();
    expect(find.text('REMATCH'), findsNothing);
    expect(find.text('READY'), findsOneWidget);
    expect(find.text('100%'), findsNWidgets(2));
    expect(game.match.phase, MatchPhase.countdown);
    // A rematch drops the cinema with the rest of the feel state.
    expect(game.roundEndCardVisible, isFalse);
  });

  testWidgets('the chosen difficulty reaches the practice bot', (tester) async {
    tester.view.physicalSize = const Size(1600, 720);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    // Normal is the default the design document asks for (GDD §8).
    expect(const BotFightScreen().difficulty, BotDifficulty.normal);

    // Same mount recipe as the card test above: the frames decode in a real
    // async zone, and `toBeLoaded()` + `ready()` hand back a mounted game.
    late final InkFightBattleGame game;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        const MaterialApp(home: BotFightScreen(difficulty: BotDifficulty.hard)),
      );
      game =
          tester
                  .widget<GameWidget<FlameGame>>(
                    find.byWidgetPredicate((w) => w is GameWidget<FlameGame>),
                  )
                  .game!
              as InkFightBattleGame;
      await game.toBeLoaded();
      await game.ready();
    });
    await tester.pump();

    expect(game.botProfile, BotProfile.hard);
  });

  /// Pumps a bare joystick over a callback recorder — no game, no assets,
  /// just the control the battle row now speaks through.
  Future<List<double>> pumpJoystick(
    WidgetTester tester,
    VoidCallback onJump,
  ) async {
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

  testWidgets('dragging the joystick right reports ~1, releasing reports 0', (
    tester,
  ) async {
    var jumps = 0;
    final axes = await pumpJoystick(tester, () => jumps++);

    final centre = tester.getCenter(find.byType(VirtualJoystick));
    final gesture = await tester.startGesture(centre);
    await tester.pump();
    // Past the 30 dp travel radius, so the axis saturates at +1.
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    expect(axes, isNotEmpty);
    expect(axes.last, closeTo(1, .01));
    expect(jumps, 0, reason: 'a horizontal drag is not a jump');

    await gesture.up();
    await tester.pump(
      const Duration(milliseconds: 150),
    ); // spring home (120 ms)
    expect(axes.last, 0, reason: 'release always reports 0');
  });

  testWidgets('flicking the joystick up fires one edge-triggered jump', (
    tester,
  ) async {
    var jumps = 0;
    final axes = await pumpJoystick(tester, () => jumps++);

    final centre = tester.getCenter(find.byType(VirtualJoystick));
    final gesture = await tester.startGesture(centre);
    // dy / travel = -40/30 ≈ -1.33, past the -.55 threshold.
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

    // Back near centre re-arms; the next flick fires again.
    await gesture.moveBy(const Offset(0, 50));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    expect(jumps, 2);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 150));
    expect(axes.last, 0);

    // A fresh gesture starts armed.
    final second = await tester.startGesture(centre);
    await second.moveBy(const Offset(0, -40));
    await tester.pump();
    expect(jumps, 3);
    await second.up();
    await tester.pump(const Duration(milliseconds: 150));
  });
}
