import 'package:flame/components.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inkfight/game/audio/fight_sounds.dart';
import 'package:inkfight/game/bot/bot_strategy.dart';
import 'package:inkfight/game/ink_fight_battle_game.dart';
import 'package:inkfight/game/rules/fighter_state.dart';
import 'package:inkfight/game/rules/input_command.dart';
import 'package:inkfight/game/rules/match_controller.dart';
import 'package:inkfight/game/rules/match_rules.dart';

/// Coverage for the game-feel pass (docs/technical/GAME_FEEL.md): the frame
/// data the animations must obey (§1), hit-stop (§2), the knockout cinematic
/// (§5) and the movement detail (§6), plus the hit events the controller now
/// reports. The screen's overlay lives in `bot_fight_screen_test.dart`, the
/// arena smoke test in `bot_fight_game_test.dart`.
///
/// The `sound cues` group at the end is the one place the fight is listened
/// to: it injects [_RecordingSounds], so it hears every cue without the audio
/// plugin ever being loaded.
class _RecordingSounds implements FightSounds {
  /// Every cue the arena played, in order.
  final List<FightCue> cues = <FightCue>[];

  /// How many times the game asked for the cache to warm up.
  int warmUps = 0;

  @override
  void play(FightCue cue) => cues.add(cue);

  @override
  Future<void> warmUp() async => warmUps++;
}

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
    FightSounds? sounds,
  }) async {
    final game = InkFightBattleGame(
      botProfile: botProfile,
      sounds: sounds ?? const SilentFightSounds(),
    );
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
      // Frame 003, the contact pose, is on screen while the hitbox is open.
      expect(visibleFrame(player), 3);

      // Four more updates close the window at 160 ms; the sprite has recoiled.
      tick(game, 4);
      expect(
        rules.lightAttack.isActiveAt(
          game.match.stateOf(FighterId.player).actionElapsedMs,
        ),
        isFalse,
      );
      expect(visibleFrame(player), greaterThan(3));
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
        expect(player.animation!.frames, hasLength(7)); // no idle bookends
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
      expect(player.animation!.frames, hasLength(5));
    });

    test(
      'idle keeps its 560 ms breath however many frames have landed',
      () async {
        final game = await loadedGame();
        pastCountdown(game);
        // Four keyframes plus the loop-seam in-between (prompt pack §5); the
        // rival also has the 002 → 003 one, the player's is still to come.
        for (final (fighter, frames) in [
          (playerOf(game), 5),
          (rivalOf(game), 6),
        ]) {
          expect(fighter.animation!.frames, hasLength(frames));
          expect(fighter.animation!.loop, isTrue);
          expect(totalMsOf(fighter), closeTo(560, 1e-6));
        }
      },
    );
  });

  group('§1 hit reactions', () {
    /// Walks the player in until the heavy kick would reach the rival.
    void walkInForKick(InkFightBattleGame game) {
      final match = game.match;
      game.setPlayerMoving(true);
      var guard = 0;
      while (match.distanceBetween(FighterId.player, FighterId.rival) > 52 &&
          guard++ < 600) {
        tick(game, 1);
      }
      game.setPlayerMoving(false);
    }

    test('a heavy kick that lands plays the heavy hurt cycle', () async {
      final game = await loadedGame();
      pastCountdown(game);
      final match = game.match;
      final rival = rivalOf(game);

      walkInForKick(game);
      game.sendPlayerAction(InputAction.heavyKick);
      var guard = 0;
      while (match.stateOf(FighterId.rival).action != FighterAction.hitstun &&
          guard++ < 200) {
        tick(game, 1);
      }
      expect(
        match.stateOf(FighterId.rival).stunRemainingMs,
        match.rules.heavyAttack.hitstunMs,
      );

      // Four delivered frames, paced to the heavy hitstun, not the light one.
      expect(rival.animation!.frames, hasLength(4));
      expect(totalMsOf(rival), 420);
      expect(rival.animation!.loop, isFalse);
      // It starts on the impact frame, which is the first one shown.
      expect(visibleFrame(rival), 0);
    });

    test('a blocked hit holds the guard and never plays a flinch', () async {
      final game = await loadedGame();
      pastCountdown(game);
      final match = game.match;
      final rival = rivalOf(game);

      walkInForKick(game);
      // The rival raises its guard, and the heavy kick meets it.
      match.submit(
        const InputCommand(
          fighter: FighterId.rival,
          action: InputAction.block,
          sequence: 1,
        ),
      );
      game.sendPlayerAction(InputAction.heavyKick);

      var sawBlockstun = false;
      for (var i = 0; i < 120; i++) {
        tick(game, 1);
        if (match.stateOf(FighterId.rival).action == FighterAction.blockstun) {
          sawBlockstun = true;
          // The held-guard cycle: two frames, looping, never the hurt cycles.
          expect(rival.animation!.frames, hasLength(2));
          expect(rival.animation!.loop, isTrue);
        }
      }
      expect(
        sawBlockstun,
        isTrue,
        reason: 'the heavy should have been guarded',
      );
      expect(
        match.rival.health,
        match.rules.health - match.rules.heavyAttack.blockedDamage,
      );
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
        // ...a jab hands the rival the light hurt cycle, which spans exactly
        // the light hitstun (§1). A heavy kick gets its own cycle, below.
        expect(rival.animation!.frames, hasLength(5));
        expect(totalMsOf(rival), 220);
        // The in-betweens only split the gaps: the stagger still lands at
        // 70 ms and the recovered pose at 150 ms, holding to the end.
        final hurtStarts = <int>[0];
        for (final f in rival.animation!.frames) {
          hurtStarts.add(hurtStarts.last + (f.stepTime * 1000).round());
        }
        expect(hurtStarts[2], 70);
        expect(hurtStarts[4], 150);
        expect(rival.animation!.loop, isFalse);

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

    test(
      'a counter-hit knockdown plays the fall, holds it, then stands',
      () async {
        final game = await loadedGame();
        pastCountdown(game);
        final match = game.match;
        final rival = rivalOf(game);

        // Walk the player to a gap the rival's jab cannot reach, but the heavy can.
        game.setPlayerMoving(true);
        var guard = 0;
        while (match.distanceBetween(FighterId.player, FighterId.rival) > 52 &&
            guard++ < 600) {
          tick(game, 1);
        }
        game.setPlayerMoving(false);

        // The rival throws a jab from out of reach and holds it in recovery;
        // the player's heavy kick lands on it while it is still attacking.
        match.submit(
          const InputCommand(
            fighter: FighterId.rival,
            action: InputAction.lightPunch,
            sequence: 1,
          ),
        );
        game.sendPlayerAction(InputAction.heavyKick);

        guard = 0;
        while (!match.stateOf(FighterId.rival).isKnockedDown && guard++ < 120) {
          tick(game, 1);
        }
        expect(match.stateOf(FighterId.rival).isKnockedDown, isTrue);

        // The fall: the 600 ms knockdown cycle, first frame at 90 ms.
        expect(rival.animation!.frames, hasLength(5));
        expect(rival.animation!.frames.first.stepTime, .09);
        expect(rival.animation!.loop, isFalse);

        // Once the cycle has run out it holds its last frame on the floor, for
        // as long as the rules keep the fighter down.
        guard = 0;
        while (visibleFrame(rival) < 4 && guard++ < 120) {
          tick(game, 1);
        }
        expect(visibleFrame(rival), 4);
        expect(match.stateOf(FighterId.rival).isKnockedDown, isTrue);

        // Then the window ends and the rival is back on its feet.
        guard = 0;
        while (match.stateOf(FighterId.rival).isKnockedDown && guard++ < 300) {
          tick(game, 1);
        }
        expect(match.stateOf(FighterId.rival).action, FighterAction.idle);
        tick(game, 1);
        expect(
          rival.animation!.frames,
          hasLength(6),
          reason: 'idle cycle again',
        );
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

      // Frame-sized steps on purpose: `tick` consumes whole 16 ms slices and
      // clamps one call to `maxCatchUpMs` (250 ms), so a single .5 s jump both
      // loses its remainder and drifts ~20 ms per call — far enough to fall out
      // of the beat windows below.
      void step(int frames) {
        for (var i = 0; i < frames; i++) {
          match.tick(.016);
        }
      }

      step(31); // ~500 ms in: beat "3"
      expect(match.countdownRemainingMs, inInclusiveRange(1501, 2000));
      step(31); // "2"
      expect(match.countdownRemainingMs, inInclusiveRange(1001, 1500));
      step(31); // "1"
      expect(match.countdownRemainingMs, inInclusiveRange(501, 1000));
      step(31); // "FIGHT!"
      expect(match.countdownRemainingMs, lessThanOrEqualTo(500));
      step(31);
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
      // Six keyframes plus two in-betweens, one per half-stride.
      expect(player.animation!.frames, hasLength(8));
      expect(rival.animation!.frames, hasLength(8));
      // cycleMs = (unitsPerCycle / walkSpeed) * 1000, spread over the frames,
      // with the measured strides: player 529 canvas px ≈ 48.0 arena units,
      // rival 497 px ≈ 45.1 units (GAME_FEEL §6).
      double unitsPerCycle(SpriteAnimationComponent fighter) =>
          fighter.animation!.frames.first.stepTime *
          fighter.animation!.frames.length *
          walkSpeed;
      final playerUnits = unitsPerCycle(player);
      final rivalUnits = unitsPerCycle(rival);
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
      final reach = match.rules.lightAttack.reach;
      match.setMoveAxis(FighterId.player, 1);
      for (
        var i = 0;
        i < 200 && (match.rival.x - match.player.x) > reach * .9;
        i++
      ) {
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
      expect(player.animation!.frames, hasLength(8));
      final full = player.animation!.frames.first.stepTime;

      game.setPlayerMoveAxis(.5);
      tick(game, 4);
      expect(player.animation!.frames, hasLength(8)); // same cycle, rescaled
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

  group('debug hitbox geometry', () {
    const rules = MatchRules.standard;

    DebugFighterBoxes boxesFor(FighterAction action, int elapsedMs) {
      return debugHitboxGeometry(rules, [
        FighterState(
          id: FighterId.player,
          x: 110,
          health: rules.health,
          facing: 1,
          action: action,
          actionElapsedMs: elapsedMs,
        ),
      ]).single;
    }

    test('the overlay is off by default', () {
      expect(InkFightBattleGame().debugOverlay, isFalse);
    });

    test('reach matches the rules frame for both attacks', () {
      expect(
        boxesFor(FighterAction.lightPunch, 0).reach,
        rules.lightAttack.reach,
      );
      expect(
        boxesFor(FighterAction.heavyKick, 0).reach,
        rules.heavyAttack.reach,
      );
      // No hitbox outside an attack.
      expect(boxesFor(FighterAction.idle, 0).reach, 0);
      expect(boxesFor(FighterAction.walk, 0).reach, 0);
      expect(boxesFor(FighterAction.block, 0).reach, 0);
    });

    test('the active flag flips exactly on the window edges', () {
      final light = rules.lightAttack;
      bool activeAt(int elapsedMs) =>
          boxesFor(FighterAction.lightPunch, elapsedMs).isActive;
      expect(activeAt(light.startupMs - 1), isFalse);
      expect(activeAt(light.startupMs), isTrue);
      expect(activeAt(light.startupMs + light.activeMs - 1), isTrue);
      expect(activeAt(light.startupMs + light.activeMs), isFalse);

      final heavy = rules.heavyAttack;
      expect(
        boxesFor(FighterAction.heavyKick, heavy.startupMs).isActive,
        isTrue,
      );
      expect(
        boxesFor(
          FighterAction.heavyKick,
          heavy.startupMs + heavy.activeMs,
        ).isActive,
        isFalse,
      );
    });

    test('the pushbox spans exactly minFighterDistance', () {
      final boxes = boxesFor(FighterAction.idle, 0);
      expect(boxes.pushHalfWidth * 2, rules.minFighterDistance);
      expect(boxes.x, 110);
      expect(boxes.facing, 1);
    });
  });

  group('haptics', () {
    /// Records platform haptic calls while the test drives the arena.
    List<MethodCall> recordHaptics() {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            calls.add(call);
            return null;
          });
      return calls;
    }

    /// Walks the player in and jabs until one lands (the §2 pattern).
    void landOneJab(InkFightBattleGame game) {
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
    }

    test('haptics are enabled by default', () {
      expect(InkFightBattleGame().hapticsEnabled, isTrue);
    });

    test('a connect produces exactly one haptic call', () async {
      final haptics = recordHaptics();
      final game = await loadedGame();
      pastCountdown(game);

      landOneJab(game);
      expect(haptics, hasLength(1));
      expect(haptics.single.method, 'HapticFeedback.vibrate');
      expect(haptics.single.arguments, 'HapticFeedbackType.lightImpact');
    });

    test('a whiff stays silent', () async {
      final haptics = recordHaptics();
      final game = await loadedGame();
      pastCountdown(game);

      // Opening gap is 80 units, past every reach: the jab closes on air.
      game.sendPlayerAction(InputAction.lightPunch);
      var guard = 0;
      while (game.whiffFxCount == 0 && guard++ < 40) {
        tick(game, 1);
      }
      expect(game.whiffFxCount, greaterThan(0));
      tick(game, 20); // through recovery: still nothing to feel
      expect(haptics, isEmpty);
    });

    test('hapticsEnabled = false silences every cue', () async {
      final haptics = recordHaptics();
      final game = await loadedGame();
      game.hapticsEnabled = false;
      pastCountdown(game);

      landOneJab(game);
      expect(haptics, isEmpty);
    });
  });

  group('sound cues', () {
    /// The fake the arena is listened to through — the plugin is never
    /// constructed anywhere in this group.
    late _RecordingSounds sounds;

    setUp(() => sounds = _RecordingSounds());

    /// The guard bot: thinks every tick, never swings, and always raises its
    /// guard at an incoming swing — `blockChance: 1` on the bot's own seeded
    /// random, so the guard is deterministic, not lucky.
    // A pure guard: it blocks every wind-up it sees and never swings itself.
    // `hesitationChance: 1` is what actually stops it attacking — the long
    // attack cooldown alone does not, because the cooldown starts at zero and
    // the bot's *first* swing is always allowed. That swing used to land on
    // the player and put its own impact cue into the recording, which is why
    // "a guarded hit plays the clack and no impact" saw a `hitLight`.
    const guardBot = BotProfile(
      difficulty: BotDifficulty.hard,
      thinkIntervalMs: 16,
      reactionMs: 0,
      attackCooldownMs: 60000,
      blockChance: 1,
      heavyChance: 0,
      hesitationChance: 1,
      recoveryMs: 0,
      preferredGap: 40,
    );

    /// The recorded cues with the walking taps taken out. The footfall is a
    /// bed under the whole fight — walking into range sprinkles taps through
    /// any recording — so the impact groups assert on what is left.
    List<FightCue> withoutFootfalls() => sounds.cues
        .where((cue) => cue != FightCue.stepTap)
        .toList(growable: false);

    /// Every footfall recorded so far.
    List<FightCue> footfalls() => sounds.cues
        .where((cue) => cue == FightCue.stepTap)
        .toList(growable: false);

    /// Walks the player in and lands one jab (the §2 pattern the haptics
    /// group uses; its copy is private to that group, so this one keeps the
    /// cues group self-contained).
    void landOneJab(InkFightBattleGame game) {
      final jabReach = game.match.rules.lightAttack.reach;
      var landed = false;
      for (var i = 0; i < 400 && !landed; i++) {
        final player = game.match.stateOf(FighterId.player);
        final gap = (game.match.stateOf(FighterId.rival).x - player.x).abs();
        game.setPlayerMoving(gap > jabReach * .9);
        if (gap <= jabReach * .9 && player.canAct) {
          game.sendPlayerAction(InputAction.lightPunch);
        }
        tick(game, 1);
        landed = game.match.stateOf(FighterId.rival).health < 100;
      }
      expect(landed, isTrue, reason: 'the light punch should connect');
    }

    /// Walks the player in and lands one heavy kick (the §2 pattern, with
    /// the kick's longer reach).
    void landOneHeavy(InkFightBattleGame game) {
      final reach = game.match.rules.heavyAttack.reach;
      var landed = false;
      for (var i = 0; i < 600 && !landed; i++) {
        final player = game.match.stateOf(FighterId.player);
        final gap = (game.match.stateOf(FighterId.rival).x - player.x).abs();
        game.setPlayerMoving(gap > reach * .9);
        if (gap <= reach * .9 && player.canAct) {
          game.sendPlayerAction(InputAction.heavyKick);
        }
        tick(game, 1);
        landed = game.match.stateOf(FighterId.rival).health < 100;
      }
      expect(landed, isTrue, reason: 'the heavy kick should connect');
    }

    test('a light connect plays the tick, after its own whoosh', () async {
      final game = await loadedGame(sounds: sounds);
      pastCountdown(game);
      landOneJab(game);

      // Exactly the round's sounds, in order: three counting beats, the
      // swing's whoosh, then the impact the connect carries. (The footfalls
      // of the walk-in are heard too; they are asserted on their own below.)
      expect(withoutFootfalls(), <FightCue>[
        FightCue.countdownBlip,
        FightCue.countdownBlip,
        FightCue.countdownBlip,
        FightCue.whooshLight,
        FightCue.hitLight,
      ]);
    });

    test('a heavy connect plays the thud, after its own whoosh', () async {
      final game = await loadedGame(sounds: sounds);
      pastCountdown(game);
      landOneHeavy(game);

      expect(withoutFootfalls(), <FightCue>[
        FightCue.countdownBlip,
        FightCue.countdownBlip,
        FightCue.countdownBlip,
        FightCue.whooshHeavy,
        FightCue.hitHeavy,
      ]);
    });

    test('walking taps a footfall, and standing still is silent', () async {
      final game = await loadedGame(sounds: sounds);
      pastCountdown(game);

      // A fighter on the spot makes no noise at all.
      tick(game, 30);
      expect(footfalls(), isEmpty, reason: 'standing still has no stride');

      // ~0.67 s of walking at 78 u/s is ~52 units: two footstep puffs, and
      // every second puff is the heard footfall.
      game.setPlayerMoveAxis(1);
      tick(game, 40);
      game.setPlayerMoveAxis(0);
      expect(footfalls(), hasLength(1));

      // Stopping stops the taps with the feet.
      final heard = footfalls().length;
      tick(game, 40);
      expect(footfalls(), hasLength(heard));
    });

    test('a guarded hit plays the clack and no impact', () async {
      final game = await loadedGame(botProfile: guardBot, sounds: sounds);
      pastCountdown(game);

      // Walk in and swing only from inside the jab's reach; the guard is
      // always up by the time the active window opens.
      final jabReach = game.match.rules.lightAttack.reach;
      var guarded = false;
      for (var i = 0; i < 600 && !guarded; i++) {
        final player = game.match.stateOf(FighterId.player);
        final gap = (game.match.stateOf(FighterId.rival).x - player.x).abs();
        game.setPlayerMoving(gap > jabReach * .9);
        if (gap <= jabReach * .9 && player.canAct) {
          game.sendPlayerAction(InputAction.lightPunch);
        }
        tick(game, 1);
        guarded = sounds.cues.contains(FightCue.blocked);
      }

      expect(sounds.cues, contains(FightCue.blocked));
      expect(sounds.cues, isNot(contains(FightCue.hitLight)));
      expect(sounds.cues, isNot(contains(FightCue.hitHeavy)));
    });

    test('a whiff only whooshes — no impact, nothing extra', () async {
      final game = await loadedGame(sounds: sounds);
      pastCountdown(game);

      // Opening gap is 80 units, past every reach: the jab cuts air.
      game.sendPlayerAction(InputAction.lightPunch);
      var guard = 0;
      while (game.whiffFxCount == 0 && guard++ < 40) {
        tick(game, 1);
      }
      tick(game, 20); // through recovery: still nothing to hear

      expect(sounds.cues, <FightCue>[
        FightCue.countdownBlip,
        FightCue.countdownBlip,
        FightCue.countdownBlip,
        FightCue.whooshLight,
      ]);
    });

    test('the KO plays the gong once, and the reveal its sting', () async {
      final game = await loadedGame(
        botProfile: BotProfile.normal,
        sounds: sounds,
      );
      pastCountdown(game);
      var guard = 0;
      while (!game.match.isFinished && guard++ < 4200) {
        tick(game, 1);
      }
      expect(game.match.isFinished, isTrue);
      tick(game, 90); // the slow motion and the frozen beat, to the card

      expect(
        sounds.cues.where((cue) => cue == FightCue.koGong),
        hasLength(1),
        reason: 'one gong per knockout, never per frame',
      );
      expect(
        sounds.cues.where((cue) => cue == FightCue.roundSting),
        hasLength(1),
        reason: 'the result sting rides the same once-only reveal',
      );
    });

    test('the countdown lays down exactly three blips', () async {
      final game = await loadedGame(sounds: sounds);
      pastCountdown(game);

      expect(sounds.cues, <FightCue>[
        FightCue.countdownBlip,
        FightCue.countdownBlip,
        FightCue.countdownBlip,
      ], reason: '3 · 2 · 1 blip; the FIGHT! beat stays silent');
    });

    test('soundEnabled = false silences the whole fight', () async {
      final game = await loadedGame(sounds: sounds);
      game.soundEnabled = false;
      pastCountdown(game); // would blip three times
      landOneJab(game); // would whoosh and tick

      expect(sounds.cues, isEmpty);
    });

    test('onLoad warms the seam once, and the game holds it', () async {
      final game = await loadedGame(sounds: sounds);

      expect(sounds.warmUps, 1);
      expect(game.sounds, same(sounds));
    });

    test('the suite never reaches the audio plugin', () async {
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      // The channels the real implementation would speak through: the
      // audioplayers method channels, and path_provider — audioplayers'
      // cache copies each asset into a temp dir before the native side may
      // read it. A fight that uses the injected seam must leave all three
      // silent.
      for (final name in [
        'xyz.luan/audioplayers',
        'xyz.luan/audioplayers.global',
        'plugins.flutter.io/path_provider',
      ]) {
        final channel = MethodChannel(name);
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      }

      final game = await loadedGame(sounds: sounds);
      pastCountdown(game);
      landOneJab(game);

      expect(sounds.cues, isNotEmpty, reason: 'the fight really sounded');
      expect(
        calls,
        isEmpty,
        reason: 'every cue played through the injected seam, not the plugin',
      );
    });
  });
}
