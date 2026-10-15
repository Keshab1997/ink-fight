import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/rendering.dart';

import '../rules/fighter_state.dart';
import '../rules/match_controller.dart';
import '../rules/match_rules.dart';

/// Observes delivered walk frames rather than owning a second stride clock.
/// Marks are returned to ArenaAtmosphere's shared fade/render/reset machinery.
class ArenaFootwork {
  final Map<FighterId, ({FighterAction action, double x, int half})> _previous =
      {};
  final Set<FighterId> _pendingScar = {};
  int _scarCount = 0;

  void onHit(HitEvent event) {
    if (event.kind == HitKind.hit && event.knockdown && _scarCount < 2) {
      _pendingScar.add(event.defender);
    }
  }

  void observe(
    FighterState state,
    SpriteAnimationComponent? sprite,
    double viewportWidth,
    double simDt,
    void Function(FootPlant) plant,
  ) {
    if (sprite == null || viewportWidth <= 0 || simDt <= 0) return;
    final frame = sprite.animationTicker?.currentIndex ?? 0;
    final frames = sprite.animation?.frames.length ?? 1;
    final half = frame < math.max(1, frames ~/ 2) ? 0 : 1;
    final previous = _previous[state.id];
    final grounded =
        state.action == FighterAction.idle ||
        state.action == FighterAction.walk;
    final landed =
        previous != null &&
        grounded &&
        (previous.action == FighterAction.jump ||
            previous.action == FighterAction.knockdown);
    final stepped =
        previous != null &&
        state.action == FighterAction.walk &&
        (state.x - previous.x).abs() > .000001 &&
        (previous.action != FighterAction.walk || previous.half != half);
    final xShare = (sprite.position.x / viewportWidth).clamp(0.0, 1.0);
    if (landed || stepped) {
      // Alternate the soles at the delivered cycle's planted-foot phases.
      final footOffset = landed ? 0.0 : (half == 0 ? -.18 : .18) * state.facing;
      plant(FootPlant(xShare: xShare, offsetShare: footOffset, hard: landed));
    }
    if (_pendingScar.contains(state.id) &&
        _scarCount < 2 &&
        ((state.isKnockedDown && (sprite.animationTicker?.done() ?? false)) ||
            (landed && previous.action == FighterAction.knockdown))) {
      // The confirmed knockdown's FALL has finished, not just its hit-stop.
      // Sampling the rendered x here puts the scar where the body came down.
      plant(FootPlant(xShare: xShare, scar: true, facing: state.facing));
      _pendingScar.remove(state.id);
      _scarCount++;
    }
    _previous[state.id] = (action: state.action, x: state.x, half: half);
  }

  void reset() {
    _previous.clear();
    _pendingScar.clear();
    _scarCount = 0;
  }
}

class FootPlant {
  const FootPlant({
    required this.xShare,
    this.offsetShare = 0,
    this.hard = false,
    this.scar = false,
    this.facing = 1,
  });
  final double xShare;
  final double offsetShare;
  final bool hard;
  final bool scar;
  final double facing;
}

/// The game already draws rival first, player second. Keep that order: shade
/// only the rear sprite's EXISTING alpha, then let the front cover it normally.
/// No opaque overlay, no change to alpha/pose/facing/priority or collision.
Decorator? overlapDepth(
  SpriteAnimationComponent rear,
  SpriteAnimationComponent front,
) {
  final h = math.min(rear.size.y, front.size.y);
  if (h <= 0) return null;
  final dx = front.position.x - rear.position.x;
  final overlap = (1 - dx.abs() / (h * .55)).clamp(0.0, 1.0);
  if (overlap == 0 || (front.position.y - rear.position.y).abs() > h * .15) {
    return null;
  }
  final centre = ui.Offset(
    front.position.x - dx.sign * h * .27,
    rear.position.y - rear.size.y * (.121 + .43),
  );
  return _ContactDepth(
    rear.decorator,
    rear.toRect(),
    centre,
    h * .13,
    overlap * .16,
  );
}

class _ContactDepth extends Decorator {
  _ContactDepth(
    this.original,
    this.bounds,
    this.centre,
    this.radius,
    this.opacity,
  );
  final Decorator original;
  final ui.Rect bounds;
  final ui.Offset centre;
  final double radius;
  final double opacity;

  @override
  void apply(void Function(ui.Canvas) draw, ui.Canvas canvas) {
    final saveCount = canvas.getSaveCount();
    canvas.saveLayer(bounds, ui.Paint());
    try {
      original.applyChain(draw, canvas);
      canvas.translate(centre.dx, centre.dy);
      canvas.scale(.65, 1);
      canvas.drawCircle(
        ui.Offset.zero,
        radius,
        ui.Paint()
          ..blendMode = ui.BlendMode.srcATop
          ..shader = ui.Gradient.radial(ui.Offset.zero, radius, [
            ui.Color.fromRGBO(16, 16, 16, opacity),
            const ui.Color(0x00101010),
          ]),
      );
    } finally {
      canvas.restoreToCount(saveCount);
    }
  }
}
