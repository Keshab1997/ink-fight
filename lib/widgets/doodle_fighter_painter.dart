import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class DoodleFightersPainter extends CustomPainter {
  const DoodleFightersPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final floor = size.height * .73;
    final scale = math.min(size.width / 720, size.height / 360);
    final left = Offset(size.width * .28, floor - 4);
    final right = Offset(size.width * .72, floor - 4);

    _drawMotionMarks(canvas, size, floor, scale);
    _drawFighter(
      canvas,
      origin: left,
      scale: scale,
      facingRight: true,
      leaning: -.05,
    );
    _drawFighter(
      canvas,
      origin: right,
      scale: scale,
      facingRight: false,
      leaning: .04,
      bot: true,
    );
    _drawVs(canvas, Offset(size.width / 2, size.height * .42), scale);
  }

  void _drawFighter(
    Canvas canvas, {
    required Offset origin,
    required double scale,
    required bool facingRight,
    required double leaning,
    bool bot = false,
  }) {
    final stroke = Paint()
      ..color = InkColors.ink
      ..strokeWidth = 5.4 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final softStroke = Paint()
      ..color = InkColors.ink.withValues(alpha: .45)
      ..strokeWidth = 2.2 * scale
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final fill = Paint()
      ..color = bot ? InkColors.ink : InkColors.paper
      ..style = PaintingStyle.fill;

    final direction = facingRight ? 1.0 : -1.0;
    final head = origin + Offset(0, -132 * scale);
    final chest = origin + Offset(leaning * 44 * scale, -74 * scale);
    final hip = origin + Offset(leaning * 66 * scale, -10 * scale);

    canvas.drawCircle(head, 30 * scale, fill);
    canvas.drawCircle(head, 30 * scale, stroke);

    final faceX = head.dx + direction * 8 * scale;
    final facePaint = Paint()
      ..color = bot ? InkColors.paper : InkColors.ink
      ..strokeWidth = 4 * scale
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(
      Offset(faceX, head.dy - 5 * scale),
      2.4 * scale,
      facePaint,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(faceX - direction * 1 * scale, head.dy + 8 * scale),
        width: 17 * scale,
        height: 10 * scale,
      ),
      .1,
      direction * 2.7,
      false,
      facePaint,
    );

    final torso = Path()
      ..moveTo(chest.dx - 22 * scale, chest.dy - 12 * scale)
      ..quadraticBezierTo(
        chest.dx + direction * 24 * scale,
        chest.dy + 12 * scale,
        hip.dx + direction * 18 * scale,
        hip.dy,
      )
      ..quadraticBezierTo(
        hip.dx - direction * 17 * scale,
        hip.dy + 15 * scale,
        chest.dx - 22 * scale,
        chest.dy - 12 * scale,
      )
      ..close();
    canvas.drawPath(torso, fill);
    canvas.drawPath(torso, stroke);

    final backArm = chest + Offset(-direction * 11 * scale, 0);
    final backElbow = backArm + Offset(-direction * 30 * scale, 20 * scale);
    final backHand = backElbow + Offset(-direction * 12 * scale, 28 * scale);
    canvas.drawLine(backArm, backElbow, stroke);
    canvas.drawLine(backElbow, backHand, stroke);

    final frontArm = chest + Offset(direction * 13 * scale, -3 * scale);
    final frontElbow = frontArm + Offset(direction * 34 * scale, -26 * scale);
    final frontHand = frontElbow + Offset(direction * 26 * scale, 7 * scale);
    canvas.drawLine(frontArm, frontElbow, stroke);
    canvas.drawLine(frontElbow, frontHand, stroke);
    canvas.drawCircle(frontHand, 8 * scale, bot ? fill : stroke);
    canvas.drawCircle(frontHand, 8 * scale, stroke);

    final backLeg = hip + Offset(-direction * 5 * scale, 8 * scale);
    final backKnee = backLeg + Offset(-direction * 18 * scale, 38 * scale);
    final backFoot = backKnee + Offset(-direction * 23 * scale, 26 * scale);
    canvas.drawLine(backLeg, backKnee, stroke);
    canvas.drawLine(backKnee, backFoot, stroke);

    final frontLeg = hip + Offset(direction * 8 * scale, 8 * scale);
    final frontKnee = frontLeg + Offset(direction * 22 * scale, 34 * scale);
    final frontFoot = frontKnee + Offset(direction * 26 * scale, 22 * scale);
    canvas.drawLine(frontLeg, frontKnee, stroke);
    canvas.drawLine(frontKnee, frontFoot, stroke);

    final belt = Paint()
      ..color = bot ? InkColors.paper : InkColors.ink
      ..strokeWidth = 3.2 * scale
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(chest.dx - 16 * scale, chest.dy + 11 * scale),
      Offset(chest.dx + 18 * scale, chest.dy + 11 * scale),
      belt,
    );

    final sketch = Path()
      ..moveTo(head.dx - direction * 23 * scale, head.dy - 27 * scale)
      ..quadraticBezierTo(
        head.dx - direction * 2 * scale,
        head.dy - 46 * scale,
        head.dx + direction * 26 * scale,
        head.dy - 23 * scale,
      );
    canvas.drawPath(sketch, softStroke);
  }

  void _drawMotionMarks(Canvas canvas, Size size, double floor, double scale) {
    final paint = Paint()
      ..color = InkColors.ink.withValues(alpha: .28)
      ..strokeWidth = 3 * scale
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final leftStart = Offset(size.width * .08, floor - 120 * scale);
    final rightStart = Offset(size.width * .92, floor - 164 * scale);
    canvas.drawArc(
      Rect.fromLTWH(leftStart.dx, leftStart.dy, 84 * scale, 42 * scale),
      -.4,
      1.1,
      false,
      paint,
    );
    canvas.drawArc(
      Rect.fromLTWH(
        rightStart.dx - 84 * scale,
        rightStart.dy,
        84 * scale,
        42 * scale,
      ),
      2.45,
      1.1,
      false,
      paint,
    );

    for (var i = 0; i < 4; i++) {
      final y = floor - (24 + i * 13) * scale;
      canvas.drawLine(
        Offset(size.width * .39, y),
        Offset(size.width * .44, y - 5 * scale),
        paint,
      );
      canvas.drawLine(
        Offset(size.width * .56, y - 5 * scale),
        Offset(size.width * .61, y),
        paint,
      );
    }
  }

  void _drawVs(Canvas canvas, Offset center, double scale) {
    final painter = TextPainter(
      text: TextSpan(
        text: 'VS',
        style: TextStyle(
          color: InkColors.ink.withValues(alpha: .18),
          fontSize: 34 * scale,
          fontWeight: FontWeight.w900,
          letterSpacing: -1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant DoodleFightersPainter oldDelegate) => false;
}
