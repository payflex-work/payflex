import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Primary CTA button — the logo's blue→green gradient as flat fill.
/// Soft, tight, neutral elevation shadow only — never a colored glow.
///
/// Design lint rule: no `BoxShadow` with spread/blur used to fake a glow.
/// No colored shadows. No `Container` decorations simulating neon.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final bool fullWidth;
  final double? width;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.fullWidth = false,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final btn = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Container(
          width: fullWidth ? double.infinity : width,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            // Soft, low-opacity, close, neutral elevation shadow —
            // never colored glow.
            boxShadow: [
              BoxShadow(
                color: (isDark ? AppColors.darkNavy : AppColors.lightBg)
                    .withOpacity(0.2),
                blurRadius: 12,
                offset: const Offset(0, 4),
                spreadRadius: 0,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading) ...[
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.textWhite),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ] else ...[
                if (icon != null) ...[
                  Icon(icon, size: 20, color: AppColors.textWhite),
                  const SizedBox(width: AppSpacing.sm),
                ],
              ],
              Text(
                label,
                style: AppTypography.heading2.copyWith(
                  color: AppColors.textWhite,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return btn
        .animate()
        .fadeIn(duration: 200.ms)
        .slideY(begin: 0.04, end: 0.0, duration: 200.ms);
  }
}

class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            border: Border.all(
              color: isDark
                  ? AppColors.primaryGreen.withOpacity(0.4)
                  : AppColors.primaryBlue.withOpacity(0.4),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: AppColors.primaryGreen),
                const SizedBox(width: AppSpacing.sm),
              ],
              Text(
                label,
                style: AppTypography.heading2.copyWith(
                  color: AppColors.primaryGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
