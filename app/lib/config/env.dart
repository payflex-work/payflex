import 'dart:io';

import 'package:flutter/foundation.dart';

/// Base URL of the PayFlex orchestration backend (NestJS) — NOT BMONI's
/// API. The app never talks to BMONI directly; every call goes through
/// our own backend, which owns the single BmoniClient. See
/// backend/src/bmoni/bmoni-client.service.ts.
///
/// Override at build/run time with:
///   flutter run --dart-define=BACKEND_BASE_URL=http://10.0.2.2:3000
/// (10.0.2.2 is the Android emulator's alias for the host machine's
/// localhost; use http://localhost:3000 for iOS simulator.)
///
/// For a deployed backend pass its HTTPS origin, with no trailing slash:
///   flutter run --dart-define=BACKEND_BASE_URL=https://payflex-backend.up.railway.app
/// See docs/deploy.md ("Point the Flutter app at the deployed backend").
class Env {
  static const backendBaseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  /// Fail fast on a release build pointed at a cleartext HTTP origin.
  ///
  /// Android (API 28+) and iOS (ATS) block plain http:// by default, so a
  /// release build with a leftover localhost/emulator base URL would
  /// compile fine and then die on the first API call with an opaque
  /// socket error. Throwing here turns that into an obvious,
  /// actionable launch failure instead. Debug/profile builds are exempt:
  /// that's exactly where http:// against 10.0.2.2/localhost is wanted.
  static void assertSafeConfig() {
    if (!kReleaseMode) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (backendBaseUrl.startsWith('http://')) {
      throw StateError(
        'BACKEND_BASE_URL is "$backendBaseUrl" but release builds on '
        'Android/iOS only allow HTTPS origins. Build with '
        '--dart-define=BACKEND_BASE_URL=https://<deployed-backend> '
        '(see docs/deploy.md).',
      );
    }
  }
}
