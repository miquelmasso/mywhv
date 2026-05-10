import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class SoftUpdateBanner extends StatelessWidget {
  const SoftUpdateBanner({
    super.key,
    required this.message,
    required this.onUpdateNow,
  });

  final String message;
  final VoidCallback onUpdateNow;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 18,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF2F0),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.system_update_alt_rounded,
                size: 22,
                color: Color(0xFFCC6F6A),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Update available',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF1F1A17),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF5C524D),
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onUpdateNow,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF3D6FFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Update now',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ForceUpdateOverlay extends StatelessWidget {
  const ForceUpdateOverlay({
    super.key,
    required this.message,
    required this.onUpdateNow,
    required this.onCopyStoreLink,
    required this.storeUrl,
    required this.isLaunchingListenable,
    required this.errorMessageListenable,
  });

  final String message;
  final VoidCallback onUpdateNow;
  final VoidCallback onCopyStoreLink;
  final String storeUrl;
  final ValueListenable<bool> isLaunchingListenable;
  final ValueListenable<String?> errorMessageListenable;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(color: Colors.black.withValues(alpha: 0.36)),
          ),
        ),
        SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Material(
                  color: Colors.white,
                  elevation: 20,
                  borderRadius: BorderRadius.circular(28),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF2F0),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.system_update_rounded,
                            color: Color(0xFFCC6F6A),
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Update available',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1F1A17),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.45,
                            color: Color(0xFF5C524D),
                          ),
                        ),
                        const SizedBox(height: 22),
                        ValueListenableBuilder<String?>(
                          valueListenable: errorMessageListenable,
                          builder: (context, errorMessage, _) {
                            if (errorMessage == null || errorMessage.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                12,
                                14,
                                12,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF2F0),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    errorMessage,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFB85F59),
                                      height: 1.35,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    storeUrl,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF7A5F59),
                                      height: 1.35,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: OutlinedButton(
                                      onPressed: onCopyStoreLink,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(
                                          0xFFB85F59,
                                        ),
                                        side: const BorderSide(
                                          color: Color(0xFFE7B6B1),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                      ),
                                      child: const Text('Copy update link'),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        ValueListenableBuilder<bool>(
                          valueListenable: isLaunchingListenable,
                          builder: (context, isLaunching, _) {
                            return SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: isLaunching ? null : onUpdateNow,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF3D6FFF),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                child: isLaunching
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        'Update now',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
