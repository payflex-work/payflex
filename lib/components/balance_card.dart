import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../theme/money_formatter.dart';
import 'brand_signature.dart';

/// The balance card — visual anchor of wallet home.
/// Gradient background (blue→green, flat not glowing), large balance
/// number that counts up on first load, subtle ribbon watermark
/// in the corner.
class BalanceCard extends StatefulWidget {
  final double balance;
  final String currency;
  final bool animate;
  final VoidCallback? onTap;

  const BalanceCard({
    super.key,
    required this.balance,
    this.currency = 'USD',
    this.animate = true,
    this.onTap,
  });

  @override
  State<BalanceCard> createState() => _BalanceCardState();
}

class _BalanceCardState extends State<BalanceCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _countController;
  late Animation<double> _countAnimation;

  String _displayBalance = '';

  @override
  void initState() {
    super.initState();
    _countController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _countAnimation = Tween<double>(
      begin: 0.0,
      end: widget.balance,
    ).animate(CurvedAnimation(
      parent: _countController,
      curve: Curves.easeOutExpo,
    ));
  }

  @override
  void dispose() {
    _countController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: [
            BoxShadow(
              color: (isDark ? AppColors.darkNavy : AppColors.lightBg)
                  .withOpacity(0.35),
              blurRadius: 24,
              offset: const Offset(0, 12),
              spreadRadius: 0,
            ),
          ],
        ),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Stack(
          children: [
            // Subtle ribbon watermark in top-right corner — flat, low opacity
            Positioned(
              top: -AppSpacing.lg,
              right: -AppSpacing.lg,
              child: RibbonPath(
                size: 80,
                opacity: 0.18,
                filled: true,
              ),
            ),
            // Balance content
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Your balance',
                  style: AppTypography.caption.copyWith(
                    color: isDark
                        ? AppColors.textOffWhite.withOpacity(0.75)
                        : AppColors.textMutedLight.withOpacity(0.8),
                  ),
                )
                    .animate(onPlay: (c) => c.repeat())
                    .fadeIn(duration: 200.ms),
                const SizedBox(height: AppSpacing.xs),
                AnimatedBuilder(
                  animation: _countAnimation,
                  builder: (context, child) {
                    final current = _countAnimation.value;
                    final whole = current.round();
                    final decimal = current - whole;
                    final wholeStr =
                        NumberFormat('#,##0').format(whole);
                    if (decimal.abs() < 0.005) {
                      _displayBalance = wholeStr;
                    } else {
                      final decStr =
                          NumberFormat('.00#').format(decimal)
                              .replaceFirst('-', '');
                      _displayBalance = '$wholeStr$decStr';
                    }
                    return Text(
                      _displayBalance,
                      style: AppTypography.balanceDisplay.copyWith(
                        color: AppColors.textWhite,
                      ),
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  MoneyFormatter.currencyCode,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textWhite.withOpacity(0.85),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 350.ms, delay: 80.ms)
        .slideY(begin: 0.06, end: 0.0, duration: 350.ms, delay: 80.ms)
        .scale(begin: const Offset(0.97, 0.97), end: const Offset(1, 1),
            duration: 350.ms, delay: 80.ms);
  }
}
