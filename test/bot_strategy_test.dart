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

  double gap() => (match.rival.x - match.player.x).abs();

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

/// A bot that never walks or swings on its own — hesitation holds it still —
/// so the only thing it can do is punish. The short reaction keeps a scripted
/// punish inside the player's recovery.
BotProfile punisher({required double punishChance}) => BotProfile(
  difficulty: BotDifficulty.hard,
  thinkIntervalMs: 16,
  reactionMs: 1,
  attackCooldownMs: 600000,
  blockChance: 0,
  heavyChance: 0,
  hesitationChance: 1,
  recoveryMs: 120,
  preferredGap: 42,
  punishChance: punishChance,
);

/// A bot that swings its heavy as soon as it can, and never punishes, guards,
/// or swings again. The only attack it throws is the one the test watches.
const BotProfile heavyOnce = BotProfile(
  difficulty: BotDifficulty.normal,
  thinkIntervalMs: 40,
  reactionMs: 140,
  attackCooldownMs: 600000,
  blockChance: 0,
  heavyChance: 1,
  hesitationChance: 0,
  recoveryMs: 200,
  preferredGap: 42,
);

/// Walks the player east until the gap is within [maxGap], one tick at a time.
void walkPlayerTo(FightHarness fight, double maxGap) {
  fight.holdPlayer(1);
  var guard = 0;
  while (fight.gap() > maxGap && guard++ < 600) {
    fight.step();
  }
  fight.holdPlayer(0);
}

/// Plays one whole match between two bots and returns how it ended.
MatchOutcome? duel(BotProfile player, BotProfile rival, {required int seed}) {
  final rules = MatchRules.standard;
  final match = MatchController();
  final playerBot = BotController(
    profile: player,
    fighter: FighterId.player,
    seed: seed,
  );
  final rivalBot = BotController(
    profile: rival,
    fighter: FighterId.rival,
    seed: seed + 1000,
  );
  final slice = rules.tickMs / 1000;
  var steps = 0;
  while (!match.isFinished && steps++ < 20000) {
    playerBot.update(slice, match);
    rivalBot.update(slice, match);
    match.tick(slice);
  }
  return match.outcome;
}

/// Plays [sharper] against [milder] over many seeds, with each bot taking
/// both sides, and checks that the sharper preset wins more of the duels.
void expectSharperWins(BotProfile sharper, BotProfile milder) {
  const seeds = 20;
  var sharperWins = 0;
  var milderWins = 0;
  for (var seed = 1; seed <= seeds; seed++) {
    final asPlayer = duel(sharper, milder, seed: seed);
    final asRival = duel(milder, sharper, seed: seed);
    if (asPlayer == MatchOutcome.playerWin) {
      sharperWins++;
    }
    if (asPlayer == MatchOutcome.rivalWin) {
      milderWins++;
    }
    if (asRival == MatchOutcome.rivalWin) {
      sharperWins++;
    }
    if (asRival == MatchOutcome.playerWin) {
      milderWins++;
    }
  }
  expect(
    sharperWins,
    greaterThan(milderWins),
    reason: '${sharper.difficulty.name} against ${milder.difficulty.name}',
  );
}

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
      expect(profile.punishChance, inInclusiveRange(0, 1));
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
      expect(sharper.punishChance, greaterThan(milder.punishChance));
    }
  });

  test('every hit the bot lands is exactly a rules-table hit', () {
    final fight = FightHarness();
    fight.skipCountdown();

    var previous = fight.match.player.health;
    var round = fight.match.roundNumber;
    var hits = 0;
    for (var i = 0; i < 40 * 1000 ~/ rules.tickMs; i++) {
      if (fight.match.isFinished) {
        break;
      }
      fight.step();
      final health = fight.match.player.health;
      final drop = previous - health;
      previous = health;
      // A decided round hands both fighters a full bar again, so the drain is
      // read per round: best of three means a KO decides a ROUND, and not
      // always the match.
      if (fight.match.roundNumber != round) {
        round = fight.match.roundNumber;
        continue;
      }
      if (drop == 0) {
        continue;
      }
      hits++;
      if (health == 0) {
        // The last hit only has to take the rest of the bar.
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

  test('a punish lands through a command the controller accepted', () {
    final fight = FightHarness(profile: punisher(punishChance: 1));
    fight.skipCountdown();
    // Just outside the jab's reach: the whole active window misses.
    walkPlayerTo(fight, 47);
    expect(fight.gap(), greaterThan(rules.lightAttack.reach));

    fight.pressPlayer(InputAction.lightPunch);
    var punished = false;
    int? hitMs;
    var elapsedMs = 0;
    while (elapsedMs < rules.lightAttack.totalMs + 200) {
      final before = fight.match.rival.action;
      fight.step();
      elapsedMs += rules.tickMs;
      if (!punished && fight.match.rival.action == FighterAction.lightPunch) {
        // The punch only shows up once the controller accepted it, which is
        // only possible from a state that can act.
        expect(
          before == FighterAction.idle || before == FighterAction.walk,
          isTrue,
        );
        punished = true;
      }
      if (hitMs == null && fight.match.player.health < rules.health) {
        hitMs = elapsedMs;
      }
    }

    expect(punished, isTrue, reason: 'the rival took the opening');
    expect(hitMs, isNotNull, reason: 'and the punch landed');
    expect(
      hitMs!,
      lessThanOrEqualTo(rules.lightAttack.totalMs),
      reason: 'inside the whiff\'s recovery',
    );
    expect(fight.match.player.health, rules.health - rules.lightAttack.damage);
  });

  test('the same opening goes unpunished when the chance is zero', () {
    final fight = FightHarness(profile: punisher(punishChance: 0));
    fight.skipCountdown();
    walkPlayerTo(fight, 47);

    fight.pressPlayer(InputAction.lightPunch);
    fight.advance(rules.lightAttack.totalMs + 200);

    expect(fight.match.player.health, rules.health);
    expect(fight.match.rival.action, FighterAction.idle);
  });

  test('the bot does not punish while the opponent is still in startup', () {
    final fight = FightHarness(profile: punisher(punishChance: 1));
    fight.skipCountdown();
    walkPlayerTo(fight, 47);

    fight.pressPlayer(InputAction.lightPunch);
    // Ten ticks reach 160 ms: the jab's window has just closed, but the bot
    // has only seen the opponent still in startup and active frames.
    final ticks = (rules.lightAttack.startupMs + 60) ~/ rules.tickMs;
    for (var tick = 0; tick < ticks; tick++) {
      fight.step();
      expect(
        fight.match.rival.action,
        isNot(FighterAction.lightPunch),
        reason: 'no punish before the opening',
      );
    }
  });

  test('after its own whiffed heavy, the player\'s jab still lands', () {
    final fight = FightHarness(profile: heavyOnce, seed: 3);
    fight.skipCountdown();

    // The bot walks in and throws its heavy; the player steps back at once,
    // so the kick's whole active window is out of reach.
    var kicked = false;
    for (var i = 0; i < 400 && !kicked; i++) {
      fight.step();
      if (fight.match.rival.action == FighterAction.heavyKick) {
        fight.holdPlayer(-1);
        kicked = true;
      }
    }
    expect(kicked, isTrue, reason: 'the bot should have swung');
    fight.advance(rules.heavyAttack.totalMs);
    fight.holdPlayer(0);
    expect(fight.match.rival.health, rules.health, reason: 'the kick whiffed');

    // Walk back in and jab. The bot's own recovery is no shield.
    walkPlayerTo(fight, rules.lightAttack.reach * .9);
    fight.pressPlayer(InputAction.lightPunch);
    fight.advance(rules.lightAttack.totalMs);

    expect(
      fight.match.rival.health,
      lessThan(rules.health),
      reason: 'the bot must never be unpunishable',
    );
  });

  test('every preset reaches a decided result against itself', () {
    for (final profile in [
      BotProfile.easy,
      BotProfile.normal,
      BotProfile.hard,
    ]) {
      for (var seed = 1; seed <= 4; seed++) {
        expect(
          duel(profile, profile, seed: seed),
          isNotNull,
          reason: '${profile.difficulty.name} seed $seed',
        );
      }
    }
  });

  test('the bot never swings at a downed opponent, and swings once up', () {
    // The bot idles while the player walks into range of its heavy kick.
    const waiting = BotProfile(
      difficulty: BotDifficulty.easy,
      thinkIntervalMs: 16,
      reactionMs: 1,
      attackCooldownMs: 0,
      blockChance: 0,
      heavyChance: 1,
      hesitationChance: 1,
      recoveryMs: 0,
      preferredGap: 42,
    );
    // Then it attacks at every chance, with no cooldown: the only thing that
    // can stop it from swinging at a downed player is the rule under test.
    const striker = BotProfile(
      difficulty: BotDifficulty.hard,
      thinkIntervalMs: 16,
      reactionMs: 1,
      attackCooldownMs: 0,
      blockChance: 0,
      heavyChance: 1,
      hesitationChance: 0,
      recoveryMs: 0,
      preferredGap: 42,
    );
    final match = MatchController();
    final rules = match.rules;
    final slice = rules.tickMs / 1000;
    for (var ms = 0; ms < rules.countdownMs; ms += rules.tickMs) {
      match.tick(slice);
    }

    var bot = BotController(profile: waiting, seed: 1);
    match.setMoveAxis(FighterId.player, 1);
    var guard = 0;
    while (match.distanceBetween(FighterId.player, FighterId.rival) > 52 &&
        guard++ < 600) {
      bot.update(slice, match);
      match.tick(slice);
    }
    match.setMoveAxis(FighterId.player, 0);

    // Now the bot starts its heavy, and the player answers with a jab from
    // out of the bot's reach that is still in recovery when the heavy lands.
    bot = BotController(profile: striker, seed: 1);
    guard = 0;
    while (match.rival.action != FighterAction.heavyKick && guard++ < 200) {
      bot.update(slice, match);
      match.tick(slice);
    }
    expect(match.rival.action, FighterAction.heavyKick);
    match.submit(
      const InputCommand(
        fighter: FighterId.player,
        action: InputAction.lightPunch,
        sequence: 1,
      ),
    );
    bot.update(slice, match);
    match.tick(slice);

    // Watch for the player going down, then for any swing the bot starts
    // while it lies there, then for the bot swinging again once it is up.
    bool isSwing(FighterAction action) =>
        action == FighterAction.lightPunch || action == FighterAction.heavyKick;
    var prev = match.rival.action;
    var wentDown = false;
    var swungWhileDown = false;
    var swungAfterUp = false;
    for (var i = 0; i < 400 && !swungAfterUp; i++) {
      bot.update(slice, match);
      match.tick(slice);
      final now = match.rival.action;
      final started = isSwing(now) && !isSwing(prev);
      prev = now;
      if (match.player.isKnockedDown) {
        wentDown = true;
        swungWhileDown = swungWhileDown || started;
      } else if (wentDown && started) {
        swungAfterUp = true;
      }
    }

    expect(wentDown, isTrue, reason: 'the counter-hit put the player down');
    expect(swungWhileDown, isFalse, reason: 'no swing at a body on the floor');
    expect(swungAfterUp, isTrue, reason: 'the bot attacks again once up');
  });

  test('a sharper preset wins the majority of duels across seeds', () {
    expectSharperWins(BotProfile.hard, BotProfile.normal);
    expectSharperWins(BotProfile.normal, BotProfile.easy);
  });
}
