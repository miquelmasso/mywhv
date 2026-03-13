import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'onboarding_steps.dart';

class OnboardingOverlay extends StatelessWidget {
  const OnboardingOverlay({
    super.key,
    required this.step,
    required this.stepIndex,
    required this.totalSteps,
    required this.onPrimaryPressed,
    required this.onSkipPressed,
    this.highlightRect,
  });

  final OnboardingStepData step;
  final int stepIndex;
  final int totalSteps;
  final Rect? highlightRect;
  final VoidCallback onPrimaryPressed;
  final VoidCallback onSkipPressed;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: _OnboardingScene(
            key: ValueKey<String>(step.id),
            step: step,
            stepIndex: stepIndex,
            totalSteps: totalSteps,
            highlightRect: highlightRect,
            onPrimaryPressed: onPrimaryPressed,
            onSkipPressed: onSkipPressed,
          ),
        ),
      ),
    );
  }
}

class _OnboardingScene extends StatelessWidget {
  const _OnboardingScene({
    super.key,
    required this.step,
    required this.stepIndex,
    required this.totalSteps,
    required this.onPrimaryPressed,
    required this.onSkipPressed,
    this.highlightRect,
  });

  final OnboardingStepData step;
  final int stepIndex;
  final int totalSteps;
  final Rect? highlightRect;
  final VoidCallback onPrimaryPressed;
  final VoidCallback onSkipPressed;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final safePadding = mediaQuery.padding;
    final size = mediaQuery.size;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: const SizedBox.expand(),
            ),
          ),
          CustomPaint(
            size: size,
            painter: _SpotlightPainter(
              highlightRect: highlightRect,
              overlayOpacity: step.target == OnboardingTarget.mapArea
                  ? 0.86
                  : 0.78,
            ),
          ),
          if (step.isWelcome)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: _OnboardingCard(
                    step: step,
                    stepIndex: stepIndex,
                    totalSteps: totalSteps,
                    onPrimaryPressed: onPrimaryPressed,
                    onSkipPressed: onSkipPressed,
                  ),
                ),
              ),
            )
          else
            Positioned(
              left: 16,
              right: 16,
              top: _cardTop(safePadding, size),
              bottom: _cardBottom(safePadding, size),
              child: Align(
                alignment: _cardAlignment(size),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.min(size.width - 32, 360),
                  ),
                  child: _OnboardingCard(
                    step: step,
                    stepIndex: stepIndex,
                    totalSteps: totalSteps,
                    onPrimaryPressed: onPrimaryPressed,
                    onSkipPressed: onSkipPressed,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Alignment _cardAlignment(Size size) {
    final rect = highlightRect;
    if (rect == null) {
      return Alignment.bottomCenter;
    }
    return rect.center.dy < size.height * 0.48
        ? Alignment.bottomCenter
        : Alignment.topCenter;
  }

  double? _cardTop(EdgeInsets safePadding, Size size) {
    final rect = highlightRect;
    if (rect == null || rect.center.dy < size.height * 0.48) {
      return null;
    }
    return safePadding.top + 20;
  }

  double? _cardBottom(EdgeInsets safePadding, Size size) {
    final rect = highlightRect;
    if (rect == null || rect.center.dy >= size.height * 0.48) {
      return null;
    }
    return safePadding.bottom + 96;
  }
}

class _OnboardingCard extends StatelessWidget {
  const _OnboardingCard({
    required this.step,
    required this.stepIndex,
    required this.totalSteps,
    required this.onPrimaryPressed,
    required this.onSkipPressed,
  });

  final OnboardingStepData step;
  final int stepIndex;
  final int totalSteps;
  final VoidCallback onPrimaryPressed;
  final VoidCallback onSkipPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF151515).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x52000000),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              step.title,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              step.description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.84),
                height: 1.45,
              ),
            ),
            if (step.bullets.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final bullet in step.bullets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 7, right: 8),
                        child: Icon(
                          Icons.circle,
                          size: 6,
                          color: Colors.white70,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          bullet,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.84),
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 18),
            Row(
              children: List<Widget>.generate(
                totalSteps,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  margin: EdgeInsets.only(
                    right: index == totalSteps - 1 ? 0 : 8,
                  ),
                  height: 8,
                  width: index == stepIndex ? 22 : 8,
                  decoration: BoxDecoration(
                    color: index == stepIndex
                        ? const Color(0xFFFFA000)
                        : Colors.white.withValues(alpha: 0.24),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                TextButton(
                  onPressed: onSkipPressed,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white.withValues(alpha: 0.86),
                  ),
                  child: const Text('Skip'),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: onPrimaryPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFA000),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(step.primaryLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({this.highlightRect, required this.overlayOpacity});

  final Rect? highlightRect;
  final double overlayOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPath = Path()..addRect(Offset.zero & size);
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: overlayOpacity)
      ..style = PaintingStyle.fill;

    if (highlightRect == null) {
      canvas.drawPath(overlayPath, paint);
      return;
    }

    final paddedRect = highlightRect!.inflate(12);
    final cutout = RRect.fromRectAndRadius(
      paddedRect,
      const Radius.circular(24),
    );
    final cutoutPath = Path()..addRRect(cutout);
    final maskedPath = Path.combine(
      PathOperation.difference,
      overlayPath,
      cutoutPath,
    );
    canvas.drawPath(maskedPath, paint);

    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.88)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(cutout, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) =>
      oldDelegate.highlightRect != highlightRect ||
      oldDelegate.overlayOpacity != overlayOpacity;
}
