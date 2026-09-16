<p align="center">
  <img src="app/assets/brand/payflex_logo.png" alt="PayFlex logo" width="140">
</p>

<p align="center">
  <a href="https://github.com/payflex-work/payflex/actions/workflows/backend-tests.yml">
    <img src="https://github.com/payflex-work/payflex/actions/workflows/backend-tests.yml/badge.svg" alt="Backend tests">
  </a>
  <a href="https://github.com/payflex-work/payflex/actions/workflows/backend-docker.yml">
    <img src="https://github.com/payflex-work/payflex/actions/workflows/backend-docker.yml/badge.svg" alt="Backend Docker">
  </a>
  <a href="https://nextgen-4.gitbook.io/nextgen-docs/backend">
    <img src="https://img.shields.io/badge/docs-GitBook-blue" alt="Documentation">
  </a>
</p>

# PayFlex

📖 **Documentation**: [NextGen GitBook Docs](https://nextgen-4.gitbook.io/nextgen-docs/backend)

> **Honest status: this is a working Stellar *testnet* application, not a bank.**
> Fiat on/off-ramps and identity verification (KYC) are **not implemented** —
> no provider is plugged in, the app is hard-gated from ever claiming otherwise,
> and several features that need a fiat rail are paused, not faked.
> See **[`/docs/fiat-kyc-gap.md`](docs/fiat-kyc-gap.md)** for the full, unvarnished picture.

PayFlex is a non-custodial payments app on Stellar: every user **is** a Stellar
account. The keypair is generated on-device, the secret seed never leaves the
phone, and every payment is built, signed, and submitted from the device.

**Contents**: [Stellar is the only rail](#stellar-is-the-only-rail) ·
[What works today](#what-works-today-testnet) ·
[What is paused](#what-is-paused-honestly--not-hidden) ·
[The fiat/KYC gap](#the-fiatkyc-plug-in-gap) ·
[Documentation](#documentation) · [Architecture](#architecture) ·
[Getting started](#getting-started) ·
[Verification status](#verification-status) ·
[Engineering rules](#engineering-rules)

## Stellar is the only rail

There is no secondary settlement system, no treasury account, no parallel
banking layer. The architecture:

- **Non-custodial by design.** The Stellar secret key lives in the platform
  keychain/keystore (`flutter_secure_storage`); only public keys and
  signatures ever leave the device. Accepted trade-off: lose the device and
  the seed, lose the account — there is no support-restore path.
  See [`docs/stellar/accounts-and-keys.md`](docs/stellar/accounts-and-keys.md).
- **The backend never signs.** PayFlex's NestJS backend (`backend/src/stellar/`)
  is a thin, read-only companion: account lookups, transaction-history
  verification for recorded transfers, and read-only Soroban contract reads.
  It has no deposit, withdraw, or send endpoint.
- **The app talks to Horizon directly** using the official
  `stellar_flutter_sdk` (mobile) and `@stellar/stellar-sdk` (backend
  verification). Login is a challenge signed with the user's own Ed25519 key
  and verified against the registered public key — no passwords.
- **Every recorded payment is verified on-chain.** When the app reports a
  transfer, the backend pulls the real transaction from Horizon and checks it
  matches every claimed field before storing anything —
  [`docs/stellar/payments-lifecycle.md`](docs/stellar/payments-lifecycle.md)
  walks the full path.

## What works today (testnet)

| Feature | How |
|---|---|
| **Transfers / PayTag / QR Pay** | resolve → PIN → build → sign on-device → submit → record (verified) |
| **Standing plans** | scheduler marks payments DUE; paying is the normal on-device flow (no delegated debit exists on Stellar, and the app refuses to fake one) |
| **Safebox group savings** | a real **Soroban escrow contract** (`backend/contracts/safebox`): owner/admin-only withdrawal and the 3-admin cap enforced **on-chain**; contributions/withdrawals in the contract's own ledger, visible to all members |
| **Send via link** | non-custodial on-chain **claimable balances** — escrowed by the chain, never by PayFlex ([links](docs/stellar/payments-lifecycle.md#claimable-balances-send-via-link)) |
| **Split bills** | orchestration only; each contributor pays the creator with an independent on-device payment |
| **Offline Reserve / optical QR** | two-device offline handoff signed by an independent device key; **redemption** settles as a real Stellar payment on reconnect ([how it works](docs/stellar/offline-reserve.md)) |
| **Admin** | server-gated (`AdminGuard`); shows Stellar accounts, verified transfers, and Safebox (Soroban) state |

## What is paused, honestly — not hidden

These features had no function without a fiat rail. They are gated at the
architecture level (the backend's `GatedModule` and hard-gate flags), and the
UI shows clearly-labeled "coming soon" states rather than fake flows:

- **Virtual cards** — Stellar has no card-issuing capability; needs a processor
  partner.
- **Agent cash-in/cash-out network** — existed to bridge physical cash to fiat
  balances.
- **Betting page funding** — moved fiat to licensed betting providers.
- **Loans / savings goals** — no treasury to disburse from, no KYC'd history
  to score.

Attempting to reach the gated backend endpoints fails closed — see
`backend/src/gated/` and `backend/test/gated-features.e2e-spec.ts`.

## The fiat/KYC plug-in gap

Two clean, unimplemented interfaces mark the seam where a real provider plugs
in later — docstrings only, no fake implementations, no placeholder
credentials:

- `backend/src/providers/identity-verification-provider.ts` (KYC; SEP-12-shaped)
- `backend/src/providers/fiat-rail-provider.ts` (deposit/withdraw fiat ↔ Stellar asset; SEP-6/24-shaped)

The full analysis — what a real implementation would look like, and every
feature paused because of the gap — is in
[`docs/fiat-kyc-gap.md`](docs/fiat-kyc-gap.md).

`identityVerified` and `fiatCapable` default to `false` on every account and
**no code path can set them true** until a real provider exists. Reference
options for later (a real anchor such as LINK/NGNC, or another regulated
partner) are discussed without commitment in `/docs/fiat-kyc-gap.md`.

## Documentation

- **GitBook Documentation**: [https://nextgen-4.gitbook.io/nextgen-docs/backend](https://nextgen-4.gitbook.io/nextgen-docs/backend)
- **In-repo docs**: [`docs/README.md`](docs/README.md) is the index; the map below says what each document answers.

| Document | Answers the question… |
|---|---|
| [`docs/architecture.md`](docs/architecture.md) | How is the system put together, and why can't the backend move money? |
| [`docs/deploy.md`](docs/deploy.md) | How do I deploy the backend (Railway / Render / Fly.io) and point the app at it? |
| [`docs/fiat-kyc-gap.md`](docs/fiat-kyc-gap.md) | What can this app *not* do, and where would a real fiat/KYC provider plug in? |
| [`docs/stellar/README.md`](docs/stellar/README.md) | Index of the Stellar deep dives: accounts & keys, SEP-10 login, payments lifecycle, Safebox (Soroban), the offline protocol, testnet vs mainnet. |
| [`docs/scf-application/README.md`](docs/scf-application/README.md) | Stellar Community Fund submission drafts (project-specific, not engineering docs). |

## Architecture

```
app/       Flutter mobile app (iOS + Android) — non-custodial Stellar wallet
backend/   NestJS service: directory, verification, orchestration (never signs)
contracts/ backend/contracts/safebox — the Soroban escrow contract
docs/      this documentation set — start at docs/README.md
```

Two hard boundaries hold it together:

- **The Flutter app talks to the backend AND to Horizon directly.** The
  backend orchestrates and verifies; it can never move funds.
- **Key material lives in exactly two places on-device:** the Stellar key
  (`StellarKeyService`, platform keychain) that owns the account, and the
  offline-protocol device key (`DeviceKeyService`) that signs optical
  handoffs. Both are PIN-gated at the point of use.

## Getting started

### Backend

```bash
cd backend
npm install
cp .env.example .env
docker compose up -d           # Postgres + Redis for local dev
npx prisma migrate dev         # creates the schema (first run only)
npm run start:dev              # http://localhost:3000
npm test                       # e2e suites (includes the hard-gate test)
```

### Soroban Safebox contract

```bash
cd backend/contracts/safebox
cargo build --target wasm32v1-none --release   # or: stellar contract build
cargo test                                     # on-chain enforcement tests
```

Deploy from the app or CLI, then register the contract id with the backend
(the backend verifies on-chain that the caller really is the contract owner
before accepting the registration).

### Mobile app

```bash
cd app
flutter pub get
flutter run --dart-define=BACKEND_BASE_URL=http://10.0.2.2:3000
flutter analyze
flutter test
```

Onboarding: create account → set PIN (generates the Stellar keypair on-device,
registers the public key) → **Friendbot funds the account on testnet**. On
mainnet, activation requires a real minimum-reserve payment from an
already-funded account — the app deliberately does not automate holding or
paying out that reserve.

### Testnet verification script

```bash
cd backend
npm run stellar:testnet-walkthrough   # two accounts, XLM + issued-asset payments, history
npm run verify:offline                # offline protocol primitives
```

## Verification status

- Backend: `tsc --noEmit` clean; e2e suites green (transfers, standing plans,
  links, QR, **and the hard gate**); the Stellar rail is verified against the
  live testnet by the walkthrough script.
- Flutter: `flutter analyze` / `flutter test` for the offline protocol and
  Stellar models; the full end-to-end app flow needs a device/emulator.
- Not production-ready by design while the fiat/KYC gate is closed: see the
  honest-status note at the top and `/docs/fiat-kyc-gap.md`.

## Engineering rules

- No key generation, storage, or signing outside `StellarKeyService` /
  `DeviceKeyService` / `WalletService` — never inline in a screen.
- The local user id is persisted on first creation (device + backend) — a user
  is never recreated on relaunch.
- Every route requires a valid access token by default (`AuthGuard`); a route
  opts out explicitly with `@Public()`, never implicitly.
- Every money-movement screen uses the shared confirmation flow
  (`signAndSubmitTransfer` + `showPfConfirmation`).
- All monetary formatting goes through the shared money utilities, never
  inline conversions.
- The docs must never call this app production-ready or launch-ready while
  the fiat/KYC gate is closed.

## Third-party notices

PayFlex includes algorithmic components under open-source licenses — see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) (the Decimen Optical
Transfer offline-QR transport, MIT).
