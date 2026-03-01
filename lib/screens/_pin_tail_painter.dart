import 'package:flutter/material.dart';

class PinTailPainter extends CustomPainter {
  const PinTailPainter({
    required this.color,
    this.borderColor,
    this.borderWidth = 1.2,
    this.drawTopBorder = true,
  });
  final Color color;
  final Color? borderColor;
  final double borderWidth;
  final bool drawTopBorder;

  @override
  void paint(Canvas canvas, Size size) {
    final paintFill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width / 2, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(path, paintFill);
    if (borderColor != null) {
      final paintBorder = Paint()
        ..color = borderColor!
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      if (drawTopBorder) {
        canvas.drawPath(path, paintBorder);
      } else {
        final sidePath = Path()
          ..moveTo(size.width / 2, size.height)
          ..lineTo(0, 0)
          ..moveTo(size.width / 2, size.height)
          ..lineTo(size.width, 0);
        canvas.drawPath(sidePath, paintBorder);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
