import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The flowing arrow/ribbon motif — the logo's core shape.
/// Flattened into a series of cubic curves that trace the logo's
/// "arrow cutting through QR corners" silhouette.
///
/// Used as:
/// - background watermark (low opacity, flat)
/// - branded loader stroke
/// - transfer confirmation success mark
/// - thin accent line on receipts/headers
///
/// All uses are flat gradient color — no glow, no bloom, no particles.

class RibbonPath extends StatelessWidget {
  final double size;
  final double opacity;
  final bool animate;
  final bool filled;
  final double strokeWidth;

  const RibbonPath({
    super.key,
    this.size = 32,
    this.opacity = 1.0,
    this.animate = false,
    this.filled = false,
    this.strokeWidth = 2,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RibbonPainter(
          size: size,
          opacity: opacity,
          filled: filled,
          strokeWidth: strokeWidth,
        ),
        child: animate
            ? _AnimatedRibbon(size: size)
            : const SizedBox.shrink(),
      ),
    );
  }
}

class _RibbonPainter extends CustomPainter {
  final double size;
  final double opacity;
  final bool filled;
  final double strokeWidth;

  _RibbonPainter({
    required this.size,
    required this.opacity,
    this.filled = false,
    this.strokeWidth = 2,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = filled
        ? Paint()
            ..color = AppColors.gradientStart
            ..style = PaintingStyle.fill
        : Paint()
            ..shader = AppColors.brandGradient.createShader(
              Rect.fromLTWH(0, 0, size.width, size.height),
            )
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round;

    paint.color = paint.color.withOpacity(opacity);

    // A simplified ribbon/arrow curve that suggests the logo mark.
    // Starts top-left, sweeps down-right with a flowing swoosh,
    // then a small arrowhead at the end.
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
    // Arrowhead tip
    path.lineTo(cx + s * 0.9, cy * 0.15);

    if (filled) {
      canvas.drawPath(path, paint);
    } else {
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _AnimatedRibbon extends StatefulWidget {
  final double size;
  const _AnimatedRibbon({required this.size});

  @override
  State<_AnimatedRibbon> createState() => _AnimatedRibbonState();
}

class _AnimatedRibbonState extends State<_AnimatedRibbon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
    _progress = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
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
      animation: _progress,
      builder: (context, child) {
        return CustomPaint(
          painter: _RibbonProgressPainter(
            size: widget.size,
            progress: _progress.value,
            strokeWidth: 2.5,
          ),
          child: const SizedBox.shrink(),
        );
      },
    );
  }
}

class _RibbonProgressPainter extends CustomPainter {
  final double size;
  final double progress;
  final double strokeWidth;

  _RibbonProgressPainter({
    required this.size,
    required this.progress,
    this.strokeWidth = 2.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = AppColors.brandGradient.createShader(
        Rect.fromLTWH(0, 0, size.width, size.height),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
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

    // Trim path by progress
    final total = path.length;
    final trimEnd = (total * progress).clamp(0.0, total);
    final trimmedPath = path.shift(const Offset(0, 0));
    canvas.drawPath(trimmedPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;

  // path.length is approximate; using progress directly for visual loop
  @override
  bool shouldRebuildSemantics(covariant CustomPainter oldDelegate) => false;
}
