import 'package:flutter/material.dart';
import '../../services/local_user_store.dart';
import '../../theme/payflex_tokens.dart';
import '../../theme/payflex_theme.dart';
import '../../widgets/pf_brand_poster.dart';
import '../../widgets/pf_buttons.dart';
import 'create_user_screen.dart';

/// ──────────────────────────────────────────────────────────────────────────
/// Intro carousel — the first thing a brand-new user sees, before account
/// creation. Three pages, each anchored by the approved brand poster
/// (app icon, wordmark, "MORE CONTROL. MORE POSSIBILITIES.", the four
/// pillars):
///   1. The poster itself — the brand moment, verbatim.
///   2. What PayFlex does — the four pillars, in the app's own voice.
///   3. How the money is kept safe — the on-device key + PIN promise.
///
/// Shown once per install (LocalUserStore.introSeen), skipped on every
/// later launch. Motion is restrained per design brief §2: ease-out
/// fades/translates only, no bounce, no glow.
/// ──────────────────────────────────────────────────────────────────────────
class IntroScreen extends StatefulWidget {
  final LocalUserStore store;
  const IntroScreen({super.key, required this.store});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  static const _pages = _IntroPage.all;

  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _index == _pages.length - 1;

  Future<void> _finish() async {
    await widget.store.setIntroSeen();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const CreateUserScreen()),
    );
  }

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: PfMotion.base,
      curve: PfMotion.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: PayFlexTheme.dark,
      child: Scaffold(
        backgroundColor: Colors.transparent, // reveal PfBackground waves
        body: SafeArea(
          child: Column(
            children: [
              // Skip — quiet, top-right, always reachable.
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: _finish,
                  style: TextButton.styleFrom(
                    foregroundColor: PfColors.onNavyMuted,
                  ),
                  child: const Text('Skip'),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => _IntroPageView(page: _pages[i]),
                ),
              ),
              // Page dots.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pages.length, (i) {
                  final active = i == _index;
                  return AnimatedContainer(
                    duration: PfMotion.fast,
                    curve: PfMotion.easeOut,
                    width: active ? 22 : 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(PfRadius.pill),
                      gradient: active ? PfGradient.tickDark : null,
                      color: active
                          ? null
                          : PfColors.onNavyMuted.withValues(alpha: 0.3),
                    ),
                  );
                }),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  PfSpace.xl, PfSpace.lg, PfSpace.xl, PfSpace.xxl,
                ),
                child: Row(
                  children: [
                    if (!_isLast) ...[
                      TextButton(
                        onPressed: _finish,
                        style: TextButton.styleFrom(
                          foregroundColor: PfColors.onNavyMuted,
                        ),
                        child: const Text('Skip'),
                      ),
                      const Spacer(),
                    ],
                    Expanded(
                      child: PfPrimaryButton(
                        label: _isLast ? "Let's get started" : 'Next',
                        icon: _isLast ? Icons.arrow_forward_rounded : null,
                        onPressed: _next,
                        height: 52,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One carousel page: poster hero on top, copy below.
class _IntroPageView extends StatelessWidget {
  final _IntroPage page;
  const _IntroPageView({required this.page});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // The poster keeps its landscape shape — cap it by height so the
      // copy below always survives on small screens.
      final posterHeight = (constraints.maxHeight * 0.46)
          .clamp(180.0, 300.0)
          .toDouble();

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: PfSpace.xl),
        child: Column(
          children: [
            SizedBox(
              height: posterHeight,
              // Pages 2–3 soften the art (blurred, no veil) so it reads as
              // ambient brand texture on navy while the copy leads.
              child: PfBrandPoster(
                width: double.infinity,
                blurred: page.blurPoster,
              ),
            ),
            const SizedBox(height: PfSpace.xl),
            Text(
              page.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: PfColors.onNavy,
                fontSize: 23,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                height: 1.15,
              ),
            ),
            const SizedBox(height: PfSpace.md),
            Text(
              page.body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: PfColors.onNavyMuted,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _IntroPage {
  final String title;
  final String body;
  // Pages 2–3 use the art softly defocused (no veil) as ambient brand
  // texture; page 1 shows the poster verbatim.
  final bool blurPoster;

  const _IntroPage({
    required this.title,
    required this.body,
    this.blurPoster = false,
  });

  static const all = <_IntroPage>[
    // 1 — the brand moment, verbatim from the approved art.
    _IntroPage(
      title: 'More control. More possibilities.',
      body:
          'PayFlex is your wallet, savings and everyday money moves in one '
          'app — built to move the way you do.',
    ),
    // 2 — the four pillars, in app voice (mirrors the poster strip).
    _IntroPage(
      title: 'Send, save, spend, grow — together',
      body:
          'Send money instantly, stash savings toward goals, spend freely '
          'with your card, and grow with agents and community savings.',
      blurPoster: true,
    ),
    // 3 — the security promise (matches Settings' security posture).
    _IntroPage(
      title: 'Your keys stay yours',
      body:
          'Your wallet key never leaves this device, and every payment is '
          'signed with your 6-digit PIN. Safe, fast, global.',
      blurPoster: true,
    ),
  ];
}
