import 'package:flutter/material.dart';
import '../theme/payflex_tokens.dart';
import '../theme/payflex_theme.dart';
import '../widgets/pf_states.dart';

/// Honest "not built" screen, matching StubRailsScreen's pattern. BMONI's
/// API has no card-issuance primitive at all, and there is no processor
/// integration (Stripe Issuing, Marqeta, or similar) anywhere in this
/// codebase — a real virtual card needs both a product decision and a
/// processor partnership before anything here can be more than this.
/// Never render a fake card number/CVV/expiry: that would look like a
/// real financial instrument backed by nothing.
class VirtualCardScreen extends StatelessWidget {
  const VirtualCardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: PayFlexTheme.light,
      child: Scaffold(
        backgroundColor: PfColors.offWhite,
        appBar: AppBar(
          title: const Text('Virtual card'),
          backgroundColor: PfColors.offWhite,
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(PfSpace.xl),
                child: const PfEmptyState(
                  icon: Icons.credit_card_outlined,
                  title: 'Virtual cards are coming',
                  message:
                      'Issuing a real card needs a card-network/processor '
                      'partnership PayFlex doesn’t have yet, plus the '
                      'compliance work that comes with it — nothing here is '
                      'wired up on the backend either. This screen exists so '
                      'the feature has a real, honest home once that’s in '
                      'place, rather than a placeholder that pretends to be a '
                      'working card.',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
