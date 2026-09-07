import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../components/primary_button.dart';
import '../components/transfer_confirmation.dart';
import '../components/branded_loader.dart';
import '../components/receipt_view.dart';
import '../theme/money_formatter.dart';
import '../core/app_state.dart';

/// Transfer screen — send money.
///
/// Flow:
///   1. Amount input (flat, no glow, careful formatting)
///   2. Recipient selector (list/entry)
///   3. QR scan view (camera placeholder)
///   4. Confirm payment sheet — shared-element/Hero transition from
///      the QR frame, not a hard page cut
///   5. Transfer confirmation animation (ribbon draws itself, settles)
///
/// Motto: QR scan → confirm transition morphs the QR frame into the
/// confirm sheet via shared-element/Hero transition.
class TransferScreen extends StatefulWidget {
  final WalletState wallet;

  const TransferScreen({super.key, required this.wallet});

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen>
    with SingleTickerProviderStateMixin {
  final _amountKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _recipientController = TextEditingController();

  int _step = 0;
  bool _isScanning = false;
  bool _isConfirming = false;
  bool _showConfirmation = false;

  double _amount = 0.0;
  String _recipient = '';
  String _reference = '';
  DateTime _timestamp = DateTime.now();

  @override
  void dispose() {
    _amountController.dispose();
    _recipientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Send money'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Step indicator
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  _StepPill(
                    label: 'Amount',
                    isActive: _step >= 0,
                    isComplete: _step > 0,
                    isDark: isDark,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _StepPill(
                    label: 'Recipient',
                    isActive: _step >= 1,
                    isComplete: _step > 1,
                    isDark: isDark,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _StepPill(
                    label: 'Confirm',
                    isActive: _step >= 2,
                    isComplete: _step > 2,
                    isDark: isDark,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: _buildStepContent(isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepContent(bool isDark) {
    switch (_step) {
      case 0:
        return _buildAmountStep(isDark);
      case 1:
        return _buildRecipientStep(isDark);
      case 2:
        return _buildQRScanStep(isDark);
      case 3:
        return _buildConfirmStep(isDark);
      default:
        return _buildAmountStep(isDark);
    }
  }

  Widget _buildAmountStep(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How much do you want to send?',
            style: AppTypography.heading1.copyWith(
              color: isDark
                  ? AppColors.textWhite
                  : AppColors.textDark,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Form(
            key: _amountKey,
            child: TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true),
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Amount',
                hintText: '0.00',
                prefixText: '\$ ',
              ),
              validator: (v) {
                if (v == null || v.isEmpty) {
                  return 'Enter an amount';
                }
                final val = double.tryParse(v);
                if (val == null || val <= 0) {
                  return 'Enter a valid amount';
                }
                return null;
              },
              onFieldSubmitted: (v) {
                final val = double.tryParse(v);
                if (val != null && val > 0) {
                  setState(() {
                    _amount = val;
                    _step = 1;
                  });
                }
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Quick amount chips
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [10, 25, 50, 100].map((a) {
              final isSelected = _amount == a;
              return GestureDetector(
                onTap: () {
                  setState(() => _amount = a);
                  _amountController.text = a.toString();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primaryBlue
                        : AppColors.darkSurfaceAlt,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                  child: Text(
                    '\$$a',
                    style: AppTypography.body.copyWith(
                      color: isSelected
                          ? AppColors.textWhite
                          : AppColors.textOffWhite,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const Spacer(),
          // Balance footer
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurface
                        : AppColors.lightSurface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF2A3355)
                          : const Color(0xFFE0E0DC),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.account_balance_wallet_outlined,
                        color: AppColors.textMutedDark,
                        size: 18,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Your balance',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textMutedDark,
                              ),
                            ),
                            Text(
                              MoneyFormatter.format(
                                  widget.wallet.balance),
                              style: AppTypography.body.copyWith(
                                color: isDark
                                    ? AppColors.textOffWhite
                                    : AppColors.textDark,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Continue',
            onPressed: () {
              if (_amountKey.currentState!.validate()) {
                setState(() => _step = 1);
              }
            },
            icon: Icons.arrow_forward,
          ),
          const SizedBox(height: AppSpacing.md),
          TextButton(
            onTap: () {
              setState(() => _step = 2);
            },
            child: Text(
              'Scan QR instead',
              style: AppTypography.body.copyWith(
                color: AppColors.primaryGreen,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 300.ms)
        .slideY(begin: 0.03, end: 0.0, duration: 300.ms);
  }

  Widget _buildRecipientStep(bool isDark) {
    final isPicking = _recipient.isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Send to',
                style: AppTypography.heading2.copyWith(
                  color: isDark
                      ? AppColors.textWhite
                      : AppColors.textDark,
                ),
              ),
              const Spacer(),
              if (!isPicking)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _recipient = '';
                      _step = 1;
                    });
                  },
                  child: Text(
                    'Change',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.primaryGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (isPicking) ...[
            // Recipient entry — designed, not bare
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.lg,
              ),
              decoration: BoxDecoration(
                color: AppColors.darkSurface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: AppColors.darkSurfaceAlt,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.darkNavy.withOpacity(0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.darkSurfaceAlt,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person_add_outlined,
                      color: AppColors.textMutedDark,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Enter recipient',
                          style: AppTypography.body.copyWith(
                            color: isDark
                                ? AppColors.textOffWhite
                                : AppColors.textDark,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Name, email, or phone number',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textMutedDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Icon(
                    Icons.arrow_forward,
                    color: isDark
                        ? AppColors.textMutedDark
                        : AppColors.textMutedLight,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _recipientController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Recipient name',
                hintText: 'Full name',
              ),
              onFieldSubmitted: (v) {
                if (v.trim().isNotEmpty) {
                  setState(() {
                    _recipient = v.trim();
                    _step = 2;
                  });
                }
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'Use this recipient',
              onPressed: () {
                if (_recipientController.text.trim().isNotEmpty) {
                  setState(() {
                    _recipient = _recipientController.text.trim();
                    _step = 2;
                  });
                }
              },
              icon: Icons.check,
            ),
            const SizedBox(height: AppSpacing.md),
            TextButton(
              onTap: () {
                setState(() => _step = 0);
              },
              child: Text(
                'Go back',
                style: AppTypography.body.copyWith(
                  color: AppColors.textMutedDark,
                ),
              ),
            ),
          ] else ...[
            // Selected recipient preview
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.darkSurfaceAlt,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person_outline,
                      color: AppColors.primaryBlue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _recipient,
                          style: AppTypography.body.copyWith(
                            color: isDark
                                ? AppColors.textWhite
                                : AppColors.textDark,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'Will receive \$${MoneyFormatter.formatNumber(_amount)}',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textMutedDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.check_circle_outline,
                    color: AppColors.primaryGreen,
                    size: 20,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'Scan QR',
              onPressed: () {
                setState(() {
                  _isScanning = true;
                  _step = 2;
                });
              },
              icon: Icons.qr_code_scanner,
            ),
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(
              label: 'Confirm & send',
              onPressed: () {
                setState(() {
                  _isConfirming = true;
                  _reference =
                      MoneyFormatter.referenceNumber();
                  _timestamp = DateTime.now();
                  _step = 3;
                  Future.delayed(const Duration(milliseconds: 300), () {
                    if (mounted) {
                      setState(() {
                        _isConfirming = false;
                        _showConfirmation = true;
                      });
                    }
                  });
                });
              },
              icon: Icons.arrow_forward,
            ),
          ],
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 300.ms)
        .slideY(begin: 0.03, end: 0.0, duration: 300.ms);
  }

  Widget _buildQRScanStep(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        children: [
          const Spacer(flex: 1),
          // QR scan view — camera placeholder with flat frame
          GestureDetector(
            onTap: () {
              // Simulate scan success → confirm sheet via Hero/shared
              // transition on the QR frame, not a hard page cut.
              setState(() {
                _step = 3;
                _reference = MoneyFormatter.referenceNumber();
                _timestamp = DateTime.now();
                _isConfirming = true;
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (mounted) {
                    setState(() {
                      _isConfirming = false;
                      _showConfirmation = true;
                    });
                  }
                });
              });
            },
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                color: AppColors.darkSurface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: AppColors.primaryGreen.withOpacity(0.5),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.darkNavy.withOpacity(0.3),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Scan frame — dashed corner brackets (logo's QR-corner motif,
                  // just 4 corners, not scattered everywhere)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ScanFramePainter(
                        color: AppColors.primaryGreen,
                        cornerLength: 36,
                        gap: 18,
                      ),
                      child: const SizedBox.shrink(),
                    ),
                  ),
                  // Center icon
                  const Icon(
                    Icons.qr_code_scanner,
                    color: AppColors.primaryGreen,
                    size: 48,
                  ),
                  // Scan line animation
                  Positioned(
                    top: 40,
                    left: 40,
                    right: 40,
                    child: _ScanLine(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Position the QR code within the frame',
            style: AppTypography.body.copyWith(
              color: isDark
                  ? AppColors.textOffWhite
                  : AppColors.textDark,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Or tap to confirm the displayed code',
            style: AppTypography.caption.copyWith(
              color: AppColors.textMutedDark,
            ),
          ),
          const Spacer(flex: 1),
          PrimaryButton(
            label: 'Confirm & continue',
            onPressed: () {
              setState(() {
                _step = 3;
                _reference = MoneyFormatter.referenceNumber();
                _timestamp = DateTime.now();
                _isConfirming = true;
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (mounted) {
                    setState(() {
                      _isConfirming = false;
                      _showConfirmation = true;
                    });
                  }
                });
              });
            },
            icon: Icons.arrow_forward,
          ),
          const SizedBox(height: AppSpacing.md),
          TextButton(
            onTap: () {
              setState(() => _step = 1);
            },
            child: Text(
              'Enter recipient manually',
              style: AppTypography.body.copyWith(
                color: AppColors.textMutedDark,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 350.ms)
        .scale(begin: const Offset(0.96, 0.96), end: const Offset(1, 1),
            duration: 350.ms);
  }

  Widget _buildConfirmStep(bool isDark) {
    if (!_isConfirming && !_showConfirmation) {
      // Transition state: loading branded loader while preparing
      return Center(
        child: Column(
          children: [
            const BrandedLoader(size: 48),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Preparing transfer...',
              style: AppTypography.body.copyWith(
                color: isDark
                    ? AppColors.textOffWhite
                    : AppColors.textDark,
              ),
            ),
          ],
        ),
      );
    }

    if (_isConfirming) {
      return Center(
        child: Column(
          children: [
            const BrandedLoader(size: 48),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Sending...',
              style: AppTypography.body.copyWith(
                color: isDark
                    ? AppColors.textOffWhite
                    : AppColors.textDark,
              ),
            ),
          ],
        ),
      );
    }

    if (_showConfirmation) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            // Transfer confirmation animation — ribbon draws itself,
            // settles, flat gradient, no glow, no particles.
            // This is the emotional payoff moment.
            Center(
              child: TransferConfirmationAnimation(
                size: 140,
                duration: const Duration(milliseconds: 1000),
                onComplete: () {
                  // Mark as completed — update receipt status
                },
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            // Confirmation receipt
            ReceiptView(
              recipient: _recipient,
              amount: _amount,
              reference: _reference,
              timestamp: _timestamp,
              status: ReceiptStatus.completed,
              isLight: false,
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'Done',
              onPressed: () {
                Navigator.of(context).pop();
              },
              fullWidth: true,
              icon: Icons.check,
            ),
            const SizedBox(height: AppSpacing.md),
            TextButton(
              onTap: () {
                Navigator.of(context).pop();
              },
              child: Text(
                'Close',
                style: AppTypography.body.copyWith(
                  color: AppColors.textMutedDark,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Pre-confirm summary (before loading state kicks in)
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Confirm payment',
            style: AppTypography.heading1.copyWith(
              color: isDark
                  ? AppColors.textWhite
                  : AppColors.textDark,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Shared QR frame preview — this is the element that morphs
          // into the confirm sheet via Hero/shared transition.
          // In a real implementation, wrap this with Hero().
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              color: AppColors.darkSurface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: AppColors.primaryGreen.withOpacity(0.4),
                width: 2,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ScanFramePainter(
                      color: AppColors.primaryGreen,
                      cornerLength: 28,
                      gap: 14,
                    ),
                    child: const SizedBox.shrink(),
                  ),
                ),
                Text(
                  _reference,
                  style: AppTypography.mono.copyWith(
                    color: AppColors.primaryGreen,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkSurface
                  : AppColors.lightSurface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF2A3355)
                    : const Color(0xFFE0E0DC),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                _ConfirmRow(
                  label: 'Recipient',
                  value: _recipient,
                  isDark: isDark,
                ),
                const Divider(height: AppSpacing.md),
                _ConfirmRow(
                  label: 'Amount',
                  value: MoneyFormatter.format(_amount),
                  isDark: isDark,
                  isAmount: true,
                ),
                const Divider(height: AppSpacing.md),
                _ConfirmRow(
                  label: 'Reference',
                  value: _reference,
                  isDark: isDark,
                ),
                const Divider(height: AppSpacing.md),
                _ConfirmRow(
                  label: 'Fee',
                  value: '\$0.00',
                  isDark: isDark,
                  fee: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Notice
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppRadius.xs),
              border: Border.all(
                color: AppColors.primaryBlue.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 16,
                  color: AppColors.primaryBlue,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'This transfer is irreversible. Make sure the recipient and amount are correct.',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.primaryBlue,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Send \$${MoneyFormatter.formatNumber(_amount)}',
            onPressed: () {
              setState(() {
                _isConfirming = true;
                _reference = MoneyFormatter.referenceNumber();
                _timestamp = DateTime.now();
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (mounted) {
                    setState(() {
                      _isConfirming = false;
                      _showConfirmation = true;
                    });
                  }
                });
              });
            },
            icon: Icons.send,
            fullWidth: true,
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 350.ms)
        .slideY(begin: 0.03, end: 0.0, duration: 350.ms);
  }
}

class _StepPill extends StatelessWidget {
  final String label;
  final bool isActive;
  final bool isComplete;
  final bool isDark;

  const _StepPill({
    required this.label,
    required this.isActive,
    required this.isComplete,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: AppMotion.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: isComplete
            ? AppColors.primaryGreen.withOpacity(0.2)
            : isActive
                ? AppColors.primaryBlue.withOpacity(0.15)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(
          color: isComplete
              ? AppColors.primaryGreen.withOpacity(0.5)
              : isActive
                  ? AppColors.primaryBlue.withOpacity(0.4)
                  : Colors.transparent,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isComplete
                ? Icons.check
                : isActive
                    ? Icons.circle
                    : Icons.circle_outlined,
            size: 14,
            color: isComplete
                ? AppColors.primaryGreen
                : isActive
                    ? AppColors.primaryBlue
                    : isDark
                        ? AppColors.textMutedDark
                        : AppColors.textMutedLight,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: isComplete
                  ? AppColors.primaryGreen
                  : isActive
                      ? AppColors.primaryBlue
                      : isDark
                          ? AppColors.textMutedDark
                          : AppColors.textMutedLight,
              fontWeight: isComplete ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;
  final bool isAmount;
  final bool fee;

  const _ConfirmRow({
    required this.label,
    required this.value,
    required this.isDark,
    this.isAmount = false,
    this.fee = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: isDark
                  ? AppColors.textMutedDark
                  : AppColors.textMutedLight,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: AppTypography.body.copyWith(
              color: isAmount
                  ? AppColors.success
                  : fee
                      ? AppColors.success
                      : isDark
                          ? AppColors.textOffWhite
                          : AppColors.textDark,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanFramePainter extends CustomPainter {
  final Color color;
  final double cornerLength;
  final double gap;

  _ScanFramePainter({
    required this.color,
    required this.cornerRadius,
    this.cornerLength = 36,
    this.gap = 18,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    // 4 corners — QR-style brackets, logo motif
    // Top-left
    canvas.drawLine(Offset(gap, gap), Offset(gap, gap + cornerLength), paint);
    canvas.drawLine(
        Offset(gap, gap), Offset(gap + cornerLength, gap), paint);
    // Top-right
    canvas.drawLine(
        Offset(w - gap - cornerLength, gap), Offset(w - gap, gap), paint);
    canvas.drawLine(
        Offset(w - gap, gap), Offset(w - gap, gap + cornerLength), paint);
    // Bottom-left
    canvas.drawLine(Offset(gap, h - gap - cornerLength), Offset(gap, h - gap),
        paint);
    canvas.drawLine(Offset(gap, h - gap), Offset(gap + cornerLength, h - gap),
        paint);
    // Bottom-right
    canvas.drawLine(
        Offset(w - gap - cornerLength, h - gap), Offset(w - gap, h - gap), paint);
    canvas.drawLine(
        Offset(w - gap, h - gap - cornerLength), Offset(w - gap, h - gap), paint);
  }

  double cornerLength;

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _ScanLine extends StatefulWidget {
  @override
  State<_ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<_ScanLine>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _offset = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _offset,
      builder: (context, child) {
        return Container(
          height: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.transparent,
                AppColors.primaryGreen,
                Colors.transparent,
              ],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
          child: Align(
            alignment: Alignment.center,
            child: Container(
              width: 40,
              height: 2,
              decoration: BoxDecoration(
                color: AppColors.primaryGreen,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        );
      },
    );
  }
}
