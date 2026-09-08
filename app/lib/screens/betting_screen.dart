import 'package:flutter/material.dart';
import '../theme/payflex_tokens.dart';
import '../theme/payflex_theme.dart';
import '../widgets/pf_states.dart';

/// Honest "not built" screen, matching StubRailsScreen's pattern. Betting
/// funding needs real regulatory licensing (jurisdiction-dependent) and a
/// merchant/provider integration — neither exists in this codebase, and
/// there is nothing on the backend to fund. Never render a working-looking
/// bet-placement flow with no real backing.
class BettingScreen extends StatelessWidget {
  const BettingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: PayFlexTheme.light,
      child: Scaffold(
        backgroundColor: PfColors.offWhite,
        appBar: AppBar(
          title: const Text('Betting funding'),
          backgroundColor: PfColors.offWhite,
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(PfSpace.xl),
                child: const PfEmptyState(
                  icon: Icons.sports_soccer_outlined,
                  title: 'Pending licensing',
                  message:
                      'Betting funding needs real regulatory licensing in '
                      'whichever jurisdiction it launches, plus a licensed '
                      'merchant/provider to actually fund — neither exists '
                      'yet, and nothing on the backend supports it. This '
                      'screen is a placeholder for that, not a working '
                      'feature.',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
