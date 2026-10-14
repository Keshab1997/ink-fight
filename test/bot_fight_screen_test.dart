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

    // The one-time controls card greets first; GOT IT clears the way.
    await tester.tap(find.text('GOT IT'));
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
    // A decided match cannot be paused: the button is gone with the card up.
    expect(find.byIcon(Icons.pause_rounded), findsNothing);
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
    // Dismiss the one-time controls card like a player would.
    await tester.tap(find.text('GOT IT'));
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

  /// Mounts the screen the proven way (the frames decode in a real async
  /// zone) and leaves the one-time controls card up, as a fresh mount does.
  Future<InkFightBattleGame> mountFight(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 720);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

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
    return game;
  }

  testWidgets('pause freezes the match clock and RESUME runs it again', (
    tester,
  ) async {
    final game = await mountFight(tester);
    await tester.tap(find.text('GOT IT'));
    await tester.pump();

    // Headlessly into live combat, then let the clock run a second.
    for (var i = 0; i < 190 && game.match.phase != MatchPhase.fighting; i++) {
      game.update(1 / 60);
    }
    expect(game.match.phase, MatchPhase.fighting);
    for (var i = 0; i < 60; i++) {
      game.update(1 / 60);
    }
    final clock = game.match.timeRemainingMs;
    expect(clock, lessThan(game.match.rules.roundMs));

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();
    expect(find.text('PAUSED'), findsOneWidget);
    expect(game.paused, isTrue);

    // Real time passes, the match does not move.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      game.match.timeRemainingMs,
      clock,
      reason: 'the stopped engine freezes the clock',
    );

    await tester.tap(find.text('RESUME'));
    await tester.pump();
    expect(find.text('PAUSED'), findsNothing);
    expect(game.paused, isFalse);

    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    expect(game.match.timeRemainingMs, lessThan(clock));
  });

  testWidgets('RESTART winds health and the clock back to fresh values', (
    tester,
  ) async {
    final game = await mountFight(tester);
    await tester.tap(find.text('GOT IT'));
    await tester.pump();

    // ~7 s of headless combat: the countdown passes, the clock runs down and
    // the normal bot has been working on the player.
    for (var i = 0; i < 430; i++) {
      game.update(1 / 60);
    }
    expect(game.match.isFinished, isFalse);
    expect(game.match.timeRemainingMs, lessThan(game.match.rules.roundMs));

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();
    await tester.tap(find.text('RESTART'));
    await tester.pump();

    expect(find.text('PAUSED'), findsNothing);
    expect(game.paused, isFalse, reason: 'RESTART resumes the engine');
    expect(game.match.phase, MatchPhase.countdown);
    expect(game.match.timeRemainingMs, game.match.rules.roundMs);
    expect(
      game.match.stateOf(FighterId.player).health,
      game.match.rules.health,
    );
    expect(game.match.stateOf(FighterId.rival).health, game.match.rules.health);

    // And the fresh countdown visibly runs on the resumed engine.
    final countdown = game.match.countdownRemainingMs;
    await tester.pump(const Duration(milliseconds: 300));
    expect(game.match.countdownRemainingMs, lessThan(countdown));
  });

  testWidgets('the controls card greets once per mount, pause keeps it '
      'readable', (tester) async {
    final game = await mountFight(tester);

    // First mount: the card is up over the arena.
    expect(find.text('GOT IT'), findsOneWidget);
    expect(find.text('CONTROLS'), findsOneWidget);
    expect(find.textContaining('joystick'), findsNWidgets(2));

    await tester.tap(find.text('GOT IT'));
    await tester.pump();
    expect(find.text('GOT IT'), findsNothing);

    // It does not come back on its own within this screen's lifetime.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('GOT IT'), findsNothing);

    // The pause overlay's CONTROLS makes it readable at any time — over the
    // overlay, with the engine still stopped.
    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();
    expect(find.text('PAUSED'), findsOneWidget);
    await tester.tap(find.text('CONTROLS'));
    await tester.pump();
    expect(find.text('GOT IT'), findsOneWidget);
    expect(game.paused, isTrue);

    await tester.tap(find.text('GOT IT'));
    await tester.pump();
    expect(
      find.text('PAUSED'),
      findsOneWidget,
      reason: 'GOT IT returns to the pause overlay underneath',
    );
    expect(game.paused, isTrue);

    await tester.tap(find.text('RESUME'));
    await tester.pump();
    expect(find.text('PAUSED'), findsNothing);
    expect(game.paused, isFalse);
  });
}
