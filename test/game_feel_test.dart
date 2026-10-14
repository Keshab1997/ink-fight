import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inkfight/game/bot/bot_strategy.dart';
import 'package:inkfight/game/ink_fight_battle_game.dart';
import 'package:inkfight/game/rules/input_command.dart';
import 'package:inkfight/game/rules/match_controller.dart';
import 'package:inkfight/game/rules/match_rules.dart';

/// Coverage for the game-feel pass (docs/technical/GAME_FEEL.md): the frame
/// data the animations must obey (§1), hit-stop (§2), the knockout cinematic
/// (§5) and the movement detail (§6), plus the hit events the controller now
/// reports. The screen's overlay lives in `bot_fight_screen_test.dart`, the
/// arena smoke test in `bot_fight_game_test.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A bot that never acts, so every test below watches exactly one fighter.
  const passiveBot = BotProfile(
    difficulty: BotDifficulty.easy,
    thinkIntervalMs: 60000,
    reactionMs: 60000,
    attackCooldownMs: 60000,
    blockChance: 0,
    heavyChance: 0,
    hesitationChance: 1,
    recoveryMs: 0,
    preferredGap: 90,
  );

  Future<InkFightBattleGame> loadedGame({
    BotProfile botProfile = passiveBot,
  }) async {
    final game = InkFightBattleGame(botProfile: botProfile);
    game.onGameResize(Vector2(960, 540));
    await game.onLoad();
    return game;
  }

  List<SpriteAnimationComponent> fightersOf(InkFightBattleGame game) =>
      game.children.whereType<SpriteAnimationComponent>().toList();

  SpriteAnimationComponent rivalOf(InkFightBattleGame game) =>
      fightersOf(game)[0];
  SpriteAnimationComponent playerOf(InkFightBattleGame game) =>
      fightersOf(game)[1];

  void tick(InkFightBattleGame game, int frames) {
    for (var i = 0; i < frames; i++) {
      game.update(1 / 60);
    }
  }

  /// Past the 2000 ms intro countdown, into live combat.
  void pastCountdown(InkFightBattleGame game) => tick(game, 130);

  /// The frame index a component is showing right now.
  int visibleFrame(SpriteAnimationComponent component) =>
      component.animationTicker!.currentIndex;

  double totalMsOf(SpriteAnimationComponent component) => component
      .animation!
      .frames
      .fold<double>(0, (sum, frame) => sum + frame.stepTime * 1000);

  group('§1 frame-data-driven animation', () {
    test('the light punch contact frame shows exactly in the active window', () async {
      final game = await loadedGame();
      pastCountdown(game);
      final player = playerOf(game);
      final rules = game.match.rules;

      game.sendPlayerAction(InputAction.lightPunch);
      // The controller steps in 16 ms slices of the 1/60 s frame time; six
      // updates put the match clock at 96 ms — inside the 90–160 ms window.
      tick(game, 6);
      final state = game.match.stateOf(FighterId.player);
      expect(state.action, FighterAction.lightPunch);
      expect(
        rules.lightAttack.isActiveAt(state.actionElapsedMs),
        isTrue,
        reason: 'elapsed ${state.actionElapsedMs} ms should be active',
      );
      // Frame 002, the contact pose, is on screen while the hitbox is open.
      expect(visibleFrame(player), 2);

      // Four more updates close the window at 160 ms; the sprite has recoiled.
      tick(game, 4);
      expect(
        rules.lightAttack.isActiveAt(
          game.match.stateOf(FighterId.player).actionElapsedMs,
        ),
        isFalse,
      );
      expect(visibleFrame(player), greaterThan(2));
    });

    test(
      'the heavy kick contact frame shows exactly in the active window',
      () async {
        final game = await loadedGame();
        pastCountdown(game);
        final player = playerOf(game);
        final rules = game.match.rules;

        game.sendPlayerAction(InputAction.heavyKick);
        // Fifteen updates put the match clock at 240 ms — the window opens.
        tick(game, 15);
        final state = game.match.stateOf(FighterId.player);
        expect(
          rules.heavyAttack.isActiveAt(state.actionElapsedMs),
          isTrue,
          reason: 'elapsed ${state.actionElapsedMs} ms should be active',
        );
        expect(visibleFrame(player), 3); // frame 003 is the contact pose

        tick(game, 6); // 336 ms: the 240–330 ms window has closed
        expect(
          rules.heavyAttack.isActiveAt(
            game.match.stateOf(FighterId.player).actionElapsedMs,
          ),
          isFalse,
        );
        expect(visibleFrame(player), greaterThan(3));
      },
    );

    test(
      'attack and jump cycles last exactly as long as the rules say',
      () async {
        final game = await loadedGame();
        pastCountdown(game);
        final player = playerOf(game);
        final rules = game.match.rules;

        game.sendPlayerAction(InputAction.lightPunch);
        tick(game, 1);
        expect(player.animation!.frames, hasLength(5)); // no idle bookends
        expect(totalMsOf(player), rules.lightAttack.totalMs.toDouble());

        pastCountdown(game); // let the punch finish into idle
        game.sendPlayerAction(InputAction.heavyKick);
        tick(game, 1);
        expect(player.animation!.frames, hasLength(6));
        expect(totalMsOf(player), rules.heavyAttack.totalMs.toDouble());
      },
    );

    test('the guard raises, holds and drops on the feel schedule', () async {
      final game = await loadedGame();
      pastCountdown(game);
      final player = playerOf(game);

      game.sendPlayerAction(InputAction.block);
      tick(game, 2); // ~32 ms in: still the 90 ms raise
      expect(player.animation!.frames, hasLength(1));

      tick(game, 5); // ~112 ms: the held guard loops frames 001–002
      expect(player.animation!.frames, hasLength(2));
      expect(player.animation!.loop, isTrue);

      // The release frame covers the final 120 ms of the 640 ms hold.
      var guard = 0;
      while (game.match.stateOf(FighterId.player).blockRemainingMs > 120 &&
          guard++ < 60) {
        tick(game, 1);
      }
      expect(game.match.stateOf(FighterId.player).action, FighterAction.block);
      expect(player.animation!.frames, hasLength(1));
      expect(player.animation!.loop, isFalse);

      // ...and the fighter is back on its feet afterwards.
      guard = 0;
      while (game.match.stateOf(FighterId.player).action ==
              FighterAction.block &&
          guard++ < 30) {
        tick(game, 1);
      }
      expect(game.match.stateOf(FighterId.player).action, FighterAction.idle);
      expect(player.animation!.frames, hasLength(4));
    });
  });

  group('§2 hit-stop', () {
    test(
      'a clean hit freezes the fight for its weight but never the ink',
      () async {
        final game = await loadedGame();
        pastCountdown(game);
        final rival = rivalOf(game);

        // Walk in and jab until it lands (the pattern the smoke test uses).
        final jabReach = game.match.rules.lightAttack.reach;
        game.setPlayerMoving(true);
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
          tick(game, 1);
          landed = game.match.stateOf(FighterId.rival).health < 100;
        }
        expect(landed, isTrue, reason: 'the light punch should connect');

        // A light hit stops the world for 70 ms...
        expect(game.hitStopRemainingMs, 70);
        expect(
          game.liveEffectCount,
          greaterThan(0),
          reason: 'the burst spawned',
        );
        // ...the hurt cycle it just handed the rival spans the heavy hitstun,
        // holding its last frame for the shorter light one (§1).
        expect(rival.animation!.frames, hasLength(3));
        expect(totalMsOf(rival), 420);

        final clock = game.match.timeRemainingMs;
        final rivalX = game.match.stateOf(FighterId.rival).x;
        tick(game, 4); // 67 ms of real time: inside the stop
        expect(game.match.timeRemainingMs, clock, reason: 'clock frozen');
        expect(
          game.match.stateOf(FighterId.rival).x,
          rivalX,
          reason: 'knockback frozen mid-stop',
        );
        expect(
          game.liveEffectCount,
          greaterThan(0),
          reason: 'ink still flying',
        );

        tick(game, 4); // ~133 ms: the stop is over, the fight resumes
        expect(game.match.timeRemainingMs, lessThan(clock));
        expect(
          game.match.stateOf(FighterId.rival).x,
          isNot(rivalX),
          reason: 'the shove resumes with the fight',
        );
      },
    );
  });

  group('§5 round flow', () {
    test(
      'a knockout plays slow-motion and a frozen beat before the card',
      () async {
        final game = await loadedGame(botProfile: BotProfile.normal);

        // Stand still; the normal bot finishes the player inside the round.
        for (var i = 0; i < 4200 && !game.match.isFinished; i++) {
          game.update(1 / 60);
        }
        expect(game.match.isFinished, isTrue);
        expect(game.match.stateOf(FighterId.player).health, 0);
        expect(game.match.outcome, MatchOutcome.rivalWin);

        // The card does NOT stamp in over the knockout blow.
        expect(game.roundEndCardVisible, isFalse);

        // 350 ms of slow motion + 250 ms frozen = 36 frames of cinema.
        var guard = 0;
        while (!game.roundEndCardVisible && guard++ < 90) {
          game.update(1 / 60);
        }
        expect(game.roundEndCardVisible, isTrue);
        expect(guard, greaterThanOrEqualTo(35));
        expect(guard, lessThanOrEqualTo(45));

        // The loser is mid-fall: the knockdown cycle (90 ms first frame)...
        final loser = playerOf(game);
        expect(loser.animation!.frames, hasLength(5));
        expect(loser.animation!.frames.first.stepTime, .09);
        expect(loser.animation!.loop, isFalse);
        // ...and the winner loops its victory.
        final winner = rivalOf(game);
        expect(winner.animation!.loop, isTrue);

        // Once 600 ms of animation time has run, the defeat cycle takes over
        // and holds the loser on the ground.
        tick(game, 45);
        expect(loser.animation!.frames, hasLength(5));
        expect(loser.animation!.frames.first.stepTime, .12);
        expect(loser.animation!.loop, isFalse);
      },
    );

    test('a match the clock decides reveals its card at once', () async {
      final game =
          await loadedGame(); // passive bot, idle player: nobody swings

      // 2 s countdown + 60 s round = 3720 frames; give it room.
      for (var i = 0; i < 4000 && !game.match.isFinished; i++) {
        game.update(1 / 60);
      }
      expect(game.match.isFinished, isTrue);
      expect(game.match.outcome, MatchOutcome.draw);
      expect(game.roundEndCardVisible, isTrue, reason: 'no KO, no cinema');
    });

    test('the countdown getter walks the four beats', () {
      final match = MatchController();
      expect(match.countdownRemainingMs, 2000);
      expect(match.phase, MatchPhase.countdown);
      match.tick(.25);
      expect(match.countdownRemainingMs, greaterThan(1500)); // beat "3"
      match.tick(.5);
      expect(match.countdownRemainingMs, inInclusiveRange(1001, 1500)); // "2"
      match.tick(.5);
      expect(match.countdownRemainingMs, inInclusiveRange(501, 1000)); // "1"
      match.tick(.5);
      expect(match.countdownRemainingMs, lessThanOrEqualTo(500)); // "FIGHT!"
      match.tick(.5);
      expect(match.phase, MatchPhase.fighting);
    });
  });

  group('§6 movement detail', () {
    test('the walk cycle steps the stride the art actually draws', () async {
      // A bot that only walks: closes to its preferred gap and never swings.
      final walker = const BotProfile(
        difficulty: BotDifficulty.easy,
        thinkIntervalMs: 25,
        reactionMs: 60000,
        attackCooldownMs: 60000,
        blockChance: 0,
        heavyChance: 0,
        hesitationChance: 0,
        recoveryMs: 0,
        preferredGap: 40,
      );
      final game = await loadedGame(botProfile: walker);
      pastCountdown(game);
      final player = playerOf(game);
      final rival = rivalOf(game);

      game.setPlayerMoving(true);
      tick(game, 3); // both are walking towards each other now

      final walkSpeed = game.match.rules.walkSpeed;
      expect(player.animation!.frames, hasLength(6));
      expect(rival.animation!.frames, hasLength(6));
      // cycleMs = (unitsPerCycle / walkSpeed) * 1000, stepTime = cycleMs / 6,
      // with the measured strides: player 529 canvas px ≈ 48.0 arena units,
      // rival 497 px ≈ 45.1 units (GAME_FEEL §6).
      final playerUnits =
          player.animation!.frames.first.stepTime * 6 * walkSpeed;
      final rivalUnits = rival.animation!.frames.first.stepTime * 6 * walkSpeed;
      expect(playerUnits, closeTo(48.0, .6));
      expect(rivalUnits, closeTo(45.1, .6));
    });

    test('landing squashes for 90 ms and kicks up a puff', () async {
      final game = await loadedGame();
      pastCountdown(game);
      final player = playerOf(game);

      game.sendPlayerAction(InputAction.jump);
      var guard = 0;
      while (game.match.stateOf(FighterId.player).isAirborne && guard++ < 80) {
        tick(game, 1);
      }
      expect(game.match.stateOf(FighterId.player).action, FighterAction.idle);

      // The landing frame squashes the sprite towards the floor...
      expect(player.scale.y, closeTo(.94, .001));
      expect(game.liveEffectCount, greaterThan(0), reason: 'puff at the feet');
      tick(game, 3); // ~50 ms in: still squashed
      expect(player.scale.y, closeTo(.94, .001));
      tick(game, 4); // ~117 ms: the 90 ms squash is over
      expect(player.scale.y, 1);
    });
  });

  group('§7 difficulty', () {
    test('the arena and the presets default to Normal', () {
      expect(InkFightBattleGame().botProfile, BotProfile.normal);
      expect(BotProfile.defaultProfile, BotProfile.normal);
    });

    test('BotProfile.forDifficulty maps the menu enum onto the presets', () {
      expect(BotProfile.forDifficulty(BotDifficulty.easy), BotProfile.easy);
      expect(BotProfile.forDifficulty(BotDifficulty.normal), BotProfile.normal);
      expect(BotProfile.forDifficulty(BotDifficulty.hard), BotProfile.hard);
    });
  });

  group('controller hit events', () {
    /// Runs a controller past its countdown into live combat.
    MatchController fightingMatch({MatchRules rules = MatchRules.standard}) {
      final match = MatchController(rules: rules);
      for (var i = 0; i < 130; i++) {
        match.tick(1 / 60);
      }
      expect(match.phase, MatchPhase.fighting);
      return match;
    }

    /// Walks the player east until the gap is within light-punch reach.
    void walkIntoRange(MatchController match) {
      match.setMoveAxis(FighterId.player, 1);
      for (var i = 0; i < 200 && (match.rival.x - match.player.x) > 50; i++) {
        match.tick(1 / 60);
      }
      match.setMoveAxis(FighterId.player, 0);
      match.drainHitEvents();
    }

    test(
      'a clean hit reports attacker, defender, weight and contact point',
      () {
        final match = fightingMatch();
        walkIntoRange(match);
        final playerX = match.player.x;
        final rivalX = match.rival.x;

        match.submit(
          InputCommand(
            fighter: FighterId.player,
            action: InputAction.lightPunch,
            sequence: 1,
          ),
        );
        match.tick(.12); // through the 90 ms startup, inside the active window

        final events = match.drainHitEvents();
        expect(events, hasLength(1));
        final event = events.single;
        expect(event.kind, HitKind.hit);
        expect(event.attacker, FighterId.player);
        expect(event.defender, FighterId.rival);
        expect(event.heavy, isFalse);
        expect(event.ko, isFalse);
        expect(event.x, closeTo((playerX + rivalX) / 2, .001));
        expect(match.rival.health, lessThan(match.rules.health));
        // Draining is draining: the same hit is never reported twice.
        expect(match.drainHitEvents(), isEmpty);
      },
    );

    test('a guarded hit reports blocked and only the chip damage', () {
      final match = fightingMatch();
      walkIntoRange(match);

      match.submit(
        InputCommand(
          fighter: FighterId.rival,
          action: InputAction.block,
          sequence: 1,
        ),
      );
      match.submit(
        InputCommand(
          fighter: FighterId.player,
          action: InputAction.lightPunch,
          sequence: 1,
        ),
      );
      match.tick(.12);

      final events = match.drainHitEvents();
      expect(events, hasLength(1));
      expect(events.single.kind, HitKind.blocked);
      expect(events.single.ko, isFalse);
      // A blocked light punch is fully absorbed and puts the guard in
      // blockstun — all of it straight off the rules table.
      expect(match.rival.health, match.rules.health);
      expect(match.rival.action, FighterAction.blockstun);
    });

    test('a swing that closes on air reports a whiff at the attacker', () {
      final match = fightingMatch();
      // The fighters start 80 units apart — outside the light punch's reach.
      expect(
        (match.rival.x - match.player.x).abs(),
        greaterThan(match.rules.lightAttack.reach),
      );
      final playerX = match.player.x;

      match.submit(
        InputCommand(
          fighter: FighterId.player,
          action: InputAction.lightPunch,
          sequence: 1,
        ),
      );
      match.tick(.1); // the active window opens at 90 ms, not yet closed
      expect(match.drainHitEvents(), isEmpty);
      match.tick(.1); // it closed at 160 ms: the whiff is reported now

      final events = match.drainHitEvents();
      expect(events, hasLength(1));
      expect(events.single.kind, HitKind.whiff);
      expect(events.single.attacker, FighterId.player);
      expect(events.single.x, playerX);
      expect(events.single.ko, isFalse);
    });

    test('the killing blow carries ko', () {
      final match = fightingMatch(
        rules: const MatchRules(health: 6), // one light punch is lethal
      );
      walkIntoRange(match);

      match.submit(
        InputCommand(
          fighter: FighterId.player,
          action: InputAction.lightPunch,
          sequence: 1,
        ),
      );
      match.tick(.12);

      final events = match.drainHitEvents();
      expect(events, hasLength(1));
      expect(events.single.kind, HitKind.hit);
      expect(events.single.ko, isTrue);
      expect(match.isFinished, isTrue);
      expect(match.outcome, MatchOutcome.playerWin);
    });

    test('reset clears undrained events', () {
      final match = fightingMatch();
      walkIntoRange(match);
      match.submit(
        InputCommand(
          fighter: FighterId.player,
          action: InputAction.lightPunch,
          sequence: 1,
        ),
      );
      match.tick(.12);
      match.reset();
      expect(match.drainHitEvents(), isEmpty);
      expect(match.countdownRemainingMs, match.rules.countdownMs);
    });
  });

  group('whiff presentation', () {
    test(
      'a miss sweeps ink, leans in and settles — with no hit-stop',
      () async {
        final game = await loadedGame();
        pastCountdown(game);
        final player = playerOf(game);
        final rules = game.match.rules;
        double rulesXpx() =>
            game.match.stateOf(FighterId.player).x / rules.arenaWidth * 960;

        // Opening gap is 80 units, past every reach: the jab closes on air.
        game.sendPlayerAction(InputAction.lightPunch);
        var guard = 0;
        while (game.whiffFxCount == 0 && guard++ < 40) {
          tick(game, 1);
        }

        // The cue lands mid-swing, when the window closes: the streak is on
        // screen while the fist is still out, and the clock never stopped.
        expect(game.whiffFxCount, greaterThan(0));
        expect(
          game.match.stateOf(FighterId.player).action,
          FighterAction.lightPunch,
        );
        expect(game.hitStopRemainingMs, 0);

        // Leaning into the miss: ahead of the rules x a few frames later...
        tick(game, 3);
        expect(player.position.x, greaterThan(rulesXpx() + 2));

        // ...and settled back once recovery runs out.
        bool settled() =>
            game.match.stateOf(FighterId.player).action == FighterAction.idle;
        guard = 0;
        while (!settled() && guard++ < 40) {
          tick(game, 1);
        }
        tick(game, 3);
        expect(player.position.x, closeTo(rulesXpx(), 1.5));
        expect(game.whiffFxCount, 0);
      },
    );
  });

  group('walk-speed-driven animation', () {
    test('a half-pushed stick plays a half-speed walk cycle', () async {
      final game = await loadedGame();
      pastCountdown(game);
      final player = playerOf(game);

      game.setPlayerMoveAxis(1);
      tick(game, 3);
      expect(player.animation!.frames, hasLength(6));
      final full = player.animation!.frames.first.stepTime;

      game.setPlayerMoveAxis(.5);
      tick(game, 4);
      expect(player.animation!.frames, hasLength(6)); // same cycle, rescaled
      expect(
        player.animation!.frames.first.stepTime,
        closeTo(full * 2, full * .05),
      );
    });

    test('walking away leans back and every stride puffs ink', () async {
      final game = await loadedGame();
      pastCountdown(game);

      // The player starts left of the rival: a negative axis is a retreat.
      game.setPlayerMoveAxis(-.5);
      tick(game, 2);
      expect(game.isRetreating(FighterId.player), isTrue);

      game.setPlayerMoveAxis(.5);
      tick(game, 2);
      expect(game.isRetreating(FighterId.player), isFalse);

      // A footstep puff every ~20 units: poll a full-speed walk for one.
      game.setPlayerMoving(true);
      var guard = 0;
      var sawPuff = false;
      while (guard++ < 30 && !sawPuff) {
        tick(game, 1);
        sawPuff = game.liveEffectCount > 0;
      }
      expect(sawPuff, isTrue, reason: 'a footstep puff should show');
    });
  });
}
