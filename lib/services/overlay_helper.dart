import 'package:flutter/material.dart';

class OverlayHelper {
  static Future<void> showCopiedOverlay(
      BuildContext context, TickerProvider vsync, String label) async {
    final overlay = Overlay.of(context);
    final animationController = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 250),
    );

    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => FadeTransition(
        opacity: animationController,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF9F5EF),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);
    await animationController.forward();
    await Future.delayed(const Duration(seconds: 1));
    await animationController.reverse();
    overlayEntry.remove();
    animationController.dispose();
  }
}
