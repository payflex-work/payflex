import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';

/// PayFlex navigation router.
/// Uses consistent fade-through transitions between major sections
/// rather than the default platform slide-in.
class PayFlexRouter {
  static const _curve = AppMotion.easeOut;
  static const _duration = AppMotion.pageTransition;

  static PageRoute<dynamic> page(Widget child, {bool fadeIn = true}) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) {
        return child;
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: AppMotion.easeOutExpo),
        );
        final offset = Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: animation, curve: AppMotion.easeOut),
        );

        var childWithOpacity = AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            return Opacity(
              opacity: opacity.value,
              child: child,
            );
          },
          child: child,
        );

        if (fadeIn) {
          childWithOpacity = SlideTransition(
            position: offset,
            child: childWithOpacity,
          );
        }

        return FadeTransition(
          opacity: opacity,
          child: childWithOpacity,
        );
      },
      transitionDuration: _duration,
      reverseTransitionDuration: _duration,
    );
  }

  /// Shared-element-like transition placeholder for QR → confirm.
  /// Animates opacity and scale of the shared QR frame widget.
  static Widget shared(QWidget shared, Widget target) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      transitionBuilder: (child, animation) {
        return ScaleTransition(
          scale: animation,
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
      child: target,
    );
  }
}

typedef QWidget = Widget;
