import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/doodle_fighter_painter.dart';

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
        final compact = constraints.maxWidth < 980;
        final horizontalPadding = compact ? 24.0 : 52.0;

        return Stack(
          children: [
            const Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: PaperGridPainter()),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                24,
                horizontalPadding,
                18,
              ),
              child: Column(
                children: [
                  const _TopBar(),
                  const SizedBox(height: 18),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: compact ? 290 : 360,
                          child: const SingleChildScrollView(
                            child: _MenuPanel(),
                          ),
                        ),
                        SizedBox(width: compact ? 24 : 48),
                        const Expanded(child: _ArenaPreview()),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const _FooterMeta(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: InkColors.ink,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'IF',
            style: TextStyle(
              color: InkColors.white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Text(
          'KESHAB STUDIOS',
          style: TextStyle(
            color: InkColors.inkSoft,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.2,
          ),
        ),
        const Spacer(),
        const _StatusPill(icon: Icons.circle, label: 'LOCAL BUILD / 001'),
      ],
    );
  }
}

class _MenuPanel extends StatelessWidget {
  const _MenuPanel();

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Online 1v1 is coming after the bot fight slice.'),
      ),
    );
  }

  void _showSettings(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Settings'),
          content: const Text(
            'Audio, haptics, accessibility, and account settings will live here.\n\n'
            'This first run is focused on the landscape home screen.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('CLOSE'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text(
          'THE ARENA',
          style: TextStyle(
            color: InkColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.4,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'INK\nFIGHT',
          style: TextStyle(
            color: InkColors.ink,
            fontSize: 56,
            height: .88,
            fontWeight: FontWeight.w900,
            letterSpacing: -3.6,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Doodle Combat',
          style: TextStyle(
            color: InkColors.inkSoft,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: .2,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'A clean line. A sharp hit.\nOwn the page.',
          style: TextStyle(
            color: InkColors.muted,
            fontSize: 14,
            height: 1.45,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 26),
        _ActionButton(
          label: 'BOT FIGHT',
          caption: 'PRACTICE THE BASICS',
          icon: Icons.bolt_rounded,
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Bot Fight arena is the next screen to build.'),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        _ActionButton(
          label: 'ONLINE 1V1',
          caption: 'COMING IN A LATER BUILD',
          icon: Icons.lock_outline_rounded,
          locked: true,
          onTap: () => _showComingSoon(context),
        ),
        const SizedBox(height: 10),
        _ActionButton(
          label: 'SETTINGS',
          caption: 'AUDIO / HAPTICS / HELP',
          icon: Icons.tune_rounded,
          compact: true,
          onTap: () => _showSettings(context),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: InkColors.ink,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 9),
            const Text(
              'BOT MODE READY',
              style: TextStyle(
                color: InkColors.inkSoft,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.3,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ArenaPreview extends StatelessWidget {
  const _ArenaPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: InkColors.paperDeep.withValues(alpha: .58),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: InkColors.line),
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: ArenaTexturePainter()),
          ),
          Positioned(
            top: 22,
            left: 24,
            child: _Tag(label: 'BOT FIGHT / PRACTICE'),
          ),
          const Positioned(top: 22, right: 24, child: _Tag(label: '01 : 00')),
          const Positioned.fill(
            child: Padding(
              padding: EdgeInsets.fromLTRB(26, 62, 26, 56),
              child: CustomPaint(painter: DoodleFightersPainter()),
            ),
          ),
          Positioned(
            left: 26,
            right: 26,
            bottom: 20,
            child: Row(
              children: [
                const Expanded(child: _HealthLine(label: 'YOU', value: .82)),
                const SizedBox(width: 18),
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: InkColors.ink,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'VS',
                    style: TextStyle(
                      color: InkColors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                const Expanded(child: _HealthLine(label: 'BOT', value: .64)),
              ],
            ),
          ),
        ],
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
            Text(
              label,
              style: const TextStyle(
                color: InkColors.inkSoft,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.6,
              ),
            ),
            Text(
              '${(value * 100).round()}%',
              style: const TextStyle(
                color: InkColors.muted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            minHeight: 6,
            value: value,
            backgroundColor: InkColors.white.withValues(alpha: .72),
            color: InkColors.ink,
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
    final background = compact
        ? InkColors.white.withValues(alpha: .35)
        : locked
        ? InkColors.paperDeep.withValues(alpha: .8)
        : InkColors.ink;
    final foreground = compact || locked ? InkColors.inkSoft : InkColors.white;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: compact ? 50 : 58,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: compact || locked ? InkColors.line : InkColors.ink,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: foreground, size: compact ? 18 : 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 3),
                      Text(
                        caption,
                        style: TextStyle(
                          color: foreground.withValues(alpha: .62),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .7,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                color: foreground.withValues(alpha: compact ? .7 : .9),
                size: 18,
              ),
            ],
          ),
        ),
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
        color: InkColors.white.withValues(alpha: .66),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: InkColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        child: Text(
          label,
          style: const TextStyle(
            color: InkColors.inkSoft,
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: InkColors.white.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: InkColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: InkColors.ink, size: 9),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
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

class _FooterMeta extends StatelessWidget {
  const _FooterMeta();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'PREMIUM MONOCHROME COMBAT',
          style: TextStyle(
            color: InkColors.muted,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
        const Spacer(),
        Text(
          'LANDSCAPE  •  60 FPS TARGET  •  ONLINE 1V1 SOON',
          style: TextStyle(
            color: InkColors.muted.withValues(alpha: .84),
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.05,
          ),
        ),
      ],
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
      ..color = InkColors.line.withValues(alpha: .23)
      ..strokeWidth = 1;
    final dotPaint = Paint()..color = InkColors.line.withValues(alpha: .36);

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
      ..color = InkColors.ink.withValues(alpha: .06)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final horizon = size.height * .72;

    canvas.drawLine(Offset(0, horizon), Offset(size.width, horizon), ink);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, horizon),
        width: size.width * .48,
        height: size.height * .18,
      ),
      ink,
    );
    for (var i = 0; i < 7; i++) {
      final x = size.width * (.08 + i * .14);
      canvas.drawLine(
        Offset(x, horizon),
        Offset(size.width / 2 + (x - size.width / 2) * .48, size.height),
        ink,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ArenaTexturePainter oldDelegate) => false;
}
