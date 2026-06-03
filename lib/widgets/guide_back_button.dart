import 'package:flutter/material.dart';

class GuideBackButton extends StatelessWidget {
  const GuideBackButton({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 5,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap ?? () => Navigator.of(context).maybePop(),
        child: const SizedBox(
          width: 48,
          height: 48,
          child: Icon(Icons.arrow_back, color: Color(0xFF1D222B), size: 26),
        ),
      ),
    );
  }
}
