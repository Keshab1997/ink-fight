import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inkfight/game/audio/fight_sounds.dart';
import 'package:inkfight/game/bot/bot_strategy.dart';
import 'package:inkfight/game/ink_fight_battle_game.dart';
import 'package:inkfight/game/rules/input_command.dart';
import 'package:inkfight/game/rules/match_controller.dart';
import 'package:inkfight/game/rules/match_rules.dart';
import 'package:inkfight/screens/bot_fight_screen.dart';
import 'package:inkfight/state/ink_settings.dart';
import 'package:inkfight/theme/app_theme.dart';
import 'package:inkfight/widgets/virtual_joystick.dart';

class _RecordingFightSounds implements FightSounds {
  final List<FightCue> cues = [];

  @override
  void play(FightCue cue) => cues.add(cue);

  @override
  Future<void> warmUp() async {}
}

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
      await tester.pumpWidget(
        MaterialApp(
          home: BotFightScreen(
            rules: const MatchRules(roundsToWin: 1),
            settings: InkSettings(),
            sounds: const SilentFightSounds(),
          ),
        ),
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
    var previousTrail = tester
        .widgetList<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        )
        .first
        .value!;
    expect(previousTrail, greaterThan(0), reason: 'KO does not snap the trail');
    var guard = 0;
    while (!game.roundEndCardVisible && guard++ < 90) {
      await tester.pump(const Duration(milliseconds: 17));
      final trail = tester
          .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .first
          .value!;
      expect(
        trail,
        inInclusiveRange(0, previousTrail),
        reason: 'monotone KO drain never overshoots its live edge',
      );
      previousTrail = trail;
    }
    expect(game.roundEndCardVisible, isTrue);
    expect(guard, greaterThanOrEqualTo(35), reason: '~600 ms of cinema');

    expect(find.text('REMATCH'), findsOneWidget);
    final bars = tester
        .widgetList<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        )
        .toList();
    expect(bars[0].value, 0, reason: 'KO trail finishes exactly at live zero');
    expect(bars[1].value, 0);

    double stampScale() => tester
        .widget<Transform>(find.byKey(const ValueKey('round-end-stamp-scale')))
        .transform
        .storage[0];
    double stampOpacity() => tester
        .widget<Opacity>(find.byKey(const ValueKey('round-end-stamp-opacity')))
        .opacity;
    expect(stampScale(), closeTo(1.06, .0001));
    expect(stampOpacity(), 0);
    await tester.pump(const Duration(milliseconds: 90));
    expect(stampScale(), inExclusiveRange(1, 1.06));
    expect(stampOpacity(), inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 90));
    expect(stampScale(), 1);
    expect(stampOpacity(), 1);
    expect(
      tester
          .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .first
          .value,
      0,
      reason: 'no residual trail behind the card',
    );
    // A decided match cannot be paused: the button is gone with the card up.
    expect(find.byIcon(Icons.pause_rounded), findsNothing);
    expect(
      find.text(
        game.match.outcome == MatchOutcome.playerWin
            ? 'MATCH WON'
            : 'MATCH LOST',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('REMATCH'));
    await tester.pump();
    expect(find.text('REMATCH'), findsNothing);
    // This single-round fixture starts the normal countdown at once.
    expect(find.text('3'), findsOneWidget);
    expect(find.textContaining(RegExp(r'ROUND \d+')), findsNothing);
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
    expect(
      BotFightScreen(settings: InkSettings()).difficulty,
      BotDifficulty.normal,
    );

    // Same mount recipe as the card test above: the frames decode in a real
    // async zone, and `toBeLoaded()` + `ready()` hand back a mounted game.
    late final InkFightBattleGame game;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: BotFightScreen(
            rules: const MatchRules(roundsToWin: 1),
            difficulty: BotDifficulty.hard,
            settings: InkSettings(),
            sounds: const SilentFightSounds(),
          ),
        ),
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
  /// [settings] is the model the screen mounts with; tests that care about a
  /// preference pass their own, the rest get a fresh default one.
  Future<InkFightBattleGame> mountFight(
    WidgetTester tester, {
    InkSettings? settings,
    FightSounds sounds = const SilentFightSounds(),
    MatchRules rules = const MatchRules(roundsToWin: 1),
  }) async {
    tester.view.physicalSize = const Size(1600, 720);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    late final InkFightBattleGame game;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: BotFightScreen(
            rules: rules,
            settings: settings ?? InkSettings(),
            // Silent on purpose: the screen's own path builds the real audio
            // seam, and no test may load the plugin.
            sounds: sounds,
          ),
        ),
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
    return game;
  }

  testWidgets(
    'best-of-three draws show round notices; only match end shows match card',
    (tester) async {
      expect(BotFightScreen(settings: InkSettings()).rules.roundsToWin, 2);
      final game = await mountFight(tester, rules: MatchRules.standard);
      await tester.tap(find.text('GOT IT'));
      await tester.pump();
      game.pauseEngine(); // drive rules deterministically, without bot input
      for (var round = 1; round <= 3; round++) {
        while (game.match.countdownRemainingMs > 0) {
          game.match.tick(.016);
        }
        var guard = 0;
        while (!game.match.isFinished &&
            game.match.roundNumber == round &&
            guard++ < 5000) {
          game.match.tick(.016);
        }
        expect(guard, lessThan(5000));
        game.update(.001); // a positive render frame drains/syncs the boundary
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(); // apply the post-simulation round snapshot
        expect(game.match.playerRoundWins, 0);
        expect(game.match.rivalRoundWins, 0);
        if (round < 3) {
          expect(game.match.roundNumber, round + 1);
          expect(game.match.phase, MatchPhase.countdown);
          expect(find.text('3'), findsOneWidget);
          expect(find.text('ROUND $round DRAW'), findsOneWidget);
          expect(find.text('100%'), findsNWidgets(2));
          expect(find.text('REMATCH'), findsNothing);
          expect(game.roundEndCardVisible, isFalse);
        } else {
          expect(game.match.roundNumber, 3);
          expect(game.match.outcome, MatchOutcome.draw);
          expect(find.text('MATCH DRAW'), findsOneWidget);
          expect(find.text('REMATCH'), findsOneWidget);
          expect(game.roundEndCardVisible, isTrue);
        }
        if (round == 3) {
          expect(find.byKey(const ValueKey('round-result-card')), findsNothing);
        }
      }
      await tester.tap(find.text('REMATCH'));
      await tester.pump(const Duration(milliseconds: 17));
      expect(game.match.roundNumber, 1);
      expect(game.match.playerRoundWins, 0);
      expect(game.match.rivalRoundWins, 0);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('REMATCH'), findsNothing);
    },
  );

  // A round-boundary driver, unlike hurtTo's single-round health threshold.
  // Rules decide the winner; this helper only sends real combat inputs.
  void knockoutRound(InkFightBattleGame game, FighterId winner) {
    final match = game.match;
    while (match.phase == MatchPhase.countdown) {
      match.tick(.016);
    }
    final round = match.roundNumber;
    var guard = 0;
    while (!match.isFinished && match.roundNumber == round && guard++ < 1000) {
      final state = match.stateOf(winner);
      final victim = winner == FighterId.player ? match.rival : match.player;
      final gap = victim.x - state.x;
      final approach = gap.abs() > match.rules.lightAttack.reach * .85;
      match.setMoveAxis(winner, approach ? gap.sign : 0);
      if (!approach && state.canAct) {
        match.submit(
          InputCommand(
            fighter: winner,
            action: InputAction.lightPunch,
            sequence: guard,
          ),
        );
      }
      match.tick(.016);
    }
    expect(guard, lessThan(1000));
    game.update(.000001); // drain closing hit; reset presentation, never scores
  }

  testWidgets(
    'round pips show a lost round then a won match, and reset cleanly',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final game = await mountFight(
          tester,
          rules: const MatchRules(health: 6),
        );
        await tester.tap(find.text('GOT IT'));
        await tester.pump();
        game.pauseEngine();
        tester.view.physicalSize = const Size(640, 360);
        tester.view.devicePixelRatio = 1;
        await tester.pump(const Duration(milliseconds: 1));

        void expectPips(FighterId fighter, int wins) {
          final label = fighter == FighterId.player ? 'You' : 'Crimson Rival';
          expect(
            find.bySemanticsLabel('$label: $wins of 2 round wins'),
            findsOneWidget,
          );
          for (var i = 0; i < 2; i++) {
            final pip = tester.widget<Container>(
              find.byKey(ValueKey('round-pip-${fighter.name}-$i')),
            );
            final decoration = pip.decoration! as BoxDecoration;
            expect(
              decoration.color,
              i < wins ? InkColors.ink : InkColors.white,
            );
            expect(
              decoration.border,
              Border.all(color: InkColors.ink, width: 1.5),
            );
          }
          expect(
            find.byKey(ValueKey('round-pip-${fighter.name}-2')),
            findsNothing,
          );
        }

        expectPips(FighterId.player, 0);
        expectPips(FighterId.rival, 0);
        for (final fighter in FighterId.values) {
          final pips = tester.getRect(
            find.byKey(ValueKey('round-pips-${fighter.name}')),
          );
          for (final bar in ['YOU', 'CRIMSON RIVAL']) {
            expect(
              pips.overlaps(
                tester.getRect(find.byKey(ValueKey('health-live-$bar'))),
              ),
              isFalse,
            );
          }
          expect(pips.overlaps(tester.getRect(find.text('3'))), isFalse);
          expect(pips.top, greaterThanOrEqualTo(14));
          expect(
            pips.bottom,
            lessThan(50),
            reason: 'fixed label row above the arena, no HUD growth',
          );
        }

        final winners = [FighterId.rival, FighterId.player, FighterId.player];
        for (var i = 0; i < winners.length; i++) {
          knockoutRound(game, winners[i]);
          await tester.pump(const Duration(milliseconds: 1));
          await tester.pump();
          if (i < 2) {
            expect(game.match.phase, MatchPhase.countdown);
            expect(
              game.match.countdownRemainingMs,
              game.match.rules.countdownMs,
            );
            expect(
              find.text('3'),
              findsOneWidget,
              reason: 'notice does not delay or cover countdown',
            );
            expect(
              find.text(i == 0 ? 'ROUND 1 LOST' : 'ROUND 2 WON'),
              findsOneWidget,
            );
            expect(find.text('REMATCH'), findsNothing);
            expectPips(FighterId.player, i);
            expectPips(FighterId.rival, 1);
            expect(game.stats.history.length, i + 1);
            expect(game.stats.history.last.hitsLanded, i);
            expect(
              game.stats.observeMatch(game.match),
              same(game.stats.history.last),
            );
            // The notice is round-local and disappears on live combat.
            while (game.match.phase == MatchPhase.countdown) {
              game.match.tick(.016);
            }
            game.update(.000001);
            await tester.pump(const Duration(milliseconds: 1));
            expect(
              find.byKey(const ValueKey('round-result-card')),
              findsNothing,
            );
          }
        }
        expect(
          game.match.outcome,
          MatchOutcome.playerWin,
          reason: 'losing a round is not losing the match',
        );
        for (var i = 0; i < 90 && !game.roundEndCardVisible; i++) {
          game.update(.017);
        }
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(milliseconds: 180));
        expect(find.text('MATCH WON'), findsOneWidget);
        expect(find.text('ROUNDS 2 – 1'), findsOneWidget);
        await tester.pump(); // final-round capture notifies the recap subtree
        expect(game.stats.history.map((r) => r.hitsLanded), [0, 1, 1]);
        expect(game.stats.history.map((r) => r.outcome), [
          MatchOutcome.rivalWin,
          MatchOutcome.playerWin,
          MatchOutcome.playerWin,
        ]);
        for (var round = 1; round <= 3; round++) {
          expect(find.byKey(ValueKey('round-recap-$round')), findsOneWidget);
          expect(
            tester
                .widget<Text>(find.byKey(ValueKey('round-recap-hits-$round')))
                .data,
            round == 1 ? '0' : '1',
          );
        }
        expect(find.text('YOUR HITS'), findsOneWidget);
        expect(find.byKey(const ValueKey('round-result-card')), findsNothing);
        expectPips(FighterId.player, 2);
        expectPips(FighterId.rival, 1);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('REMATCH'));
        await tester.tap(find.text('REMATCH'));
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump();
        game.pauseEngine();
        expectPips(FighterId.player, 0);
        expectPips(FighterId.rival, 0);
        expect(game.stats.history, isEmpty);
        expect(find.byKey(const ValueKey('round-recap')), findsNothing);
        expect(find.text('3'), findsOneWidget);
        expect(find.byKey(const ValueKey('round-result-card')), findsNothing);
        expect(find.byKey(const ValueKey('match-result-label')), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        expect(
          tester.takeException(),
          isNull,
          reason: 'no result animation survives unmount',
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('pips use the configured win target rather than assuming two', (
    tester,
  ) async {
    final game = await mountFight(
      tester,
      rules: const MatchRules(roundsToWin: 3),
    );
    await tester.tap(find.text('GOT IT'));
    await tester.pump();
    game.pauseEngine();
    for (final fighter in FighterId.values) {
      for (var i = 0; i < game.match.rules.roundsToWin; i++) {
        expect(
          find.byKey(ValueKey('round-pip-${fighter.name}-$i')),
          findsOneWidget,
        );
      }
      expect(find.byKey(ValueKey('round-pip-${fighter.name}-3')), findsNothing);
    }
    expect(
      find.byKey(const ValueKey('round-result-card')),
      findsNothing,
      reason: 'a fresh match has no previous-round result',
    );
  });

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

  testWidgets('backgrounding stops the fight — the return hands the player '
      'the choice', (tester) async {
    final game = await mountFight(tester);
    await tester.tap(find.text('GOT IT'));
    await tester.pump();

    // Into live combat, with some of the clock already spent.
    for (var i = 0; i < 190 && game.match.phase != MatchPhase.fighting; i++) {
      game.update(1 / 60);
    }
    expect(game.match.phase, MatchPhase.fighting);
    for (var i = 0; i < 60; i++) {
      game.update(1 / 60);
    }
    final clock = game.match.timeRemainingMs;
    expect(clock, lessThan(game.match.rules.roundMs));

    // The player leaves the app mid-fight: nothing may keep running, and
    // nothing may be decided off-screen.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(game.paused, isTrue, reason: 'the system pause stops the engine');
    expect(
      find.text('PAUSED'),
      findsNothing,
      reason: 'there is nothing to read off-screen',
    );

    // Away for a while: the round clock must not notice (catch-up clamps).
    await tester.pump(const Duration(seconds: 5));
    expect(game.match.timeRemainingMs, clock);

    // Back in: the fight does not silently resume — the player chooses.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(game.paused, isTrue, reason: 'still stopped behind the overlay');
    expect(find.text('PAUSED'), findsOneWidget);
    expect(game.match.timeRemainingMs, clock);

    // Frozen while the overlay is up; thawed only by the player's RESUME.
    await tester.pump(const Duration(milliseconds: 400));
    expect(game.match.timeRemainingMs, clock);
    await tester.tap(find.text('RESUME'));
    await tester.pump();
    expect(find.text('PAUSED'), findsNothing);
    expect(game.paused, isFalse);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    expect(game.match.timeRemainingMs, lessThan(clock));
  });

  testWidgets('backgrounding under the round-end card leaves the card alone', (
    tester,
  ) async {
    final game = await mountFight(tester);
    await tester.tap(find.text('GOT IT'));
    await tester.pump();

    // Play the same idle loss as the card test, cinema included.
    for (var i = 0; i < 4200 && !game.match.isFinished; i++) {
      game.update(1 / 60);
    }
    expect(game.match.isFinished, isTrue);
    await tester.pump();
    var guard = 0;
    while (!game.roundEndCardVisible && guard++ < 90) {
      await tester.pump(const Duration(milliseconds: 17));
    }
    expect(game.roundEndCardVisible, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    // The decided match has nothing left to freeze, and no overlay may cover
    // the card that already owns REMATCH and the way out.
    expect(find.text('PAUSED'), findsNothing);
    expect(find.text('REMATCH'), findsOneWidget);
    expect(
      game.paused,
      isFalse,
      reason: 'the engine may idle again — there is nothing left to fight',
    );
  });

  testWidgets('unmounting the arena cleans up and a remount starts fresh', (
    tester,
  ) async {
    final game = await mountFight(tester);
    await tester.tap(find.text('GOT IT'));
    await tester.pump();

    // A dirty fight: countdown spent, clock run down, someone has been hit.
    for (var i = 0; i < 430; i++) {
      game.update(1 / 60);
    }
    expect(game.match.timeRemainingMs, lessThan(game.match.rules.roundMs));

    // Leave the way QUIT TO MENU does: the screen unmounts, stops the engine
    // and takes its lifecycle observer off the binding's list.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(find.byType(BotFightScreen), findsNothing);
    expect(game.paused, isTrue, reason: 'leaving the screen stops the engine');

    // A later lifecycle edge must not reach the dead screen: no crash, and no
    // overlay anywhere afterwards.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('PAUSED'), findsNothing);

    // Coming back builds a whole new game: no round card, no cinema, no stuck
    // pause, full health and a full clock.
    final rematch = await mountFight(tester);
    expect(rematch, isNot(same(game)));
    expect(rematch.paused, isFalse);
    expect(rematch.match.phase, MatchPhase.countdown);
    expect(rematch.match.timeRemainingMs, rematch.match.rules.roundMs);
    expect(
      rematch.match.stateOf(FighterId.player).health,
      rematch.match.rules.health,
    );
    expect(
      rematch.match.stateOf(FighterId.rival).health,
      rematch.match.rules.health,
    );
    expect(rematch.roundEndCardVisible, isFalse);
    expect(find.text('PAUSED'), findsNothing);
    expect(
      find.text('GOT IT'),
      findsOneWidget,
      reason: 'a fresh mount greets again and inherits nothing',
    );
  });

  /// Records every call the app makes on `SystemChannels.platform` — the
  /// channel `HapticFeedback` speaks through. Same recipe as the haptics
  /// group in `game_feel_test.dart`.
  List<MethodCall> recordPlatformCalls() {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    return calls;
  }

  /// Just the vibration traffic: the channel carries other calls too
  /// (Material's buttons play a system click when tapped), and this test is
  /// about haptics.
  List<MethodCall> hapticCalls(List<MethodCall> calls) =>
      calls.where((call) => call.method == 'HapticFeedback.vibrate').toList();

  /// Ticks the opening countdown away so the match is live.
  void pastCountdown(InkFightBattleGame game) {
    for (var i = 0; i < 190 && game.match.phase != MatchPhase.fighting; i++) {
      game.update(1 / 60);
    }
    expect(game.match.phase, MatchPhase.fighting);
  }

  /// Walks the player in and jabs until one lands (the §2 pattern the haptics
  /// group in `game_feel_test.dart` uses).
  void landOneJab(InkFightBattleGame game) {
    final jabReach = game.match.rules.lightAttack.reach;
    var landed = false;
    for (var i = 0; i < 400 && !landed; i++) {
      final player = game.match.stateOf(FighterId.player);
      final gap = (game.match.stateOf(FighterId.rival).x - player.x).abs();
      if (gap > jabReach * .9) {
        game.setPlayerMoving(true);
      } else {
        game.setPlayerMoving(false);
        if (player.canAct) {
          game.sendPlayerAction(InputAction.lightPunch);
        }
      }
      game.update(1 / 60);
      landed = game.match.stateOf(FighterId.rival).health < 100;
    }
    expect(landed, isTrue, reason: 'the light punch should connect');
  }

  testWidgets('HAPTICS off in the model silences a landed connect', (
    tester,
  ) async {
    final calls = recordPlatformCalls();
    final game = await mountFight(
      tester,
      settings: InkSettings(hapticsOn: false),
    );
    expect(
      game.hapticsEnabled,
      isFalse,
      reason: 'the mount puts the model on the game',
    );

    pastCountdown(game);
    landOneJab(game);
    expect(
      hapticCalls(calls),
      isEmpty,
      reason: 'the switch the player flipped reaches the platform channel',
    );
  });

  testWidgets('HAPTICS on cues a landed hit, and the model drives it live', (
    tester,
  ) async {
    final calls = recordPlatformCalls();
    final settings = InkSettings();
    final game = await mountFight(tester, settings: settings);
    expect(game.hapticsEnabled, isTrue);

    // The screen listens to the model while it is alive: a flip lands on the
    // game at once, in both directions.
    settings.hapticsOn = false;
    expect(game.hapticsEnabled, isFalse);
    settings.hapticsOn = true;
    expect(game.hapticsEnabled, isTrue);

    pastCountdown(game);
    landOneJab(game);

    // One cue per landed connect is the feel test's promise — it fights a
    // passive bot there. The live practice bot may trade in the same window,
    // so this asserts the cue the player's own connect carries: a light
    // impact on the platform channel, while the switch is on.
    expect(
      hapticCalls(calls).map((call) => call.arguments),
      contains('HapticFeedbackType.lightImpact'),
    );
  });

  testWidgets('SOUND off in the model leaves the mounted fight silent', (
    tester,
  ) async {
    final game = await mountFight(
      tester,
      settings: InkSettings(soundOn: false),
    );

    expect(
      game.soundEnabled,
      isFalse,
      reason: 'the mount puts the model on the game',
    );
    expect(
      game.sounds,
      isA<SilentFightSounds>(),
      reason: 'the screen hands its injected seam to the game',
    );
    // The app's own path passes no seam — `null` here — and the screen then
    // builds the real `FlameFightSounds` (see `initState`); no test mounts
    // that path, so the audio plugin is never loaded in this suite.
    expect(BotFightScreen(settings: InkSettings()).sounds, isNull);
  });

  testWidgets('the SOUND switch reaches a live game through the listener', (
    tester,
  ) async {
    final settings = InkSettings();
    final game = await mountFight(tester, settings: settings);
    expect(game.soundEnabled, isTrue);

    settings.soundOn = false;
    expect(game.soundEnabled, isFalse);
    settings.soundOn = true;
    expect(game.soundEnabled, isTrue);
  });

  testWidgets('a landed hit leaves a damage trail that eases down', (
    tester,
  ) async {
    final game = await mountFight(tester);
    await tester.tap(find.text('GOT IT'));
    await tester.pump();

    // An idle player takes the bot's first connect headlessly.
    for (var i = 0; i < 1200; i++) {
      if (game.match.stateOf(FighterId.player).health <
          game.match.rules.health) {
        break;
      }
      game.update(1 / 60);
    }
    expect(
      game.match.stateOf(FighterId.player).health,
      lessThan(game.match.rules.health),
    );

    // All four bars on screen: YOU's trail-and-crisp pair rides first —
    // the HUD row builds YOU before CRIMSON RIVAL — and the flash is the
    // one Opacity washed over a white plate.
    List<double> allBars() => tester
        .widgetList<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        )
        .map((bar) => bar.value!)
        .toList();
    double flashWash() => tester
        .widgetList<Opacity>(
          find.byWidgetPredicate(
            (widget) => widget is Opacity && widget.child is ColoredBox,
          ),
        )
        .first
        .opacity;

    // First live frame: the crisp bar snaps and the wash flashes; the
    // second lets the trail ease off its old edge.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    final target =
        game.match.stateOf(FighterId.player).health / game.match.rules.health;
    final mid = allBars();
    expect(mid, hasLength(4), reason: 'two layers on each of two bars');
    expect(mid[1], closeTo(target, .0001), reason: 'the crisp bar snaps');
    expect(mid[0], greaterThan(mid[1]), reason: 'the trail holds the edge');
    expect(mid[0], lessThan(1.0), reason: '...already easing down');
    expect(flashWash(), greaterThan(0));

    // Freeze the fight: the trail must finish on ticker time alone.
    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    final frozenTarget =
        game.match.stateOf(FighterId.player).health / game.match.rules.health;
    final settled = allBars();
    expect(settled, hasLength(4));
    expect(settled[1], closeTo(frozenTarget, .0001));
    expect(settled[0], frozenTarget);
    expect(flashWash(), lessThan(.01));
  });

  testWidgets('the countdown chip counts 3-2-1-FIGHT from the rules', (
    tester,
  ) async {
    final game = await mountFight(tester);
    await tester.tap(find.text('GOT IT'));
    await tester.pump();

    Future<void> expectBeat(String beat, int floorMs) async {
      for (
        var i = 0;
        i < 200 && game.match.countdownRemainingMs > floorMs;
        i++
      ) {
        game.update(1 / 60);
      }
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      expect(find.text(beat), findsOneWidget);
    }

    await expectBeat('3', 2000);
    await expectBeat('2', 1400);
    await expectBeat('1', 900);
    await expectBeat('FIGHT!', 400);

    // Past the countdown the chip is the round clock again.
    for (var i = 0; i < 190 && game.match.phase != MatchPhase.fighting; i++) {
      game.update(1 / 60);
    }
    expect(game.match.phase, MatchPhase.fighting);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.text('01 : 00'), findsOneWidget);
  });

  testWidgets('FIGHT! and its sting share one tick, once per rematch', (
    tester,
  ) async {
    final sounds = _RecordingFightSounds();
    final game = await mountFight(tester, sounds: sounds);
    await tester.tap(find.text('GOT IT'));
    await tester.pump();
    game.pauseEngine();

    void reachFightBeat() {
      for (var i = 0; i < 200 && game.match.countdownRemainingMs > 500; i++) {
        game.update(1 / 60);
      }
    }

    expect(sounds.cues.where((cue) => cue == FightCue.roundSting), isEmpty);
    reachFightBeat();
    // Manual sim time has reached the beat, but the chip has not drawn it.
    expect(find.text('FIGHT!'), findsNothing);
    expect(sounds.cues.where((cue) => cue == FightCue.roundSting), isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('FIGHT!'), findsOneWidget);
    expect(
      sounds.cues.where((cue) => cue == FightCue.roundSting),
      hasLength(1),
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      sounds.cues.where((cue) => cue == FightCue.roundSting),
      hasLength(1),
    );

    game.restartMatch();
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('3'), findsOneWidget);
    reachFightBeat();
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('FIGHT!'), findsOneWidget);
    expect(
      sounds.cues.where((cue) => cue == FightCue.roundSting),
      hasLength(2),
    );
  });

  testWidgets('muted FIGHT! stays silent even when sound is enabled mid-beat', (
    tester,
  ) async {
    final sounds = _RecordingFightSounds();
    final settings = InkSettings(soundOn: false);
    final game = await mountFight(tester, settings: settings, sounds: sounds);
    await tester.tap(find.text('GOT IT'));
    await tester.pump();
    game.pauseEngine();
    for (var i = 0; i < 200 && game.match.countdownRemainingMs > 500; i++) {
      game.update(1 / 60);
    }
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('FIGHT!'), findsOneWidget);
    expect(sounds.cues, isEmpty);
    settings.soundOn = true;
    await tester.pump(const Duration(milliseconds: 100));
    expect(sounds.cues, isEmpty);
  });

  testWidgets('FIGHT! strobes on sim time across its beat', (tester) async {
    final game = await mountFight(tester);
    await tester.tap(find.text('GOT IT'));
    await tester.pump();

    double chipFlash() => tester
        .widget<Opacity>(
          find.ancestor(
            of: find.text('FIGHT!'),
            matching: find.byType(Opacity),
          ),
        )
        .opacity;

    // Land mid-cell in two neighbouring blink cells (125 ms halves).
    for (var i = 0; i < 200 && game.match.countdownRemainingMs > 450; i++) {
      game.update(1 / 60);
    }
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.text('FIGHT!'), findsOneWidget);
    expect(chipFlash(), .45);

    for (var i = 0; i < 200 && game.match.countdownRemainingMs > 350; i++) {
      game.update(1 / 60);
    }
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.text('FIGHT!'), findsOneWidget);
    expect(chipFlash(), 1.0);
  });

  testWidgets('a pressed button answers with a smaller, inked plate', (
    tester,
  ) async {
    final game = await mountFight(tester);
    await tester.tap(find.text('GOT IT'));
    await tester.pump();
    pastCountdown(game);
    await tester.pump(const Duration(milliseconds: 50));

    double punchScale() {
      final plate = tester.widget<Transform>(
        find.ancestor(of: find.text('PUNCH'), matching: find.byType(Transform)),
      );
      return plate.transform.storage[0];
    }

    expect(punchScale(), closeTo(1, .0001));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('PUNCH')),
    );
    await tester.pump();
    expect(punchScale(), closeTo(.93, .0001));

    await gesture.up();
    await tester.pump();
    expect(punchScale(), closeTo(1, .0001));
  });

  testWidgets('buttons go quiet while the player cannot act', (tester) async {
    final game = await mountFight(tester);
    await tester.tap(find.text('GOT IT'));
    await tester.pump();
    pastCountdown(game);
    await tester.pump(const Duration(milliseconds: 50));

    double punchDim() => tester
        .widget<Opacity>(
          find.ancestor(of: find.text('PUNCH'), matching: find.byType(Opacity)),
        )
        .opacity;

    expect(punchDim(), 1.0);

    // A jab commits the player; freeze mid-swing and the row reads busy.
    game.sendPlayerAction(InputAction.lightPunch);
    for (var i = 0; i < 5; i++) {
      game.update(1 / 60);
    }
    expect(game.match.stateOf(FighterId.player).canAct, isFalse);
    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump(const Duration(milliseconds: 50));
    expect(punchDim(), .55);

    // Through recovery and idle again: full voice back.
    await tester.tap(find.text('RESUME'));
    await tester.pump();
    for (
      var i = 0;
      i < 120 && !game.match.stateOf(FighterId.player).canAct;
      i++
    ) {
      game.update(1 / 60);
    }
    expect(game.match.stateOf(FighterId.player).canAct, isTrue);
    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump(const Duration(milliseconds: 50));
    expect(punchDim(), 1.0);
  });

  HitEvent statEvent(FighterId attacker, HitKind kind) => HitEvent(
    attacker: attacker,
    defender: attacker == FighterId.player ? FighterId.rival : FighterId.player,
    kind: kind,
    heavy: false,
    x: 150,
    ko: false,
  );

  testWidgets('combo stamps re-enter, stay above fill and reset at failure', (
    tester,
  ) async {
    final game = await mountFight(tester);
    await tester.tap(find.text('GOT IT'));
    await tester.pump();
    game.pauseEngine();
    game.stats.onHit(statEvent(FighterId.player, HitKind.hit));
    await tester.pump();
    expect(find.text('1 HITS'), findsNothing);
    game.stats.onHit(statEvent(FighterId.player, HitKind.hit));
    await tester.pump();
    expect(find.text('2 HITS'), findsOneWidget);
    double scale() => tester
        .widget<Transform>(find.byKey(const ValueKey('combo-scale')))
        .transform
        .storage[0];
    expect(scale(), closeTo(1.06, .0001));
    await tester.pump(const Duration(milliseconds: 180));
    expect(scale(), 1);
    expect(
      tester.getRect(find.text('2 HITS')).bottom,
      lessThan(
        tester.getRect(find.byKey(const ValueKey('health-live-YOU'))).top,
      ),
    );
    game.stats.onHit(statEvent(FighterId.player, HitKind.hit));
    await tester.pump();
    expect(find.text('3 HITS'), findsOneWidget);
    expect(scale(), closeTo(1.06, .0001), reason: 'new count re-stamps');
    // At compact landscape the badge remains inside the existing HUD label.
    tester.view.physicalSize = const Size(640, 360);
    tester.view.devicePixelRatio = 1;
    await tester.pump(const Duration(milliseconds: 180));
    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.text('3 HITS')).bottom,
      lessThan(
        tester.getRect(find.byKey(const ValueKey('health-live-YOU'))).top,
      ),
    );
    game.stats.onHit(statEvent(FighterId.player, HitKind.whiff));
    await tester.pump();
    expect(find.text('3 HITS'), findsNothing);
    game.stats.onHit(statEvent(FighterId.player, HitKind.hit));
    game.stats.onHit(statEvent(FighterId.player, HitKind.hit));
    await tester.pump();
    expect(find.text('2 HITS'), findsOneWidget);
    game.stats.onHit(statEvent(FighterId.rival, HitKind.hit));
    await tester.pump();
    expect(find.text('2 HITS'), findsNothing);
    expect(game.stats.maxCombo, 3);
    game.restartMatch();
    await tester.pump();
    expect(game.stats.hitsLanded, 0);
    expect(game.stats.maxCombo, 0);
  });

  testWidgets(
    'real resolved connects reach stats through the single arena drain',
    (tester) async {
      final game = await mountFight(tester);
      pastCountdown(game);
      landOneJab(game);
      expect(game.stats.hitsLanded, greaterThanOrEqualTo(1));
      final hits = game.stats.hitsLanded;
      game.update(0);
      expect(
        game.stats.hitsLanded,
        hits,
        reason: 'the hit is not counted twice',
      );
    },
  );

  void clockTo(InkFightBattleGame game, int remainingMs) {
    for (var i = 0; i < 5000 && game.match.timeRemainingMs > remainingMs; i++) {
      // Drive only the rules clock so the bot cannot end a clock-only test.
      game.match.tick(.016);
    }
  }

  testWidgets('10-second pulse freezes on pause, 3/2/1 blips replace ticks', (
    tester,
  ) async {
    final sounds = _RecordingFightSounds();
    final game = await mountFight(tester, sounds: sounds);
    await tester.tap(find.text('GOT IT'));
    await tester.pump();
    pastCountdown(game);
    game.pauseEngine();
    sounds.cues.clear();
    clockTo(game, 11000);
    await tester.pump(const Duration(milliseconds: 1));
    expect(sounds.cues, isEmpty);
    Color plate() =>
        (tester
                    .widget<Container>(
                      find.byKey(const ValueKey('timer-chip-plate')),
                    )
                    .decoration!
                as BoxDecoration)
            .color!;
    final normal = plate();
    for (var second = 10; second >= 1; second--) {
      clockTo(game, second * 1000);
      sounds.cues.clear();
      await tester.pump(const Duration(milliseconds: 1));
      expect(
        find.text('00 : ${second.toString().padLeft(2, '0')}'),
        findsOneWidget,
      );
      expect(sounds.cues, [
        second <= 3 ? FightCue.countdownBlip : FightCue.clockTick,
      ]);
      final frozenPlate = plate();
      expect(frozenPlate, isNot(normal));
      expect(
        frozenPlate,
        isNot(const Color(0xFFC51F3A)),
        reason: 'restrained tint',
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(plate(), frozenPlate, reason: 'pulse holds sim time while paused');
      expect(sounds.cues, hasLength(1), reason: 'no repeat or double tick');
    }
    clockTo(game, 0);
    sounds.cues.clear();
    await tester.pump(const Duration(milliseconds: 1));
    expect(sounds.cues, isEmpty);
    expect(plate(), normal, reason: 'urgency ends with the fight');
    game.restartMatch();
    await tester.pump(const Duration(milliseconds: 1));
    pastCountdown(game);
    clockTo(game, 10000);
    sounds.cues.clear();
    await tester.pump(const Duration(milliseconds: 1));
    expect(sounds.cues, [
      FightCue.clockTick,
    ], reason: 'rematch re-arms clock cues');
  });

  testWidgets(
    'muted late-clock ticks and blips are consumed without catch-up',
    (tester) async {
      final sounds = _RecordingFightSounds();
      final settings = InkSettings(soundOn: false);
      final game = await mountFight(tester, sounds: sounds, settings: settings);
      await tester.tap(find.text('GOT IT'));
      await tester.pump();
      pastCountdown(game);
      game.pauseEngine();
      clockTo(game, 10000);
      await tester.pump(const Duration(milliseconds: 1));
      expect(sounds.cues, isEmpty);
      settings.soundOn = true;
      await tester.pump(const Duration(milliseconds: 100));
      expect(sounds.cues, isEmpty);
      settings.soundOn = false;
      clockTo(game, 3000);
      await tester.pump(const Duration(milliseconds: 1));
      expect(sounds.cues, isEmpty);
      settings.soundOn = true;
      await tester.pump(const Duration(milliseconds: 100));
      expect(sounds.cues, isEmpty);
    },
  );

  testWidgets('result row retains whole-match totals and rematch clears them', (
    tester,
  ) async {
    final game = await mountFight(tester);
    await tester.tap(find.text('GOT IT'));
    await tester.pump();
    pastCountdown(game);
    game.pauseEngine();
    game.stats.onHit(statEvent(FighterId.player, HitKind.hit));
    game.stats.onHit(statEvent(FighterId.player, HitKind.hit));
    game.stats.onHit(statEvent(FighterId.player, HitKind.whiff));
    game.stats.onHit(statEvent(FighterId.player, HitKind.hit));
    game.stats.onHit(statEvent(FighterId.rival, HitKind.blocked));
    clockTo(game, 0);
    game.update(1 / 60);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    for (final entry in {
      'HITS LANDED': '3',
      'BLOCKS': '1',
      'MAX COMBO': '2',
    }.entries) {
      expect(find.text(entry.key), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(ValueKey('result-${entry.key}'))).data,
        entry.value,
      );
    }
    final paper = tester.widget<Container>(
      find.byKey(const ValueKey('round-end-paper')),
    );
    expect(
      (paper.decoration! as BoxDecoration).gradient,
      isNull,
      reason: 'draws have no losing half',
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('result-TIME'))).data,
      '01:00',
    );
    tester.view.physicalSize = const Size(640, 360);
    tester.view.devicePixelRatio = 1;
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      find.text('1 HITS'),
      findsNothing,
      reason: 'finished HUD has no combo badge',
    );
    await tester.tap(find.text('REMATCH'));
    await tester.pump();
    expect(
      [game.stats.hitsLanded, game.stats.blocks, game.stats.maxCombo],
      [0, 0, 0],
    );
    expect(find.text('HITS LANDED'), findsNothing);
  });

  // Move/attack through the public controller, without running the bot.
  // The arena then consumes the real resolved events once, just as in play.
  void hurtTo(InkFightBattleGame game, FighterId victim, int threshold) {
    final attacker = victim == FighterId.player
        ? FighterId.rival
        : FighterId.player;
    final match = game.match;
    for (
      var i = 0;
      i < 8000 && match.stateOf(victim).health >= threshold;
      i++
    ) {
      final state = match.stateOf(attacker);
      final gap = match.stateOf(victim).x - state.x;
      final approach = gap.abs() > match.rules.lightAttack.reach * .85;
      match.setMoveAxis(attacker, approach ? gap.sign : 0);
      if (!approach && state.canAct) {
        match.submit(
          InputCommand(
            fighter: attacker,
            action: InputAction.lightPunch,
            sequence: 10000 + i,
          ),
        );
      }
      match.tick(.016);
    }
    match.setMoveAxis(attacker, 0);
    expect(match.stateOf(victim).health, lessThan(threshold));
    game.update(.000001);
  }

  Future<List<int>> dripAlpha(WidgetTester tester, String label) async {
    final paint = tester.widget<CustomPaint>(
      find.byKey(ValueKey('health-drip-$label')),
    );
    final size = tester.getSize(find.byKey(ValueKey('health-drip-$label')));
    final pixels = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      paint.painter!.paint(Canvas(recorder), size);
      final picture = recorder.endRecording();
      final image = await picture.toImage(
        size.width.ceil(),
        size.height.ceil(),
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final bytes = data!.buffer.asUint8List();
      final alpha = [for (var i = 3; i < bytes.length; i += 4) bytes[i]];
      image.dispose();
      picture.dispose();
      return alpha;
    });
    return pixels!;
  }

  for (final victim in FighterId.values) {
    testWidgets(
      'low-health drip for $victim attaches, detaches and clears on recovery',
      (tester) async {
        final game = await mountFight(tester);
        await tester.tap(find.text('GOT IT'));
        await tester.pump();
        pastCountdown(game);
        game.pauseEngine();
        final label = victim == FighterId.player ? 'YOU' : 'CRIMSON RIVAL';
        final drip = find.byKey(ValueKey('health-drip-$label'));
        expect(drip, findsNothing, reason: 'healthy bars stay dry');
        hurtTo(game, victim, 25);
        await tester.pump(const Duration(milliseconds: 1));
        expect(drip, findsOneWidget);
        final health = game.match.stateOf(victim).health;
        expect(health, inInclusiveRange(1, 24));
        final bar = find.byKey(ValueKey('health-live-$label'));
        final barRect = tester.getRect(bar);
        final dripRect = tester.getRect(drip);
        expect(dripRect.top, greaterThanOrEqualTo(barRect.bottom));
        expect(dripRect.height, 8);
        expect(dripRect.width, barRect.width);
        final live = tester.widget<LinearProgressIndicator>(bar).value;
        expect(live, health / game.match.rules.health);
        await tester.pump(const Duration(milliseconds: 300));
        final attached = await dripAlpha(tester, label);
        final width = tester.getSize(drip).width.ceil();
        expect(
          attached.take(width).any((alpha) => alpha > 0),
          isTrue,
          reason: 'the attached neck starts below the live fill',
        );
        await tester.pump(const Duration(milliseconds: 900));
        final detached = await dripAlpha(tester, label);
        expect(
          detached.take(width).every((alpha) => alpha == 0),
          isTrue,
          reason: 'the neck is gone once the bead detaches',
        );
        expect(
          detached.any((alpha) => alpha > 0),
          isTrue,
          reason: 'one faint falling drop remains in the gutter',
        );
        expect(
          tester.widget<LinearProgressIndicator>(bar).value,
          live,
          reason: 'a drip never modifies health',
        );
        game.restartMatch();
        await tester.pump();
        expect(
          drip,
          findsNothing,
          reason: 'recovery clears detached ink immediately',
        );
        expect(find.text('100%'), findsNWidgets(2));
      },
    );
  }

  testWidgets(
    'escalating stats keep sound-off hits silent and reset on rematch',
    (tester) async {
      final sounds = _RecordingFightSounds();
      final game = await mountFight(
        tester,
        settings: InkSettings(soundOn: false),
        sounds: sounds,
      );
      await tester.tap(find.text('GOT IT'));
      await tester.pump();
      pastCountdown(game);
      game.pauseEngine();
      hurtTo(game, FighterId.rival, 80);
      await tester.pump(const Duration(milliseconds: 1));
      expect(game.stats.combo, greaterThanOrEqualTo(4));
      expect(game.stats.hitPitchCombo, game.stats.combo);
      expect(
        sounds.cues,
        isEmpty,
        reason: 'the existing gate precedes every escalating cue',
      );
      game.restartMatch();
      await tester.pump();
      expect(game.stats.hitPitchCombo, 0);
      expect(sounds.cues, isEmpty);
    },
  );

  for (final victim in FighterId.values) {
    testWidgets('only $victim losing half receives the consequence wash', (
      tester,
    ) async {
      final game = await mountFight(tester);
      await tester.tap(find.text('GOT IT'));
      await tester.pump();
      pastCountdown(game);
      game.pauseEngine();
      hurtTo(game, victim, 1);
      for (var i = 0; i < 90 && !game.roundEndCardVisible; i++) {
        game.update(.017);
      }
      expect(game.roundEndCardVisible, isTrue);
      expect(
        game.match.outcome,
        victim == FighterId.player
            ? MatchOutcome.rivalWin
            : MatchOutcome.playerWin,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      final face = tester.widget<Container>(
        find.byKey(const ValueKey('round-end-paper')),
      );
      final gradient =
          (face.decoration! as BoxDecoration).gradient! as LinearGradient;
      final white = Colors.white;
      final winnerColours = victim == FighterId.player
          ? gradient.colors.skip(2)
          : gradient.colors.take(2);
      final loserColours = victim == FighterId.player
          ? gradient.colors.take(2)
          : gradient.colors.skip(2);
      expect(winnerColours, everyElement(white));
      expect(loserColours, everyElement(isNot(white)));
      expect(gradient.stops, [0, .5, .5, 1]);
      await tester.pump();
      final manifest = await tester.runAsync(
        () => AssetManifest.loadFromAssetBundle(rootBundle),
      );
      for (final fighter in FighterId.values) {
        final name = fighter == FighterId.player
            ? 'player_ink_fighter'
            : 'bot_crimson_rival';
        final pose = fighter == victim ? 'defeat' : 'victory';
        final prefix = 'assets/characters/runtime/$name/$pose/';
        final paths =
            manifest!
                .listAssets()
                .where(
                  (path) => path.startsWith(prefix) && path.endsWith('.png'),
                )
                .toList()
              ..sort();
        final image = tester.widget<Image>(
          find.byKey(ValueKey('result-art-$fighter')),
        );
        String framePath() {
          final frame = tester.widget<Image>(
            find.byKey(ValueKey('result-art-$fighter')),
          );
          return ((frame.image as ResizeImage).imageProvider as AssetImage)
              .assetName;
        }

        expect(
          ((image.image as ResizeImage).imageProvider as AssetImage).assetName,
          isIn(paths),
        );
        final first = framePath();
        final seen = <String>{};
        for (var i = 0; i < paths.length; i++) {
          seen.add(framePath());
          await tester.pump(const Duration(milliseconds: 120));
        }
        expect(
          seen,
          unorderedEquals(paths),
          reason: 'play every delivered $pose frame, without assuming a count',
        );
        expect(
          framePath(),
          first,
          reason: 'the cycle loops instead of holding a still',
        );
      }
      final seconds =
          ((game.match.rules.roundMs - game.match.timeRemainingMs) / 1000)
              .ceil();
      final time =
          '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('result-TIME'))).data,
        time,
      );
      expect(find.byTooltip('Elapsed fight time'), findsOneWidget);
      final statsRow = tester.widget<Container>(
        find.byKey(const ValueKey('result-stats-row')),
      );
      expect(
        (statsRow.decoration! as BoxDecoration).color,
        victim == FighterId.player
            ? isNot(Colors.transparent)
            : Colors.transparent,
      );

      expect(
        find.byKey(const ValueKey('health-drip-YOU')),
        findsNothing,
        reason: victim == FighterId.player
            ? 'a KO bar is dry'
            : 'healthy player is dry',
      );
      expect(
        find.byKey(const ValueKey('health-drip-CRIMSON RIVAL')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unravel cues whiff, hit taken and round-end breaks once each', (
    tester,
  ) async {
    final sounds = _RecordingFightSounds();
    final game = await mountFight(tester, sounds: sounds);
    await tester.tap(find.text('GOT IT'));
    await tester.pump();
    pastCountdown(game);
    game.pauseEngine();
    sounds.cues.clear();
    void combo() {
      game.stats.onHit(statEvent(FighterId.player, HitKind.hit));
      game.stats.onHit(statEvent(FighterId.player, HitKind.hit));
    }

    combo();
    game.stats.onHit(statEvent(FighterId.player, HitKind.whiff));
    game.stats.onHit(statEvent(FighterId.player, HitKind.whiff));
    expect(
      sounds.cues.where((cue) => cue == FightCue.comboUnravel),
      hasLength(1),
    );
    combo();
    game.stats.onHit(statEvent(FighterId.rival, HitKind.hit));
    expect(
      sounds.cues.where((cue) => cue == FightCue.comboUnravel),
      hasLength(2),
    );
    combo();
    clockTo(game, 0);
    game.update(.000001);
    await tester.pump(const Duration(milliseconds: 1));
    expect(
      sounds.cues.where((cue) => cue == FightCue.comboUnravel),
      hasLength(3),
    );
    expect(game.stats.combo, 0);
    expect(game.stats.maxCombo, 2);
    await tester.pump(const Duration(milliseconds: 180));
    expect(
      sounds.cues.where((cue) => cue == FightCue.comboUnravel),
      hasLength(3),
    );
  });

  testWidgets('muted unravel never catches up when sound returns', (
    tester,
  ) async {
    final sounds = _RecordingFightSounds();
    final settings = InkSettings(soundOn: false);
    final game = await mountFight(tester, settings: settings, sounds: sounds);
    await tester.tap(find.text('GOT IT'));
    await tester.pump();
    pastCountdown(game);
    game.pauseEngine();
    for (var i = 0; i < 2; i++) {
      game.stats.onHit(statEvent(FighterId.player, HitKind.hit));
    }
    game.stats.onHit(statEvent(FighterId.player, HitKind.whiff));
    settings.soundOn = true;
    await tester.pump(const Duration(milliseconds: 1));
    expect(sounds.cues, isEmpty);
    settings.soundOn = false;
    for (var i = 0; i < 2; i++) {
      game.stats.onHit(statEvent(FighterId.player, HitKind.hit));
    }
    clockTo(game, 0);
    game.update(.000001);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(sounds.cues, isEmpty);
    await tester.tap(find.text('REMATCH'));
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
    expect(sounds.cues, isEmpty);
    settings.soundOn = true;
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      sounds.cues.where(
        (cue) => cue == FightCue.comboUnravel || cue == FightCue.roundSting,
      ),
      isEmpty,
      reason: 'no late unravel or fabricated round sting; normal countdown blips may play',
    );
  });

  testWidgets(
    'rematches start the existing countdown without round stamps or extra sting',
    (tester) async {
      final sounds = _RecordingFightSounds();
      final game = await mountFight(tester, sounds: sounds);
      await tester.tap(find.text('GOT IT'));
      await tester.pump();
      for (var attempt = 0; attempt < 2; attempt++) {
        pastCountdown(game);
        game.pauseEngine();
        clockTo(game, 0);
        game.update(.000001);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 180));
        sounds.cues.clear();
        await tester.tap(find.text('REMATCH'));
        await tester.pump();
        expect(find.textContaining(RegExp(r'ROUND \d+')), findsNothing);
        expect(find.text('3'), findsOneWidget);
        expect(find.text('FIGHT!'), findsNothing);
        expect(game.match.phase, MatchPhase.countdown);
        expect(sounds.cues.where((cue) => cue == FightCue.roundSting), isEmpty);
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          game.match.countdownRemainingMs,
          lessThan(game.match.rules.countdownMs),
          reason: 'no presentation-only pre-count hold',
        );
      }
    },
  );

  testWidgets('the arena HUD fits 640x360 without overflow', (tester) async {
    final game = await mountFight(tester);
    await tester.tap(find.text('GOT IT'));
    await tester.pump();
    pastCountdown(game);

    tester.view.physicalSize = const Size(640, 360);
    tester.view.devicePixelRatio = 1;
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('YOU'), findsOneWidget);
    expect(find.text('CRIMSON RIVAL'), findsOneWidget);
    expect(game.match.phase, MatchPhase.fighting);
    expect(tester.takeException(), isNull);
  });
}
