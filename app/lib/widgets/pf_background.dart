import 'package:flutter/material.dart';
import '../theme/payflex_tokens.dart';

/// ──────────────────────────────────────────────────────────────────────────
/// PfBackground — the brand waves wallpaper (assets/brand/payflex_bg*.png),
/// mounted ONCE behind every route via MaterialApp.builder. Screens make
/// their navy scaffold transparent to let it through; light "business"
/// surfaces stay opaque by design (brief §1: light chrome for forms, navy
/// chrome for wallet surfaces — the wallpaper only replaces navy).
///
/// Sizing for PC vs phone: the source art is landscape; on a tall phone
/// screen BoxFit.cover of the landscape file would crop most of the waves
/// away. So two sized variants ship and [PfBackground] picks by aspect:
///   • wide viewports (desktop/web/landscape) → payflex_bg.png (1536×1024)
///   • tall/narrow viewports (phones)         → payflex_bg_portrait.png
///     (a 512×1024 strip of the same art, pre-cropped so cover keeps the
///     bottom ribbon + dot matrix instead of the sides)
/// A subtle navy scrim keeps the art ambient — content always legible,
/// no hot spots behind cards, matching the "no glow" restraint rule.
///
/// Content lane (PC vs phone): the app is designed phone-first, so on
/// wide viewports the route content is centred in a [laneWidth] canvas
/// over the wallpaper instead of stretching edge-to-edge. Phones get the
/// full width. The constraint wraps the Navigator, so it applies to every
/// screen, dialog and bottom sheet — current and future — in one place.
/// ──────────────────────────────────────────────────────────────────────────
class PfBackground extends StatelessWidget {
  /// Max width of the centred content canvas on wide viewports (PC,
  /// tablet landscape). Inactive below this width — phones stay full-bleed.
  static const double laneWidth = 640;

  final Widget child;

  const PfBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final aspect = size.aspectRatio; // width / height
        // Phones in portrait sit well below 1.0 (e.g. 390/844 ≈ 0.46);
        // desktop windows and tablets sit at or above it.
        final asset = aspect < 0.8
            ? 'assets/brand/payflex_bg_portrait.png'
            : 'assets/brand/payflex_bg.png';

        return DecoratedBox(
          decoration: const BoxDecoration(color: PfColors.navy),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                asset,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                // If the asset is missing the DecoratedBox above already
                // renders the correct flat navy — nothing else to do.
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
              // Scrim: flat navy wash so lists/cards read over the waves.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      PfColors.navy.withValues(alpha: 0.42),
                      PfColors.navy.withValues(alpha: 0.18),
                      PfColors.navy.withValues(alpha: 0.50),
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
              // Content lane: full-bleed on phones, centred canvas on PC.
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: size.width > laneWidth ? laneWidth : double.infinity,
                  ),
                  child: child,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
