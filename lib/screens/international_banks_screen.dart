import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/affiliate_links_service.dart';
import '../services/external_link_service.dart';
import '../utils/app_i18n.dart';
import '../widgets/guide_back_button.dart';

class InternationalBanksScreen extends StatelessWidget {
  const InternationalBanksScreen({super.key});

  static const List<_BankOption> _banks = [
    _BankOption(
      name: 'Revolut',
      asset: 'assets/icons/Revolut Logo .svg',
      affiliateLinkKey: 'revolut_link',
      background: Color(0xFFFFFFFF),
      foreground: Color(0xFF151922),
    ),
    _BankOption(
      name: 'Trade Republic',
      asset: 'assets/icons/Trade-Republic logo.png',
      affiliateLinkKey: 'trade_republic_link',
      logoPadding: 5,
      background: Color(0xFFFFFFFF),
      foreground: Color(0xFF9A7A42),
    ),
    _BankOption(
      name: 'Wise',
      asset: 'assets/icons/wise logo.png',
      affiliateLinkKey: 'wise_link',
      background: Color(0xFFFFFFFF),
      foreground: Color(0xFF4E8D57),
    ),
    _BankOption(
      name: 'N26',
      asset: 'assets/icons/n26 logo.png',
      directLink: 'https://n26.com/r/miquelm1156?cid=CTK&lang=es',
      discountCode: 'miquelm1156',
      discountButtonLabelKey: 'banks.go_n26',
      background: Color(0xFFFFFFFF),
      foreground: Color(0xFF5B8DB8),
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
                  Expanded(
                    child: FutureBuilder<Map<String, String>>(
                      future: AppI18n.load(),
                      initialData: AppI18n.forCode('en'),
                      builder: (context, snapshot) {
                        final strings = snapshot.data ?? AppI18n.forCode('en');
                        return Text(
                          AppI18n.t(strings, 'banks.title'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF151922),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
                itemCount: _banks.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  return _BankCard(bank: _banks[index]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showInternationalBanksDialog(BuildContext context) async {
  final strings = await AppI18n.load();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          AppI18n.t(strings, 'banks.title'),
          textAlign: TextAlign.center,
          style: const TextStyle(
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
              i < InternationalBanksScreen._banks.length;
              i++
            ) ...[
              _BankPopupButton(
                bank: InternationalBanksScreen._banks[i],
                parentContext: context,
              ),
              if (i != InternationalBanksScreen._banks.length - 1)
                const SizedBox(height: 12),
            ],
          ],
        ),
      );
    },
  );
}

class _BankPopupButton extends StatelessWidget {
  const _BankPopupButton({required this.bank, required this.parentContext});

  final _BankOption bank;
  final BuildContext parentContext;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFF7F5),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _BankCard(
          bank: bank,
        )._handleTap(context, parentDialogContext: parentContext),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 46,
                height: 46,
                child: FittedBox(child: _BankLogo(bank: bank)),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  bank.name,
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

class _BankCard extends StatelessWidget {
  const _BankCard({required this.bank});

  final _BankOption bank;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 108,
        padding: const EdgeInsets.symmetric(horizontal: 18),
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
          onTap: () => _handleTap(context),
          child: Row(
            children: [
              _BankLogo(bank: bank),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  bank.name,
                  style: const TextStyle(
                    color: Color(0xFF151922),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleTap(
    BuildContext context, {
    BuildContext? parentDialogContext,
  }) async {
    if (bank.discountCode != null && bank.directLink != null) {
      if (parentDialogContext != null) {
        Navigator.of(context).pop();
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      final shouldOpenUrl = await _showBankDiscountDialog(
        parentDialogContext ?? context,
        discountCode: bank.discountCode!,
        buttonLabel: bank.discountButtonLabelKey == null
            ? bank.name
            : AppI18n.t(await AppI18n.load(), bank.discountButtonLabelKey!),
      );
      if (shouldOpenUrl == true && (parentDialogContext ?? context).mounted) {
        await _openUrl(parentDialogContext ?? context, bank.directLink!);
      }
      if (parentDialogContext != null && parentDialogContext.mounted) {
        await showInternationalBanksDialog(parentDialogContext);
      }
      return;
    }

    if (bank.directLink != null) {
      await _openUrl(context, bank.directLink!);
      return;
    }

    if (bank.affiliateLinkKey != null) {
      await _openAffiliateLink(context, bank.affiliateLinkKey!);
    }
  }

  Future<void> _openAffiliateLink(BuildContext context, String key) async {
    final link = await AffiliateLinksService.instance.getLink(key);
    if (!context.mounted) return;

    if (link.isEmpty) {
      await ExternalLinkService.showBrokenLinkDialog(context);
      return;
    }

    await _openUrl(context, link);
  }

  Future<bool?> _showBankDiscountDialog(
    BuildContext context, {
    required String discountCode,
    required String buttonLabel,
  }) async {
    const accentColor = Color(0xFF11B39C);
    final strings = await AppI18n.load();
    if (!context.mounted) return null;

    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            AppI18n.t(strings, 'common.discount_code'),
            textAlign: TextAlign.center,
            style: const TextStyle(
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
                    await Clipboard.setData(ClipboardData(text: discountCode));
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
                        Expanded(
                          child: Text(
                            discountCode,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: accentColor,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: AppI18n.t(strings, 'common.copy_code'),
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: discountCode),
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
                child: Text(
                  buttonLabel,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openUrl(BuildContext context, String url) async {
    await ExternalLinkService.open(context, url);
  }
}

class _BankLogo extends StatelessWidget {
  const _BankLogo({required this.bank});

  final _BankOption bank;

  @override
  Widget build(BuildContext context) {
    final asset = bank.asset;
    return Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bank.background,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            spreadRadius: -5,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: asset == null
          ? Text(
              bank.initials,
              style: TextStyle(
                color: bank.foreground,
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            )
          : Padding(
              padding: EdgeInsets.all(bank.logoPadding),
              child: asset.toLowerCase().endsWith('.svg')
                  ? SvgPicture.asset(asset, fit: BoxFit.contain)
                  : Image.asset(
                      asset,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
            ),
    );
  }
}

class _BankOption {
  const _BankOption({
    required this.name,
    required this.background,
    required this.foreground,
    this.asset,
    this.affiliateLinkKey,
    this.directLink,
    this.discountCode,
    this.discountButtonLabelKey,
    this.logoPadding = 10,
  }) : initials = '';

  final String name;
  final String? asset;
  final String? affiliateLinkKey;
  final String? directLink;
  final String? discountCode;
  final String? discountButtonLabelKey;
  final String initials;
  final Color background;
  final Color foreground;
  final double logoPadding;
}
