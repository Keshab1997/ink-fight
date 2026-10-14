import 'match_rules.dart';

/// One fighter's whole state at one instant.
///
/// Immutable on purpose: the controller replaces the object instead of
/// mutating it, so a hit resolved this tick can never edit a state some other
/// code is already reading. The class is also free of widgets and rendering
/// objects, which is what lets the same value travel to a server later
/// (docs/technical/TECHNICAL_ARCHITECTURE.md, "Domain boundaries").
class FighterState {
  const FighterState({
    required this.id,
    required this.x,
    required this.health,
    required this.facing,
    this.action = FighterAction.idle,
    this.actionElapsedMs = 0,
    this.stunRemainingMs = 0,
    this.blockRemainingMs = 0,
    this.jumpRemainingMs = 0,
    this.pushVelocity = 0,
    this.attackConnected = false,
  });

  final FighterId id;

  /// Position along the arena line, in arena units (0 … `arenaWidth`).
  final double x;
  final int health;

  /// 1 faces right, -1 faces left. Locked while attacking or blocking.
  final double facing;

  final FighterAction action;

  /// Milliseconds spent in the current action; drives `isActiveAt` for attacks.
  final int actionElapsedMs;
  final int stunRemainingMs;
  final int blockRemainingMs;
  final int jumpRemainingMs;

  /// Units per second the fighter is still being shoved across its stun.
  final double pushVelocity;

  /// An attack may only land once; this flips when it does.
  final bool attackConnected;

  /// Only idle and walking fighters may start something new. Attacks, jumps,
  /// blocks and stuns are all committed windows, which is what makes a whiff
  /// punishable.
  bool get canAct =>
      action == FighterAction.idle || action == FighterAction.walk;

  bool get isAirborne => action == FighterAction.jump;

  bool get isStunned =>
      action == FighterAction.hitstun || action == FighterAction.blockstun;

  bool get isAttacking =>
      action == FighterAction.lightPunch || action == FighterAction.heavyKick;

  bool get isBlocking => action == FighterAction.block;

  FighterState copyWith({
    double? x,
    int? health,
    double? facing,
    FighterAction? action,
    int? actionElapsedMs,
    int? stunRemainingMs,
    int? blockRemainingMs,
    int? jumpRemainingMs,
    double? pushVelocity,
    bool? attackConnected,
  }) {
    return FighterState(
      id: id,
      x: x ?? this.x,
      health: health ?? this.health,
      facing: facing ?? this.facing,
      action: action ?? this.action,
      actionElapsedMs: actionElapsedMs ?? this.actionElapsedMs,
      stunRemainingMs: stunRemainingMs ?? this.stunRemainingMs,
      blockRemainingMs: blockRemainingMs ?? this.blockRemainingMs,
      jumpRemainingMs: jumpRemainingMs ?? this.jumpRemainingMs,
      pushVelocity: pushVelocity ?? this.pushVelocity,
      attackConnected: attackConnected ?? this.attackConnected,
    );
  }
}
