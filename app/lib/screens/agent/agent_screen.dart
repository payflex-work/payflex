import 'package:flutter/material.dart';
import '../../theme/payflex_tokens.dart';
import '../../theme/payflex_theme.dart';
import '../../widgets/pf_states.dart';

/// PAUSED FEATURE — hard-gated. An agent converts physical cash to digital
/// and back; that requires a real fiat rail (the cash side) AND verified
/// identity (the regulatory side). Neither exists in this build: no fiat
/// provider is plugged in and nobody can pass the identity-verification
/// gate, so the backend's agent endpoints refuse every request with 403 —
/// by architecture, not by UI. See docs/fiat-kyc-gap.md.
class AgentScreen extends StatelessWidget {
  const AgentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: PayFlexTheme.light,
      child: Scaffold(
        backgroundColor: PfColors.offWhite,
        appBar: AppBar(
          title: const Text('Agent mode'),
          backgroundColor: PfColors.offWhite,
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: const Padding(
                padding: EdgeInsets.all(PfSpace.xl),
                child: PfEmptyState(
                  icon: Icons.storefront_outlined,
                  title: 'Agent cash-in / cash-out is paused',
                  message:
                      'Agents bridge physical cash to digital balances — which '
                      'needs a real fiat rail and verified identity. Neither '
                      'is configured in PayFlex yet: no fiat provider is '
                      'plugged in and no KYC provider exists, so this feature '
                      'is unavailable to everyone, by design.\n\n'
                      'See docs/fiat-kyc-gap.md for what plugs in here later.',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
