import 'package:flutter/material.dart';

import '../game/rules/match_rules.dart';
import '../theme/app_theme.dart';
import 'app_routes.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: OrientationBuilder(
          builder: (context, orientation) {
            if (orientation == Orientation.portrait) {
              return const _RotateDeviceView();
            }
            return const _LandscapeHome();
          },
        ),
      ),
    );
  }
}

class _LandscapeHome extends StatelessWidget {
  const _LandscapeHome();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final padding = compact ? 16.0 : 34.0;

        return Stack(
          children: [
            const Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: PaperGridPainter()),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(padding, 14, padding, 12),
              child: Column(
                children: [
                  _Header(compact: compact),
                  SizedBox(height: compact ? 10 : 16),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 3, child: _HeroCopy(compact: compact)),
                        SizedBox(width: compact ? 14 : 28),
                        const Expanded(flex: 5, child: _ArenaPreview()),
                      ],
                    ),
                  ),
                  SizedBox(height: compact ? 10 : 14),
                  _ActionRail(compact: compact),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: compact ? 36 : 42,
          height: compact ? 36 : 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: InkColors.ink,
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Text(
            'IF',
            style: TextStyle(
              color: InkColors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'INK FIGHT',
          style: TextStyle(
            color: InkColors.ink,
            fontSize: compact ? 20 : 24,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.2,
          ),
        ),
        const SizedBox(width: 12),
        Container(width: 1, height: 22, color: InkColors.line),
        const SizedBox(width: 12),
        const Text(
          'DOODLE COMBAT',
          style: TextStyle(
            color: InkColors.muted,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.8,
          ),
        ),
        const Spacer(),
        if (!compact)
          const _StatusPill(icon: Icons.circle, label: 'LOCAL BUILD / 001'),
      ],
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({required this.compact});

  final bool compact;

  void _showIntro(BuildContext context) {
    Navigator.of(context).pushNamed(InkRoutes.difficulty);
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      // The copy is a fixed composition — a three-line title, a two-line
      // subtitle, a badge — and on a short landscape window the column is
      // simply taller than the slot it sits in. Scaling it down keeps the
      // whole composition readable instead of clipping the badge off the
      // bottom, and at every size where it fits nothing is scaled at all.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Eyebrow(label: '01 / TRAINING GROUNDS'),
            SizedBox(height: compact ? 10 : 16),
            Text(
              'DRAW.\nFIGHT.\nDOMINATE.',
              style: TextStyle(
                color: InkColors.ink,
                fontSize: compact ? 31 : 42,
                height: .89,
                fontWeight: FontWeight.w900,
                letterSpacing: -2.4,
              ),
            ),
            SizedBox(height: compact ? 10 : 14),
            Text(
              'A clean line. A sharp hit.\nOwn the page.',
              style: TextStyle(
                color: InkColors.muted,
                fontSize: compact ? 12 : 14,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: compact ? 14 : 20),
            InkWell(
              onTap: () => _showIntro(context),
              borderRadius: BorderRadius.circular(99),
              child: const _ReadyBadge(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArenaPreview extends StatelessWidget {
  const _ArenaPreview();

  /// Vignette: this preview is a posed picture, not a live match, so both
  /// health lines stand full. The bar is the table's own full health over
  /// itself, so a tuning change cannot leave the menu showing a stale bar.
  static final int _vignetteFull = MatchRules.standard.health;

  /// The clock chip, read from the table: a round is 60 seconds, so the chip
  /// says `01 : 00` because the rules say so, not because the string is real.
  static String _clockLabel() {
    final totalSeconds = MatchRules.standard.roundMs ~/ 1000;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes : $seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: InkColors.paperDeep.withValues(alpha: .68),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: InkColors.line),
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: ArenaTexturePainter()),
          ),
          const Positioned(
            top: 16,
            left: 18,
            child: _Tag(label: 'BOT FIGHT / PRACTICE'),
          ),
          Positioned(top: 16, right: 18, child: _Tag(label: _clockLabel())),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 24, 14, 42),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Image.asset(
                      'assets/ui/home_player_kick.png',
                      fit: BoxFit.contain,
                      alignment: Alignment.bottomCenter,
                    ),
                  ),
                  Expanded(
                    // A presentational mirror for the menu composition only:
                    // the delivered pose faces right, and the preview wants
                    // the two fighters squaring up. The art on disk is
                    // untouched, and the arena keeps its regenerated frames.
                    child: Transform.flip(
                      flipX: true,
                      child: Image.asset(
                        'assets/ui/home_rival_punch.png',
                        fit: BoxFit.contain,
                        alignment: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 14,
            child: Row(
              children: [
                Expanded(
                  child: _HealthLine(
                    label: 'YOU',
                    value: _vignetteFull / MatchRules.standard.health,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: InkColors.ink,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Text(
                    'VS',
                    style: TextStyle(
                      color: InkColors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _HealthLine(
                    label: 'CRIMSON RIVAL',
                    value: _vignetteFull / MatchRules.standard.health,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRail extends StatelessWidget {
  const _ActionRail({required this.compact});

  final bool compact;

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Online 1v1 is coming after the bot fight slice.'),
      ),
    );
  }

  void _showSettings(BuildContext context) {
    Navigator.of(context).pushNamed(InkRoutes.settings);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: _ActionButton(
            label: 'BOT FIGHT',
            caption: 'PRACTICE THE BASICS',
            icon: Icons.bolt_rounded,
            onTap: () => Navigator.of(context).pushNamed(InkRoutes.difficulty),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 4,
          child: _ActionButton(
            label: 'ONLINE 1V1',
            caption: 'COMING SOON',
            icon: Icons.lock_outline_rounded,
            locked: true,
            onTap: () => _showComingSoon(context),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: _ActionButton(
            label: 'SETTINGS',
            caption: 'AUDIO / HELP',
            icon: Icons.tune_rounded,
            compact: compact,
            onTap: () => _showSettings(context),
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.caption,
    required this.icon,
    required this.onTap,
    this.locked = false,
    this.compact = false,
  });

  final String label;
  final String caption;
  final IconData icon;
  final VoidCallback onTap;
  final bool locked;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final background = locked
        ? InkColors.paperDeep.withValues(alpha: .92)
        : InkColors.ink;
    final foreground = locked ? InkColors.inkSoft : InkColors.white;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: compact ? 52 : 58,
          padding: EdgeInsets.symmetric(horizontal: compact ? 11 : 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: locked ? InkColors.line : InkColors.ink),
          ),
          child: Row(
            children: [
              Icon(icon, color: foreground, size: compact ? 17 : 20),
              SizedBox(width: compact ? 7 : 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: compact ? 10 : 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: compact ? .7 : 1,
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 2),
                      Text(
                        caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground.withValues(alpha: .62),
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .6,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                color: foreground.withValues(alpha: .7),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HealthLine extends StatelessWidget {
  const _HealthLine({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // The rival's name is long; on a narrow preview it clips with an
            // ellipsis instead of pushing the percentage off the strip.
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: InkColors.inkSoft,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                ),
              ),
            ),
            Text(
              '${(value * 100).round()}%',
              style: const TextStyle(
                color: InkColors.muted,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            minHeight: 5,
            value: value,
            backgroundColor: InkColors.white.withValues(alpha: .72),
            color: InkColors.ink,
          ),
        ),
      ],
    );
  }
}

class _ReadyBadge extends StatelessWidget {
  const _ReadyBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: InkColors.white.withValues(alpha: .58),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: InkColors.line),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, color: InkColors.ink, size: 8),
          SizedBox(width: 8),
          Text(
            'BOT MODE READY',
            style: TextStyle(
              color: InkColors.inkSoft,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: InkColors.muted,
        fontSize: 10,
        fontWeight: FontWeight.w900,
        letterSpacing: 2,
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: InkColors.white.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: InkColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: const TextStyle(
            color: InkColors.inkSoft,
            fontSize: 8,
            fontWeight: FontWeight.w900,
            letterSpacing: .9,
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: InkColors.white.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: InkColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: InkColors.ink, size: 8),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: InkColors.inkSoft,
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: .9,
            ),
          ),
        ],
      ),
    );
  }
}

class _RotateDeviceView extends StatelessWidget {
  const _RotateDeviceView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.screen_rotation_alt_rounded, size: 42),
            const SizedBox(height: 14),
            Text(
              'Rotate your device',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text('INK FIGHT is designed for landscape play.'),
          ],
        ),
      ),
    );
  }
}

class PaperGridPainter extends CustomPainter {
  const PaperGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = InkColors.line.withValues(alpha: .2)
      ..strokeWidth = 1;
    final dotPaint = Paint()..color = InkColors.line.withValues(alpha: .34);

    for (double x = 0; x < size.width; x += 48) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
    for (double y = 0; y < size.height; y += 48) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
    for (double x = 24; x < size.width; x += 96) {
      for (double y = 24; y < size.height; y += 96) {
        canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant PaperGridPainter oldDelegate) => false;
}

class ArenaTexturePainter extends CustomPainter {
  const ArenaTexturePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()
      ..color = InkColors.ink.withValues(alpha: .08)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final horizon = size.height * .75;

    canvas.drawLine(Offset(0, horizon), Offset(size.width, horizon), ink);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, horizon),
        width: size.width * .56,
        height: size.height * .2,
      ),
      ink,
    );
    for (var i = 0; i < 8; i++) {
      final x = size.width * (.04 + i * .14);
      canvas.drawLine(
        Offset(x, horizon),
        Offset(size.width / 2 + (x - size.width / 2) * .45, size.height),
        ink,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ArenaTexturePainter oldDelegate) => false;
}
