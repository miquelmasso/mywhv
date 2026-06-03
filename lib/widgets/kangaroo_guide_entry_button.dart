import 'package:flutter/material.dart';

import '../services/journey_guide_progress_service.dart';

class KangarooGuideEntryButton extends StatefulWidget {
  const KangarooGuideEntryButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  State<KangarooGuideEntryButton> createState() =>
      _KangarooGuideEntryButtonState();
}

class _KangarooGuideEntryButtonState extends State<KangarooGuideEntryButton>
    with SingleTickerProviderStateMixin {
  static const String _kangarooIconAsset = 'assets/ kangaroo_icon.png';

  late final AnimationController _controller;
  late final Animation<double> _scale;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _scale = CurvedAnimation(parent: _controller, curve: Curves.easeOutBack);
    _prepareVisibility();
  }

  Future<void> _prepareVisibility() async {
    final finished =
        await JourneyGuideProgressService.instance.isJourneyFinished();
    if (!mounted || finished) return;
    setState(() => _visible = true);
    _controller.forward();
  }

  void _hide() {
    if (!mounted || !_visible) return;
    _controller.reverse().then((_) {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    return Positioned(
      right: 18,
      bottom: 118,
      child: ScaleTransition(
        scale: _scale,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              constraints: const BoxConstraints(maxWidth: 176),
              margin: const EdgeInsets.only(right: 8, bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 18,
                    spreadRadius: -6,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Text(
                'Deixa’m guiar-te per Austràlia 🇦🇺',
                style: TextStyle(
                  color: Color(0xFF1D222B),
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  height: 1.15,
                ),
              ),
            ),
            Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 8,
              shadowColor: Colors.black.withValues(alpha: 0.18),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () {
                  _hide();
                  widget.onTap();
                },
                child: Container(
                  width: 62,
                  height: 62,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFF2D14B)),
                  ),
                  child: ClipOval(
                    child: Image.asset(_kangarooIconAsset, fit: BoxFit.cover),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
