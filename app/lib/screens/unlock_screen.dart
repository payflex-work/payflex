import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/session_manager.dart';
import 'wallet_home_screen.dart';

/// Shown on a cold start when a local wallet/PIN already exist on this
/// device but there's no valid session (no persisted refresh token, or the
/// backend rejected it) — the user proves ownership of the on-device key
/// once more via the normal challenge-response login.
class UnlockScreen extends StatefulWidget {
  final String appUserId;
  const UnlockScreen({super.key, required this.appUserId});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _pinController = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _unlock() async {
    if (_pinController.text.length != 6) {
      setState(() => _error = 'PIN must be exactly 6 digits');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SessionManager.login(widget.appUserId, _pinController.text);
      final user = await ApiClient().getUser(widget.appUserId);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => WalletHomeScreen(user: user)),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enter your PIN')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Enter your 6-digit PIN to unlock your wallet.'),
            const SizedBox(height: 16),
            TextField(
              controller: _pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(labelText: 'PIN'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            FilledButton(
              onPressed: _busy ? null : _unlock,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Unlock'),
            ),
          ],
        ),
      ),
    );
  }
}
