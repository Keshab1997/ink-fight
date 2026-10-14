import 'package:flutter_test/flutter_test.dart';

import 'package:inkfight/game/bot/bot_strategy.dart';
import 'package:inkfight/game/rules/input_command.dart';
import 'package:inkfight/game/rules/match_controller.dart';
import 'package:inkfight/game/rules/match_rules.dart';

/// A whole fight, frame by frame: the bot plays the rival, the test plays the
/// player. Nothing here reaches inside the match — the bot only ever sees what
/// a real controller would expose.
class FightHarness {
  FightHarness({this.profile = BotProfile.normal, int seed = 7})
    : match = MatchController() {
    bot = BotController(profile: profile, seed: seed);
  }

  final MatchRules rules = MatchRules.standard;
  final BotProfile profile;
  final MatchController match;
  late final BotController bot;
  int _sequence = 0;

  void step() {
    final slice = rules.tickMs / 1000;
    bot.update(slice, match);
    match.tick(slice);
  }

  void advance(int ms) {
    for (var elapsed = 0; elapsed < ms; elapsed += rules.tickMs) {
      step();
    }
  }

  void skipCountdown() => advance(rules.countdownMs);

  void pressPlayer(InputAction action) {
    _sequence++;
    match.submit(
      InputCommand(
        fighter: FighterId.player,
        action: action,
        sequence: _sequence,
      ),
    );
  }

  void holdPlayer(double axis) => match.setMoveAxis(FighterId.player, axis);

  /// Walks the player into range and throws a heavy kick, then watches the
  /// rival for [watchMs] to see how it answered.
  bool playerHeavyKick({required bool sawGuard}) {
    var guarded = sawGuard;
    holdPlayer(1);
    advance(700);
    holdPlayer(0);
    pressPlayer(InputAction.heavyKick);
    for (
      var elapsed = 0;
      elapsed < rules.heavyAttack.totalMs;
      elapsed += rules.tickMs
    ) {
      step();
      if (match.rival.action == FighterAction.blockstun) {
        guarded = true;
      }
    }
    holdPlayer(-1);
    advance(400);
    holdPlayer(0);
    return guarded;
  }
}

/// A bot that can never swing, so the test can watch its guard alone.
const BotProfile guardianOnly = BotProfile(
  difficulty: BotDifficulty.normal,
  thinkIntervalMs: 40,
  reactionMs: 140,
  attackCooldownMs: 600000,
  blockChance: .6,
  heavyChance: 0,
  hesitationChance: 0,
  recoveryMs: 200,
  preferredGap: 52,
);

/// The same bot with a reaction too slow to catch a heavy kick.
const BotProfile tooSlowToGuard = BotProfile(
  difficulty: BotDifficulty.easy,
  thinkIntervalMs: 40,
  reactionMs: 600,
  attackCooldownMs: 600000,
  blockChance: 1,
  heavyChance: 0,
  hesitationChance: 0,
  recoveryMs: 200,
  preferredGap: 52,
);

void main() {
  final rules = MatchRules.standard;

  test('difficulty changes how the bot plays, never what a hit does', () {
    const ladder = [BotProfile.easy, BotProfile.normal, BotProfile.hard];

    for (final profile in ladder) {
      expect(profile.thinkIntervalMs, greaterThan(0));
      expect(profile.reactionMs, greaterThan(0));
      expect(profile.attackCooldownMs, greaterThan(0));
      expect(profile.recoveryMs, greaterThan(0), reason: 'never unpunishable');
      expect(profile.blockChance, greaterThan(0));
      expect(
        profile.blockChance,
        lessThan(1),
        reason: 'a guard that never fails cannot be opened up',
      );
      expect(
        profile.reactionMs,
        lessThan(rules.heavyAttack.startupMs),
        reason: 'every difficulty must have a chance to see a heavy coming',
      );
      expect(
        profile.preferredGap,
        lessThanOrEqualTo(rules.heavyAttack.reach),
        reason: 'or the bot would hold outside its own range and never swing',
      );
    }

    for (var i = 1; i < ladder.length; i++) {
      final milder = ladder[i - 1];
      final sharper = ladder[i];
      expect(sharper.reactionMs, lessThan(milder.reactionMs));
      expect(sharper.attackCooldownMs, lessThan(milder.attackCooldownMs));
      expect(sharper.blockChance, greaterThan(milder.blockChance));
      expect(sharper.hesitationChance, lessThan(milder.hesitationChance));
      expect(sharper.preferredGap, lessThan(milder.preferredGap));
    }
  });

  test('every hit the bot lands is exactly a rules-table hit', () {
    final fight = FightHarness();
    fight.skipCountdown();

    var previous = fight.match.player.health;
    var hits = 0;
    for (var i = 0; i < 40 * 1000 ~/ rules.tickMs; i++) {
      fight.step();
      final health = fight.match.player.health;
      final drop = previous - health;
      previous = health;
      if (drop == 0) {
        continue;
      }
      hits++;
      if (health == 0) {
        // The last hit only has to take the rest of the bar.
        expect(fight.match.isFinished, isTrue);
        expect(drop, lessThanOrEqualTo(rules.heavyAttack.damage));
        continue;
      }
      expect(
        drop,
        anyOf(rules.lightAttack.damage, rules.heavyAttack.damage),
        reason: 'the bot may not deal damage the table does not describe',
      );
    }

    expect(hits, greaterThan(0), reason: 'the player never fought back');
  });

  test('every difficulty can finish a fight against a passive player', () {
    for (final profile in [
      BotProfile.easy,
      BotProfile.normal,
      BotProfile.hard,
    ]) {
      final fight = FightHarness(profile: profile);
      fight.skipCountdown();
      fight.advance(rules.roundMs);

      expect(
        fight.match.outcome,
        MatchOutcome.rivalWin,
        reason: '${profile.difficulty.name} should close out a fight',
      );
      expect(fight.match.player.health, 0);
    }
  });

  test('a normal bot guards a heavy kick it can see coming', () {
    final fight = FightHarness(profile: guardianOnly, seed: 3);
    fight.skipCountdown();

    var guarded = false;
    for (var swings = 0; swings < 10 && !guarded; swings++) {
      guarded = fight.playerHeavyKick(sawGuard: guarded);
    }

    expect(guarded, isTrue, reason: 'the rival should have blocked once');
    expect(
      fight.match.rival.health,
      greaterThan(0),
      reason: 'guarding should have kept the heavy off it',
    );
  });

  test('a bot too slow to react never guards, however willing', () {
    final fight = FightHarness(profile: tooSlowToGuard, seed: 3);
    fight.skipCountdown();

    var guarded = false;
    for (var swings = 0; swings < 6; swings++) {
      guarded = fight.playerHeavyKick(sawGuard: guarded);
    }

    expect(guarded, isFalse);
  });

  test('the same seed plays the same fight twice', () {
    List<Object?> play() {
      final fight = FightHarness(seed: 11);
      fight.skipCountdown();
      fight.holdPlayer(1);
      fight.advance(500);
      fight.holdPlayer(0);
      fight.pressPlayer(InputAction.heavyKick);
      fight.advance(700);
      fight.pressPlayer(InputAction.lightPunch);
      fight.advance(600);
      fight.pressPlayer(InputAction.block);
      fight.advance(900);
      fight.holdPlayer(-1);
      fight.advance(600);

      return <Object?>[
        fight.match.player.x,
        fight.match.rival.x,
        fight.match.player.health,
        fight.match.rival.health,
        fight.match.timeRemainingMs,
        fight.match.rival.action,
      ];
    }

    expect(play(), play());
  });

  test('a rematch starts clean, and the bot fights the new fight too', () {
    final fight = FightHarness(seed: 5);
    fight.skipCountdown();
    fight.holdPlayer(1);
    fight.advance(3000);
    fight.holdPlayer(0);
    fight.advance(3000);
    expect(
      fight.match.player.health,
      lessThan(rules.health),
      reason: 'the bot should be fighting before the rematch',
    );

    fight.match.reset();
    fight.bot.reset();

    // A fresh fight, not a continuation of the last one. (The next fight is a
    // new draw from the bot's seeded random, which is the point of a rematch —
    // only the *match* state is required to be clean.)
    expect(fight.match.phase, MatchPhase.countdown);
    expect(fight.match.outcome, isNull);
    expect(fight.match.timeRemainingMs, rules.roundMs);
    expect(fight.match.player.health, rules.health);
    expect(fight.match.rival.health, rules.health);
    expect(fight.match.player.x, rules.startX);
    expect(fight.match.rival.x, rules.rivalStartX);

    fight.skipCountdown();
    fight.holdPlayer(1);
    fight.advance(6000);
    fight.holdPlayer(0);
    expect(
      fight.match.player.health,
      lessThan(rules.health),
      reason: 'the bot should still fight after a rematch',
    );
  });
}
