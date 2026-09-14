import 'package:flutter/material.dart';
import '../../theme/payflex_tokens.dart';
import '../../theme/payflex_theme.dart';
import '../../widgets/pf_states.dart';

/// PAUSED FEATURE — honesty first. A loan product needs a treasury to
/// disburse from and verified history to score against; this app has
/// neither (no fiat rail, no KYC provider — see docs/fiat-kyc-gap.md).
/// This screen says so plainly instead of rendering a working-looking
/// loan flow with no backing.
class LoansScreen extends StatelessWidget {
  const LoansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: PayFlexTheme.light,
      child: Scaffold(
        backgroundColor: PfColors.offWhite,
        appBar: AppBar(
          title: const Text('Loans'),
          backgroundColor: PfColors.offWhite,
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: const Padding(
                padding: EdgeInsets.all(PfSpace.xl),
                child: PfEmptyState(
                  icon: Icons.account_balance_outlined,
                  title: 'Loans are paused',
                  message:
                      'Lending needs a funding source and real identity '
                      'verification — neither exists in this build. '
                      'PayFlex has no treasury to disburse from and no KYC '
                      'provider to score applicants, so there is nothing '
                      'honest to show here yet.\n\n'
                      'This is a deliberate pause, not a hidden feature — '
                      'see docs/fiat-kyc-gap.md for what a future lending '
                      'integration needs.',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
