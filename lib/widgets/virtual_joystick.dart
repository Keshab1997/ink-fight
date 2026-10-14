import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A thumb-driven movement pad in the arena's ink style — the sibling of the
/// screen's `_ControlButton`: white paper under a thin line, an ink thumb.
///
/// The fight is a one-dimensional line, so only the horizontal share of the
/// drag reaches the arena: `onAxisChanged` reports -1 (back) … +1 (towards
/// the rival) with a dead zone around centre. The vertical share belongs to
/// the jump alone: pushing the thumb up past [jumpThresholdDy] fires
/// [onJump] once, edge-triggered — the thumb has to come back near centre
/// (or the gesture has to end) before it can fire again.
class VirtualJoystick extends StatefulWidget {
  const VirtualJoystick({
    super.key,
    required this.onAxisChanged,
    this.onJump,
    this.size = defaultSize,
  });

  /// Called while dragging whenever the axis moves by more than
  /// [axisEpsilon], with 0 inside the [deadZone], and unconditionally with 0
  /// on release or cancel.
  final ValueChanged<double> onAxisChanged;

  /// One jump per upward flick; see [jumpThresholdDy].
  final VoidCallback? onJump;

  /// Pad diameter in logical pixels. The battle row budgets at most 108 dp
  /// for the joystick so a 360 dp-wide window still fits its controls.
  final double size;

  static const double defaultSize = 104;

  /// Thumb diameter as a share of the pad: 44 dp on the 104 dp default.
  static const double thumbShare = 44 / 104;

  /// |axis| below this reports 0 — a resting thumb must not drift the
  /// fighter.
  static const double deadZone = .15;

  /// Smallest axis movement worth a callback.
  static const double axisEpsilon = .01;

  /// Normalised vertical drag (dy / travel radius, y grows downwards) that
  /// fires the jump.
  static const double jumpThresholdDy = -.55;

  /// The thumb must rise back above this before the next jump may fire.
  static const double jumpRearmDy = -.3;

  /// How long the thumb takes to spring home after a release.
  static const Duration springHome = Duration(milliseconds: 120);

  @override
  State<VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<VirtualJoystick>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spring = AnimationController(
    vsync: this,
    duration: VirtualJoystick.springHome,
  );

  /// Thumb offset from the pad centre, in logical pixels.
  Offset _thumb = Offset.zero;
  Offset _springFrom = Offset.zero;
  double _lastAxis = 0;
  bool _jumpArmed = true;

  /// How far the thumb centre may travel: pad radius minus thumb radius, so
  /// the thumb kisses the pad edge at a full axis.
  double get _travel => widget.size / 2 * (1 - VirtualJoystick.thumbShare);

  @override
  void initState() {
    super.initState();
    _spring.addListener(_onSpringTick);
  }

  @override
  void dispose() {
    _spring.removeListener(_onSpringTick);
    _spring.dispose();
    super.dispose();
  }

  void _onSpringTick() {
    setState(() {
      _thumb = Offset.lerp(
        _springFrom,
        Offset.zero,
        Curves.easeOut.transform(_spring.value),
      )!;
    });
  }

  void _onPanStart(DragStartDetails details) {
    _spring.stop();
    _jumpArmed = true;
    _follow(details.localPosition);
  }

  void _onPanUpdate(DragUpdateDetails details) =>
      _follow(details.localPosition);

  /// Maps the finger onto the thumb, the axis and the jump edge.
  void _follow(Offset local) {
    final delta = local - Offset(widget.size / 2, widget.size / 2);
    final travel = _travel;
    final distance = delta.distance;
    final clamped = distance > travel ? delta * (travel / distance) : delta;

    final rawAxis = (delta.dx / travel).clamp(-1.0, 1.0);
    final axis = rawAxis.abs() < VirtualJoystick.deadZone ? 0.0 : rawAxis;

    setState(() => _thumb = clamped);
    _reportAxis(axis);

    final normalizedDy = delta.dy / travel;
    if (_jumpArmed && normalizedDy < VirtualJoystick.jumpThresholdDy) {
      _jumpArmed = false;
      widget.onJump?.call();
    } else if (!_jumpArmed && normalizedDy > VirtualJoystick.jumpRearmDy) {
      _jumpArmed = true;
    }
  }

  void _reportAxis(double axis) {
    if ((axis - _lastAxis).abs() <= VirtualJoystick.axisEpsilon) {
      return;
    }
    _lastAxis = axis;
    widget.onAxisChanged(axis);
  }

  void _release() {
    _springFrom = _thumb;
    _spring.forward(from: 0);
    _jumpArmed = true;
    _lastAxis = 0;
    widget.onAxisChanged(0);
  }

  @override
  Widget build(BuildContext context) {
    final thumbSize = widget.size * VirtualJoystick.thumbShare;
    return Semantics(
      label: 'Movement joystick',
      value: _lastAxis.toStringAsFixed(2),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: (_) => _release(),
        onPanCancel: _release,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // The pad fills the box; the thumb rides inside it.
              Container(
                decoration: BoxDecoration(
                  color: InkColors.white.withValues(alpha: .78),
                  shape: BoxShape.circle,
                  border: Border.all(color: InkColors.line),
                ),
              ),
              Transform.translate(
                offset: _thumb,
                child: Container(
                  width: thumbSize,
                  height: thumbSize,
                  decoration: const BoxDecoration(
                    color: InkColors.ink,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
