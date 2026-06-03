import 'package:flutter/material.dart';

import '../services/external_link_service.dart';
import '../widgets/guide_back_button.dart';

class FastJobsScreen extends StatelessWidget {
  const FastJobsScreen({super.key});

  static const List<_FastJobProvider> _providers = [
    _FastJobProvider(
      name: 'Uber Eats',
      logo: 'Uber Eats',
      imageAsset: 'assets/uber eats icona.png',
      color: Color(0xFF142328),
      accent: Color(0xFF5EC7C1),
    ),
    _FastJobProvider(
      name: 'Uber Drive',
      logo: 'Uber',
      imageAsset: 'assets/Uber icona.jpg',
      color: Color(0xFF111111),
      accent: Color(0xFFD9EAF7),
    ),
    _FastJobProvider(
      name: 'DoorDash',
      logo: 'DoorDash',
      imageAsset: 'assets/DoorDash icona.png',
      color: Color(0xFFE65A4F),
      accent: Color(0xFFFFE4E0),
    ),
    _FastJobProvider(
      name: 'GoGet',
      logo: 'GoGet',
      imageAsset: 'assets/GoGet icona.jpg',
      color: Color(0xFF3267B1),
      accent: Color(0xFFE2ECFA),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F6),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
              child: Row(
                children: [
                  GuideBackButton(onTap: () => Navigator.of(context).pop()),
                  const Expanded(
                    child: Text(
                      'Fast jobs to start',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF151922),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
                itemCount: _providers.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  return _FastJobButton(provider: _providers[index]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showFastJobsDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Fast jobs to start',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF151922),
            fontSize: 21,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < FastJobsScreen._providers.length; i++) ...[
              _FastJobPopupButton(provider: FastJobsScreen._providers[i]),
              if (i != FastJobsScreen._providers.length - 1)
                const SizedBox(height: 12),
            ],
          ],
        ),
      );
    },
  );
}

class _FastJobPopupButton extends StatelessWidget {
  const _FastJobPopupButton({required this.provider});

  final _FastJobProvider provider;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFF7F5),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          ExternalLinkService.showBrokenLinkDialog(context);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: ClipOval(
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: provider.imageAsset == null
                        ? Center(
                            child: Text(
                              provider.logo,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: provider.color,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0,
                              ),
                            ),
                          )
                        : Image.asset(
                            provider.imageAsset!,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  provider.name,
                  style: const TextStyle(
                    color: Color(0xFF8A4A3A),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF9B6A5D)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FastJobButton extends StatelessWidget {
  const _FastJobButton({required this.provider});

  final _FastJobProvider provider;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 112,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 18,
              spreadRadius: -6,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {},
          child: Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 14,
                    spreadRadius: -5,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: ClipOval(
                child: SizedBox(
                  width: 68,
                  height: 68,
                  child: provider.imageAsset == null
                      ? Center(
                          child: Text(
                            provider.logo,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: provider.color,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                          ),
                        )
                      : Image.asset(
                          provider.imageAsset!,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FastJobProvider {
  const _FastJobProvider({
    required this.name,
    required this.logo,
    required this.color,
    required this.accent,
    this.imageAsset,
  });

  final String name;
  final String logo;
  final Color color;
  final Color accent;
  final String? imageAsset;
}
