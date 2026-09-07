import 'package:flutter/material.dart';
import 'services/local_user_store.dart';
import 'services/api_client.dart';
import 'services/session_manager.dart';
import 'services/wallet_service.dart';
import 'screens/onboarding/create_user_screen.dart';
import 'screens/unlock_screen.dart';
import 'screens/wallet_home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  WalletService.initialize();
  runApp(const PayFlexApp());
}

class PayFlexApp extends StatelessWidget {
  const PayFlexApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PayFlex',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const _StartupGate(),
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

class _StartupGateState extends State<_StartupGate> {
  final _store = LocalUserStore();
  final _api = ApiClient();

  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    final appUserId = await _store.getAppUserId();
    if (!mounted) return;
    if (appUserId == null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const CreateUserScreen()),
      );
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
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => WalletHomeScreen(user: user)),
        );
        return;
      } catch (_) {
        // Falls through to the PIN/create-user fallback below.
      }
    }

    final hasWallet = await WalletService.hasWallet();
    final hasPin = await WalletService.hasPin();
    if (!mounted) return;
    if (hasWallet && hasPin) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => UnlockScreen(appUserId: appUserId)),
      );
      return;
    }

    // Local id points at a user with no on-device key yet to log in
    // with (e.g. onboarding was interrupted, or pointed at a different
    // backend/DB) — fall back to creation rather than getting stuck on a
    // blank screen. POST /users is idempotent by phone/email, so this
    // resumes the same account rather than forking a new one.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const CreateUserScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
