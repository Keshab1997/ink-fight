import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class DoodleFightersPainter extends CustomPainter {
  const DoodleFightersPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / 620, size.height / 300);
    final floor = size.height * .84;
    final playerOrigin = Offset(size.width * .28, floor);
    final botOrigin = Offset(size.width * .72, floor);

    _drawInkBurst(canvas, Offset(size.width / 2, size.height * .48), scale);
    _drawSpeedLines(canvas, size, scale);
    _drawFighter(
      canvas,
      origin: playerOrigin,
      scale: scale,
      facingRight: true,
      bot: false,
    );
    _drawFighter(
      canvas,
      origin: botOrigin,
      scale: scale,
      facingRight: false,
      bot: true,
    );
  }

  void _drawFighter(
    Canvas canvas, {
    required Offset origin,
    required double scale,
    required bool facingRight,
    required bool bot,
  }) {
    final direction = facingRight ? 1.0 : -1.0;
    final outline = Paint()
      ..color = InkColors.ink
      ..strokeWidth = 6.2 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final sketch = Paint()
      ..color = InkColors.ink.withValues(alpha: .38)
      ..strokeWidth = 2.3 * scale
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final fill = Paint()
      ..color = bot ? InkColors.ink : InkColors.paper
      ..style = PaintingStyle.fill;
    final detail = Paint()
      ..color = bot ? InkColors.paper : InkColors.ink
      ..strokeWidth = 3.4 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final head = origin + Offset(0, -151 * scale);
    final chest = origin + Offset(direction * 5 * scale, -93 * scale);
    final hip = origin + Offset(-direction * 4 * scale, -32 * scale);

    _drawHead(
      canvas,
      head,
      scale,
      facingRight,
      bot,
      fill,
      outline,
      detail,
      sketch,
    );
    _drawTorso(canvas, chest, hip, scale, bot, fill, outline, detail);
    _drawArms(canvas, chest, scale, direction, bot, fill, outline, detail);
    _drawLegs(canvas, hip, origin, scale, direction, outline, sketch);

    final looseLine = Path()
      ..moveTo(head.dx - direction * 27 * scale, head.dy - 35 * scale)
      ..quadraticBezierTo(
        head.dx - direction * 4 * scale,
        head.dy - 57 * scale,
        head.dx + direction * 28 * scale,
        head.dy - 34 * scale,
      );
    canvas.drawPath(looseLine, sketch);
  }

  void _drawHead(
    Canvas canvas,
    Offset head,
    double scale,
    bool facingRight,
    bool bot,
    Paint fill,
    Paint outline,
    Paint detail,
    Paint sketch,
  ) {
    final radius = 35 * scale;
    final direction = facingRight ? 1.0 : -1.0;
    final headShape = Path()
      ..moveTo(head.dx, head.dy - radius)
      ..quadraticBezierTo(
        head.dx + radius * .9,
        head.dy - radius * .95,
        head.dx + radius,
        head.dy + radius * .05,
      )
      ..quadraticBezierTo(
        head.dx + radius * .8,
        head.dy + radius * 1.03,
        head.dx - radius * .08,
        head.dy + radius,
      )
      ..quadraticBezierTo(
        head.dx - radius * 1.04,
        head.dy + radius * .74,
        head.dx - radius,
        head.dy - radius * .04,
      )
      ..quadraticBezierTo(
        head.dx - radius * .82,
        head.dy - radius * .96,
        head.dx,
        head.dy - radius,
      )
      ..close();
    canvas.drawPath(headShape, fill);
    canvas.drawPath(headShape, outline);

    final eye = Offset(head.dx + direction * 10 * scale, head.dy - 5 * scale);
    canvas.drawCircle(eye, 3 * scale, detail..style = PaintingStyle.fill);
    canvas.drawLine(
      Offset(eye.dx - direction * 11 * scale, eye.dy - 11 * scale),
      Offset(eye.dx + direction * 1 * scale, eye.dy - 14 * scale),
      detail,
    );

    final mouth = Path()
      ..moveTo(head.dx + direction * 3 * scale, head.dy + 13 * scale)
      ..quadraticBezierTo(
        head.dx + direction * 12 * scale,
        head.dy + 19 * scale,
        head.dx + direction * 21 * scale,
        head.dy + 11 * scale,
      );
    canvas.drawPath(mouth, detail);

    final hair = Path()
      ..moveTo(head.dx - direction * 30 * scale, head.dy - 24 * scale)
      ..quadraticBezierTo(
        head.dx - direction * 8 * scale,
        head.dy - 51 * scale,
        head.dx + direction * 29 * scale,
        head.dy - 26 * scale,
      );
    canvas.drawPath(hair, sketch);
    if (bot) {
      canvas.drawLine(
        Offset(head.dx - 20 * scale, head.dy - 25 * scale),
        Offset(head.dx + 20 * scale, head.dy - 25 * scale),
        detail,
      );
    }
  }

  void _drawTorso(
    Canvas canvas,
    Offset chest,
    Offset hip,
    double scale,
    bool bot,
    Paint fill,
    Paint outline,
    Paint detail,
  ) {
    final body = Path()
      ..moveTo(chest.dx - 27 * scale, chest.dy - 16 * scale)
      ..quadraticBezierTo(
        chest.dx,
        chest.dy - 28 * scale,
        chest.dx + 28 * scale,
        chest.dy - 12 * scale,
      )
      ..lineTo(hip.dx + 24 * scale, hip.dy + 4 * scale)
      ..quadraticBezierTo(
        hip.dx,
        hip.dy + 20 * scale,
        hip.dx - 26 * scale,
        hip.dy + 3 * scale,
      )
      ..close();
    canvas.drawPath(body, fill);
    canvas.drawPath(body, outline);

    final belt = Paint()
      ..color = bot ? InkColors.paper : InkColors.ink
      ..strokeWidth = 4 * scale
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(hip.dx - 20 * scale, hip.dy - 3 * scale),
      Offset(hip.dx + 20 * scale, hip.dy - 3 * scale),
      belt,
    );

    final emblem = Path()
      ..moveTo(chest.dx, chest.dy - 3 * scale)
      ..lineTo(chest.dx + 8 * scale, chest.dy + 8 * scale)
      ..lineTo(chest.dx, chest.dy + 16 * scale)
      ..lineTo(chest.dx - 8 * scale, chest.dy + 8 * scale)
      ..close();
    canvas.drawPath(emblem, detail..style = PaintingStyle.stroke);
  }

  void _drawArms(
    Canvas canvas,
    Offset chest,
    double scale,
    double direction,
    bool bot,
    Paint fill,
    Paint outline,
    Paint detail,
  ) {
    final frontShoulder = chest + Offset(direction * 19 * scale, -3 * scale);
    final frontElbow = chest + Offset(direction * 49 * scale, -28 * scale);
    final frontFist = chest + Offset(direction * 83 * scale, -19 * scale);
    canvas.drawLine(frontShoulder, frontElbow, outline);
    canvas.drawLine(frontElbow, frontFist, outline);
    canvas.drawCircle(frontFist, 12 * scale, bot ? fill : outline);
    canvas.drawCircle(frontFist, 12 * scale, outline);

    final backShoulder = chest + Offset(-direction * 19 * scale, -2 * scale);
    final backElbow = chest + Offset(-direction * 43 * scale, -50 * scale);
    final backHand = chest + Offset(-direction * 39 * scale, -83 * scale);
    canvas.drawLine(backShoulder, backElbow, outline);
    canvas.drawLine(backElbow, backHand, outline);
    canvas.drawCircle(backHand, 10 * scale, bot ? fill : outline);
    canvas.drawCircle(backHand, 10 * scale, outline);

    final guard = Paint()
      ..color = bot ? InkColors.paper.withValues(alpha: .8) : InkColors.ink
      ..strokeWidth = 2.2 * scale
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(backHand.dx - direction * 8 * scale, backHand.dy - 4 * scale),
      Offset(backHand.dx + direction * 7 * scale, backHand.dy + 5 * scale),
      guard,
    );
  }

  void _drawLegs(
    Canvas canvas,
    Offset hip,
    Offset origin,
    double scale,
    double direction,
    Paint outline,
    Paint sketch,
  ) {
    final backLeg = hip + Offset(-direction * 10 * scale, 6 * scale);
    final backKnee = backLeg + Offset(-direction * 28 * scale, 45 * scale);
    final backFoot = backKnee + Offset(-direction * 27 * scale, 30 * scale);
    canvas.drawLine(backLeg, backKnee, outline);
    canvas.drawLine(backKnee, backFoot, outline);
    canvas.drawLine(
      backFoot,
      backFoot + Offset(direction * 16 * scale, 0),
      outline,
    );

    final frontLeg = hip + Offset(direction * 11 * scale, 6 * scale);
    final frontKnee = frontLeg + Offset(direction * 25 * scale, 37 * scale);
    final frontFoot = frontKnee + Offset(direction * 34 * scale, 22 * scale);
    canvas.drawLine(frontLeg, frontKnee, outline);
    canvas.drawLine(frontKnee, frontFoot, outline);
    canvas.drawLine(
      frontFoot,
      frontFoot + Offset(-direction * 17 * scale, 0),
      outline,
    );

    canvas.drawLine(
      Offset(origin.dx - 22 * scale, origin.dy + 5 * scale),
      Offset(origin.dx + 25 * scale, origin.dy + 5 * scale),
      sketch,
    );
  }

  void _drawInkBurst(Canvas canvas, Offset center, double scale) {
    final fill = Paint()
      ..color = InkColors.ink.withValues(alpha: .1)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = InkColors.ink.withValues(alpha: .34)
      ..strokeWidth = 3 * scale
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final burst = Path()
      ..moveTo(center.dx, center.dy - 60 * scale)
      ..lineTo(center.dx + 17 * scale, center.dy - 22 * scale)
      ..lineTo(center.dx + 62 * scale, center.dy - 17 * scale)
      ..lineTo(center.dx + 26 * scale, center.dy + 5 * scale)
      ..lineTo(center.dx + 38 * scale, center.dy + 48 * scale)
      ..lineTo(center.dx, center.dy + 23 * scale)
      ..lineTo(center.dx - 38 * scale, center.dy + 48 * scale)
      ..lineTo(center.dx - 26 * scale, center.dy + 5 * scale)
      ..lineTo(center.dx - 62 * scale, center.dy - 17 * scale)
      ..lineTo(center.dx - 17 * scale, center.dy - 22 * scale)
      ..close();
    canvas.drawPath(burst, fill);
    canvas.drawPath(burst, stroke);

    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4;
      final start =
          center + Offset(math.cos(angle) * 58, math.sin(angle) * 42) * scale;
      final end =
          center + Offset(math.cos(angle) * 76, math.sin(angle) * 56) * scale;
      canvas.drawLine(start, end, stroke);
    }
  }

  void _drawSpeedLines(Canvas canvas, Size size, double scale) {
    final paint = Paint()
      ..color = InkColors.ink.withValues(alpha: .26)
      ..strokeWidth = 3 * scale
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 3; i++) {
      final y = size.height * (.2 + i * .07);
      canvas.drawLine(
        Offset(size.width * (.08 + i * .02), y),
        Offset(size.width * (.2 + i * .02), y - 8 * scale),
        paint,
      );
      canvas.drawLine(
        Offset(size.width * (.8 - i * .02), y - 10 * scale),
        Offset(size.width * (.92 - i * .02), y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant DoodleFightersPainter oldDelegate) => false;
}
