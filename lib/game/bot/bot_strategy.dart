import 'dart:math' as math;

import '../rules/fighter_state.dart';
import '../rules/input_command.dart';
import '../rules/match_controller.dart';
import '../rules/match_rules.dart';

/// How hard the practice opponent is allowed to think.
enum BotDifficulty { easy, normal, hard }

/// One difficulty preset.
///
/// A profile may only change *how well the bot plays* — its reaction, its
/// appetite for blocking, how often it hesitates. It may never change what a
/// hit does: the bot fires the same [InputCommand]s a player does and the
/// controller resolves them on the same [MatchRules] table. That is the "fair
/// practice opponent, not a cheating opponent" rule from
/// docs/product/GAME_DESIGN_DOCUMENT.md §8, and the numbers below are the only
/// place difficulty may live.
class BotProfile {
  const BotProfile({
    required this.difficulty,
    required this.thinkIntervalMs,
    required this.reactionMs,
    required this.attackCooldownMs,
    required this.blockChance,
    required this.heavyChance,
    required this.hesitationChance,
    required this.recoveryMs,
    required this.preferredGap,
  });

  final BotDifficulty difficulty;

  /// How often the bot gets to make a fresh decision.
  final int thinkIntervalMs;

  /// Delay between seeing an attack wind up and being allowed to guard. It has
  /// to stay below the heavy kick's startup or the bot could never block one,
  /// which is why the fairness test pins that relationship.
  final int reactionMs;

  /// Minimum gap between the bot's own attacks: it respects its cooldowns.
  final int attackCooldownMs;

  /// Chance of actually guarding when it reacts in time. Never 1 — a bot that
  /// cannot be opened up is not a practice partner.
  final double blockChance;

  /// How often the bot opens with the heavy kick instead of the jab.
  final double heavyChance;

  /// How often it simply does nothing for a think. Easy leans on this hard:
  /// those are the visible openings.
  final double hesitationChance;

  /// Pause after guarding, before it is allowed to act again.
  final int recoveryMs;

  /// The gap the bot tries to hold when it is not swinging, in arena units.
  /// It stays inside the heavy kick's reach — a bot that hovers just outside
  /// its own range would never attack at all. Hard stands closest, which is
  /// what makes its pressure uncomfortable.
  final double preferredGap;

  static const BotProfile easy = BotProfile(
    difficulty: BotDifficulty.easy,
    thinkIntervalMs: 50,
    reactionMs: 210,
    attackCooldownMs: 1300,
    blockChance: .35,
    heavyChance: .25,
    hesitationChance: .35,
    recoveryMs: 320,
    preferredGap: 62,
  );

  static const BotProfile normal = BotProfile(
    difficulty: BotDifficulty.normal,
    thinkIntervalMs: 40,
    reactionMs: 140,
    attackCooldownMs: 850,
    blockChance: .6,
    heavyChance: .4,
    hesitationChance: .12,
    recoveryMs: 200,
    preferredGap: 52,
  );

  static const BotProfile hard = BotProfile(
    difficulty: BotDifficulty.hard,
    thinkIntervalMs: 25,
    reactionMs: 70,
    attackCooldownMs: 540,
    blockChance: .8,
    heavyChance: .5,
    hesitationChance: .03,
    recoveryMs: 120,
    preferredGap: 42,
  );

  /// Normal is the default preset, per the design document.
  static const BotProfile defaultProfile = normal;
}

/// Plays one side of a match — the rival, by default — through the same input
/// API a human uses.
///
/// The bot is driven by the arena: call [update] once per frame with the frame
/// time and the live [MatchController]. Everything it decides is an intent
/// (a movement axis or one [InputCommand]); whether that intent is legal, and
/// what it does to the fight, is the controller's business alone.
///
/// Decisions are drawn from a seeded [math.Random], so a match against the bot
/// is reproducible: same seed, same script, same fight.
class BotController {
  BotController({
    this.rules = MatchRules.standard,
    this.profile = BotProfile.defaultProfile,
    this.fighter = FighterId.rival,
    int seed = 7,
  }) : _random = math.Random(seed);

  final MatchRules rules;
  final BotProfile profile;
  final FighterId fighter;
  final math.Random _random;

  double _thinkAccumulatorMs = 0;
  double _axis = 0;
  int _attackCooldownRemainingMs = 0;
  int _recoveryRemainingMs = 0;
  int _sequence = 0;

  /// Feeds the bot one frame of match time.
  void update(double dtSeconds, MatchController match) {
    if (!dtSeconds.isFinite || dtSeconds <= 0) {
      return;
    }
    final ms = dtSeconds * 1000;
    _attackCooldownRemainingMs = math.max(
      0,
      _attackCooldownRemainingMs - ms.round(),
    );
    _recoveryRemainingMs = math.max(0, _recoveryRemainingMs - ms.round());

    _thinkAccumulatorMs += ms;
    if (_thinkAccumulatorMs < profile.thinkIntervalMs) {
      return;
    }
    _thinkAccumulatorMs = 0;
    _think(match);
  }

  /// Puts the bot back on the starting line for a rematch.
  void reset() {
    _thinkAccumulatorMs = 0;
    _axis = 0;
    _attackCooldownRemainingMs = 0;
    _recoveryRemainingMs = 0;
    _sequence = 0;
  }

  void _think(MatchController match) {
    if (match.phase != MatchPhase.fighting) {
      _hold(match);
      return;
    }

    final me = match.stateOf(fighter);
    final opponent = match.stateOf(_opponent());
    if (!me.canAct) {
      // Mid-attack, mid-jump, mid-block or stunned: nothing to decide, and a
      // command sent now would only be dropped.
      return;
    }

    final gap = (opponent.x - me.x).abs();

    // 1. A wind-up the bot can still do something about.
    if (_threatens(opponent, gap) && _roll(profile.blockChance)) {
      _press(match, InputAction.block);
      _recoveryRemainingMs = profile.recoveryMs;
      _hold(match);
      return;
    }

    // 2. The pause after a guard it just raised: an opening the player can read
    //    and exploit, which is what keeps even Hard beatable.
    if (_recoveryRemainingMs > 0) {
      _hold(match);
      return;
    }

    // 3. A beat of nothing. Easy rolls this often, and it is where its openings
    //    come from — it does not merely attack less hard, it hesitates.
    if (_roll(profile.hesitationChance)) {
      _hold(match);
      return;
    }

    // 4. In range with the cooldown clear: swing. An airborne opponent floats
    //    over the jab, so that answer is always the heavy kick.
    if (gap <= _attackGap && _attackCooldownRemainingMs <= 0) {
      final heavy = opponent.isAirborne || _roll(profile.heavyChance);
      _press(match, heavy ? InputAction.heavyKick : InputAction.lightPunch);
      _attackCooldownRemainingMs = profile.attackCooldownMs;
      _hold(match);
      return;
    }

    // 5. Otherwise it is spacing: close the gap, or back off when the opponent
    //    is standing on top of it.
    if (gap > profile.preferredGap) {
      _push(match, opponent.x > me.x ? 1 : -1);
    } else if (gap < profile.preferredGap * .7) {
      _push(match, opponent.x > me.x ? -1 : 1);
    } else {
      _hold(match);
    }
  }

  /// True while the opponent is in the wind-up the bot could still guard
  /// against: past the bot's reaction time, and not yet past the point of
  /// landing. A guard raised after the hit has connected is pointless, so the
  /// bot does not bother.
  bool _threatens(FighterState opponent, double gap) {
    if (!opponent.isAttacking || opponent.attackConnected) {
      return false;
    }
    if (gap > _attackGap * 1.15) {
      return false;
    }
    final frame = opponent.action == FighterAction.heavyKick
        ? rules.heavyAttack
        : rules.lightAttack;
    return opponent.actionElapsedMs >= profile.reactionMs &&
        opponent.actionElapsedMs < frame.startupMs;
  }

  double get _attackGap => rules.heavyAttack.reach * .95;

  void _press(MatchController match, InputAction action) {
    _sequence++;
    match.submit(
      InputCommand(fighter: fighter, action: action, sequence: _sequence),
    );
  }

  void _push(MatchController match, double direction) {
    if (_axis == direction) {
      return;
    }
    _axis = direction;
    match.setMoveAxis(fighter, direction);
  }

  void _hold(MatchController match) {
    if (_axis == 0) {
      return;
    }
    _axis = 0;
    match.setMoveAxis(fighter, 0);
  }

  bool _roll(double chance) => _random.nextDouble() < chance;

  FighterId _opponent() =>
      fighter == FighterId.player ? FighterId.rival : FighterId.player;
}
