import 'package:flutter/material.dart';

/// The wipe an incoming page makes across the sketchbook: it slides in from
/// the right over about [wipePortion] of the route's transition — roughly
/// 240 ms of the 300 ms a [MaterialPageRoute] takes — while the page it
/// covers nudges left and dims, as if the new leaf pressed the old one down.
///
/// Both halves live in this one widget because the framework hands each route
/// its own half of the story: [progress] is the route's own animation (0 → 1
/// as this page arrives), [coveredProgress] is its secondary animation (0 → 1
/// as another page is pushed over it). When this route is popped the two run
/// backwards, so the exit is the entry in reverse for free.
class InkWipeTransition extends StatelessWidget {
  const InkWipeTransition({
    super.key,
    required this.progress,
    required this.coveredProgress,
    required this.child,
  });

  /// The route's own animation: 0 while off-screen right, 1 once landed.
  final Animation<double> progress;

  /// The route's secondary animation: 0 while on top, 1 while fully covered.
  final Animation<double> coveredProgress;

  /// The arriving (or covered) page.
  final Widget child;

  /// Share of the route transition the wipe travels over. The last fifth
  /// holds still, so the page lands instead of sliding past its stop.
  static const double wipePortion = 0.8;

  /// How the wipe moves: out fast, then settling onto the page.
  static final Curve wipeCurve = Interval(
    0,
    wipePortion,
    curve: Curves.easeOutCubic,
  );

  /// The brush edge riding the wipe's leading side, in logical pixels at the
  /// wipe's start. It shrinks to nothing as the page lands, so a settled
  /// page keeps its full width — the strip is never part of the layout.
  static const double edgeWidth = 28;

  /// How far the covered page sidles left, as a share of the screen width —
  /// about one brush edge on a phone, so the two pages never fully overlap.
  static const double nudgeFraction = 0.07;

  /// The dim the covered page sinks to: readable beneath, but clearly below.
  static const double dimOpacity = 0.35;

  @override
  Widget build(BuildContext context) {
    final wipe = progress.drive(
      Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).chain(CurveTween(curve: wipeCurve)),
    );
    final settled = progress.drive(CurveTween(curve: wipeCurve));
    final nudge = coveredProgress.drive(
      Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(-nudgeFraction, 0),
      ).chain(CurveTween(curve: wipeCurve)),
    );
    final dim = coveredProgress.drive(
      Tween<double>(
        begin: 0,
        end: dimOpacity,
      ).chain(CurveTween(curve: wipeCurve)),
    );
    return SlideTransition(
      position: nudge,
      child: Stack(
        children: [
          SlideTransition(
            position: wipe,
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: settled,
                  builder: (context, edge) => SizedBox(
                    width: edgeWidth * (1 - settled.value),
                    child: edge,
                  ),
                  child: const _BrushEdge(),
                ),
                Expanded(child: child),
              ],
            ),
          ),
          FadeTransition(
            opacity: dim,
            child: const ColoredBox(color: Colors.black),
          ),
        ],
      ),
    );
  }
}

/// The soft paper edge at the wipe's leading side: transparent where it meets
/// the arriving page, warming to the sketchbook paper, then a hairline of ink
/// where it lifts off the page below.
class _BrushEdge extends StatelessWidget {
  const _BrushEdge();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.surface.withValues(alpha: 0),
            Theme.of(context).colorScheme.surface,
            Theme.of(context).colorScheme.surface,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
        border: Border(
          right: BorderSide(
            color: Theme.of(context).colorScheme.onSurface
                .withValues(alpha: 0.25),
          ),
        ),
      ),
    );
  }
}

/// Builds the sketchbook transition for every route: the ink wipe above, or a
/// plain short fade when the user asked for reduced motion
/// ([MediaQuery.disableAnimations]).
class InkPageTransitionsBuilder extends PageTransitionsBuilder {
  const InkPageTransitionsBuilder();

  /// Share of the route transition the reduced-motion fade takes: half, so
  /// the page is simply there instead of travelling.
  static const double fadePortion = 0.5;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return FadeTransition(
        opacity: animation.drive(
          CurveTween(curve: const Interval(0, fadePortion)),
        ),
        child: child,
      );
    }
    return InkWipeTransition(
      progress: animation,
      coveredProgress: secondaryAnimation,
      child: child,
    );
  }
}
