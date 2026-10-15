import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';

import '../rules/fighter_state.dart';
import '../rules/match_controller.dart';
import '../rules/match_rules.dart';

/// Grounding and contact paint, owned by ArenaAtmosphere. It only observes
/// states/events and the arena's cinematic gate; no controller or clock writes.
/// Every mark fits a .15h radius and renders BEFORE sprites, never over them.
class ArenaPhysicalPaint {
  static const double ringLifeMs = 150;
  static const int _maxRings = 8;
  static const ui.Color _ink = ui.Color(0xFF101010);
  static const ui.Color _grey = ui.Color(0xFF737373);
  final List<_ContactRing> _rings = <_ContactRing>[];
  final Map<FighterId, _KoFloor> _falls = <FighterId, _KoFloor>{};
  bool _slowMo = false;
  double _fallProgress = 0;
  double _slowMoProgress = 0;
  ui.Size _viewport = ui.Size.zero;
  double _floorY = 0;
  double _height = 0;

  /// Real time for contact rings, including hit-stop.
  /// The arena separately supplies its existing slow-mo gate for KO streaks.
  void update(double dt) {
    final ms = math.max(0.0, dt * 1000);
    for (final ring in _rings) {
      ring.ageMs += ms;
    }
    _rings.removeWhere((ring) => ring.ageMs >= ringLifeMs);
  }

  void onHit(HitEvent event, double arenaWidth) {
    if (event.kind == HitKind.whiff) return;
    if (_rings.length == _maxRings) _rings.removeAt(0);
    _rings.add(
      _ContactRing(
        xShare: (event.x / arenaWidth).clamp(0.0, 1.0),
        radius: event.kind == HitKind.blocked ? 12 : (event.heavy ? 40 : 20),
        blocked: event.kind == HitKind.blocked,
      ),
    );
    if (event.kind == HitKind.hit && event.ko) {
      // Double KO may have two losers. Each gets one floor event, not one
      // per render; the true defender x is sampled at the next world sync.
      _falls.putIfAbsent(event.defender, () => _KoFloor(arenaWidth));
    }
  }

  void syncWorld({
    required FighterState player,
    required FighterState rival,
    required bool koSlowMo,
    required double koFallProgress,
    required double koSlowMoProgress,
  }) {
    _slowMo = koSlowMo;
    _slowMoProgress = koSlowMoProgress.clamp(0.0, 1.0);
    _fallProgress = koFallProgress.clamp(0.0, 1.0);
    for (final state in <FighterState>[player, rival]) {
      final fall = _falls[state.id];
      if (fall != null && fall.xShare == null) {
        fall.xShare = (state.x / fall.arenaWidth).clamp(0.0, 1.0);
      }
    }
  }

  void layout(ui.Size viewport, double floorY, double fighterHeight) {
    _viewport = viewport;
    _floorY = floorY;
    _height = fighterHeight;
  }

  /// Ground lift comes from the rendered soles, so a paused apex holds the
  /// same shadow, landing restores it immediately, and squash cannot lift it.
  ({ui.Rect bounds, double opacity}) shadowFor(
    FighterId id,
    SpriteAnimationComponent sprite,
  ) {
    final h = sprite.size.y;
    final lift = h <= 0
        ? 0.0
        : ((_floorY - (sprite.position.y - h * .121)) / (h * .16)).clamp(
            0.0,
            1.0,
          );
    final fade = _falls.containsKey(id) ? 1 - _fallProgress : 1.0;
    return (
      bounds: ui.Rect.fromCenter(
        center: ui.Offset(sprite.position.x, _floorY),
        width: h * .28 * (1 - .45 * lift),
        height: h * .042 * (1 - .3 * lift),
      ),
      opacity: .20 * (1 - .7 * lift) * fade,
    );
  }

  void _renderShadow(
    ui.Canvas canvas,
    FighterId id,
    SpriteAnimationComponent? sprite,
  ) {
    if (sprite == null || sprite.size.y <= 0) return;
    final shadow = shadowFor(id, sprite);
    if (shadow.opacity <= 0) return;
    // Scaling a bounded radial gradient produces a soft ellipse without a
    // blur's unbounded bleed, keeping the entire shadow inside the budget.
    canvas.save();
    canvas.translate(shadow.bounds.center.dx, shadow.bounds.center.dy);
    canvas.scale(shadow.bounds.width / 2, shadow.bounds.height / 2);
    canvas.drawCircle(
      ui.Offset.zero,
      1,
      ui.Paint()
        ..shader = ui.Gradient.radial(
          ui.Offset.zero,
          1,
          <ui.Color>[
            _ink.withValues(alpha: shadow.opacity),
            _ink.withValues(alpha: 0),
          ],
          <double>[.15, 1],
        ),
    );
    canvas.restore();
  }

  /// Called by the atmosphere immediately before its existing sprite render.
  void renderBehindFighters(
    ui.Canvas canvas,
    SpriteAnimationComponent? player,
    SpriteAnimationComponent? rival,
  ) {
    if (_viewport.isEmpty || _height <= 0) return;
    canvas.save();
    canvas.clipRect(ui.Offset.zero & _viewport);
    _renderShadow(canvas, FighterId.player, player);
    _renderShadow(canvas, FighterId.rival, rival);
    _renderRings(canvas);
    _renderKoFloor(canvas);
    canvas.restore();
  }

  void _renderRings(ui.Canvas canvas) {
    for (final ring in _rings) {
      final t = (ring.ageMs / ringLifeMs).clamp(0.0, 1.0);
      final stroke = math.min(1.25, _height * .006);
      // 40/80 px diameters at normal landscape size; shrink on small screens.
      // The stroke and antialias fringe also fit inside the .15h envelope.
      final maxRadius = math.min(ring.radius, _height * .14);
      canvas.drawCircle(
        ui.Offset(ring.xShare * _viewport.width, _floorY - _height * .43),
        maxRadius * (.25 + .75 * t),
        ui.Paint()
          ..color = (ring.blocked ? _grey : _ink).withValues(
            alpha: (ring.blocked ? .24 : .46) * (1 - t),
          )
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
    }
  }

  void _renderKoFloor(ui.Canvas canvas) {
    if (!_slowMo) return;
    for (final fall in _falls.values) {
      final xShare = fall.xShare;
      if (xShare == null) continue;
      final centre = ui.Offset(xShare * _viewport.width, _floorY);
      final t = _slowMoProgress;
      final fade = 1 - t;
      if (fade > 0) {
        final radius = _height * (.025 + .105 * t);
        canvas.drawOval(
          ui.Rect.fromCenter(
            center: centre,
            width: radius * 2,
            height: radius * .55,
          ),
          ui.Paint()
            ..color = _ink.withValues(alpha: .30 * fade)
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = _height * .003,
        );
        // Five low flecks spread out and settle down, not an opaque dust cloud.
        for (var i = 0; i < 5; i++) {
          final dx = (i - 2) * _height * (.022 + .018 * t);
          final dy = -_height * .018 * (1 - t) + _height * .004 * i;
          canvas.drawOval(
            ui.Rect.fromCenter(
              center: centre + ui.Offset(dx, dy),
              width: _height * .012,
              height: _height * .006,
            ),
            ui.Paint()..color = _grey.withValues(alpha: .24 * fade),
          );
        }
      }
      // The game owns the slow-mo duration. These four short radial lines
      // disappear at that gate, never spill into the frozen beat/result card.
      final ink = ui.Paint()
        ..color = _ink.withValues(alpha: .32 * (1 - t))
        ..strokeWidth = _height * .003
        ..strokeCap = ui.StrokeCap.round;
      for (var i = 0; i < 4; i++) {
        final angle = math.pi * (.18 + i * .5);
        final direction = ui.Offset(math.cos(angle), math.sin(angle) * .35);
        canvas.drawLine(
          centre + direction * (_height * .065),
          centre + direction * (_height * .135),
          ink,
        );
      }
    }
  }

  void reset() {
    _rings.clear();
    _falls.clear();
    _slowMo = false;
    _fallProgress = 0;
    _slowMoProgress = 0;
  }

  @visibleForTesting
  int get ringCount => _rings.length;

  @visibleForTesting
  int get koCount => _falls.length;
}

class _ContactRing {
  _ContactRing({
    required this.xShare,
    required this.radius,
    required this.blocked,
  });
  final double xShare;
  final double radius;
  final bool blocked;
  double ageMs = 0;
}

class _KoFloor {
  _KoFloor(this.arenaWidth);
  final double arenaWidth;
  double? xShare;
}
