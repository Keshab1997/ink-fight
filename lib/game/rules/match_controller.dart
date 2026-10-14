import 'dart:math' as math;

import 'fighter_state.dart';
import 'input_command.dart';
import 'match_rules.dart';

/// Runs one local match on [MatchRules], tick by tick.
///
/// The controller owns the match clock, legal state transitions, collision
/// results and the final outcome — the same responsibilities the server takes
/// over in online mode (docs/technical/DECISIONS.md, ADR-004). It knows nothing
/// about Flame or widgets: the arena feeds it input and reads state back, and
/// the bot will drive `player`'s opposite through the identical API, so neither
/// side can ever take a shortcut past these rules.
class MatchController {
  MatchController({this.rules = MatchRules.standard}) {
    reset();
  }

  final MatchRules rules;

  late FighterState _player;
  late FighterState _rival;
  final Map<FighterId, double> _moveAxis = <FighterId, double>{};
  final Map<FighterId, int> _lastSequence = <FighterId, int>{};

  MatchPhase _phase = MatchPhase.countdown;
  MatchOutcome? _outcome;
  int _countdownRemainingMs = 0;
  int _timeRemainingMs = 0;
  double _accumulatorMs = 0;

  MatchPhase get phase => _phase;
  MatchOutcome? get outcome => _outcome;
  int get timeRemainingMs => _timeRemainingMs;
  FighterState get player => _player;
  FighterState get rival => _rival;
  bool get isFinished => _phase == MatchPhase.finished;

  /// The current state of either side.
  FighterState stateOf(FighterId id) =>
      id == FighterId.player ? _player : _rival;

  /// Starts a fresh match on the same rules: the rematch path, and the only
  /// way back from a finished match. Everything a match can accumulate — the
  /// clock, the sequence numbers, held movement — is cleared here.
  void reset() {
    _player = _freshState(FighterId.player, rules.startX);
    _rival = _freshState(FighterId.rival, rules.rivalStartX);
    _phase = MatchPhase.countdown;
    _outcome = null;
    _countdownRemainingMs = rules.countdownMs;
    _timeRemainingMs = rules.roundMs;
    _accumulatorMs = 0;
    _lastSequence.clear();
    _moveAxis
      ..clear()
      ..[FighterId.player] = 0
      ..[FighterId.rival] = 0;
  }

  /// Records a held direction (-1 left, 0 still, 1 right). Movement is a state,
  /// not an event, so it is remembered until it changes and applied every tick.
  void setMoveAxis(FighterId fighter, double axis) {
    _moveAxis[fighter] = axis.isFinite ? axis.clamp(-1.0, 1.0) : 0;
  }

  /// Applies one intent, or drops it. Dropped when the match is not fighting,
  /// when the command is stale (a sequence number already seen for that
  /// fighter), or when the fighter is inside a committed window — attacking,
  /// jumping, blocking or stunned. Illegal input is ignored rather than queued:
  /// a player who mashes during recovery does not get a free extra attack.
  void submit(InputCommand command) {
    final seen = _lastSequence[command.fighter];
    if (seen != null && command.sequence <= seen) {
      return;
    }
    _lastSequence[command.fighter] = command.sequence;

    if (_phase != MatchPhase.fighting) {
      return;
    }
    final fighter = stateOf(command.fighter);
    if (!fighter.canAct) {
      return;
    }

    switch (command.action) {
      case InputAction.lightPunch:
        _set(
          command.fighter,
          fighter.copyWith(
            action: FighterAction.lightPunch,
            actionElapsedMs: 0,
            attackConnected: false,
          ),
        );
      case InputAction.heavyKick:
        _set(
          command.fighter,
          fighter.copyWith(
            action: FighterAction.heavyKick,
            actionElapsedMs: 0,
            attackConnected: false,
          ),
        );
      case InputAction.jump:
        _set(
          command.fighter,
          fighter.copyWith(
            action: FighterAction.jump,
            actionElapsedMs: 0,
            jumpRemainingMs: rules.jumpMs,
          ),
        );
      case InputAction.block:
        _set(
          command.fighter,
          fighter.copyWith(
            action: FighterAction.block,
            actionElapsedMs: 0,
            blockRemainingMs: rules.blockHoldMs,
          ),
        );
    }
  }

  /// Advances the match by real elapsed seconds.
  ///
  /// The caller may pass any frame time; the controller consumes it in whole
  /// [MatchRules.tickMs] slices so the simulation never depends on how fast the
  /// device renders. A stall longer than [MatchRules.maxCatchUpMs] is clamped,
  /// because replaying ten seconds of a backgrounded match is not a feature.
  void tick(double dtSeconds) {
    if (_phase == MatchPhase.finished ||
        !dtSeconds.isFinite ||
        dtSeconds <= 0) {
      return;
    }

    _accumulatorMs += dtSeconds * 1000;
    if (_accumulatorMs > rules.maxCatchUpMs) {
      _accumulatorMs = rules.maxCatchUpMs.toDouble();
    }

    while (_accumulatorMs >= rules.tickMs) {
      _accumulatorMs -= rules.tickMs;
      _step(rules.tickMs);
      if (_phase == MatchPhase.finished) {
        _accumulatorMs = 0;
        return;
      }
    }
  }

  FighterState _freshState(FighterId id, double x) => FighterState(
    id: id,
    x: x,
    health: rules.health,
    facing: id == FighterId.player ? 1 : -1,
  );

  void _set(FighterId id, FighterState state) {
    if (id == FighterId.player) {
      _player = state;
    } else {
      _rival = state;
    }
  }

  void _step(int ms) {
    if (_phase == MatchPhase.countdown) {
      _countdownRemainingMs -= ms;
      if (_countdownRemainingMs <= 0) {
        _countdownRemainingMs = 0;
        _phase = MatchPhase.fighting;
      }
      return;
    }

    _timeRemainingMs -= ms;
    _player = _advance(_player, ms);
    _rival = _advance(_rival, ms);
    _resolveHits();
    _resolvePushbox();

    if (_player.health <= 0 || _rival.health <= 0) {
      _finish(_knockoutOutcome());
      return;
    }
    if (_timeRemainingMs <= 0) {
      _timeRemainingMs = 0;
      _finish(_timeoutOutcome());
    }
  }

  FighterState _advance(FighterState fighter, int ms) {
    switch (fighter.action) {
      case FighterAction.lightPunch:
      case FighterAction.heavyKick:
        final elapsed = fighter.actionElapsedMs + ms;
        final frame = _frameDataFor(fighter.action);
        if (elapsed >= frame.totalMs) {
          return fighter.copyWith(
            action: FighterAction.idle,
            actionElapsedMs: 0,
            attackConnected: false,
          );
        }
        return fighter.copyWith(actionElapsedMs: elapsed);

      case FighterAction.jump:
        final moved = _walk(
          fighter,
          _axisOf(fighter.id),
          ms,
          factor: rules.airControlFactor,
        );
        final remaining = fighter.jumpRemainingMs - ms;
        if (remaining <= 0) {
          return moved.copyWith(action: FighterAction.idle, jumpRemainingMs: 0);
        }
        return moved.copyWith(jumpRemainingMs: remaining);

      case FighterAction.block:
        final remaining = fighter.blockRemainingMs - ms;
        if (remaining <= 0) {
          return fighter.copyWith(
            action: FighterAction.idle,
            blockRemainingMs: 0,
          );
        }
        return fighter.copyWith(blockRemainingMs: remaining);

      case FighterAction.hitstun:
      case FighterAction.blockstun:
        final slid = _slide(fighter, ms);
        final remaining = fighter.stunRemainingMs - ms;
        if (remaining <= 0) {
          return slid.copyWith(
            action: FighterAction.idle,
            stunRemainingMs: 0,
            pushVelocity: 0,
          );
        }
        return slid.copyWith(stunRemainingMs: remaining);

      case FighterAction.idle:
      case FighterAction.walk:
        final axis = _axisOf(fighter.id);
        // A fighter on their feet squares up on their own; an attacking or
        // blocking one keeps the direction it committed to.
        final moved = _walk(_faceOpponent(fighter), axis, ms);
        return moved.copyWith(
          action: axis == 0 ? FighterAction.idle : FighterAction.walk,
        );
    }
  }

  /// Movement along the arena line, clamped to the walls.
  FighterState _walk(
    FighterState fighter,
    double axis,
    int ms, {
    double factor = 1,
  }) {
    if (axis == 0) {
      return fighter;
    }
    final step = axis * rules.walkSpeed * factor * ms / 1000;
    return fighter.copyWith(x: _clampX(fighter.x + step));
  }

  /// Knockback: the shove is spread across the stun window so the sprite
  /// slides instead of teleporting.
  FighterState _slide(FighterState fighter, int ms) {
    if (fighter.pushVelocity == 0) {
      return fighter;
    }
    return fighter.copyWith(
      x: _clampX(fighter.x + fighter.pushVelocity * ms / 1000),
    );
  }

  /// Resolves both attack hitboxes for this tick.
  ///
  /// Both fighters are checked, so simultaneous attacks can trade — being hit
  /// interrupts an attack, which is what makes a fast light punch a real answer
  /// to a slow heavy kick.
  void _resolveHits() {
    for (final id in FighterId.values) {
      final attacker = stateOf(id);
      if (!attacker.isAttacking || attacker.attackConnected) {
        continue;
      }
      final frame = _frameDataFor(attacker.action);
      if (!frame.isActiveAt(attacker.actionElapsedMs)) {
        continue;
      }

      final defender = stateOf(_opponentOf(id));
      // A light punch passes under a fighter who is in the air; a heavy kick
      // still catches them on the way up or down. Tunable here and nowhere
      // else — it is what gives the jump a defensive use.
      if (defender.isAirborne && frame == rules.lightAttack) {
        continue;
      }

      final dx = defender.x - attacker.x;
      if (dx * attacker.facing <= 0 || dx.abs() > frame.reach) {
        continue;
      }

      final blocked =
          defender.isBlocking &&
          (attacker.x - defender.x) * defender.facing > 0;
      _set(id, attacker.copyWith(attackConnected: true));
      _set(_opponentOf(id), _takeHit(defender, frame, blocked: blocked));
    }
  }

  FighterState _takeHit(
    FighterState defender,
    AttackFrameData frame, {
    required bool blocked,
  }) {
    if (blocked) {
      final stunMs = math.max(frame.blockstunMs, rules.tickMs);
      return defender.copyWith(
        health: math.max(0, defender.health - frame.blockedDamage),
        action: FighterAction.blockstun,
        actionElapsedMs: 0,
        blockRemainingMs: 0,
        stunRemainingMs: stunMs,
        pushVelocity:
            frame.knockback * rules.blockPushbackFactor / (stunMs / 1000),
      );
    }

    final stunMs = math.max(frame.hitstunMs, rules.tickMs);
    return defender.copyWith(
      health: math.max(0, defender.health - frame.damage),
      action: FighterAction.hitstun,
      actionElapsedMs: 0,
      blockRemainingMs: 0,
      stunRemainingMs: stunMs,
      pushVelocity: frame.knockback / (stunMs / 1000),
    );
  }

  /// Keeps the two fighters from standing inside each other.
  void _resolvePushbox() {
    final gap = _rival.x - _player.x;
    if (gap.abs() >= rules.minFighterDistance) {
      return;
    }
    final dir = gap < 0 ? -1.0 : 1.0;

    // The player keeps the ground he walked onto and the rival is seated a
    // pushbox away. When a wall leaves no room for that — the rival is pinned
    // against it — the rival keeps his ground and the player is held off
    // instead. One of the two always has room, so they never end a tick
    // overlapping.
    final playerX = _clampX(_player.x);
    final rivalX = _clampX(playerX + dir * rules.minFighterDistance);
    _player = _player.copyWith(x: playerX);
    if ((rivalX - playerX).abs() >= rules.minFighterDistance - .001) {
      _rival = _rival.copyWith(x: rivalX);
      return;
    }

    final seatedRivalX = _clampX(_rival.x);
    _rival = _rival.copyWith(x: seatedRivalX);
    _player = _player.copyWith(
      x: _clampX(seatedRivalX - dir * rules.minFighterDistance),
    );
  }

  FighterState _faceOpponent(FighterState fighter) {
    final opponent = stateOf(_opponentOf(fighter.id));
    if (opponent.x == fighter.x) {
      return fighter;
    }
    final facing = opponent.x > fighter.x ? 1.0 : -1.0;
    return facing == fighter.facing
        ? fighter
        : fighter.copyWith(facing: facing);
  }

  double _clampX(double x) => x.clamp(rules.minX, rules.maxX);

  AttackFrameData _frameDataFor(FighterAction action) =>
      action == FighterAction.heavyKick ? rules.heavyAttack : rules.lightAttack;

  double _axisOf(FighterId id) => _moveAxis[id] ?? 0;

  FighterId _opponentOf(FighterId id) =>
      id == FighterId.player ? FighterId.rival : FighterId.player;

  MatchOutcome _knockoutOutcome() {
    if (_player.health <= 0 && _rival.health <= 0) {
      return MatchOutcome.draw;
    }
    return _player.health <= 0 ? MatchOutcome.rivalWin : MatchOutcome.playerWin;
  }

  /// On the clock running out the healthier fighter wins and a tie is a draw,
  /// exactly as the design document specifies for the bot-fight MVP.
  MatchOutcome _timeoutOutcome() {
    if (_player.health == _rival.health) {
      return MatchOutcome.draw;
    }
    return _player.health > _rival.health
        ? MatchOutcome.playerWin
        : MatchOutcome.rivalWin;
  }

  void _finish(MatchOutcome outcome) {
    _phase = MatchPhase.finished;
    _outcome = outcome;
    _moveAxis
      ..[FighterId.player] = 0
      ..[FighterId.rival] = 0;
  }
}
