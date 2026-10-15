import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../rules/fighter_state.dart';
import '../rules/match_controller.dart';
import '../rules/match_rules.dart';

/// Travelling ink, never game physics. Distances/velocities are sprite heights
/// and sprite heights per second; analytic trajectories do not drift with fps.
/// Glyphs are tiny, apex rise < .02h, sideways travel < .14h. The vertical
/// corridor connects the existing chest contact to the floor, behind sprites.
class ArenaInkGravity {
  static const int maxDroplets = 12;
  static const int maxWallRuns = 8;
  static const double _gravity = 2.8;
  static const double _wallGravity = 1.2;
  static const double _wallLife = 1.6;
  static const ui.Color _ink = ui.Color(0xFF101010);
  final List<_Droplet> _drops = [];
  final List<_WallRun> _walls = [];
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

  /// Fixed recipes, not a random stream: identical event/facing => identical
  /// launch velocities even after other hits or a reset. Facing is locked by
  /// the rules during attack startup, so the last observed facing is exact.
  void onHit(HitEvent event, double arenaWidth) {
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
    final crossings = <({_Droplet drop, double offset, double agedMs})>[];
    for (final drop in _drops) {
      final startAge = drop.age;
      final endAge = startAge + dt;
      drop.age = math.min(endAge, drop.landingTime);
      if (endAge >= drop.landingTime) {
        crossings.add((
          drop: drop,
          offset: drop.landingTime - startAge,
          agedMs:
              (endAge - drop.landingTime) * math.max(0.0, realDt) / dt * 1000,
        ));
      }
    }
    // Even when one long frame contains several crossings, residue enters
    // the shared pool in physical landing order, not recipe iteration order.
    crossings.sort((a, b) {
      final byTime = a.offset.compareTo(b.offset);
      return byTime != 0 ? byTime : a.drop.id.compareTo(b.drop.id);
    });
    for (final crossing in crossings) {
      final drop = crossing.drop;
      land(
        InkLanding(
          xShare: (drop.originX + drop.vx * drop.landingTime * _height / _width)
              .clamp(0.0, 1.0),
          radiusShare: drop.radius,
          alreadyAgedMs: crossing.agedMs,
        ),
      );
    }
    _drops.removeWhere((drop) => drop.age >= drop.landingTime);
    for (final wall in _walls) {
      wall.age += dt;
    }
    _walls.removeWhere((wall) => wall.age >= _wallLife);
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
      final y = floorY + (-.43 + drop.vy * t + .5 * _gravity * t * t) * h;
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
    _nextId = 0;
    _walls.clear();
    _facing[FighterId.player] = 1;
    _facing[FighterId.rival] = -1;
  }

  /// Live paint counts also serve the atmosphere's read-only diagnostics.
  int get dropletCount => _drops.length;

  int get wallRunCount => _walls.length;

  @visibleForTesting
  List<({double originX, double dx, double y, double radius})> get droplets => [
    for (final drop in _drops)
      (
        originX: drop.originX,
        dx: drop.vx * drop.age,
        y: -.43 + drop.vy * drop.age + .5 * _gravity * drop.age * drop.age,
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
class InkLanding {
  const InkLanding({
    required this.xShare,
    required this.radiusShare,
    required this.alreadyAgedMs,
  });
  final double xShare;
  final double radiusShare;
  final double alreadyAgedMs;
}

class _Droplet {
  _Droplet({
    required this.id,
    required this.originX,
    required this.vx,
    required this.vy,
    required this.radius,
  }) : landingTime =
           (-vy + math.sqrt(vy * vy + 2 * ArenaInkGravity._gravity * .43)) /
           ArenaInkGravity._gravity;
  final int id;
  final double originX;
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
