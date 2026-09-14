import 'package:flutter/material.dart';
import '../../theme/payflex_tokens.dart';
import '../../theme/payflex_theme.dart';
import '../../widgets/pf_states.dart';

/// PAUSED FEATURE — honesty first. The old savings-goals ledger was an
/// app-level table; it is gone. The Stellar-native replacement for
/// personal saving is a Safebox: a Soroban contract that actually holds
/// the funds on-chain with the contribution/withdrawal ledger visible to
/// its members. This screen says so instead of rendering a goals flow
/// with no backend.
class SavingsScreen extends StatelessWidget {
  const SavingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: PayFlexTheme.light,
      child: Scaffold(
        backgroundColor: PfColors.offWhite,
        appBar: AppBar(
          title: const Text('Savings'),
          backgroundColor: PfColors.offWhite,
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: const Padding(
                padding: EdgeInsets.all(PfSpace.xl),
                child: PfEmptyState(
                  icon: Icons.savings_outlined,
                  title: 'Savings goals are paused',
                  message:
                      'For saving on-chain, Safebox is the real thing now: a '
                      'Soroban escrow contract that holds the funds and shows '
                      'every contribution and withdrawal to its members.\n\n'
                      'A dedicated goals product may return later — see '
                      'docs/fiat-kyc-gap.md.',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
