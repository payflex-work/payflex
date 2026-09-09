import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../theme/payflex_tokens.dart';

/// The approved brand poster (assets/brand/payflex_intro.png): the PayFlex
/// app icon, wordmark, tagline "MORE CONTROL. MORE POSSIBILITIES." and the
/// four-pillar strip (SEND MONEY / SAVE MORE / SPEND FREELY / GROW
/// TOGETHER) on flowing navy/aurora art.
///
/// It is the shared hero for the intro carousel and the About page so the
/// brand moment is identical in both places.
///
/// Variants:
///  • default — the poster verbatim, on either surface.
///  • [blurred] — soft defocus, no veil: ambient brand texture for use
///    on the navy surfaces (intro pages 2–3) where the copy below carries
///    the message and the art shouldn't compete.
///  • [tinted] — the light-surface variant: the navy art defocused and
///    lifted onto the off-white paper with a sharp copy re-centred on
///    top, so it sits inside light forms without an ink-black hole
///    (tokens rule: the gradient is the one strong colour move — a
///    full-bleed dark poster inside a light screen would fight that).
class PfBrandPoster extends StatelessWidget {
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius borderRadius;
  final bool blurred;
  final bool tinted;

  const PfBrandPoster({
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = const BorderRadius.all(Radius.circular(PfRadius.lg)),
    this.blurred = false,
    this.tinted = false,
  });

  @override
  Widget build(BuildContext context) {
    final image = ClipRRect(
      borderRadius: borderRadius,
      child: Image.asset(
        'assets/brand/payflex_intro.png',
        width: width,
        height: height,
        fit: fit,
        // The poster carries the brand moment on its own; if the asset is
        // missing (e.g. a clean checkout without `flutter pub get`), fall
        // back to the code-drawn mark on navy so the layout never breaks.
        // AspectRatio keeps the poster's 3:2 box even with no explicit
        // height (e.g. inside a ListView).
        errorBuilder: (_, __, ___) => AspectRatio(
          aspectRatio: 1536 / 1024,
          child: Container(
            width: width,
            height: height,
            color: PfColors.navy,
            alignment: Alignment.center,
            child: const PfPosterFallbackMark(),
          ),
        ),
      ),
    );

    if (!blurred && !tinted) return image;

    // Ambient defocus for dark surfaces — the flowing waves read as
    // texture; the poster's own small type melts away.
    if (!tinted) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: image,
        ),
      );
    }

    // Light-surface variant: defocused navy art lifted onto the light
    // paper, with a sharp copy re-centred so the icon + wordmark read.
    return ClipRRect(
      borderRadius: borderRadius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: image,
          ),
          ColoredBox(
            color: PfColors.offWhite.withValues(alpha: 0.55),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(26),
              child: Image.asset(
                'assets/brand/payflex_intro.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const PfPosterFallbackMark(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Code-drawn fallback: the ribbon mark centred on the poster navy, so a
/// missing asset still reads as PayFlex.
class PfPosterFallbackMark extends StatelessWidget {
  final double size;
  const PfPosterFallbackMark({super.key, this.size = 96});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PosterFallbackPainter(),
      ),
    );
  }
}

class _PosterFallbackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shader = PfGradient.primary.createShader(rect);

    // Rounded container echoing the logo tile.
    final tile = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: rect.center,
        width: size.width * 0.52,
        height: size.height * 0.52,
      ),
      Radius.circular(size.shortestSide * 0.14),
    );
    canvas.drawRRect(
      tile,
      Paint()
        ..shader = shader
        ..isAntiAlias = true,
    );

    // Arrow motif: ribbon stroke + arrowhead, in 100-space like PfMark.
    final markRect = Rect.fromCenter(
      center: rect.center,
      width: size.shortestSide * 0.62,
      height: size.shortestSide * 0.62,
    );
    canvas.save();
    canvas.translate(markRect.left, markRect.top);
    canvas.scale(markRect.width / 100, markRect.height / 100);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    final ribbon = Path()
      ..moveTo(20, 86)
      ..cubicTo(10, 48, 36, 60, 63, 33);
    canvas.drawPath(ribbon, paint);

    const apex = Offset(84, 20);
    const baseCenter = Offset(65.6, 38.4);
    const halfBase = 13.5;
    const perp = Offset(0.707, 0.707);
    final f1 = baseCenter + perp * halfBase;
    final f2 = baseCenter - perp * halfBase;
    canvas.drawPath(
      Path()
        ..moveTo(apex.dx, apex.dy)
        ..lineTo(f1.dx, f1.dy)
        ..lineTo(f2.dx, f2.dy)
        ..close(),
      Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.white,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PosterFallbackPainter old) => false;
}
