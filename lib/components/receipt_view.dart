import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/money_formatter.dart';
import 'brand_signature.dart';

/// An official-feeling receipt card.
///
/// Hierarchy:
///   [small flat logo mark]    → PayFlex wordmark area
///   Reference number
///   Date / time
///   Amount (large, primary)
///   Status badge
///
/// Never a wall of raw JSON-looking fields. Never glowing text.
class ReceiptView extends StatelessWidget {
  final String recipient;
  final double amount;
  final String reference;
  final DateTime timestamp;
  final ReceiptStatus status;
  final String? note;
  final bool isLight;

  const ReceiptView({
    super.key,
    required this.recipient,
    required this.amount,
    required this.reference,
    required this.timestamp,
    required this.status,
    this.note,
    this.isLight = false,
  });

  Color get _surfaceColor =>
      isLight ? AppColors.lightSurface : AppColors.darkSurface;
  Color get _textColor =>
      isLight ? AppColors.textDark : AppColors.textOffWhite;
  Color get _mutedColor =>
      isLight ? AppColors.textMutedLight : AppColors.textMutedDark;
  Color get _borderColor =>
      isLight ? const Color(0xFFE0E0DC) : const Color(0xFF2A3355);

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (status) {
      ReceiptStatus.completed => AppColors.success,
      ReceiptStatus.pending => AppColors.warning,
      ReceiptStatus.failed => AppColors.error,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: _borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: (isLight ? AppColors.lightBg : AppColors.darkNavy)
                .withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: small flat logo mark + reference
          Row(
            children: [
              // Small flat ribbon mark
              SizedBox(
                width: 28,
                height: 28,
                child: CustomPaint(
                  painter: _SmallMarkPainter(
                    color: AppColors.brandGradient,
                    size: 28,
                  ),
                  child: const SizedBox.shrink(),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PayFlex receipt',
                      style: AppTypography.bodySmall.copyWith(
                        color: _mutedColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      reference,
                      style: AppTypography.mono.copyWith(
                        color: _mutedColor,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatDate(timestamp),
                    style: AppTypography.caption.copyWith(
                      color: _mutedColor,
                    ),
                  ),
                  Text(
                    _formatTime(timestamp),
                    style: AppTypography.caption.copyWith(
                      color: _mutedColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(),
          const SizedBox(height: AppSpacing.md),
          // Recipient
          Row(
            children: [
              const Icon(
                Icons.person_outline,
                size: 18,
                color: AppColors.textMutedDark,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  recipient,
                  style: AppTypography.body.copyWith(
                    color: _textColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Amount — large, primary, hierarchy anchor
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Amount sent',
                style: AppTypography.caption.copyWith(
                  color: _mutedColor,
                ),
              ),
              Text(
                MoneyFormatter.format(amount),
                style: AppTypography.amountLarge.copyWith(
                  color: statusColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Status badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _statusIcon,
                      size: 14,
                      color: statusColor,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      status.name.toUpperCase(),
                      style: AppTypography.caption.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                'Add to digital wallet',
                style: AppTypography.bodySmall.copyWith(
                  color: _mutedColor,
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              note!,
              style: AppTypography.bodySmall.copyWith(
                color: _mutedColor,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  IconData get _statusIcon => switch (status) {
        ReceiptStatus.completed => Icons.check_circle_outline,
        ReceiptStatus.pending => Icons.pending_outlined,
        ReceiptStatus.failed => Icons.error_outline,
      };

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

enum ReceiptStatus { completed, pending, failed }

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
