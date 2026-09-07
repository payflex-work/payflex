import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import 'brand_signature.dart';

/// Branded loader — the arrow/ribbon motif tracing itself in a loop.
/// Flat gradient stroke, no glow, no particles, no default spinner.
///
/// Usage: replace every CircularProgressIndicator with this.
class BrandedLoader extends StatefulWidget {
  final double size;
  final double strokeWidth;

  const BrandedLoader({
    super.key,
    this.size = 40,
    this.strokeWidth = 3,
  });

  @override
  State<BrandedLoader> createState() => _BrandedLoaderState();
}

class _BrandedLoaderState extends State<BrandedLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
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
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(
        painter: _LoaderPainter(
          progress: _progress.value,
          strokeWidth: widget.strokeWidth,
        ),
        child: const SizedBox.shrink(),
      ),
    );
  }
}

class _LoaderPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;

  _LoaderPainter({required this.progress, this.strokeWidth = 3});

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

    // Trace the ribbon path in a 360° loop, but keep it recognizable
    // as the arrow/ribbon shape rather than an arbitrary rotating arc.
    // We draw the full ribbon path, then progressively "sweep" a thick
    // stroke along it in a loop, creating a tracer effect.
    final path = _ribbonPath(size);

    // Use dash effect: draw a segment that moves along the path.
    final total = path.length;
    final dashLength = total * 0.28;
    final gapLength = total - dashLength;
    final dashOffset = (total * (1 - progress)) % total;

    paint.style = PaintingStyle.stroke;

    final dashPath = dashPath(path, dashLength, gapLength, dashOffset);
    canvas.drawPath(dashPath, paint);
  }

  Path _ribbonPath(Size size) {
    final s = size.width;
    final inset = s * 0.12;
    final cx = s / 2;
    final cy = s / 2;

    final path = Path();
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
    return path;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

