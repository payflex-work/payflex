import 'package:flutter/material.dart';
import '../theme/payflex_tokens.dart';
import '../theme/payflex_theme.dart';
import '../widgets/pf_brand_poster.dart';
import '../widgets/pf_buttons.dart';

/// ──────────────────────────────────────────────────────────────────────────
/// About PayFlex — the info page. The approved brand poster leads the
/// screen verbatim (icon, wordmark, tagline, four pillars), followed by a
/// short "what PayFlex is" paragraph, the four pillars as quiet rows
/// (mirroring the poster strip so screen and art speak with one voice),
/// and a compact facts block (version, rails, support contact).
///
/// Reached from Settings → About PayFlex (replaces the old dialog).
/// ──────────────────────────────────────────────────────────────────────────
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: PayFlexTheme.dark,
      child: Scaffold(
        backgroundColor: Colors.transparent, // reveal PfBackground waves
        appBar: AppBar(
          title: const Text('About PayFlex'),
          backgroundColor: Colors.transparent,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(PfSpace.xl, PfSpace.sm, PfSpace.xl, 40),
          children: [
            // The brand moment — full poster, full width.
            const PfBrandPoster(width: double.infinity),

            const SizedBox(height: PfSpace.xl),

            const Text(
              'Mobile-first microfinance, built on your own wallet',
              style: TextStyle(
                color: PfColors.onNavy,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            const SizedBox(height: PfSpace.sm),
            const Text(
              'PayFlex is a mobile wallet that moves the way you do. '
              'Savings, loans and agent services are PayFlex layers on top — '
              'but the money always settles through your own smart wallet, '
              'signed on this device with your PIN.',
              style: TextStyle(
                color: PfColors.onNavyMuted,
                fontSize: 13.5,
                height: 1.55,
              ),
            ),

            const SizedBox(height: PfSpace.xxl),
            const _PillarList(),

            const SizedBox(height: PfSpace.xxl),
            const _FactsCard(),

            const SizedBox(height: PfSpace.xl),
            PfSecondaryButton(
              label: 'Done',
              onPressed: () => Navigator.of(context).pop(),
              height: 48,
            ),
          ],
        ),
      ),
    );
  }
}

/// The four pillars from the poster strip, restated as quiet rows —
/// screen and brand art telling the same story.
class _PillarList extends StatelessWidget {
  const _PillarList();

  @override
  Widget build(BuildContext context) {
    const pillars = <(IconData, String, String)>[
      (Icons.bolt_rounded, 'Send money',
          'Instant transfers, QR Pay and PayTag — receipts for every move.'),
      (Icons.savings_outlined, 'Save more',
          'Goal-based savings that track progress, not just balances.'),
      (Icons.credit_card_outlined, 'Spend freely',
          'Virtual cards and everyday payments, signed with your PIN.'),
      (Icons.groups_outlined, 'Grow together',
          'Agent cash-in/out, community savings and shared bills.'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, (icon, title, body)) in pillars.indexed) ...[
          if (i > 0) const SizedBox(height: PfSpace.md),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: PfColors.navyRaised,
              borderRadius: BorderRadius.circular(PfRadius.md),
              border: Border.all(color: PfColors.navyBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: PfColors.navyRaised2,
                    borderRadius: BorderRadius.circular(PfRadius.sm),
                  ),
                  child: Icon(icon, color: PfColors.onNavyMuted, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: PfColors.onNavy,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        body,
                        style: const TextStyle(
                          color: PfColors.onNavyMuted,
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Compact facts block — version, what settles the money, support.
class _FactsCard extends StatelessWidget {
  const _FactsCard();

  @override
  Widget build(BuildContext context) {
    const rows = <(IconData, String, String)>[
      (Icons.tag_rounded, 'Version', 'PayFlex 0.1.0'),
      (
        Icons.account_balance_wallet_outlined,
        'Rails',
        'BMONI smart-wallet · Stellar (optional parallel rail)'
      ),
      (
        Icons.support_agent_rounded,
        'Support',
        'PayFlex agents can cash you in/out and raise issues for you.'
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: PfColors.navyRaised,
        borderRadius: BorderRadius.circular(PfRadius.md),
        border: Border.all(color: PfColors.navyBorder),
      ),
      child: Column(
        children: [
          for (final (i, (icon, label, value)) in rows.indexed) ...[
            if (i > 0) const Divider(color: PfColors.navyBorder, height: 1),
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Icon(icon, color: PfColors.onNavyMuted, size: 20),
              title: Text(
                label,
                style: const TextStyle(
                  color: PfColors.onNavy,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                value,
                style: const TextStyle(
                  color: PfColors.onNavyMuted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
