import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inkfight/game/audio/fight_sounds.dart';
import 'package:inkfight/game/bot/bot_strategy.dart';
import 'package:inkfight/game/ink_fight_battle_game.dart';
import 'package:inkfight/game/rules/input_command.dart';
import 'package:inkfight/game/rules/match_rules.dart';
import 'package:inkfight/screens/bot_fight_screen.dart';
import 'package:inkfight/state/ink_settings.dart';
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
            ? 'YOU WIN'
            : 'CRIMSON RIVAL WINS',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('REMATCH'));
    await tester.pump();
    expect(find.text('REMATCH'), findsNothing);
    // The fresh countdown restarts on its first beat, not a literal READY.
    expect(find.text('3'), findsOneWidget);
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
  }) async {
    tester.view.physicalSize = const Size(1600, 720);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    late final InkFightBattleGame game;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: BotFightScreen(
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
