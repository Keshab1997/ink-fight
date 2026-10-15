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
/// appetite for blocking, how often it hesitates, how quickly it punishes. It
/// may never change what a hit does: the bot fires the same [InputCommand]s a
/// player does and the controller resolves them on the same [MatchRules]
/// table. That is the "fair practice opponent, not a cheating opponent" rule
/// from docs/product/GAME_DESIGN_DOCUMENT.md §8, and the numbers below are the
/// only place difficulty may live.
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
    this.punishChance = 0,
  });

  final BotDifficulty difficulty;

  /// How often the bot gets to make a fresh decision.
  final int thinkIntervalMs;

  /// Delay between seeing an attack wind up, or an opening open, and being
  /// allowed to act on it. For a wind-up it has to stay below the heavy
  /// kick's startup or the bot could never block one, which is why the
  /// fairness test pins that relationship.
  final int reactionMs;

  /// Minimum gap between the bot's own attacks: it respects its cooldowns.
  /// A punish and a swing at a stunned opponent are the two exceptions, and
  /// both are documented where they happen.
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

  /// Chance that the bot takes an opening it sees: the player's swing is in
  /// recovery, or has just cut air. The roll is made once per opening, so a
  /// bot either goes for an opening or lets it pass. Zero means the bot never
  /// punishes at all.
  final double punishChance;

  static const BotProfile easy = BotProfile(
    difficulty: BotDifficulty.easy,
    thinkIntervalMs: 50,
    reactionMs: 210,
    attackCooldownMs: 1300,
    blockChance: .35,
    heavyChance: .25,
    hesitationChance: .35,
    recoveryMs: 320,
    preferredGap: 54,
    punishChance: .15,
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
    punishChance: .5,
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
    punishChance: .85,
  );

  /// Normal is the default preset, per the design document.
  static const BotProfile defaultProfile = normal;

  /// Maps the menu's difficulty choice onto the presets above — the one place
  /// the picker's enum meets the numbers, so a screen can never assemble its
  /// own profile.
  static BotProfile forDifficulty(BotDifficulty difficulty) =>
      switch (difficulty) {
        BotDifficulty.easy => easy,
        BotDifficulty.normal => normal,
        BotDifficulty.hard => hard,
      };
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

  /// Match time the bot has been fed, in whole milliseconds. Reaction delays
  /// are measured against it, so they hold whatever the frame rate is.
  int _clockMs = 0;

  /// Whether the opening the bot is tracking will be punished. Null while no
  /// opening is open. Rolled once, when an opening first appears.
  bool? _openingPunish;

  /// Clock time when the current opening was first seen.
  int _openingSeenAtMs = 0;

  /// Set once the bot has committed to a punish in the current opening, so it
  /// fires at most once per opening.
  bool _punishSpent = false;

  /// Feeds the bot one frame of match time.
  void update(double dtSeconds, MatchController match) {
    if (!dtSeconds.isFinite || dtSeconds <= 0) {
      return;
    }
    final ms = dtSeconds * 1000;
    _clockMs += ms.round();
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
    _clockMs = 0;
    _openingPunish = null;
    _openingSeenAtMs = 0;
    _punishSpent = false;
  }

  void _think(MatchController match) {
    if (match.phase != MatchPhase.fighting) {
      _hold(match);
      return;
    }

    final me = match.stateOf(fighter);
    final opponent = match.stateOf(_opponent());
    _trackOpening(opponent);
    if (me.isKnockedDown) {
      // On the floor there is nothing to decide, and a command sent now would
      // only be dropped. Drop any walk held into the fall, and stop thinking.
      _hold(match);
      return;
    }
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

    // 3. An opening the bot committed to punishing. This runs ahead of the
    //    hesitation roll: the punish is already the gamble that was rolled.
    if (_punishDue(opponent)) {
      _punish(match, opponent);
      return;
    }

    // 4. A stunned opponent that a swing of ours would reach: keep swinging.
    //    Pressure ignores the cooldown on purpose — the controller already
    //    drops anything it cannot accept, and that is the only limit.
    if (opponent.isStunned) {
      final heavyLands = match.wouldConnect(fighter, FighterAction.heavyKick);
      final jabLands = match.wouldConnect(fighter, FighterAction.lightPunch);
      if (heavyLands || jabLands) {
        final heavy = heavyLands && (!jabLands || _roll(profile.heavyChance));
        _pressSwing(match, heavy);
        return;
      }
    }

    // 5. A beat of nothing. Easy rolls this often, and it is where its openings
    //    come from — it does not merely attack less hard, it hesitates.
    if (_roll(profile.hesitationChance)) {
      _hold(match);
      return;
    }

    // 6. In range with the cooldown clear: swing. An airborne opponent floats
    //    over the jab, so that answer is always the heavy kick. Otherwise the
    //    heavy is only started while the opponent's swing has not yet reached
    //    its startup, because past that point the jab wins the trade.
    // A downed opponent cannot be hit, so a swing at it is a free punish for
    // nobody. The bot waits and keeps spacing until it stands again.
    if (!opponent.isKnockedDown &&
        gap <= _attackGap &&
        _attackCooldownRemainingMs <= 0) {
      final heavy =
          opponent.isAirborne ||
          (_roll(profile.heavyChance) && !_opponentPastStartup(opponent));
      _pressSwing(match, heavy);
      return;
    }

    // 7. Otherwise it is spacing: close the gap, or back off when the opponent
    //    is standing on top of it.
    if (gap > profile.preferredGap) {
      _push(match, opponent.x > me.x ? 1 : -1);
    } else if (gap < profile.preferredGap * .7) {
      _push(match, opponent.x > me.x ? -1 : 1);
    } else {
      _hold(match);
    }
  }

  /// Tracks the opponent's opening, if it has one, and rolls once whether to
  /// punish it. A zero punish chance never rolls, so it does not perturb the
  /// random sequence the other rules draw from.
  void _trackOpening(FighterState opponent) {
    if (!_isOpening(opponent)) {
      _openingPunish = null;
      _punishSpent = false;
      return;
    }
    if (_openingPunish == null) {
      _openingSeenAtMs = _clockMs;
      _openingPunish = profile.punishChance > 0 && _roll(profile.punishChance);
    }
  }

  /// An opening is the opponent's swing once its active window has closed,
  /// whether it connected or not, and also the moment a swing is known to
  /// have whiffed. A swing that is still in startup or active is not one.
  bool _isOpening(FighterState opponent) {
    final frame = rules.reachOf(opponent.action);
    if (frame == null) {
      return false;
    }
    return opponent.attackWhiffed ||
        opponent.actionElapsedMs >= frame.startupMs + frame.activeMs;
  }

  /// A punish is due once the bot has committed to the current opening, has
  /// not already spent its one punish on it, and has waited out its reaction.
  bool _punishDue(FighterState opponent) {
    return _openingPunish == true &&
        !_punishSpent &&
        _isOpening(opponent) &&
        _clockMs - _openingSeenAtMs >= profile.reactionMs;
  }

  /// The punish itself. It steps in at full speed, ignores both the cooldown
  /// and [BotProfile.preferredGap], and swings with the attack that actually
  /// connects: the jab first, and the heavy only when it lands and the
  /// opponent's recovery is still longer than the heavy's startup.
  void _punish(MatchController match, FighterState opponent) {
    final me = match.stateOf(fighter);
    if (match.wouldConnect(fighter, FighterAction.lightPunch)) {
      _press(match, InputAction.lightPunch);
      _punishSpent = true;
      _hold(match);
      return;
    }

    final swing = rules.reachOf(opponent.action);
    final remaining = swing == null
        ? 0
        : swing.totalMs - opponent.actionElapsedMs;
    if (remaining > rules.heavyAttack.startupMs &&
        match.wouldConnect(fighter, FighterAction.heavyKick)) {
      _press(match, InputAction.heavyKick);
      _punishSpent = true;
      _hold(match);
      return;
    }

    _push(match, opponent.x > me.x ? 1 : -1);
  }

  /// Whether the opponent's current swing has already passed its startup.
  bool _opponentPastStartup(FighterState opponent) {
    final frame = rules.reachOf(opponent.action);
    return frame != null && opponent.actionElapsedMs >= frame.startupMs;
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

  /// Starts a swing, the jab or the heavy, and puts the cooldown back.
  void _pressSwing(MatchController match, bool heavy) {
    _press(match, heavy ? InputAction.heavyKick : InputAction.lightPunch);
    _attackCooldownRemainingMs = profile.attackCooldownMs;
    _hold(match);
  }

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
