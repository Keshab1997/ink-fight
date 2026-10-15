import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';

import '../rules/fighter_state.dart';
import '../rules/match_controller.dart';
import '../rules/match_rules.dart';
import 'arena_physical_paint.dart';
import 'arena_footwork.dart';
import 'arena_room.dart';

/// Paint only: the paper remembers connects, never guesses them from a pose.
/// All geometry is relative to the sprite height. Stains sit behind fighters,
/// streaks stay inside a .15-height radius, and the HUD is never painted over.
class ArenaAtmosphere {
  ArenaAtmosphere() : _grain = _recordGrain();

  static const int maxMarks = 24;
  static const double flashMs = 60;
  static const double _retireMs = 400;
  static const ui.Color _ink = ui.Color(0xFF101010);
  static const ui.Color _grey = ui.Color(0xFF737373);
  static const ui.Color _paperWhite = ui.Color(0xFFFFFFFF);
  static const ui.Color _crimson = ui.Color(0xFFC51F3A);
  static const ui.ColorFilter _whiteSilhouette = ui.ColorFilter.mode(
    _paperWhite,
    ui.BlendMode.srcIn,
  );

  // Recorded once, not randomised in render or update. Unit coordinates keep
  // the same fibres pinned to the page even when the viewport is resized.
  ui.Picture? _grain;
  final ArenaFootwork _footwork = ArenaFootwork();
  final List<_FloorDot> _footDots = [];
  final List<_FloorDot> _scars = [];
  final ArenaRoom _room = ArenaRoom();
  final ArenaPhysicalPaint _physical = ArenaPhysicalPaint();
  final math.Random _random = math.Random(71);
  final List<_FloorDot> _dots = <_FloorDot>[];
  final Map<FighterId, double> _flash = <FighterId, double>{};

  static ui.Picture _recordGrain() {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final random = math.Random(319);
    final paint = ui.Paint()
      ..color = _ink.withValues(alpha: .045)
      ..strokeWidth = .0005
      ..strokeCap = ui.StrokeCap.round;
    for (var i = 0; i < 2200; i++) {
      final x = random.nextDouble();
      final y = random.nextDouble();
      canvas.drawLine(
        ui.Offset(x, y),
        ui.Offset(x + .0004 + random.nextDouble() * .001, y + .0005),
        paint,
      );
    }
    return recorder.endRecording();
  }

  /// Behind the arena and sprites, so even the vignette cannot obscure them.
  void renderPaper(ui.Canvas canvas, ui.Size viewport) {
    if (viewport.isEmpty) {
      return;
    }
    canvas.save();
    canvas.clipRect(ui.Offset.zero & viewport);
    canvas.scale(viewport.width, viewport.height);
    canvas.drawPicture(_grain ??= _recordGrain());
    // Elliptical falloff: quiet centre, softly shaded edges, no coloured tint.
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 1, 1),
      ui.Paint()
        ..shader = ui.Gradient.radial(
          const ui.Offset(.5, .52),
          .68,
          <ui.Color>[_ink.withValues(alpha: 0), _ink.withValues(alpha: .07)],
          <double>[.38, 1],
        ),
    );
    canvas.restore();
  }

  /// Event x remains in arena coordinates; resize maps existing stains onto
  /// the same place on the paper. Only confirmed hits flash the defender.
  void onHit(HitEvent event, double arenaWidth) {
    _physical.onHit(event, arenaWidth);
    _room.onHit(event, arenaWidth: arenaWidth);
    _footwork.onHit(event);
    if (event.kind == HitKind.whiff) {
      return;
    }
    final blocked = event.kind == HitKind.blocked;
    final count = blocked ? 1 : 2 + _random.nextInt(3);
    if (!blocked) {
      _flash[event.defender] = flashMs;
    }
    for (var i = 0; i < count; i++) {
      // Under an extreme event flood the already-fading oldest dot is evicted;
      // the normal round retires it over 400 ms before another connect arrives.
      if (_dots.length == maxMarks) {
        _dots.removeAt(0);
      }
      _dots.add(
        _FloorDot(
          xShare: (event.x / arenaWidth).clamp(0.0, 1.0),
          dxShare: (_random.nextDouble() - .5) * .18,
          dyShare: (_random.nextDouble() - .5) * .035,
          radiusShare: blocked ? .004 : .004 + _random.nextDouble() * .006,
          colour: blocked
              ? _grey
              : (event.heavy && i == count - 1 ? _crimson : _ink),
          opacity: blocked ? .28 : .48,
        ),
      );
    }
    // Reserve four places for the next hit; only pressure at the cap retires
    // ink. Below it, dots live for the entire round regardless of age.
    final retireCount = math.max(0, _dots.length - (maxMarks - 4));
    for (var i = 0; i < retireCount; i++) {
      _dots[i].retiring = true;
    }
  }

  /// Real time, independent of hit-stop/KO clocks: the 60 ms flash snaps back
  /// even while the hurt pose is held. Call before consuming this frame's hits.
  void update(double dt) {
    _physical.update(dt);
    _room.updateClocks(dt);
    final ms = math.max(0.0, dt * 1000);
    for (final id in FighterId.values) {
      _flash[id] = math.max(0.0, (_flash[id] ?? 0) - ms);
    }
    for (final dot in _dots.followedBy(_footDots)) {
      if (dot.retiring) {
        dot.fadeMs += ms;
      }
    }
    _dots.removeWhere((dot) => dot.fadeMs >= dot.fadeLifeMs);
    _footDots.removeWhere((dot) => dot.fadeMs >= dot.fadeLifeMs);
  }

  /// Air follows the view clock; a boundary response is only presentation.
  void advanceRoom({
    required double realDt,
    required double effectDt,
    required bool roundEnd,
    required FighterState player,
    required FighterState rival,
    required MatchRules rules,
    SpriteAnimationComponent? playerSprite,
    SpriteAnimationComponent? rivalSprite,
    double viewportWidth = 0,
    double movementDt = 0,
  }) {
    _room.advanceAir(realDt: realDt, effectDt: effectDt, roundEnd: roundEnd);
    void plant(FootPlant plant) {
      if (plant.scar) {
        if (_scars.length < 2) {
          _scars.add(
            _FloorDot(
              xShare: plant.xShare,
              dxShare: 0,
              dyShare: 0,
              radiusShare: 0,
              colour: _grey,
              opacity: .12,
              scarFacing: plant.facing,
            ),
          );
        }
      } else {
        if (_footDots.length == 16) _footDots.removeAt(0);
        _footDots.add(
          _FloorDot(
            xShare: plant.xShare,
            dxShare: plant.offsetShare,
            dyShare: 0,
            radiusShare: plant.hard ? .013 : .007,
            colour: _grey,
            opacity: plant.hard ? .30 : .20,
            widthShare: plant.hard ? .10 : .055,
            fadeLifeMs: 1000,
          )..retiring = true,
        );
      }
    }

    _footwork.observe(player, playerSprite, viewportWidth, movementDt, plant);
    _footwork.observe(rival, rivalSprite, viewportWidth, movementDt, plant);
    _room.observeWalls(player, rival, rules, (fighter) {
      if (_dots.length == maxMarks) _dots.removeAt(0);
      _dots.add(
        _FloorDot(
          xShare: fighter.x / rules.arenaWidth,
          dxShare: 0,
          dyShare: 0,
          radiusShare: .008,
          colour: _grey,
          opacity: .30,
          smear: true,
          fadeLifeMs: 450,
        )..retiring = true,
      );
    });
  }

  void applyRoomResponse(ui.Canvas canvas, double fighterHeight) =>
      canvas.translate(_room.shakeOffset(fighterHeight), 0);

  void renderRoom(ui.Canvas canvas, ui.Size viewport, double floorY, double h) {
    _room.renderDepth(canvas, viewport, floorY, h);
    _room.renderDust(canvas, viewport, floorY, h);
  }

  /// Only observes the arena's existing KO gates, never starts a cinematic.
  void syncPhysicalWorld({
    required FighterState player,
    required FighterState rival,
    required bool koSlowMo,
    required double koFallProgress,
    required double koSlowMoProgress,
  }) => _physical.syncWorld(
    player: player,
    rival: rival,
    koSlowMo: koSlowMo,
    koFallProgress: koFallProgress,
    koSlowMoProgress: koSlowMoProgress,
  );

  void renderFloor(
    ui.Canvas canvas,
    ui.Size viewport,
    double floorY,
    double fighterHeight,
  ) {
    _physical.layout(viewport, floorY, fighterHeight);
    if (fighterHeight <= 0 || viewport.isEmpty) {
      return;
    }
    canvas.save();
    canvas.clipRect(ui.Offset.zero & viewport);
    for (final dot in _dots.followedBy(_footDots).followedBy(_scars)) {
      if (dot.scarFacing != null) {
        _renderScar(canvas, dot, viewport.width, floorY, fighterHeight);
        continue;
      }
      canvas.drawOval(
        ui.Rect.fromCenter(
          center: ui.Offset(
            dot.xShare * viewport.width + dot.dxShare * fighterHeight,
            floorY + dot.dyShare * fighterHeight,
          ),
          width:
              fighterHeight *
              (dot.widthShare ?? (dot.smear ? .12 : dot.radiusShare * 2)),
          height: dot.radiusShare * fighterHeight * 1.1,
        ),
        ui.Paint()
          ..color = dot.colour.withValues(
            alpha:
                dot.opacity * (1 - dot.fadeMs / dot.fadeLifeMs).clamp(0.0, 1.0),
          ),
      );
    }
    canvas.restore();
  }

  void _renderScar(
    ui.Canvas canvas,
    _FloorDot dot,
    double width,
    double floor,
    double h,
  ) {
    canvas.save();
    canvas.translate(dot.xShare * width, floor);
    canvas.scale(dot.scarFacing!, 1);
    final ink = ui.Paint()..color = dot.colour.withValues(alpha: dot.opacity);
    canvas.drawOval(
      ui.Rect.fromCenter(
        center: ui.Offset.zero,
        width: h * .14,
        height: h * .027,
      ),
      ink,
    );
    canvas.drawCircle(ui.Offset(-h * .095, -h * .005), h * .014, ink);
    ink
      ..strokeWidth = h * .003
      ..strokeCap = ui.StrokeCap.round;
    for (final side in [-1.0, 1.0]) {
      canvas.drawLine(
        ui.Offset(-h * .03, 0),
        ui.Offset(-h * .065, side * h * .023),
        ink,
      );
      canvas.drawLine(
        ui.Offset(h * .045, 0),
        ui.Offset(h * .12, side * h * .025),
        ink,
      );
    }
    canvas.restore();
  }

  /// Uses the rules' window, never duplicates their timings. A held active
  /// frame during hit-stop holds its streak too; recovery and startup get none.
  bool hasHeavyStreaks(FighterState state, MatchRules rules) =>
      state.action == FighterAction.heavyKick &&
      rules.heavyAttack.isActiveAt(state.actionElapsedMs);

  void renderHeavyStreaks(
    ui.Canvas canvas,
    FighterState state,
    MatchRules rules,
    SpriteAnimationComponent? sprite,
  ) {
    if (sprite == null || !hasHeavyStreaks(state, rules)) {
      return;
    }
    final height = sprite.size.y;
    final contact = ui.Offset(
      sprite.position.x + state.facing * height * .39,
      sprite.position.y - height * (.121 + .50),
    );
    canvas.save();
    canvas.translate(contact.dx, contact.dy);
    canvas.scale(state.facing, 1);
    final paint = ui.Paint()..color = _ink.withValues(alpha: .42);
    // Filled tapered ribbons, not broad strokes: all control points fit
    // within .13h of contact (including line thickness), under the .15h cap.
    for (var i = 0; i < 3; i++) {
      final y = (i - 1) * height * .037;
      final path = ui.Path()
        ..moveTo(-height * .12, y + height * .035)
        ..quadraticBezierTo(-height * .03, y - height * .035, height * .09, y)
        ..quadraticBezierTo(
          -height * .03,
          y - height * .024,
          -height * .12,
          y + height * .035,
        )
        ..close();
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  /// Filter only the sprite paint, preserving transparent pixels and every
  /// component's existing filter. No extra silhouette overlay or pose change.
  void renderFighters(
    ui.Canvas canvas,
    void Function(ui.Canvas) render,
    SpriteAnimationComponent? player,
    SpriteAnimationComponent? rival,
  ) {
    _physical.renderBehindFighters(canvas, player, rival);
    final playerFilter = player?.paint.colorFilter;
    final rivalFilter = rival?.paint.colorFilter;
    final rearDecorator = rival?.decorator;
    if (rival != null && player != null && !_isFlashing(FighterId.rival)) {
      final depth = overlapDepth(rival, player);
      if (depth != null) rival.decorator = depth;
    }
    if (player != null && _isFlashing(FighterId.player)) {
      player.paint.colorFilter = _whiteSilhouette;
    }
    if (rival != null && _isFlashing(FighterId.rival)) {
      rival.paint.colorFilter = _whiteSilhouette;
    }
    try {
      render(canvas);
    } finally {
      player?.paint.colorFilter = playerFilter;
      rival?.paint.colorFilter = rivalFilter;
      if (rival != null && rearDecorator != null) {
        rival.decorator = rearDecorator;
      }
    }
  }

  // A GameWidget may detach and later remount the same game. Release the GPU
  // recording on detach; the fixed-seed page can be recreated identically.
  void dispose() {
    _grain?.dispose();
    _grain = null;
  }

  void reset() {
    _physical.reset();
    _room.reset();
    _footwork.reset();
    _footDots.clear();
    _scars.clear();
    _dots.clear();
    _flash.clear();
  }

  @visibleForTesting
  bool isFlashing(FighterId id) => _isFlashing(id);

  bool _isFlashing(FighterId id) => (_flash[id] ?? 0) > 0;

  @visibleForTesting
  int get footScuffCount => _footDots.length;

  @visibleForTesting
  int get scarCount => _scars.length;

  @visibleForTesting
  int get markCount => _dots.length;

  @visibleForTesting
  List<double> get markOpacities => <double>[
    for (final dot in _dots)
      dot.opacity * (1 - dot.fadeMs / dot.fadeLifeMs).clamp(0.0, 1.0),
  ];
}

class _FloorDot {
  _FloorDot({
    required this.xShare,
    required this.dxShare,
    required this.dyShare,
    required this.radiusShare,
    required this.colour,
    required this.opacity,
    this.smear = false,
    this.widthShare,
    this.scarFacing,
    this.fadeLifeMs = ArenaAtmosphere._retireMs,
  });

  final double xShare;
  final double dxShare;
  final double dyShare;
  final double radiusShare;
  final ui.Color colour;
  final double opacity;
  final bool smear;
  final double? widthShare;
  final double? scarFacing;
  final double fadeLifeMs;
  bool retiring = false;
  double fadeMs = 0;
}
