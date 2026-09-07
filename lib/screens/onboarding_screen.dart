import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../components/primary_button.dart';
import '../core/app_state.dart';

/// Onboarding / KYC flow.
///
/// Principles:
///   - One action per screen
///   - Clear step progress "Step X of 5"
///   - Encouraging micro-copy — this is the part users trust least
///   - Designed empty/error states — never bare "No data" or unstyled
///     red error box
///   - Flat, premium, no glow
class OnboardingScreen extends StatefulWidget {
  final User? existingUser;
  final Function(User) onComplete;

  const OnboardingScreen({
    super.key,
    this.existingUser,
    required this.onComplete,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  int _currentStep = 0;
  final int _totalSteps = 5;

  // Step state
  String? _selectedTier;
  VerificationStatus _verificationStatus = VerificationStatus.pending;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Step progress indicator
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        'Welcome',
                        style: AppTypography.heading1.copyWith(
                          color: isDark
                              ? AppColors.textWhite
                              : AppColors.textDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Step ${_currentStep + 1} of $_totalSteps',
                        style: AppTypography.bodySmall.copyWith(
                          color: isDark
                              ? AppColors.textMutedDark
                              : AppColors.textMutedLight,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _buildStepDots(isDark),
                ],
              ),
            ),
            // Step content
            Expanded(
              child: _buildStepContent(isDark),
            ),
            // Bottom actions
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.lg,
              ),
              child: Row(
                children: [
                  if (_currentStep > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() => _currentStep--),
                        child: Text(
                          'Back',
                          style: AppTypography.body.copyWith(
                            color: isDark
                                ? AppColors.textOffWhite
                                : AppColors.textDark,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: AppSpacing.xl),
                  Expanded(
                    flex: _currentStep < _totalSteps - 1 ? 2 : 3,
                    child: PrimaryButton(
                      label: _currentStep < _totalSteps - 1
                          ? 'Continue'
                          : 'Finish setup',
                      onPressed: _handleNext,
                      icon: _currentStep < _totalSteps - 1
                          ? Icons.arrow_forward
                          : Icons.check,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepDots(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_totalSteps, (i) {
        final isActive = i <= _currentStep;
        final isComplete = i < _currentStep;
        return GestureDetector(
          onTap: i < _currentStep
              ? () => setState(() => _currentStep = i)
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: AppMotion.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: 28,
            height: 4,
            decoration: BoxDecoration(
              color: isComplete
                  ? AppColors.primaryGreen
                  : isActive
                      ? AppColors.primaryBlue
                      : AppColors.darkSurfaceAlt,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildStepContent(bool isDark) {
    switch (_currentStep) {
      case 0:
        return _buildWelcomeStep(isDark);
      case 1:
        return _buildNameStep(isDark);
      case 2:
        return _buildContactStep(isDark);
      case 3:
        return _buildTierStep(isDark);
      case 4:
        return _buildKYCStep(isDark);
      default:
        return _buildWelcomeStep(isDark);
    }
  }

  Widget _buildWelcomeStep(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Spacer(flex: 1),
          // Flat ribbon logo mark
          SizedBox(
            width: 64,
            height: 64,
            child: CustomPaint(
              painter: _SmallMarkPainter(
                color: AppColors.brandGradient,
                size: 64,
              ),
              child: const SizedBox.shrink(),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Your money, your way.',
            style: AppTypography.heading1.copyWith(
              color: isDark
                  ? AppColors.textWhite
                  : AppColors.textDark,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Fast, low-cost transfers. No hidden fees. No paperwork feel.',
            style: AppTypography.body.copyWith(
              color: isDark
                  ? AppColors.textOffWhite
                  : AppColors.textDark,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }

  Widget _buildNameStep(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What should we call you?',
            style: AppTypography.heading2.copyWith(
              color: isDark
                  ? AppColors.textWhite
                  : AppColors.textDark,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Form(
            key: _formKey,
            child: TextFormField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Full name',
                hintText: 'Enter your legal name',
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Please enter your name' : null,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'This will appear on your receipts and verification badge.',
            style: AppTypography.bodySmall.copyWith(
              color: isDark
                  ? AppColors.textMutedDark
                  : AppColors.textMutedLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactStep(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How can we reach you?',
            style: AppTypography.heading2.copyWith(
              color: isDark
                  ? AppColors.textWhite
                  : AppColors.textDark,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'you@example.com',
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Email is required';
                    if (!v.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone number',
                    hintText: '+1 555 000 0000',
                    prefixText: '+1  ',
                  ),
                  validator: (v) {
                    if (v == null || v.length < 7) {
                      return 'Enter a valid phone number';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.darkSurfaceAlt.withOpacity(0.5),
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 16,
                  color: AppColors.textMutedDark,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Your details are encrypted and never shared without your consent.',
                    style: AppTypography.bodySmall.copyWith(
                      color: isDark
                          ? AppColors.textMutedDark
                          : AppColors.textMutedLight,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTierStep(bool isDark) {
    final tiers = [
      (
        key: AccountTier.basic,
        label: 'Basic',
        desc: 'Free. Send & receive up to 2,000/month.',
        features: ['Free transfers up to \$2,000/mo', 'Standard exchange rates', 'Email support'],
        highlight: false,
      ),
      (
        key: AccountTier.standard,
        label: 'Standard',
        desc: 'Most popular. Higher limits, faster transfers.',
        features: ['Up to \$20,000/mo', 'Priority support', 'Multi-currency wallet'],
        highlight: true,
      ),
      (
        key: AccountTier.premium,
        label: 'Premium',
        desc: 'For power users. Dedicated support, higher limits.',
        features: ['Up to \$100,000/mo', 'Dedicated account manager', 'Custom rate locks'],
        highlight: false,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose your tier',
            style: AppTypography.heading2.copyWith(
              color: isDark
                  ? AppColors.textWhite
                  : AppColors.textDark,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'You can upgrade later. No commitment required.',
            style: AppTypography.bodySmall.copyWith(
              color: isDark
                  ? AppColors.textMutedDark
                  : AppColors.textMutedLight,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          ...tiers.map((t) => _buildTierCard(t, isDark)).toList(),
        ],
      ),
    );
  }

  Widget _buildTierCard((AccountTier key, String label, String desc,
      List<String> features, bool highlight) tier, bool isDark) {
    final isSelected = _selectedTier == tier.key;
    return GestureDetector(
      onTap: () => setState(() => _selectedTier = tier.key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: AppMotion.easeOut,
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.brandGradient
              : AppColors.darkSurface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryGreen
                : AppColors.darkSurfaceAlt,
            width: 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.darkNavy.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tier.label,
                        style: AppTypography.heading2.copyWith(
                          color: isSelected
                              ? AppColors.textWhite
                              : AppColors.textOffWhite,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        tier.desc,
                        style: AppTypography.bodySmall.copyWith(
                          color: isSelected
                              ? AppColors.textWhite.withOpacity(0.85)
                              : AppColors.textMutedDark,
                        ),
                      ),
                    ],
                  ),
                ),
                if (tier.highlight)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreen.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    child: Text(
                      'Popular',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.primaryGreen,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ...tier.features.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 14,
                        color: isSelected
                            ? AppColors.textWhite.withOpacity(0.8)
                            : AppColors.primaryGreen,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        f,
                        style: AppTypography.bodySmall.copyWith(
                          color: isSelected
                              ? AppColors.textWhite.withOpacity(0.8)
                              : AppColors.textOffWhite,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildKYCStep(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Almost done — quick verification',
            style: AppTypography.heading2.copyWith(
              color: isDark
                  ? AppColors.textWhite
                  : AppColors.textDark,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'This helps us keep your account secure and compliant.',
            style: AppTypography.bodySmall.copyWith(
              color: isDark
                  ? AppColors.textMutedDark
                  : AppColors.textMutedLight,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Designed empty state — "Upload ID" with helpful copy, not
          // a bare "No data" or unstyled red error box.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.darkSurface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: AppColors.darkSurfaceAlt,
                width: 1.5,
                style: BorderStyle.solid,
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
            child: Column(
              children: [
                // Placeholder upload area with flat icon and clear copy
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.darkSurfaceAlt,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.camera_alt_outlined,
                    color: AppColors.textMutedDark,
                    size: 24,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Tap to upload government-issued ID',
                  style: AppTypography.body.copyWith(
                    color: isDark
                        ? AppColors.textOffWhite
                        : AppColors.textDark,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Recommended: passport or national ID. We accept JPEG, PNG, up to 5MB.',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textMutedDark,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.md),
                TextButton(
                  onPressed: () {
                    // Simulate submission for demo — normally would
                    // trigger file picker and upload.
                    setState(() {
                      _verificationStatus = VerificationStatus.verifying;
                    });
                    Future.delayed(const Duration(seconds: 2), () {
                      if (mounted) {
                        setState(() {
                          _verificationStatus = VerificationStatus
                              .verified;
                        });
                      }
                    });
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primaryGreen,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                  ),
                  child: Text(
                    'Use sample verification',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.primaryGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_verificationStatus == VerificationStatus.verifying) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withOpacity(0.12),
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      backgroundColor: AppColors.primaryBlue.withOpacity(0.2),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.primaryBlue),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Verifying your ID...',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (_verificationStatus == VerificationStatus.verified) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.12),
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: AppColors.success,
                    size: 18,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Verified ✓',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _handleNext() {
    switch (_currentStep) {
      case 0:
        setState(() => _currentStep++);
        break;
      case 1:
        if (!_formKey.currentState!.validate()) break;
        setState(() => _currentStep++);
        break;
      case 2:
        if (!_formKey.currentState!.validate()) break;
        setState(() => _currentStep++);
        break;
      case 3:
        if (_tierSelected()) {
          setState(() => _currentStep++);
        }
        break;
      case 4:
        // Create user and complete onboarding
        final user = User(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          verification: _verificationStatus,
          tier: _selectedTier ?? AccountTier.basic,
        );
        widget.onComplete(user);
        break;
    }
  }

  bool _tierSelected() {
    if (_selectedTier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a tier to continue'),
          backgroundColor: AppColors.warning,
        ),
      );
      return false;
    }
    return true;
  }
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
