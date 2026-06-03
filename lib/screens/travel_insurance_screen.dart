import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/external_link_service.dart';
import '../widgets/guide_back_button.dart';

class TravelInsuranceScreen extends StatelessWidget {
  const TravelInsuranceScreen({super.key});

  static const List<_InsuranceProvider> _providers = [
    _InsuranceProvider(
      name: 'YoMeAnimo',
      logoText: 'YMA',
      imageAsset: 'assets/Yomeanimo icona.png',
      url:
          'https://www.yomeanimo.com/seguros-de-viaje-working-holiday?r=AdbiQKqt',
      showDiscountPopup: true,
      background: Color(0xFF5EC7C1),
      foreground: Colors.white,
    ),
    _InsuranceProvider(
      name: 'IATI Seguros',
      logoText: 'iati',
      imageAsset: 'assets/IATI icona.png',
      url:
          'https://www.iatiseguros.com?r=05683647859528&utm_source=colaboradores&utm_medium=referral',
      background: Color(0xFFFFA22E),
      foreground: Colors.white,
    ),
    _InsuranceProvider(
      name: 'Chapka',
      logoText: 'C',
      imageAsset: 'assets/Chapka icona.png',
      url: 'https://www.chapkadirect.es/index.php?app=Maiki',
      keepCircleFrame: true,
      background: Color(0xFFFFFFFF),
      foreground: Color(0xFF122447),
    ),
    _InsuranceProvider(
      name: 'SafetyWing',
      logoText: 'SW',
      imageAsset: 'assets/Safety wing icona.png',
      url:
          'https://safetywing.com/?referenceID=26508229&utm_source=26508229&utm_medium=Ambassador',
      background: Color(0xFF66B8AA),
      foreground: Colors.white,
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
                      'Travel Insurance',
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
                  return _InsuranceProviderCard(provider: _providers[index]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showTravelInsuranceDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Travel Insurance',
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
            for (
              var i = 0;
              i < TravelInsuranceScreen._providers.length;
              i++
            ) ...[
              _InsurancePopupButton(
                provider: TravelInsuranceScreen._providers[i],
                parentContext: context,
              ),
              if (i != TravelInsuranceScreen._providers.length - 1)
                const SizedBox(height: 12),
            ],
          ],
        ),
      );
    },
  );
}

class _InsurancePopupButton extends StatelessWidget {
  const _InsurancePopupButton({
    required this.provider,
    required this.parentContext,
  });

  final _InsuranceProvider provider;
  final BuildContext parentContext;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFF7F5),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: provider.url == null
            ? null
            : () => _handleProviderTap(
                context,
                provider,
                parentDialogContext: parentContext,
              ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 46,
                height: 46,
                child: FittedBox(child: _ProviderLogo(provider: provider)),
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

class _InsuranceProviderCard extends StatelessWidget {
  const _InsuranceProviderCard({required this.provider});

  final _InsuranceProvider provider;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 0,
      child: Container(
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
          onTap: provider.url == null
              ? null
              : () => _handleProviderTap(context, provider),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ProviderLogo(provider: provider),
                const SizedBox(height: 14),
                Text(
                  provider.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF161922),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _handleProviderTap(
  BuildContext context,
  _InsuranceProvider provider, {
  BuildContext? parentDialogContext,
}) async {
  final url = provider.url;
  if (url == null) return;
  if (provider.showDiscountPopup) {
    if (parentDialogContext != null) {
      Navigator.of(context).pop();
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    final shouldOpenUrl = await _showDiscountCodeDialog(
      parentDialogContext ?? context,
    );
    if (shouldOpenUrl == true && (parentDialogContext ?? context).mounted) {
      await _openProviderUrl(parentDialogContext ?? context, url);
    }
    if (parentDialogContext != null && parentDialogContext.mounted) {
      await showTravelInsuranceDialog(parentDialogContext);
    }
    return;
  }
  await _openProviderUrl(context, url);
}

Future<bool?> _showDiscountCodeDialog(BuildContext context) async {
  const accentColor = Color(0xFF66C7C1);
  const discountCode = 'MIQ5OFF';

  return showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Discount code',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: accentColor,
            fontSize: 21,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () async {
                  await Clipboard.setData(
                    const ClipboardData(text: discountCode),
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(48, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.07),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.22),
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          discountCode,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: accentColor,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy code',
                        onPressed: () async {
                          await Clipboard.setData(
                            const ClipboardData(text: discountCode),
                          );
                        },
                        icon: const Icon(
                          Icons.copy_rounded,
                          color: accentColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: accentColor.withValues(alpha: 0.11),
                foregroundColor: accentColor,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(
                'YoMeAnimo',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      );
    },
  );
}

Future<void> _openProviderUrl(BuildContext context, String url) async {
  await ExternalLinkService.open(context, url);
}

class _ProviderLogo extends StatelessWidget {
  const _ProviderLogo({required this.provider});

  final _InsuranceProvider provider;

  @override
  Widget build(BuildContext context) {
    const logoSize = 82.0;
    const assetLogoScale = 1.36;
    final imageAsset = provider.imageAsset;
    if (imageAsset != null && !provider.keepCircleFrame) {
      return SizedBox(
        width: logoSize,
        height: logoSize,
        child: ClipOval(
          child: Transform.scale(
            scale: assetLogoScale,
            child: Image.asset(
              imageAsset,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
      );
    }

    return Container(
      width: logoSize,
      height: logoSize,
      decoration: BoxDecoration(
        color: provider.background,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 14,
            spreadRadius: -5,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: imageAsset == null
          ? Text(
              provider.logoText,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: provider.foreground,
                fontSize: provider.logoText.length <= 2 ? 31 : 24,
                fontWeight: FontWeight.w800,
                height: 0.92,
                letterSpacing: 0,
              ),
            )
          : ClipOval(
              child: Image.asset(
                imageAsset,
                width: logoSize,
                height: logoSize,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
    );
  }
}

class _InsuranceProvider {
  const _InsuranceProvider({
    required this.name,
    required this.logoText,
    required this.background,
    required this.foreground,
    this.imageAsset,
    this.url,
    this.showDiscountPopup = false,
    this.keepCircleFrame = false,
  });

  final String name;
  final String logoText;
  final Color background;
  final Color foreground;
  final String? imageAsset;
  final String? url;
  final bool showDiscountPopup;
  final bool keepCircleFrame;
}
