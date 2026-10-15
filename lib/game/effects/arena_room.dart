import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../rules/fighter_state.dart';
import '../rules/match_controller.dart';
import '../rules/match_rules.dart';

/// Air and room depth behind the fighters. Local specks, scuffs and response
/// are bounded by sprite height; background shading is intentionally broad.
/// Observes states only: a wall reaction can never change a rules position.
class ArenaRoom {
  ArenaRoom() {
    reset();
  }

  static const int dustCount = 8;
  static const double _gustMs = 200;
  static const double _shakeMs = 120;
  static const ui.Color _ink = ui.Color(0xFF101010);
  final List<ui.Offset> _dust = <ui.Offset>[];
  final Map<FighterId, ({double x, bool pushingWall})> _previous = {};
  double _gustRemainingMs = 0;
  double _shakeAgeMs = _shakeMs;
  double _shakeDirection = 1;
  double _settleSeconds = 0;

  void onHit(HitEvent event) {
    if (event.kind == HitKind.hit && event.heavy) {
      _gustRemainingMs = _gustMs;
    }
  }

  void updateClocks(double dt) {
    _shakeAgeMs = math.min(_shakeMs, _shakeAgeMs + math.max(0.0, dt) * 1000);
  }

  /// effectDt is the arena's existing time-scaled clock: slow in the KO,
  /// frozen in the KO hold. Card settling uses real time, without a sim write.
  void advanceAir({
    required double realDt,
    required double effectDt,
    required bool roundEnd,
  }) {
    final real = math.max(0.0, realDt);
    final effect = math.max(0.0, effectDt);
    final boostedTime = real > 0
        ? effect * math.min(real * 1000, _gustRemainingMs) / (real * 1000)
        : 0.0;
    final driftTime = effect + boostedTime * 1.8;
    final settleDrift =
        .35 * math.exp(-_settleSeconds / .35) * (1 - math.exp(-real / .35));
    for (var i = 0; i < _dust.length; i++) {
      final p = _dust[i];
      final vx = (i.isEven ? 1 : -1) * (.003 + i * .0003);
      if (roundEnd) {
        _dust[i] = ui.Offset(
          (p.dx + vx * settleDrift).clamp(0.0, 1.0),
          math.min(1.0, p.dy + real * .35),
        );
      } else {
        // Wrap rather than respawn/re-randomise: the same eight motes persist.
        _dust[i] = ui.Offset(
          (p.dx + vx * driftTime) % 1,
          (p.dy + .0015 * driftTime) % 1,
        );
      }
    }
    _settleSeconds = roundEnd ? _settleSeconds + real : 0;
    _gustRemainingMs = math.max(0.0, _gustRemainingMs - real * 1000);
  }

  void observeWalls(
    FighterState player,
    FighterState rival,
    MatchRules rules,
    void Function(FighterState) scuff,
  ) {
    for (final fighter in [player, rival]) {
      final left = fighter.x <= rules.minX + .000001;
      final right = fighter.x >= rules.maxX - .000001;
      final outward =
          (left && fighter.pushVelocity < 0) ||
          (right && fighter.pushVelocity > 0);
      final previous = _previous[fighter.id];
      // A held shove against the wall fires once. Walking/jumping to a wall
      // does not fire, nor does the first snapshot after reset/load.
      if (previous != null &&
          outward &&
          (!previous.pushingWall || (previous.x - fighter.x).abs() > .000001)) {
        scuff(fighter);
        _shakeAgeMs = 0;
        _shakeDirection = left ? 1 : -1;
      }
      _previous[fighter.id] = (x: fighter.x, pushingWall: outward);
    }
  }

  double shakeOffset(double fighterHeight) {
    if (_shakeAgeMs >= _shakeMs || fighterHeight <= 0) return 0;
    return _shakeDirection *
        math.min(.7, fighterHeight * .002) *
        math.sin(_shakeAgeMs / 40 * math.pi * 2) *
        (1 - _shakeAgeMs / _shakeMs);
  }

  void renderDepth(
    ui.Canvas canvas,
    ui.Size viewport,
    double floorY,
    double h,
  ) {
    if (viewport.isEmpty || h <= 0) return;
    final top = math.min(floorY, viewport.height * .28);
    // Ink-only wash fades in toward the horizon; no solid panel or hard edge.
    canvas.drawRect(
      ui.Rect.fromLTRB(0, top, viewport.width, floorY),
      ui.Paint()
        ..shader = ui.Gradient.linear(ui.Offset(0, top), ui.Offset(0, floorY), [
          _ink.withValues(alpha: 0),
          _ink.withValues(alpha: .025),
        ]),
    );
    final band = h * .14;
    canvas.drawRect(
      ui.Rect.fromLTRB(0, floorY, viewport.width, floorY + band),
      ui.Paint()
        ..shader = ui.Gradient.linear(
          ui.Offset(0, floorY),
          ui.Offset(0, floorY + band),
          [
            _ink.withValues(alpha: .025),
            _ink.withValues(alpha: .045),
            _ink.withValues(alpha: 0),
          ],
          [0, .25, 1],
        ),
    );
    // A feathered horizon centred on exactly the floor used by the shadows.
    final feather = h * .006;
    canvas.drawRect(
      ui.Rect.fromLTRB(0, floorY - feather, viewport.width, floorY + feather),
      ui.Paint()
        ..shader = ui.Gradient.linear(
          ui.Offset(0, floorY - feather),
          ui.Offset(0, floorY + feather),
          [
            _ink.withValues(alpha: 0),
            _ink.withValues(alpha: .05),
            _ink.withValues(alpha: 0),
          ],
          [0, .5, 1],
        ),
    );
  }

  void renderDust(ui.Canvas canvas, ui.Size viewport, double floorY, double h) {
    if (viewport.isEmpty || h <= 0) return;
    final top = math.max(viewport.height * .30, floorY - h * .75);
    if (top >= floorY) return;
    canvas.save();
    canvas.clipRect(ui.Rect.fromLTRB(0, top, viewport.width, floorY + h * .01));
    for (var i = 0; i < _dust.length; i++) {
      final p = _dust[i];
      canvas.drawOval(
        ui.Rect.fromCenter(
          center: ui.Offset(p.dx * viewport.width, top + p.dy * (floorY - top)),
          width: h * (.004 + (i % 3) * .001),
          height: h * .003,
        ),
        ui.Paint()
          ..color = _ink.withValues(alpha: _settleSeconds > 0 ? .09 : .20),
      );
    }
    canvas.restore();
  }

  void reset() {
    final random = math.Random(907);
    _dust.clear();
    for (var i = 0; i < dustCount; i++) {
      _dust.add(
        ui.Offset(
          .04 + random.nextDouble() * .92,
          .08 + random.nextDouble() * .84,
        ),
      );
    }
    _previous.clear();
    _gustRemainingMs = 0;
    _shakeAgeMs = _shakeMs;
    _settleSeconds = 0;
  }

  @visibleForTesting
  List<ui.Offset> get dustPositions => List.unmodifiable(_dust);
}
