import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../rules/fighter_state.dart';
import '../rules/match_controller.dart';
import '../rules/match_rules.dart';

/// Travelling ink, never game physics. Distances/velocities are sprite heights
/// and sprite heights per second; analytic trajectories do not drift with fps.
/// Glyphs are tiny, apex rise < .02h, sideways travel < .14h. The vertical
/// corridor connects chest contact / carried lower-body ink to the floor,
/// behind sprites. Only this module emits new floor deposits; the owner keeps
/// their one existing capped residue pool.
class ArenaInkGravity {
  static const int maxDroplets = 12;
  static const int maxWallRuns = 8;
  static const double _gravity = 2.8;
  static const double _wallGravity = 1.2;
  static const double _wallLife = 1.6;
  static const ui.Color _ink = ui.Color(0xFF101010);
  final List<_Droplet> _drops = [];
  final List<_WallRun> _walls = [];
  final Map<FighterId, _DripSource> _drips = {};
  final Map<FighterId, _Carrier> _carriers = {};
  final Map<FighterId, _Carrier> _previousCarriers = {};
  final Map<FighterId, _BodyTrail> _trails = {};
  final Map<FighterId, double> _facing = {
    FighterId.player: 1,
    FighterId.rival: -1,
  };
  int _nextId = 0;
  double _width = 0;
  double _height = 0;

  void layout(double viewportWidth, double fighterHeight) {
    _width = viewportWidth;
    _height = fighterHeight;
  }

  void observeFacing(FighterState player, FighterState rival) {
    _facing[player.id] = player.facing;
    _facing[rival.id] = rival.facing;
  }

  /// Read-only snapshots from the arena. Rendered x carries the ink with the
  /// sprite's existing spring; the jump lift is the view's existing .16h arc.
  /// Fall height follows delivered pose progress, never a second fall timer.
  void observeCarriers(
    FighterState player,
    FighterState rival,
    MatchRules rules, {
    double? playerXShare,
    double? rivalXShare,
    double playerFallProgress = 0,
    double rivalFallProgress = 0,
    bool playerFallComplete = false,
    bool rivalFallComplete = false,
  }) {
    for (final state in [player, rival]) {
      final lift = state.isAirborne
          ? math.sin(
                  math.pi *
                      (1 - state.jumpRemainingMs / rules.jumpMs).clamp(
                        0.0,
                        1.0,
                      ),
                ) *
                .16
          : 0.0;
      final fall = (state.isKnockedDown || state.health <= 0)
          ? (state.id == FighterId.player
                    ? playerFallProgress
                    : rivalFallProgress)
                .clamp(0.0, 1.0)
          : 0.0;
      final carrier = _Carrier(
        x:
            ((state.id == FighterId.player ? playerXShare : rivalXShare) ??
                    state.x / rules.arenaWidth)
                .clamp(0.0, 1.0),
        y: -.26 - lift + .205 * fall,
        facing: state.facing,
        knockedDown: state.isKnockedDown,
        fallComplete: state.id == FighterId.player
            ? playerFallComplete
            : rivalFallComplete,
      );
      _previousCarriers[state.id] = _carriers[state.id] ?? carrier;
      _carriers[state.id] = carrier;
    }
  }

  /// Fixed recipes, not a random stream: identical event/facing => identical
  /// launch velocities even after other hits or a reset. Facing is locked by
  /// the rules during attack startup, so the last observed facing is exact.
  void onHit(HitEvent event, double arenaWidth) {
    if (event.kind == HitKind.hit) {
      // One source per fighter, not one per hit. Airborne drops already shed
      // are still subject to the same global 12-drop cap.
      _drips.remove(event.defender);
      _trails.remove(event.defender);
      if (event.heavy) _drips[event.defender] = _DripSource();
      if (event.knockdown) {
        _trails[event.defender] = _BodyTrail(_carriers[event.defender]?.x);
      }
    }
    if (_width <= 0 ||
        _height <= 0 ||
        arenaWidth <= 0 ||
        event.kind != HitKind.hit ||
        (!event.heavy && !event.knockdown)) {
      return;
    }
    final count = event.knockdown ? 4 : 3;
    final direction = _facing[event.attacker] ?? 1;
    const vx = [.10, .14, .18, .20];
    const vy = [-.20, -.24, -.18, -.22];
    for (var i = 0; i < count; i++) {
      if (_drops.length == maxDroplets) _drops.removeAt(0);
      _drops.add(
        _Droplet(
          id: ++_nextId,
          originX: (event.x / arenaWidth).clamp(0.0, 1.0),
          vx: direction * vx[i],
          vy: vy[i],
          radius: .004 + i * .0005,
        ),
      );
    }
  }

  /// Called only by the room's existing one-shot outward wall-shove gate.
  /// The wall is at the rules boundary (not the screen edge or a hitbox).
  void onWall(FighterState fighter, double arenaWidth) {
    if (_width <= 0 || _height <= 0 || arenaWidth <= 0) return;
    for (var i = 0; i < 2; i++) {
      if (_walls.length == maxWallRuns) _walls.removeAt(0);
      _walls.add(
        _WallRun(
          xShare: (fighter.x / arenaWidth).clamp(0.0, 1.0),
          dx: i == 0 ? -.006 : .006,
          vy: i == 0 ? -.18 : -.24,
        ),
      );
    }
  }

  /// Use the arena's effect clock: runs through hit-stop, slows in the KO,
  /// freezes during its hold. A crossing solves the exact positive root, not
  /// an overshot Euler sample. Only that crossing hands a mark to the owner.
  void advance(double effectDt, double realDt, void Function(InkLanding) land) {
    final dt = math.max(0.0, effectDt);
    if (dt == 0 || _width <= 0 || _height <= 0) return;
    _releaseDrips(dt);
    final deposits =
        <({double offset, int kind, int id, InkLanding landing})>[];
    _depositTrails(dt, realDt, (offset, id, landing) {
      deposits.add((offset: offset, kind: 1, id: id, landing: landing));
    });
    for (final drop in _drops) {
      final startAge = drop.age;
      final endAge = startAge + dt;
      drop.age = math.min(endAge, drop.landingTime);
      if (endAge >= drop.landingTime) {
        deposits.add((
          offset: drop.landingTime - startAge,
          kind: 0,
          id: drop.id,
          landing: InkLanding(
            xShare:
                (drop.originX + drop.vx * drop.landingTime * _height / _width)
                    .clamp(0.0, 1.0),
            radiusShare: drop.radius,
            alreadyAgedMs:
                (endAge - drop.landingTime) * math.max(0.0, realDt) / dt * 1000,
          ),
        ));
      }
    }
    // A long frame still hands the ONE capped residue pool deposits in time
    // order: spatial trail crossings and analytic drop crossings interleave.
    deposits.sort((a, b) {
      final byTime = a.offset.compareTo(b.offset);
      if (byTime != 0) return byTime;
      final byKind = a.kind.compareTo(b.kind);
      return byKind != 0 ? byKind : a.id.compareTo(b.id);
    });
    for (final deposit in deposits) {
      land(deposit.landing);
    }
    _drops.removeWhere((drop) => drop.age >= drop.landingTime);
    for (final wall in _walls) {
      wall.age += dt;
    }
    _walls.removeWhere((wall) => wall.age >= _wallLife);
    _previousCarriers.addAll(_carriers);
  }

  void _releaseDrips(double dt) {
    const releases = [.22, .58, .94, 1.30];
    final finished = <FighterId>[];
    for (final entry in _drips.entries) {
      final current = _carriers[entry.key];
      final previous = _previousCarriers[entry.key] ?? current;
      final source = entry.value;
      final end = source.age + dt;
      while (source.next < releases.length && releases[source.next] <= end) {
        if (current == null || previous == null) {
          source.next++;
          continue;
        }
        final offset = (releases[source.next] - source.age).clamp(0.0, dt);
        final fraction = offset / dt;
        final side = source.next.isEven ? -.11 : .11;
        final x = previous.x + (current.x - previous.x) * fraction;
        final y = previous.y + (current.y - previous.y) * fraction;
        final inheritedVx =
            ((current.x - previous.x) * _width / _height / dt * .3).clamp(
              -.08,
              .08,
            );
        if (_drops.length == maxDroplets) _drops.removeAt(0);
        _drops.add(
          _Droplet(
            id: ++_nextId,
            originX: (x + side * current.facing * _height / _width).clamp(
              0.0,
              1.0,
            ),
            originY: y,
            vx: inheritedVx,
            vy: .025,
            radius: .0035,
          )..age = -offset,
        );
        // The negative age exists only inside this advance: the normal
        // analytic step below ages it by dt-offset, exactly at release time.
        source.next++;
      }
      source.age = end;
      if (source.next == releases.length) finished.add(entry.key);
    }
    for (final id in finished) {
      _drips.remove(id);
    }
  }

  void _depositTrails(
    double dt,
    double realDt,
    void Function(double offset, int id, InkLanding landing) deposit,
  ) {
    const spacing =
        .045; // at most six connected, quiet fragments, < .28h total
    final finished = <FighterId>[];
    for (final entry in _trails.entries) {
      final current = _carriers[entry.key];
      if (current == null) continue;
      final trail = entry.value;
      if (!current.knockedDown && !trail.sawFall) continue;
      trail.sawFall = trail.sawFall || current.knockedDown;
      trail.lastX ??= current.x;
      var distance = (current.x - trail.lastX!) * _width / _height;
      final ending = !current.knockedDown || current.fallComplete;
      while (trail.segments < 6 &&
          (distance.abs() >= spacing || (ending && distance.abs() > .001))) {
        final step = distance.clamp(-spacing, spacing);
        final from = trail.lastX!;
        final to = from + step * _height / _width;
        final previousX = (_previousCarriers[entry.key] ?? current).x;
        final frameTravel = current.x - previousX;
        final fraction = frameTravel == 0
            ? 1.0
            : ((to - previousX) / frameTravel).clamp(0.0, 1.0);
        deposit(
          fraction * dt,
          entry.key.index * 6 + trail.segments,
          InkLanding(
            xShare: ((from + to) * .5).clamp(0.0, 1.0),
            radiusShare: .005,
            widthShare: step.abs() + .008,
            opacity: .20,
            alreadyAgedMs: (1 - fraction) * math.max(0.0, realDt) * 1000,
          ),
        );
        trail.lastX = to;
        trail.segments++;
        distance = (current.x - to) * _width / _height;
      }
      if (ending || trail.segments == 6) finished.add(entry.key);
    }
    for (final id in finished) {
      _trails.remove(id);
    }
  }

  void render(ui.Canvas canvas, ui.Size viewport, double floorY, double h) {
    if (viewport.isEmpty || h <= 0) return;
    canvas.save();
    // No HUD paint: even the highest apex stays below the arena's safe top.
    canvas.clipRect(
      ui.Rect.fromLTRB(
        0,
        math.max(viewport.height * .28, floorY - h * .47),
        viewport.width,
        floorY + h * .008,
      ),
    );
    final ink = ui.Paint()..color = _ink.withValues(alpha: .64);
    for (final drop in _drops) {
      final t = drop.age;
      final x = drop.originX * viewport.width + drop.vx * t * h;
      final y =
          floorY + (drop.originY + drop.vy * t + .5 * _gravity * t * t) * h;
      final speedY = drop.vy + _gravity * t;
      // A short ink tear aligned with velocity, never a long motion trail.
      final velocity = ui.Offset(drop.vx, speedY);
      final direction = velocity / velocity.distance;
      final point = ui.Offset(x, y);
      ink
        ..strokeWidth = h * drop.radius * 1.25
        ..strokeCap = ui.StrokeCap.round;
      canvas.drawLine(point - direction * (h * .005), point, ink);
      canvas.drawCircle(point, h * drop.radius, ink);
    }
    for (final wall in _walls) {
      final tip = wall.displacement;
      final x = wall.xShare * viewport.width + wall.dx * h;
      final origin = ui.Offset(x, floorY - h * .43);
      final alpha = .32 * (1 - wall.age / _wallLife);
      ink
        ..color = _ink.withValues(alpha: alpha)
        ..strokeWidth = h * .0025;
      canvas.drawLine(origin, origin + ui.Offset(0, tip * h), ink);
      canvas.drawCircle(origin + ui.Offset(0, tip * h), h * .0035, ink);
      // Restrained initial fleck; it stays on the wall, not on the sprite.
      canvas.drawCircle(
        origin + ui.Offset(wall.dx * h, -h * .012),
        h * .003,
        ink,
      );
    }
    canvas.restore();
  }

  void reset() {
    _drops.clear();
    _drips.clear();
    _carriers.clear();
    _previousCarriers.clear();
    _trails.clear();
    _nextId = 0;
    _walls.clear();
    _facing[FighterId.player] = 1;
    _facing[FighterId.rival] = -1;
  }

  /// Live paint counts also serve the atmosphere's read-only diagnostics.
  int get dropletCount => _drops.length;

  int get wallRunCount => _walls.length;

  int get activeDripCount => _drips.length;

  int get activeTrailCount => _trails.length;

  @visibleForTesting
  List<({double originX, double dx, double y, double radius})> get droplets => [
    for (final drop in _drops)
      (
        originX: drop.originX,
        dx: drop.vx * drop.age,
        y:
            drop.originY +
            drop.vy * drop.age +
            .5 * _gravity * drop.age * drop.age,
        radius: drop.radius,
      ),
  ];

  @visibleForTesting
  List<double> get wallDisplacements => [
    for (final wall in _walls) wall.displacement,
  ];
}

/// A landing is transient data, NOT a second floor-mark collection. The owner
/// immediately inserts it into its existing capped, fading residue pool.
/// Optional width/opacity describes a body-travel fragment in that SAME pool.
class InkLanding {
  const InkLanding({
    required this.xShare,
    required this.radiusShare,
    required this.alreadyAgedMs,
    this.widthShare,
    this.opacity = .36,
  });
  final double xShare;
  final double radiusShare;
  final double alreadyAgedMs;
  final double? widthShare;
  final double opacity;
}

class _Droplet {
  _Droplet({
    required this.id,
    required this.originX,
    this.originY = -.43,
    required this.vx,
    required this.vy,
    required this.radius,
  }) : landingTime =
           (-vy +
               math.sqrt(vy * vy + 2 * ArenaInkGravity._gravity * -originY)) /
           ArenaInkGravity._gravity;
  final int id;
  final double originX;
  final double originY;
  final double vx;
  final double vy;
  final double radius;
  final double landingTime;
  double age = 0;
}

class _WallRun {
  _WallRun({required this.xShare, required this.dx, required this.vy});
  final double xShare;
  final double dx;
  final double vy;
  double age = 0;
  double get displacement =>
      math.min(.10, vy * age + .5 * ArenaInkGravity._wallGravity * age * age);
}

class _DripSource {
  double age = 0;
  int next = 0;
}

class _Carrier {
  const _Carrier({
    required this.x,
    required this.y,
    required this.facing,
    required this.knockedDown,
    required this.fallComplete,
  });
  final double x;
  final double y;
  final double facing;
  final bool knockedDown;
  final bool fallComplete;
}

class _BodyTrail {
  _BodyTrail(this.lastX);
  double? lastX;
  bool sawFall = false;
  int segments = 0;
}
