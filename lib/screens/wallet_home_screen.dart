import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../theme/money_formatter.dart';
import '../core/app_state.dart';
import '../components/balance_card.dart';
import '../components/receipt_view.dart';
import '../components/brand_signature.dart';
import 'transfer_screen.dart';
import 'settings_screen.dart';

/// Wallet home — dark-default for wallet screens (section 1).
///
/// Layout:
///   [header with logo watermark]    ← ribbon watermark in corner
///   [BalanceCard]                    ← visual anchor, large balance
///   [Quick actions row]              ← send, receive, pay, top-up
///   [Split bill progress]            ← ring filling in flat gradient
///   [Recent transactions]            ← receipt-style list
///
/// Watermark: subtle logo ribbon shape in top-right corner, flat,
/// low opacity — not glowing.
class WalletHomeScreen extends StatefulWidget {
  final User user;
  final WalletState wallet;
  final VoidCallback onSend;
  final VoidCallback onReceive;
  final VoidCallback onPay;
  final VoidCallback onTopUp;

  const WalletHomeScreen({
    super.key,
    required this.user,
    required this.wallet,
    required this.onSend,
    required this.onReceive,
    required this.onPay,
    required this.onTopUp,
  });

  @override
  State<WalletHomeScreen> createState() => _WalletHomeScreenState();
}

class _WalletHomeScreenState extends State<WalletHomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<Transaction> _transactions = [
    Transaction(
      id: '1',
      recipient: 'Amara Osei',
      amount: 45.00,
      reference: MoneyFormatter.referenceNumber(1001),
      timestamp: DateTime.now().subtract(const Duration(hours: 2)),
      status: ReceiptStatus.completed,
    ),
    Transaction(
      id: '2',
      recipient: 'Kofi Mensa',
      amount: 120.00,
      reference: MoneyFormatter.referenceNumber(1002),
      timestamp: DateTime.now().subtract(const Duration(days: 1)),
      status: ReceiptStatus.completed,
    ),
    Transaction(
      id: '3',
      recipient: 'Split bill — Team lunch',
      amount: 68.50,
      reference: MoneyFormatter.referenceNumber(1003),
      timestamp: DateTime.now().subtract(const Duration(days: 2)),
      status: ReceiptStatus.pending,
      contributors: ['You (40%)', 'Amara', 'Kofi', 'Lena'],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _navigateToScreen(Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: _buildHeader(theme),
            ),
            // Balance card
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: BalanceCard(
                  balance: widget.wallet.balance,
                  currency: widget.wallet.currency,
                  animate: true,
                  onTap: () {
                    // Balance detail modal — placeholder
                  },
                ),
              ),
            ),
            // Quick actions
            SliverToBoxAdapter(
              child: _buildQuickActions(theme),
            ),
            // Split bill section
            SliverToBoxAdapter(
              child: _buildSplitBill(theme),
            ),
            // Divider
            SliverToBoxAdapter(
              child: const SizedBox(height: AppSpacing.sm),
            ),
            // Recent transactions header with tab bar
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Row(
                  children: [
                    Text(
                      'Recent activity',
                      style: AppTypography.heading2.copyWith(
                        color: AppColors.textOffWhite,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        // View all — placeholder
                      },
                      child: Text(
                        'See all',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.primaryGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _buildTransactionList(theme),
            ),
            // Bottom padding for nav bar
            const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(theme),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          // Small flat logo mark
          SizedBox(
            width: 36,
            height: 36,
            child: CustomPaint(
              painter: _SmallMarkPainter(
                color: AppColors.brandGradient,
                size: 36,
              ),
              child: const SizedBox.shrink(),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'PayFlex',
            style: AppTypography.heading1.copyWith(
              color: AppColors.textWhite,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          // User avatar + name
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(user: widget.user),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xs),
              decoration: BoxDecoration(
                color: AppColors.darkSurfaceAlt,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_outline,
                color: AppColors.textOffWhite,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            widget.user.name.split(' ').first,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textOffWhite,
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 300.ms)
        .slideY(begin: 0.02, end: 0.0, duration: 300.ms);
  }

  Widget _buildQuickActions(ThemeData theme) {
    final actions = [
      (icon: Icons.send_outlined, label: 'Send', action: widget.onSend),
      (icon: Icons.payments_outlined, label: 'Receive', action: widget.onReceive),
      (icon: Icons.credit_card_outlined, label: 'Pay', action: widget.onPay),
      (icon: Icons.add_circle_outline, label: 'Top up', action: widget.onTopUp),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: actions.map((a) {
          return Expanded(
            child: GestureDetector(
              onTap: a.action,
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.darkSurfaceAlt,
                      borderRadius:
                          BorderRadius.circular(AppRadius.sm),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.darkNavy.withOpacity(0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: Icon(
                      a.icon,
                      color: AppColors.textOffWhite,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    a.label,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textOffWhite,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    )
        .animate()
        .fadeIn(duration: 280.ms, delay: 180.ms)
        .slideY(begin: 0.03, end: 0.0, duration: 280.ms, delay: 180.ms);
  }

  Widget _buildSplitBill(ThemeData theme) {
    // Split bill progress: a ring filling in flat brand gradient as
    // each contributor's share lands, no glow pulse.
    final totalShares = 4.0;
    final collectedShares = 2.0;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: AppColors.darkSurfaceAlt,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Ring progress indicator
            SizedBox(
              width: 64,
              height: 64,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Background ring
                  CircularProgressIndicator(
                    value: 1.0,
                    strokeWidth: 4,
                    backgroundColor: AppColors.darkSurfaceAlt,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.textMutedDark),
                  ),
                  // Filled ring — flat brand gradient
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: CircularProgressIndicator(
                      value: collectedShares / totalShares,
                      strokeWidth: 4,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colorWithGradient(
                          AppColors.gradientStart,
                          AppColors.gradientEnd,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Split bill',
                    style: AppTypography.heading2.copyWith(
                      color: AppColors.textOffWhite,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Team lunch · 2 of 4 settled',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textMutedDark,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '\$${MoneyFormatter.formatNumber(collectedShares * 68.50 / 4)} collected',
                    style: AppTypography.body.copyWith(
                      color: AppColors.primaryGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 280.ms, delay: 280.ms)
        .slideY(begin: 0.03, end: 0.0, duration: 280.ms, delay: 280.ms);
  }

  Widget _buildTransactionList(ThemeData theme) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _transactions.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final t = _transactions[index];
        return ReceiptView(
          recipient: t.recipient,
          amount: t.amount,
          reference: t.reference,
          timestamp: t.timestamp,
          status: t.status,
          note: t.contributors != null
              ? 'Contributors: ${t.contributors!.join(", ")}'
              : null,
          isLight: false,
        );
      },
    );
  }

  Widget _buildBottomNav(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.md),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkNavy.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, -4),
            spreadRadius: 0,
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.home_outlined,
                activeIcon: Icons.home,
                label: 'Home',
                isSelected: true,
                onTap: () {},
              ),
              _NavItem(
                icon: Icons.card_membership_outlined,
                activeIcon: Icons.card_membership,
                label: 'Cards',
                onTap: () {},
              ),
              _NavItem(
                icon: Icons.account_balance_wallet_outlined,
                activeIcon: Icons.account_balance_wallet,
                label: 'Wallet',
                onTap: () {},
              ),
              _NavItem(
                icon: Icons.notifications_outlined,
                activeIcon: Icons.notifications,
                label: 'Alerts',
                onTap: () {},
              ),
              _NavItem(
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                label: 'Profile',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SettingsScreen(user: widget.user),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.isSelected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSelected ? activeIcon : icon,
            color: isSelected
                ? AppColors.primaryGreen
                : AppColors.textMutedDark,
            size: 22,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: isSelected
                  ? AppColors.primaryGreen
                  : AppColors.textMutedDark,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class Transaction {
  final String id;
  final String recipient;
  final double amount;
  final String reference;
  final DateTime timestamp;
  final ReceiptStatus status;
  final List<String>? contributors;

  const Transaction({
    required this.id,
    required this.recipient,
    required this.amount,
    required this.reference,
    required this.timestamp,
    required this.status,
    this.contributors,
  });
}

// Helper: create a Color that mimics a gradient midpoint.
// For ring indicators we use solid brand green as a placeholder;
// a real implementation would use gradient sweeps or canvas gradients.
Color colorWithGradient(Color start, Color end) {
  return AppColors.primaryGreen;
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
      ..strokeWidth = 1.8
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
