import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../core/app_state.dart';
import '../components/brand_signature.dart';

/// Settings / profile screen.
/// Account tier, verification status badge, and support access
/// all clearly visible — not hidden in submenus.
///
/// Per section 1: dark or light depending on context; for scaffolding
/// we use the same theme as the calling screen.
class SettingsScreen extends StatelessWidget {
  final User user;

  const SettingsScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          // Profile header
          SliverToBoxAdapter(
            child: _buildProfileHeader(theme, isDark),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
          // Account info
          SliverToBoxAdapter(
            child: _SectionHeader(title: 'Account'),
          ),
          SliverToBoxAdapter(
            child: _buildAccountSection(theme, isDark),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
          // Verification status badge (clearly visible, not buried)
          SliverToBoxAdapter(
            child: _buildVerificationSection(theme, isDark),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
          // Support access — clearly visible
          SliverToBoxAdapter(
            child: _SectionHeader(title: 'Support'),
          ),
          SliverToBoxAdapter(
            child: _buildSupportSection(theme, isDark),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
          // App info
          SliverToBoxAdapter(
            child: _SectionHeader(title: 'App'),
          ),
          SliverToBoxAdapter(
            child: _buildAppSection(theme, isDark),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: (isDark ? AppColors.darkNavy : AppColors.lightBg)
                .withOpacity(0.3),
            blurRadius: 24,
            offset: const Offset(0, 8),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar placeholder with flat background
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.textWhite.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_outline,
              color: AppColors.textWhite,
              size: 28,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: AppTypography.heading2.copyWith(
                    color: AppColors.textWhite,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  user.email,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textWhite.withOpacity(0.85),
                  ),
                ),
              ],
            ),
          ),
          // Small flat ribbon mark
          SizedBox(
            width: 32,
            height: 32,
            child: CustomPaint(
              painter: _SmallMarkPainter(
                color: AppColors.brandGradient,
                size: 32,
              ),
              child: const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 300.ms)
        .slideY(begin: 0.03, end: 0.0, duration: 300.ms);
  }

  Widget _buildAccountSection(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isDark ? const Color(0xFF2A3355) : const Color(0xFFE0E0DC),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          _buildAccountRow(
            context,
            icon: Icons.card_membership_outlined,
            label: 'Account tier',
            value: _tierLabel,
            trailing: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withOpacity(0.12),
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Text(
                _tierLabel,
                style: AppTypography.caption.copyWith(
                  color: AppColors.primaryGreen,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
          const Divider(height: AppSpacing.md),
          _buildAccountRow(
            context,
            icon: Icons.account_balance_outlined,
            label: 'Currency',
            value: 'USD ($)',
          ),
          const Divider(height: AppSpacing.md),
          _buildAccountRow(
            context,
            icon: Icons.history_outlined,
            label: 'Transaction history',
            value: 'View all →',
            trailingColor: AppColors.textMutedDark,
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 250.ms, delay: 100.ms);
  }

  Widget _buildVerificationSection(ThemeData theme, bool isDark) {
    final statusColor = switch (user.verification) {
      VerificationStatus.verified => AppColors.success,
      VerificationStatus.pending => AppColors.warning,
      VerificationStatus.rejected => AppColors.error,
      VerificationStatus.verifying => AppColors.primaryBlue,
    };

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: statusColor.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _verificationIcon,
                      size: 14,
                      color: statusColor,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      _verificationLabel.toUpperCase(),
                      style: AppTypography.caption.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                'Tap to update',
                style: AppTypography.bodySmall.copyWith(
                  color: statusColor,
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _verificationDescription,
            style: AppTypography.bodySmall.copyWith(
              color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () {
              // Navigate to verification flow — placeholder
            },
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Update verification'),
            style: OutlinedButton.styleFrom(
              foregroundColor: statusColor,
              side: BorderSide(color: statusColor.withOpacity(0.4)),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 250.ms, delay: 200.ms);
  }

  Widget _buildSupportSection(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isDark ? const Color(0xFF2A3355) : const Color(0xFFE0E0DC),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          _buildAccountRow(
            context,
            icon: Icons.help_outline,
            label: 'Help center',
            value: 'Browse articles →',
            trailingColor: AppColors.textMutedDark,
          ),
          const Divider(height: AppSpacing.md),
          _buildAccountRow(
            context,
            icon: Icons.chat_outlined,
            label: 'Chat with support',
            value: 'Available 24/7 →',
            trailingColor: AppColors.textMutedDark,
          ),
          const Divider(height: AppSpacing.md),
          _buildAccountRow(
            context,
            icon: Icons.email_outlined,
            label: 'Email support',
            value: 'support@payflex.example',
            trailingColor: AppColors.textMutedDark,
          ),
          const Divider(height: AppSpacing.md),
          _buildAccountRow(
            context,
            icon: Icons.phone_outlined,
            label: 'Call us',
            value: '+1 (800) 555-0199',
            trailingColor: AppColors.textMutedDark,
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 250.ms, delay: 300.ms);
  }

  Widget _buildAppSection(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isDark ? const Color(0xFF2A3355) : const Color(0xFFE0E0DC),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          _buildAccountRow(
            context,
            icon: Icons.info_outline,
            label: 'Version',
            value: '1.0.0 (1)',
            trailing: const SizedBox(),
          ),
          const Divider(height: AppSpacing.md),
          _buildAccountRow(
            context,
            icon: Icons.privacy_tip_outlined,
            label: 'Privacy policy',
            value: 'Read →',
            trailingColor: AppColors.primaryBlue,
          ),
          const Divider(height: AppSpacing.md),
          _buildAccountRow(
            context,
            icon: Icons.description_outlined,
            label: 'Terms of service',
            value: 'Read →',
            trailingColor: AppColors.primaryBlue,
          ),
          const Divider(height: AppSpacing.md),
          _buildAccountRow(
            context,
            icon: Icons.delete_outline,
            label: 'Sign out',
            value: 'Sign out →',
            trailingColor: AppColors.error,
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 250.ms, delay: 400.ms);
  }

  Widget _buildAccountRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    Widget? trailing,
    Color? trailingColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: isDark
              ? AppColors.textMutedDark
              : AppColors.textMutedLight,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            label,
            style: AppTypography.body.copyWith(
              color: isDark
                  ? AppColors.textOffWhite
                  : AppColors.textDark,
            ),
          ),
        ),
        if (trailing != null)
          trailing
        else
          Text(
            value,
            style: AppTypography.bodySmall.copyWith(
              color: trailingColor ??
                  (isDark
                      ? AppColors.textMutedDark
                      : AppColors.textMutedLight),
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    );
  }

  String get _tierLabel => switch (user.tier) {
        AccountTier.basic => 'Basic',
        AccountTier.standard => 'Standard',
        AccountTier.premium => 'Premium',
      };

  IconData get _verificationIcon => switch (user.verification) {
        VerificationStatus.verified => Icons.verified_outlined,
        VerificationStatus.pending => Icons.pending_outlined,
        VerificationStatus.rejected => Icons.error_outline,
        VerificationStatus.verifying => Icons.security_outlined,
      };

  String get _verificationLabel => switch (user.verification) {
        VerificationStatus.verified => 'Verified',
        VerificationStatus.pending => 'Pending',
        VerificationStatus.rejected => 'Action required',
        VerificationStatus.verifying => 'Verifying',
      };

  String get _verificationDescription => switch (user.verification) {
        VerificationStatus.verified =>
          'Your identity has been verified. You have full access to all account features.',
        VerificationStatus.pending =>
          'We\'re reviewing your documents. This usually takes 1–2 business days.',
        VerificationStatus.rejected =>
          'Your verification documents need attention. Please update your ID to continue.',
        VerificationStatus.verifying =>
          'Your documents are being reviewed. We\'ll notify you once complete.',
      };
}

class _SmallMarkPainter extends CustomPainter {
  final LinearGradient color;
  final double size;

  _SmallMarkPainter({required this.color, required this.size});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = color.createShader(
        Rect.fromLTWH(0, 0, size.width, size.height),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final s = size.width;
    final inset = s * 0.12;
    final cx = s / 2;
    final cy = s / 2;

    path.moveTo(inset, inset);
    path.cubicTo(
      cx * 0.4, inset * 0.2,
      cx * 1.2, cy * 0.6,
      cx + inset, cy - inset,
    );
    path.cubicTo(
      cx * 0.7, cy * 1.2,
      cx * 0.3, cy * 0.9,
      inset + s * 0.1, cy + s * 0.35,
    );
    path.cubicTo(
      cx + s * 0.6, cy * 1.1,
      cx + s * 0.8, cy * 0.5,
      cx + s * 0.75, cy * 0.2,
    );
    path.lineTo(cx + s * 0.9, cy * 0.15);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
