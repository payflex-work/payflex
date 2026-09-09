# PayFlex

A mobile-first microfinance app (in the spirit of Moniepoint / OPay) built
on top of the **BMONI Embedded API** for identity, wallets, KYC, and money
movement. PayFlex adds a savings/micro-loan layer, an agent cash-in/cash-out
network, group savings (Safebox), an offline payment protocol, and a
QR-first transfer UX on top of BMONI's smart-wallet rails.

Full spec: [`docs/BUILD_PROMPT.md`](docs/BUILD_PROMPT.md). This README
tracks what's actually been built against that spec — see the "Not built"
section near the bottom before assuming a feature exists just because it's
mentioned somewhere.

## Architecture, in one paragraph

BMONI Embedded is **not** built on Stellar — it's EVM-based managed smart
wallets (owner-proof challenge + EIP-191 signing) backed by regional
stablecoins (`USDB`, `CNGN`, `CADC`, `EURe`, `MEXe`). BMONI is the only
settlement rail in this build; nothing here talks to Stellar/Horizon/Soroban.
The Flutter app never calls BMONI directly and never touches key material
itself — it goes through the NestJS backend's single `BmoniClientService`
for every API call, and through `bmoni_embedded_sdk` for every key
generation / signing operation (the one exception, by design: the offline
protocol's device identity key is a separate Ed25519 keypair, deliberately
independent of the BMONI EVM key — see "Offline payment protocol" below).

```
app/       Flutter mobile app (iOS + Android)
backend/   NestJS orchestration service — the only thing that calls BMONI
docs/      The original build brief (source of truth for architecture)
```

## Where the BMONI API boundary actually is

**Real BMONI functionality** (`backend/src/bmoni/` wraps all of it): user
creation, on-device owner-wallet proof + managed smart wallets, the KYC
document/readiness/activation wizard, per-currency rail onboarding
(NGN/USD/CAD/EUR/MXN), wallet balances/detail, deposits, virtual bank
accounts, NGN bank withdrawal, general bank payouts, currency exchange,
the proposal → sign-payload → sign transfer primitive, and transaction
history.

**PayFlex-built, no BMONI equivalent** (all app-layer, on top of the
transfer primitive above): lending/credit scoring, savings goals, agent
cash-in/cash-out, Safebox group savings, claimable payment links
(treasury-escrowed for non-users — a real custody liability, see
`backend/prisma/schema.prisma`'s `ClaimableLink` doc comment before
touching that code), PayTag directory, QR Pay, split-bill orchestration,
and the offline payment protocol. Full phase-by-phase build history and
live-sandbox findings are in `backend/README.md` and `app/README.md`.

## Authentication

Every route requires a valid access token by default (`AuthGuard`, global
guard); a route opts out explicitly with `@Public()`. Login is
challenge-response, reusing the on-device EVM owner key every user already
has for BMONI signing — no separate password/OTP system. Rate limiting on
the auth endpoints. Full design and what was verified live:
`backend/README.md`'s Authentication section.

## Safebox group savings

Owner/admin/member roles, a 3-admin cap, owner-or-admin-only withdrawal, a
2-step ownership-transfer confirmation — all enforced server-side, not
just hidden in the UI. Contributions are real signed TRANSFER proposals
(member → treasury, same pattern as savings goals); withdrawals are
treasury-signed releases (same pattern as loan disbursement), since a
shared pool has no single member whose on-device key can sign on its
behalf. `currentBalance` is optimistic bookkeeping — this build has no way
to confirm a signed proposal actually settled on-chain, same honest
limitation `SavingsGoal.totalContributed` already carries. Verified live
end to end (`npm run sandbox:safebox`). Details: `backend/README.md`'s
Safebox section.

## Stellar rail (optional, parallel to BMONI)

A second, optional wallet on the real Stellar network — defaults to
testnet, never routed through BMONI, never replacing the primary
regulated wallet BMONI provides. On-device ED25519 keypair, real
trustlines and payments (native XLM and issued assets), mandatory
"this cannot be undone" confirmation before every send since Stellar
transactions are irreversible on-chain. Verified end to end against live
testnet (`npm run stellar:testnet-walkthrough`, from `backend/`). Full
architecture, the three-distinct-keys explanation, and mainnet
activation notes: `docs/stellar-rail.md`.

## Offline payment protocol

A separate payment path for when neither party has connectivity: an
animated "optical fountain" QR transport (`app/lib/protocol/`) carries a
signed `PaymentRequest`/`PaymentConfirmation`/`OfflineAuthorization`
exchange between two devices over the camera, backed by a
pre-provisioned, chained "Reserve" allowance (`OfflineReserveService`)
that's spent down and cryptographically chained (each authorization signs
over the previous one's state hash) entirely offline. Once either device
regains connectivity, `OfflineRedemptionService.syncAndRedeemAll` replays
the queued authorizations through the normal BMONI transfer/sign flow to
actually settle them. Uses its own Ed25519 device identity key
(`DeviceKeyService`), deliberately separate from the BMONI EVM owner key —
this proves "this physical device produced this signed message," not
KYC'd financial identity, which BMONI still governs entirely at online
settlement time. Covered by 23 Flutter tests (protocol/crypto primitives,
the reserve service, and a full two-device e2e simulation) — all passing.

## Design system

One shared token file (`app/lib/theme/payflex_tokens.dart`) and theme
(`payflex_theme.dart`) for the whole app: the blue→emerald gradient, deep
navy dark mode, a fixed spacing/radius/type scale, and a hard "no
glow/neon" rule enforced by construction (every shadow is a small,
low-opacity, neutral elevation). A shared component library
(`app/lib/widgets/pf_*.dart`) — buttons, panels, status chips, empty/error
states, the branded loader, and the shared five-step money-movement
confirmation flow (Review → Authenticate → Submit → Result → Record) —
means every money-moving screen (transfers, QR Pay, savings, loans, agent
mode, split-bill, send-via-link, Safebox) goes through the same
`signAndSubmitTransfer` + confirmation pattern rather than each building
its own. The brand waves wallpaper (`PfBackground`) mounts once behind
every route via `MaterialApp.builder` — navy scaffolds are transparent to
reveal it, light "business" surfaces stay opaque — and the approved brand
poster (`PfBrandPoster`) anchors the intro carousel (first launch only,
via `LocalUserStore.introSeen`) and the About page. `flutter analyze`
clean, `flutter test` clean; not yet visually
verified on a real device or emulator — this environment has no
display/emulator, so someone needs to actually look at it running before
calling the visual pass done.

## Development

```bash
cd backend
npm install
cp .env.example .env
docker compose up -d
npx prisma migrate dev
npm run start:dev            # backend on :3000
npm test                     # unit tests (auth, loans IDOR fix, safebox permissions)
npm run sandbox:lifecycle    # re-verify Phase 1 against the live sandbox
npm run sandbox:phase2       # re-verify Phase 2 NGN KYC + onboarding
npm run sandbox:kyc-mismatch # the deliberate BVN/name-mismatch check
npm run sandbox:phase3       # re-verify Phase 3 transfers, QR Pay, PayTag
npm run provision:treasury   # one-time: create PayFlex's treasury BMONI account
npm run sandbox:phase4       # re-verify Phase 4 savings, loans, agent mode
npm run sandbox:phase5       # re-verify Phase 5 split-bill, send-via-link/escrow
npm run sandbox:safebox      # re-verify Safebox group savings
```

```bash
cd app
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=BACKEND_BASE_URL=http://10.0.2.2:3000
```

## Current verification status

- Backend: 97 unit tests passing across 14 suites (verified this pass);
  `tsc --noEmit` clean; all sandbox scripts last verified green against
  the live BMONI sandbox per `backend/README.md`.
- Flutter: `flutter analyze` — 0 errors; `flutter test` — 36/36 passing
  (23 offline-protocol + 13 Stellar rail).
- Not yet done: `flutter build apk` (no Android SDK in this environment),
  a real on-device/emulator visual walkthrough (no display/emulator
  here), production credentials, webhook signing, and real secrets
  management (`JWT_SECRET` and the treasury key are plain env vars —
  fine for sandbox, need a real KMS before production).

## Not built

**Virtual cards and betting funding are honest stubs, not features** —
each is a screen (`app/lib/screens/virtual_card_screen.dart`,
`betting_screen.dart`) that says so plainly, with zero backend support:
card issuance needs a card-network/processor partnership and betting
funding needs jurisdiction-dependent licensing, and neither exists in
this codebase. Never render a fake card number/CVV or a working-looking
bet flow. If a future prompt references either as already built, that's
not accurate; check before trusting it. The compliance weight they carry
shouldn't be guessed at — building either needs an explicit
product/compliance spec first, not an assumption from a prompt.

By contrast, **Standing Plans and the Admin panel are built** —
recurring payments are real signed transfers on a scheduler
(`backend/src/standing-plans/`), and the admin surface is gated
server-side by `AdminGuard`, with the screen showing "admin access
required" on a 403 rather than pretending the check is client-side
(`backend/src/admin/`, `app/lib/screens/admin_screen.dart`).

## Non-negotiable engineering rules (see docs/BUILD_PROMPT.md §7)

- Every BMONI call goes through `BmoniClientService` — no ad-hoc HTTP calls
  in feature code.
- No key generation, storage, or signing outside `bmoni_embedded_sdk`
  (`WalletService`) for the BMONI key, or `DeviceKeyService` for the
  offline-protocol device key — never inline in a screen or service.
- `bmoniUserId` is persisted on first creation, both locally on-device
  (`SharedPreferences`) and in the backend's Postgres — a user is never
  recreated on relaunch.
- KYC submit order and per-currency activation are hard constraints, not
  suggestions (Phase 2).
- All monetary amounts go through one shared money-formatting utility
  rather than inline conversions (`backend/src/common/money.util.ts`,
  `app/lib/utils/money.dart`).
- A webhook receiver (`POST /webhooks/bmoni`) logs and persists every
  BMONI async event, even before all event types are acted on.
- Every route requires a valid access token by default (`AuthGuard`); a
  route opts out explicitly with `@Public()`, never implicitly.
- Every money-movement screen uses the shared confirmation flow
  (`signAndSubmitTransfer` + `showPfConfirmation`) — don't build a
  feature-specific payment sheet.
