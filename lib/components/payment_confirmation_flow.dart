import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../theme/money_formatter.dart';
import 'branded_loader.dart';
import 'primary_button.dart';
import 'transfer_confirmation.dart';

enum PaymentStep { review, authenticate, submitting, success, failure }

/// PaymentResult payload for recording
class PaymentResultPayload {
  final bool success;
  final String transactionId;
  final String recipientName;
  final double amount;
  final String currency;
  final String? error;

  const PaymentResultPayload({
    required this.success,
    required this.transactionId,
    required this.recipientName,
    required this.amount,
    this.currency = 'NGN',
    this.error,
  });
}

/// Reusable payment confirmation flow sheet following PayFlex's 5-step banking standard.
class PaymentConfirmationFlowSheet extends StatefulWidget {
  final String title;
  final String recipientName;
  final String purpose;
  final double amount;
  final String currency;
  final double fee;
  final Future<bool> Function(String pin) onAuthenticate;
  final Future<PaymentResultPayload> Function() onSubmit;
  final Function(PaymentResultPayload result)? onRecord;

  const PaymentConfirmationFlowSheet({
    super.key,
    required this.title,
    required this.recipientName,
    required this.purpose,
    required this.amount,
    this.currency = 'NGN',
    this.fee = 0.0,
    required this.onAuthenticate,
    required this.onSubmit,
    this.onRecord,
  });

  static Future<PaymentResultPayload?> show({
    required BuildContext context,
    required String title,
    required String recipientName,
    required String purpose,
    required double amount,
    String currency = 'NGN',
    double fee = 0.0,
    required Future<bool> Function(String pin) onAuthenticate,
    required Future<PaymentResultPayload> Function() onSubmit,
    Function(PaymentResultPayload result)? onRecord,
  }) {
    return showModalBottomSheet<PaymentResultPayload>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PaymentConfirmationFlowSheet(
        title: title,
        recipientName: recipientName,
        purpose: purpose,
        amount: amount,
        currency: currency,
        fee: fee,
        onAuthenticate: onAuthenticate,
        onSubmit: onSubmit,
        onRecord: onRecord,
      ),
    );
  }

  @override
  State<PaymentConfirmationFlowSheet> createState() =>
      _PaymentConfirmationFlowSheetState();
}

class _PaymentConfirmationFlowSheetState
    extends State<PaymentConfirmationFlowSheet> {
  PaymentStep _currentStep = PaymentStep.review;
  final TextEditingController _pinController = TextEditingController();
  String? _authError;
  String? _submitError;
  PaymentResultPayload? _completedPayload;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  void _proceedToAuth() {
    setState(() {
      _authError = null;
      _currentStep = PaymentStep.authenticate;
    });
  }

  Future<void> _submitAuth() async {
    if (_pinController.text.length < 4) {
      setState(() {
        _authError = 'Please enter a valid 4-digit PIN';
      });
      return;
    }

    setState(() {
      _authError = null;
      _currentStep = PaymentStep.submitting;
    });

    try {
      final isAuthed = await widget.onAuthenticate(_pinController.text);
      if (!isAuthed) {
        setState(() {
          _authError = 'Incorrect PIN. Please try again.';
          _currentStep = PaymentStep.authenticate;
        });
        return;
      }

      // Proceed to submission
      final result = await widget.onSubmit();
      if (result.success) {
        setState(() {
          _completedPayload = result;
          _currentStep = PaymentStep.success;
        });
        widget.onRecord?.call(result);
      } else {
        setState(() {
          _submitError = result.error ?? 'Transaction declined by payment rail.';
          _currentStep = PaymentStep.failure;
        });
      }
    } catch (e) {
      setState(() {
        _submitError = e.toString().replaceAll('Exception: ', '');
        _currentStep = PaymentStep.failure;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Bottom sheet handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Header title
            Text(
              widget.title,
              style: AppTypography.heading1,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),

            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _buildStepContent(isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepContent(bool isDark) {
    switch (_currentStep) {
      case PaymentStep.review:
        return _buildReviewStep(isDark);
      case PaymentStep.authenticate:
        return _buildAuthenticateStep(isDark);
      case PaymentStep.submitting:
        return _buildSubmittingStep(isDark);
      case PaymentStep.success:
        return _buildSuccessStep(isDark);
      case PaymentStep.failure:
        return _buildFailureStep(isDark);
    }
  }

  // Step 1: Review
  Widget _buildReviewStep(bool isDark) {
    final total = widget.amount + widget.fee;
    return Column(
      key: const ValueKey('review'),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            children: [
              _summaryRow('Recipient', widget.recipientName, isDark),
              const Divider(height: AppSpacing.lg),
              _summaryRow('Purpose', widget.purpose, isDark),
              const Divider(height: AppSpacing.lg),
              _summaryRow(
                'Amount',
                MoneyFormatter.format(widget.amount, currency: widget.currency),
                isDark,
              ),
              const Divider(height: AppSpacing.lg),
              _summaryRow(
                'Transaction Fee',
                widget.fee == 0 ? 'FREE (₦0.00)' : MoneyFormatter.format(widget.fee, currency: widget.currency),
                isDark,
              ),
              const Divider(height: AppSpacing.lg),
              _summaryRow(
                'Total Deduction',
                MoneyFormatter.format(total, currency: widget.currency),
                isDark,
                isBold: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(
          label: 'Confirm Payment',
          fullWidth: true,
          onPressed: _proceedToAuth,
        ),
      ],
    );
  }

  // Step 2: Authenticate
  Widget _buildAuthenticateStep(bool isDark) {
    return Column(
      key: const ValueKey('auth'),
      children: [
        Text(
          'Enter 4-Digit Security PIN',
          style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Re-confirming payment of ${MoneyFormatter.format(widget.amount + widget.fee, currency: widget.currency)} to ${widget.recipientName}',
          style: AppTypography.caption,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _pinController,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          textAlign: TextAlign.center,
          style: AppTypography.heading1.copyWith(letterSpacing: 12),
          decoration: InputDecoration(
            hintText: '••••',
            counterText: '',
            errorText: _authError,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            Expanded(
              child: SecondaryButton(
                label: 'Back',
                onPressed: () {
                  setState(() {
                    _currentStep = PaymentStep.review;
                  });
                },
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: PrimaryButton(
                label: 'Authorize',
                fullWidth: true,
                onPressed: _submitAuth,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Step 3: Submitting
  Widget _buildSubmittingStep(bool isDark) {
    return Column(
      key: const ValueKey('submitting'),
      children: [
        const SizedBox(height: AppSpacing.lg),
        const BrandedLoader(size: 60, strokeWidth: 4),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Signing & Processing Payment...',
          style: AppTypography.heading2,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Submitting signed payload to settlement network',
          style: AppTypography.caption,
        ),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }

  // Step 4: Success
  Widget _buildSuccessStep(bool isDark) {
    return Column(
      key: const ValueKey('success'),
      children: [
        TransferConfirmationAnimation(
          size: 100,
          onComplete: () {},
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Payment Successful!',
          style: AppTypography.heading1.copyWith(color: AppColors.success),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Transferred ${MoneyFormatter.format(widget.amount, currency: widget.currency)} to ${widget.recipientName}',
          style: AppTypography.bodySmall,
          textAlign: TextAlign.center,
        ),
        if (_completedPayload != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Ref ID: ${_completedPayload!.transactionId}',
            style: AppTypography.mono.copyWith(fontSize: 12),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(
          label: 'Done',
          fullWidth: true,
          onPressed: () {
            Navigator.of(context).pop(_completedPayload);
          },
        ),
      ],
    );
  }

  // Step 4: Failure
  Widget _buildFailureStep(bool isDark) {
    return Column(
      key: const ValueKey('failure'),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.error.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.error_outline, color: AppColors.error, size: 48),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Payment Failed',
          style: AppTypography.heading1.copyWith(color: AppColors.error),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _submitError ?? 'Transaction declined. Please check details and retry.',
          style: AppTypography.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            Expanded(
              child: SecondaryButton(
                label: 'Cancel',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: PrimaryButton(
                label: 'Retry',
                fullWidth: true,
                onPressed: _proceedToAuth,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String value, bool isDark, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
          ),
        ),
        Text(
          value,
          style: isBold
              ? AppTypography.heading2.copyWith(color: AppColors.primaryGreen)
              : AppTypography.body.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
