import 'dart:math';
import 'package:flutter/material.dart';

/// Simple radial overlay with 12 month chips positioned around a center offset.
class HarvestMonthsRadialOverlay extends StatelessWidget {
  final Offset centerScreen;
  final double radius;
  final bool visible;

  const HarvestMonthsRadialOverlay({
    super.key,
    required this.centerScreen,
    this.radius = 50,
    this.visible = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    const months = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
    return Stack(
      children: List.generate(months.length, (i) {
        final angle = (-pi / 2) + (i * 2 * pi / 12); // start at top
        final dx = centerScreen.dx + radius * cos(angle);
        final dy = centerScreen.dy + radius * sin(angle);
        return Positioned(
          left: dx - 12, // center a 24px chip
          top: dy - 12,
          child: _MonthChip(label: months[i]),
        );
      }),
    );
  }
}

class _MonthChip extends StatelessWidget {
  final String label;
  const _MonthChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: Colors.black.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
    );
  }
}
