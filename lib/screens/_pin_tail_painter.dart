import 'package:flutter/material.dart';

class PinTailPainter extends CustomPainter {
  const PinTailPainter({required this.color, this.borderColor});
  final Color color;
  final Color? borderColor;

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
        ..strokeWidth = 1.2;
      canvas.drawPath(path, paintBorder);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
