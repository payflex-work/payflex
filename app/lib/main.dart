import 'package:flutter/material.dart';
import 'config/env.dart';
import 'services/local_user_store.dart';
import 'services/api_client.dart';
import 'services/session_manager.dart';
import 'services/wallet_service.dart';
import 'theme/payflex_tokens.dart';
import 'theme/payflex_theme.dart';
import 'widgets/pf_background.dart';
import 'widgets/pf_mark.dart';
import 'widgets/pf_motion.dart';
import 'screens/onboarding/create_user_screen.dart';
import 'screens/onboarding/intro_screen.dart';
import 'screens/unlock_screen.dart';
import 'screens/wallet_home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Env.assertSafeConfig(); // release builds must not target http:// (see env.dart)
  // The persisted dark/light choice (default: dark). Unawaited on
  // purpose: PfAppearance.mode defaults to dark, the MaterialApp is a
  // ValueListenableBuilder over it, so when the pref resolves the UI
  // simply rebuilds. Blocking first paint on a SharedPreferences disk
  // read here was measurable cold-start cost for zero visible benefit —
  // worst case is one dark-first frame before a stored 'light' lands.
  PfAppearance.init().ignore();
  runApp(const PayFlexApp());
}

class PayFlexApp extends StatelessWidget {
  const PayFlexApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: PfAppearance.mode,
      builder: (context, mode, _) => MaterialApp(
        title: 'PayFlex',
        debugShowCheckedModeBanner: false,
        theme: PayFlexTheme.light,
        darkTheme: PayFlexTheme.dark,
        themeMode: mode,
        // The brand waves wallpaper lives ONCE behind every route:
        // MaterialApp.builder wraps the Navigator, so all screens —
        // current and future — sit on the same ambient art without each
        // Scaffold having to paint it. Opaque scaffolds (light forms,
        // dialogs) simply cover it; transparent navy scaffolds reveal it.
        builder: (context, child) => PfBackground(
          child: child ?? const SizedBox.shrink(),
        ),
        // One consistent restrained transition for every route (design
        // brief §2, item 4) — configured per-theme in payflex_theme.dart.
        home: const _StartupGate(),
      ),
    );
  }
}

/// Decides, once at launch, whether we already have a local PayFlex user
/// (skip straight to the wallet) or need to run creation from scratch.
/// This is the app-side half of "never recreate a user on relaunch" —
/// the backend enforces it too, but checking here avoids even attempting
/// the call.
class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate>
    with SingleTickerProviderStateMixin {
  final _store = LocalUserStore();
  final _api = ApiClient();
  late final AnimationController _brandBeat;

  @override
  void initState() {
    super.initState();
    // The splash mark draws once over 1250ms; hold the launch surface a
    // beat past that (plus a fade) so the brand moment always completes,
    // even when the startup decision resolves in tens of milliseconds.
    // This is a deliberately timed beat, not artificial lag: the decision
    // work below runs in parallel with it.
    _brandBeat = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1750),
    )..forward();
    _decide();
  }

  /// Replaces the splash with [screen], but never before the brand beat
  /// has finished playing — every exit from the splash funnels through
  /// here, so the mark always gets to land no matter how fast the
  /// decision storage reads resolve.
  Future<void> _go(Widget screen) async {
    await _brandBeat.forward().orCancel;
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  Future<void> _decide() async {
    final appUserId = await _store.getAppUserId();
    if (!mounted) return;
    if (appUserId == null) {
      // First-run (or post-sign-out): run the intro carousel once before
      // account creation — it only gates a brand-new start, never the
      // resume/PIN paths below.
      final seenIntro = await _store.hasSeenIntro();
      if (!mounted) return;
      if (!seenIntro) {
        await _go(IntroScreen(store: _store));
      } else {
        await _go(const CreateUserScreen());
      }
      return;
    }

    // Every protected route now needs an access token — try to resume
    // silently from a persisted refresh token first (no PIN prompt) before
    // falling back to a PIN-triggered login. See services/session_manager.dart.
    final restored = await SessionManager.tryRestoreSession();
    if (restored) {
      try {
        final user = await _api.getUser(appUserId);
        if (!mounted) return;
        await _go(WalletHomeScreen(user: user));
        return;
      } catch (_) {
        // Falls through to the PIN/create-user fallback below.
      }
    }

    final hasWallet = await WalletService.hasWallet();
    final hasPin = await WalletService.hasPin();
    if (!mounted) return;
    if (hasWallet && hasPin) {
      await _go(UnlockScreen(appUserId: appUserId));
      return;
    }

    // Local id points at a user whose onboarding never finished on this
    // device (no Stellar key / PIN to log in with — interrupted, or the
    // app was pointed at a different backend/DB) — fall back to creation
    // rather than getting stuck on a blank screen. POST /users is
    // idempotent by phone/email, so this resumes the same account rather
    // than forking a new one.
    await _go(const CreateUserScreen());
  }

  @override
  Widget build(BuildContext context) {
    return const _SplashView();
  }
}

/// Branded launch surface — the brand waves wallpaper (PfBackground,
/// mounted app-wide) on the logo's navy. The mark DRAWS ITSELF (same
/// code-drawn motif as the loader and transfer confirmation), the
/// wordmark fades up once it has landed, and the ribbon loader traces
/// underneath while the startup decision finishes. Dark-default per the
/// design brief (§1). The launch moment, implemented as specced: the brand mark DRAWS ITSELF
/// (the ribbon traces in flat blue→emerald gradient, the arrowhead settles
/// — the same code-drawn motif as the loader and transfer confirmation,
/// never a static PNG standing in for an animation), the wordmark fades up
/// once the mark has landed. No glow, no bounce.
class _SplashView extends StatelessWidget {
  const _SplashView();

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: PayFlexTheme.dark,
      child: Scaffold(
        backgroundColor: Colors.transparent, // reveal PfBackground waves
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),
              SizedBox(
                width: 148,
                height: 148,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 1250),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, _) =>
                      CustomPaint(painter: PfMarkPainter(t: t)),
                ),
              ),
              const SizedBox(height: 26),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 450),
                curve: PfMotion.easeOut,
                builder: (context, t, child) => Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, 10 * (1 - t)),
                    child: child,
                  ),
                ),
                child: const Column(
                  children: [
                    Text(
                      'PayFlex',
                      style: TextStyle(
                        color: PfColors.onNavy,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Digital finance that moves with you',
                      style: TextStyle(
                        color: PfColors.onNavyMuted,
                        fontSize: 13.5,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 3),
              const Padding(
                padding: EdgeInsets.only(bottom: 40),
                child: PfBrandedLoader(size: 40),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
