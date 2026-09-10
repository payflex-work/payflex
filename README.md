<p align="center">
  <img src="app/assets/brand/payflex_logo.png" alt="PayFlex logo" width="140">
</p>

<h1 align="center">PayFlex</h1>

<p align="center">
  <strong>Mobile-first microfinance — savings, loans, agents, and group savings on the BMONI Embedded API</strong>
</p>

---

## What is PayFlex?

PayFlex is a mobile-first microfinance app (in the spirit of Moniepoint / OPay)
built on top of the **BMONI Embedded API** for identity, wallets, KYC, and money
movement. PayFlex adds an app-layer on top of BMONI's smart-wallet rails:

| Feature | What it does |
|---|---|
| **Savings goals** | Scheduled contributions the user signs in-app when due |
| **Loans & credit scoring** | Apply, get scored on transaction history, repay in-app |
| **Agent cash-in / cash-out** | Human agent network for physical ↔ digital cash conversion |
| **Safebox group savings** | Shared pools with owner/admin roles and treasury-signed withdrawals |
| **QR Pay & PayTag** | Scan-to-pay and `@handle` directory on the shared transfer flow |
| **Split bills** | One bill, several contributors, each pays their own share |
| **Send via link** | Claimable payment links (treasury-escrowed for non-users) |
| **Offline payment protocol** | Signed payments exchanged device-to-device over animated QR, settled on reconnect |
| **Standing plans** | Recurring signed transfers on a scheduler |
| **Stellar rail** | Optional, non-custodial crypto wallet parallel to BMONI |

## Architecture

```
app/       Flutter mobile app (iOS + Android)
backend/   NestJS orchestration service — the only thing that calls BMONI
```

BMONI Embedded is **not** built on Stellar — it's EVM-based managed smart
wallets (owner-proof challenge + EIP-191 signing) backed by regional
stablecoins (`USDB`, `CNGN`, `CADC`, `EURe`, `MEXe`). BMONI is the only
settlement rail for the primary wallet. The optional Stellar wallet is a
separate, self-contained module (`backend/src/stellar/`, `app/lib/stellar/`).

Two hard boundaries hold the architecture together:

- **The Flutter app never calls BMONI directly.** Every network call goes
  through the PayFlex backend's single `BmoniClientService`.
- **The app never touches BMONI key material outside `bmoni_embedded_sdk`.**
  The private key never leaves the device; only public addresses and
  EIP-191 signatures are ever sent to the backend.

## The three keys — do not conflate them

| Key | Curve / encoding | Held by | Purpose |
|---|---|---|---|
| BMONI owner key | secp256k1, EIP-191 | `bmoni_embedded_sdk` (native platform storage) | Owns the KYC'd smart wallet; signs BMONI transfer proposals |
| Offline-protocol device key | ED25519, raw hex | `DeviceKeyService` (SharedPreferences, hook-injectable) | Signs offline optical-handoff payments — proves *device* identity, not legal identity |
| Stellar key | ED25519, StrKey (`G...`/`S...`) | `StellarKeyService` (`flutter_secure_storage` — platform keychain/keystore) | Owns the Stellar account; signs Stellar transactions |

They share curves but are never reused across each other — different
encoding, different network, different blast radius. The Stellar key is the
one on-device secret using real secure storage (Keychain/Keystore), a
deliberate requirement of that rail, not an inconsistency.

## Features in depth

### Authentication

Challenge-response login reusing the on-device EVM owner key every user
already has for BMONI signing — no separate password/OTP system. Every route
requires a valid access token by default (`AuthGuard`, registered globally);
a route opts out explicitly with `@Public()`, never implicitly. The admin
surface is gated server-side by `AdminGuard`. Rate limiting on auth endpoints.

### Safebox group savings

Owner/admin/member roles, a 3-admin cap, owner-or-admin-only withdrawal, and
a 2-step ownership-transfer confirmation — all enforced server-side, not just
hidden in the UI. Contributions are real signed TRANSFER proposals (member →
treasury); withdrawals are treasury-signed releases, since a shared pool has
no single member whose on-device key can sign on its behalf. `currentBalance`
is optimistic bookkeeping — there is no way to confirm a signed proposal
actually settled on-chain.

### Loans & credit scoring

Loan applications are scored on transaction history and account age
(`SimpleCreditScoringStrategy`). Approval and disbursement are automatic —
disbursement is **the one case in the app where PayFlex signs a transfer
itself**, server-side, because PayFlex's own money moves under PayFlex's own
authority. The treasury key is a plain env var in this build, which is
explicitly unacceptable for production (needs a real KMS/HSM).

### Send via link (escrow)

A known recipient gets a plain transfer; an unknown one routes through
PayFlex's own escrow: the sender signs a proposal into the treasury and gets
a claim token to share. **PayFlex is holding a real customer's funds for as
long as a link sits unclaimed** — a genuine custody liability. The claimant
must hold a wallet in the escrowed currency before they can claim (BMONI
enforces this).

### Offline payment protocol

A separate payment path for when neither party has connectivity: an animated
"optical fountain" QR transport (`app/lib/protocol/`) carries a signed
`PaymentRequest` / `PaymentConfirmation` / `OfflineAuthorization` exchange
between two devices over the camera, backed by a pre-provisioned, chained
"Reserve" allowance (`OfflineReserveService`) that's spent down and
cryptographically chained (each authorization signs over the previous one's
state hash) entirely offline. Once either device regains connectivity,
`OfflineRedemptionService.syncAndRedeemAll` replays the queued authorizations
through the normal BMONI transfer flow to settle them.

### Stellar rail (optional, parallel to BMONI)

A second, optional wallet on the real Stellar network — defaults to testnet,
never routed through BMONI, never replacing the primary regulated wallet.
Real trustlines and payments (native XLM and issued assets), mandatory
"this cannot be undone" confirmation before every send, and a pre-flight
trustline check so a payment can't fail on-chain for a reason the app could
have caught. Verified end to end against live testnet.

**Non-custodial by design.** The Stellar secret key is generated on the
user's device, stored in the platform keychain/keystore, and never sent to
the PayFlex backend — the backend's `StellarModule` is read-only (public
Horizon data only). PayFlex cannot move a user's Stellar funds and holds no
custody. The accepted trade-off: a user who loses their device and secret key
loses account access — there is no support-restore path. Testnet accounts
fund via Friendbot; mainnet activation requires an explicit env flag plus a
real minimum-balance payment, which the app deliberately does not automate.

### Design system

One shared token file (`app/lib/theme/payflex_tokens.dart`) and theme
(`payflex_theme.dart`): the blue→emerald gradient, deep navy dark mode, fixed
spacing/radius/type scale, and a hard "no glow/neon" rule — every shadow is a
small, low-opacity, neutral elevation. A shared component library
(`app/lib/widgets/pf_*.dart`) means every money-moving screen (transfers, QR
Pay, savings, loans, agent mode, split-bill, send-via-link, Safebox) goes
through the same five-step confirmation flow: **Review → Authenticate →
Submit → Result → Record** — rather than each building its own payment sheet.

## Getting started

### Backend

```bash
cd backend
npm install
cp .env.example .env           # sandbox key is already filled in
docker compose up -d           # Postgres + Redis for local dev
npx prisma migrate dev         # creates the schema (first run only)
npm run provision:treasury     # one-time: creates PayFlex's own treasury BMONI account
                               # (paste its output's two lines into .env — required for
                               # loan disbursement and link escrow; everything else works without it)
npm run start:dev              # http://localhost:3000
npm test                       # unit tests
```

### Mobile app

The repo holds the Dart application code (`lib/` + `pubspec.yaml`). One-time
setup on a machine with the Flutter SDK installed:

```bash
flutter create --org com.payflex --project-name payflex .   # adds android/ios/ without touching lib/ or pubspec.yaml
flutter pub get

# Camera permission is required for KYC document capture (image_picker)
# AND QR scanning (mobile_scanner reuses the same permission) — add to
# android/app/src/main/AndroidManifest.xml:
#   <uses-permission android:name="android.permission.CAMERA" />
# and to ios/Runner/Info.plist:
#   <key>NSCameraUsageDescription</key>
#   <string>PayFlex needs your camera to verify your identity documents and scan payment QR codes.</string>

# Point at your locally running backend. 10.0.2.2 is the Android emulator's
# alias for the host's localhost; use localhost for iOS simulator, or your
# LAN IP for a physical device.
flutter run --dart-define=BACKEND_BASE_URL=http://10.0.2.2:3000
flutter analyze
flutter test
```

### Sandbox verification scripts

Each walks a full phase against the live BMONI sandbox
(`https://embedded-dev.bmoni.com`) using the real service classes — run from
`backend/`:

```bash
npm run sandbox:lifecycle      # Phase 1: user + wallet lifecycle
npm run sandbox:phase2         # Phase 2: NGN KYC wizard + rail onboarding
npm run sandbox:kyc-mismatch   # the deliberate BVN/name-mismatch check
npm run sandbox:phase3         # Phase 3: transfers, QR Pay, PayTag
npm run sandbox:phase4         # Phase 4: savings, loans (auto-disbursement), agent mode
npm run sandbox:phase5         # Phase 5: split-bill, send-via-link/escrow
npm run sandbox:safebox        # Safebox group savings
npm run sandbox:standing-plans # recurring payments
npm run verify:offline         # offline payment protocol primitives
npm run stellar:testnet-walkthrough  # Stellar rail against live testnet
```

## Key signing model

BMONI's signing model has **no delegated / pre-authorized debit mechanism**:
every transfer — savings contribution, loan repayment, agent cash-out,
Safebox contribution — is signed by the paying party's own on-device key.
Schedulers only flip things to *due* or *pending*; a human still has to open
the app and sign. This is a real constraint of an architecture where key
custody never leaves the user's device, not a shortcut. The only
server-side signing is PayFlex's treasury account (loan disbursement,
Safebox withdrawal release, link escrow release) — PayFlex's own money under
PayFlex's own authority.

## Verification status

- Backend: 97 unit tests passing across 14 suites; `tsc --noEmit` clean;
  sandbox scripts verified green against the live BMONI sandbox.
- Flutter: `flutter analyze` — 0 errors; `flutter test` — 36/36 passing
  (23 offline-protocol + 13 Stellar rail).
- Not yet done: `flutter build apk` (no Android SDK in the build
  environment), a real on-device visual walkthrough, production
  credentials, webhook signing, and real secrets management (`JWT_SECRET`
  and the treasury key are plain env vars — fine for sandbox, need a real
  KMS before production).

## Not built

**Virtual cards and betting funding are honest stubs, not features** — each
is a screen (`app/lib/screens/virtual_card_screen.dart`,
`betting_screen.dart`) that says so plainly, with zero backend support: card
issuance needs a card-network/processor partnership and betting funding
needs jurisdiction-dependent licensing. Never render a fake card number/CVV
or a working-looking bet flow.

By contrast, **Standing Plans and the Admin panel are built** — recurring
payments are real signed transfers on a scheduler (`backend/src/standing-plans/`),
and the admin surface is gated server-side by `AdminGuard`.

## Engineering rules

- Every BMONI call goes through `BmoniClientService` — no ad-hoc HTTP calls
  in feature code.
- No key generation, storage, or signing outside `bmoni_embedded_sdk`
  (`WalletService`) for the BMONI key, `DeviceKeyService` for the
  offline-protocol device key, or `StellarKeyService` for the Stellar key —
  never inline in a screen or service.
- `bmoniUserId` is persisted on first creation, both locally on-device
  (`SharedPreferences`) and in the backend's Postgres — a user is never
  recreated on relaunch.
- KYC submit order and per-currency activation are hard constraints, not
  suggestions.
- All monetary amounts go through one shared money-formatting utility rather
  than inline conversions (`backend/src/common/money.util.ts`,
  `app/lib/utils/money.dart`).
- A webhook receiver (`POST /webhooks/bmoni`) logs and persists every BMONI
  async event, even before all event types are acted on.
- Every route requires a valid access token by default (`AuthGuard`); a
  route opts out explicitly with `@Public()`, never implicitly.
- Every money-movement screen uses the shared confirmation flow
  (`signAndSubmitTransfer` + `showPfConfirmation`) — don't build a
  feature-specific payment sheet.

## Third-party notices

PayFlex includes algorithmic components under open-source licenses — see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) (the Decimen Optical
Transfer offline-QR transport, MIT).
