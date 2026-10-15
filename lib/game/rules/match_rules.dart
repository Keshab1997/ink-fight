/// Deterministic match rules for the offline bot fight.
///
/// Everything a match can do is decided by this table: the arena is a flat
/// 1-D line measured in arena units, every timing is a whole number of
/// milliseconds, and the simulation advances in whole ticks so the same input
/// script always produces the same match. No Flutter and no Flame types appear
/// here on purpose — the renderer reads the result, it never decides it, and
/// the bot and the future server must reuse these numbers instead of carrying
/// their own (docs/technical/DECISIONS.md, ADR-002 / ADR-004).
library;

/// Which side of the arena a fighter is on.
enum FighterId { player, rival }

/// Where a match is: the intro countdown, live combat, or a decided result.
enum MatchPhase { countdown, fighting, finished }

/// How a finished match ended. A timeout can end in a draw; a knockout cannot.
enum MatchOutcome { playerWin, rivalWin, draw }

/// The states a fighter can be in, in the order the design document draws them
/// (`Idle → Move → Attack startup → Active hitbox → Recovery → Hitstun /
/// Blockstun → …`).
///
/// [knockdown] is the fall a counter-hit heavy kick puts its target through:
/// the fighter is on the floor, cannot act, and cannot be hit until it stands
/// again (see [MatchRules.knockdownMs]). An ordinary hit still only holds the
/// target in hitstun, and a blow that takes the last of the health is a
/// knockout, which never enters knockdown. Dodge/dash, which the design
/// document marks optional for the first slice, is still not modelled.
enum FighterAction {
  idle,
  walk,
  jump,
  lightPunch,
  heavyKick,
  block,
  hitstun,
  blockstun,
  knockdown,
}

/// One attack's numbers, in the shape a fighting game publishes them.
///
/// `reach` is measured centre-to-centre, so a hit lands when
/// `(defender.x - attacker.x).abs() <= reach`. Measured on the delivered
/// sprites, the visible body spans about ±29 arena units around its centre
/// (300-unit arena), so two bodies first touch at a centre distance of about
/// 58. Reach is kept close to that, so a clean hit reads as contact instead of
/// damage arriving from across the room.
/// `blockedDamage` is stated per attack instead of being derived from a global
/// multiplier: a blocked light punch is fully absorbed (0) while a blocked
/// heavy kick still chips, and the table should say so out loud.
class AttackFrameData {
  const AttackFrameData({
    required this.startupMs,
    required this.activeMs,
    required this.recoveryMs,
    required this.damage,
    required this.blockedDamage,
    required this.reach,
    required this.knockback,
    required this.hitstunMs,
    required this.blockstunMs,
  });

  final int startupMs;
  final int activeMs;
  final int recoveryMs;
  final int damage;
  final int blockedDamage;
  final double reach;

  /// Units the target is pushed across its stun window, not an instant jump.
  final double knockback;
  final int hitstunMs;
  final int blockstunMs;

  int get totalMs => startupMs + activeMs + recoveryMs;

  /// The active hitbox window: after startup, before recovery.
  bool isActiveAt(int elapsedMs) =>
      elapsedMs >= startupMs && elapsedMs < startupMs + activeMs;
}

/// The tuning table: first to two round wins by default (at most three
/// 60-second rounds). Set roundsToWin to one for the single-round mode.
///
/// These are starting numbers for playtesting, not final balance: the design
/// document asks for a 60–120 second match, and the frame data below aims a
/// clean fight at roughly 8–14 landed hits. Change them here only — nothing
/// else in the repository is allowed to hold a combat constant.
class MatchRules {
  const MatchRules({
    this.health = 100,
    this.roundMs = 60000,
    this.roundsToWin = 2,
    this.countdownMs = 2000,
    this.tickMs = 16,
    this.maxCatchUpMs = 250,
    this.arenaWidth = 300,
    this.fighterHalfWidth = 15,
    this.minFighterDistance = 30,
    this.startX = 110,
    this.walkSpeed = 78,
    this.airControlFactor = .8,
    this.jumpMs = 700,
    this.blockHoldMs = 640,
    this.blockPushbackFactor = .4,
    this.knockdownMs = 840,
    this.lightAttack = const AttackFrameData(
      startupMs: 90,
      activeMs: 70,
      recoveryMs: 190,
      damage: 6,
      blockedDamage: 0,
      reach: 46,
      knockback: 8,
      hitstunMs: 220,
      blockstunMs: 150,
    ),
    this.heavyAttack = const AttackFrameData(
      startupMs: 240,
      activeMs: 90,
      recoveryMs: 340,
      damage: 14,
      blockedDamage: 2,
      reach: 58,
      knockback: 20,
      hitstunMs: 420,
      blockstunMs: 260,
    ),
  }) : assert(roundsToWin > 0);

  /// The table every normal match plays on.
  static const MatchRules standard = MatchRules();

  final int health;
  final int roundMs;

  /// Wins needed for a match. Drawn rounds award neither fighter a win.
  final int roundsToWin;
  int get maxRounds => 2 * roundsToWin - 1;
  final int countdownMs;

  /// The simulation slice. 16 ms is one frame of 60 FPS rounded down, so a
  /// `tick()` driven by the frame clock stays in step with the display.
  final int tickMs;

  /// Longest stall the simulation will replay in one call. Without it a paused
  /// debugger or a backgrounded app would fast-forward the whole match.
  final int maxCatchUpMs;

  final double arenaWidth;
  final double fighterHalfWidth;

  /// Closest two fighters may stand: the pushbox that stops them overlapping.
  final double minFighterDistance;

  /// Where the player starts; the rival mirrors it, so a match opens with the
  /// fighters apart and out of reach of every attack.
  final double startX;

  final double walkSpeed;

  /// Movement keeps this much of its speed while airborne.
  final double airControlFactor;

  final int jumpMs;

  /// How long one block button press holds the guard up.
  final int blockHoldMs;

  /// A blocked hit still shoves the blocker, at this share of the knockback.
  final double blockPushbackFactor;

  /// How long a counter-hit knockdown keeps the fighter down. The arena's
  /// delivered fall is 600 ms (90 + 100 + 120 + 140 + 150) and holds the last
  /// frame; the other 240 ms is the beat on the floor before the fighter
  /// stands. The fall is presentation, so the window is what the rules count.
  final int knockdownMs;

  final AttackFrameData lightAttack;
  final AttackFrameData heavyAttack;

  double get minX => fighterHalfWidth;
  double get maxX => arenaWidth - fighterHalfWidth;
  double get rivalStartX => arenaWidth - startX;

  /// The attack numbers for [action], or `null` when the action is not an
  /// attack (idle, walk, jump, block and the two stuns carry no hitbox).
  ///
  /// The view and the bot read reach through this instead of comparing
  /// against the frame objects by identity, so "what can this fighter hit
  /// with right now" is one lookup. It returns the same instances as
  /// [lightAttack] and [heavyAttack], never copies.
  AttackFrameData? reachOf(FighterAction action) {
    return switch (action) {
      FighterAction.lightPunch => lightAttack,
      FighterAction.heavyKick => heavyAttack,
      _ => null,
    };
  }
}
