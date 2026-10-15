import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:inkfight/game/bot/bot_strategy.dart';
import 'package:inkfight/game/rules/fighter_state.dart';
import 'package:inkfight/game/rules/match_controller.dart';
import 'package:inkfight/game/rules/match_rules.dart';

/// A bot-vs-bot soak: full matches at every difficulty on a jittered
/// frame-time script with a stall and a zero dt, checking the simulation's
/// standing promises after every frame.
///
/// Witness-only: if anything here fails, the failure is reported with its
/// seed and the sim is left untouched — this file never fixes `lib/game`.
/// Seeds: frame script 42; bots easy 11/12, normal 201/202, hard 301/302
/// (player bot / rival bot).
const int _scriptSeed = 42;

/// More frames than any 60-second match can need, even if every frame were
/// the script's shortest: the loop fails loudly instead of hanging forever.
const int _maxFrames = 40000;

/// Think-then-step, the arena's frame order: both bots decide on the current
/// state, then the simulation consumes the frame.
void _frame(
  MatchController match,
  BotController playerBot,
  BotController rivalBot,
  double dt,
) {
  playerBot.update(dt, match);
  rivalBot.update(dt, match);
  match.tick(dt);
}

/// A deterministic frame-time script: 60 FPS with jitter, one stall longer
/// than [MatchRules.maxCatchUpMs] halfway through, one zero dt at 3/4.
List<double> _frameScript({int frames = 4096}) {
  final rng = math.Random(_scriptSeed);
  final script = List<double>.generate(
    frames,
    (_) => 0.008 + rng.nextDouble() * 0.017,
  );
  script[frames ~/ 2] = 0.4;
  script[frames * 3 ~/ 4] = 0;
  return script;
}

/// Runs [match] to a decision on [script] (cycled), checking the standing
/// promises after every frame: finite coordinates inside the walls, health
/// draining monotonically from full to floored at zero.
void _runToDecision(
  MatchController match,
  BotController playerBot,
  BotController rivalBot,
  List<double> script,
) {
  final rules = match.rules;
  var playerHealth = rules.health;
  var rivalHealth = rules.health;
  var frame = 0;
  var round = match.roundNumber;
  while (!match.isFinished) {
    _frame(match, playerBot, rivalBot, script[frame % script.length]);
    frame++;
    // A decided round hands both fighters a full bar again, so "health drains
    // and never climbs" is a PER-ROUND invariant now that a match is best of
    // three. Restart the baselines at the boundary instead of failing there.
    if (match.roundNumber != round) {
      round = match.roundNumber;
      playerHealth = rules.health;
      rivalHealth = rules.health;
    }
    for (final fighter in [match.player, match.rival]) {
      expect(
        fighter.x.isFinite,
        isTrue,
        reason: 'frame $frame ${fighter.id} x finite',
      );
      expect(
        fighter.x,
        inInclusiveRange(rules.minX, rules.maxX),
        reason: 'frame $frame ${fighter.id} x inside the walls',
      );
    }
    expect(
      match.player.health,
      inInclusiveRange(0, playerHealth),
      reason: 'frame $frame player health drains, never climbs',
    );
    expect(
      match.rival.health,
      inInclusiveRange(0, rivalHealth),
      reason: 'frame $frame rival health drains, never climbs',
    );
    playerHealth = match.player.health;
    rivalHealth = match.rival.health;
    if (frame >= _maxFrames) {
      fail('still fighting after $_maxFrames frames');
    }
  }
  expect(match.outcome, isNotNull, reason: 'a decision in-round');
}

/// Every observable scalar of a match in one string: doubles print
/// shortest-round-trip, so equal fingerprints mean bit-identical matches.
String _fingerprint(MatchController match) {
  String fighter(FighterState s) =>
      '${s.x}|${s.health}|${s.facing}|${s.action}|'
      '${s.actionElapsedMs}|${s.stunRemainingMs}|${s.blockRemainingMs}|'
      '${s.knockdownRemainingMs}|'
      '${s.jumpRemainingMs}|${s.pushVelocity}|${s.attackConnected}|'
      '${s.attackWhiffed}';

  return '${match.phase}|${match.outcome}|${match.timeRemainingMs}|'
      '${match.countdownRemainingMs}|${fighter(match.player)}|'
      '${fighter(match.rival)}';
}

/// Plays one full bot-vs-bot match and hands back the decided controller.
MatchController _playOut({
  required BotDifficulty difficulty,
  required int playerSeed,
  required int rivalSeed,
}) {
  final match = MatchController();
  final profile = BotProfile.forDifficulty(difficulty);
  _runToDecision(
    match,
    BotController(
      profile: profile,
      fighter: FighterId.player,
      seed: playerSeed,
    ),
    BotController(profile: profile, fighter: FighterId.rival, seed: rivalSeed),
    _frameScript(),
  );
  return match;
}

void main() {
  group('bot-vs-bot soak', () {
    const seeds = {
      BotDifficulty.easy: (11, 12),
      BotDifficulty.normal: (201, 202),
      BotDifficulty.hard: (301, 302),
    };
    for (final entry in seeds.entries) {
      test('${entry.key.name} reaches a decision under jitter', () {
        final match = _playOut(
          difficulty: entry.key,
          playerSeed: entry.value.$1,
          rivalSeed: entry.value.$2,
        );

        expect(match.isFinished, isTrue);
        expect(match.outcome, isNotNull);
      });
    }
  });

  test('ticks after the finish change nothing', () {
    final match = _playOut(
      difficulty: BotDifficulty.normal,
      playerSeed: 201,
      rivalSeed: 202,
    );
    final decided = _fingerprint(match);

    match.tick(0.016);
    match.tick(1);
    match.tick(0);

    expect(_fingerprint(match), decided);
  });

  test('same seeds and script replay bit-identically', () {
    final first = _fingerprint(
      _playOut(
        difficulty: BotDifficulty.normal,
        playerSeed: 201,
        rivalSeed: 202,
      ),
    );
    final second = _fingerprint(
      _playOut(
        difficulty: BotDifficulty.normal,
        playerSeed: 201,
        rivalSeed: 202,
      ),
    );

    expect(second, first);
  });

  test('five resets equal a fresh controller', () {
    final match = MatchController();
    final profile = BotProfile.normal;
    final playerBot = BotController(
      profile: profile,
      fighter: FighterId.player,
      seed: 201,
    );
    final rivalBot = BotController(
      profile: profile,
      fighter: FighterId.rival,
      seed: 202,
    );
    final script = _frameScript();
    // Dirty the match mid-fight: held movement, sequence numbers, events.
    for (var frame = 0; frame < 500; frame++) {
      _frame(match, playerBot, rivalBot, script[frame % script.length]);
    }

    for (var i = 0; i < 5; i++) {
      match.reset();
    }

    expect(_fingerprint(match), _fingerprint(MatchController()));
  });

  test('a reset rematch plays clean to a decision', () {
    final match = MatchController();
    const profile = BotProfile.hard;
    final playerBot = BotController(
      profile: profile,
      fighter: FighterId.player,
      seed: 301,
    );
    final rivalBot = BotController(
      profile: profile,
      fighter: FighterId.rival,
      seed: 302,
    );
    final script = _frameScript();
    _runToDecision(match, playerBot, rivalBot, script);

    match.reset();
    playerBot.reset();
    rivalBot.reset();
    _runToDecision(match, playerBot, rivalBot, script);

    expect(match.isFinished, isTrue);
    expect(match.outcome, isNotNull);
  });
}
