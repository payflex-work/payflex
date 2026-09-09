# PayFlex — Stellar Rail

A second, **optional** payment rail on the real Stellar network, built
alongside BMONI Embedded — never routed through it, never replacing it.
BMONI remains the app's primary, regulated, KYC'd wallet. This exists for
users who also want a crypto-native option, and as groundwork for future
Stellar-anchor on/off-ramps BMONI doesn't cover.

If you're looking for the narrower Soroban-contract integration discussed
in `docs/research/safebox-stellar-compliance.md` and scaffolded in
`backend/src/stellar-rail/` — that's a **different, more specific**
piece of work (integrating against one particular external contract,
still waiting on that contract's reference). This document describes the
generic user-facing Stellar wallet in `backend/src/stellar/` and
`app/lib/stellar/`. The two are not in conflict; they may eventually
share the on-device key-management pattern described below.

## Why Stellar, and what it adds

Stellar is a real, production-grade blockchain purpose-built for
payments and asset issuance — low-cost, fast settlement, and a mature
stablecoin/anchor ecosystem. It gives PayFlex:

- Cross-border transfers where Stellar's low fees and ~5s settlement are
  a real advantage over traditional rails.
- A crypto-native wallet option for users who want one.
- A foundation for future Stellar-anchor on/off-ramps.

## The three keys in this app — do not conflate them

| Key | Curve/encoding | Held by | Purpose |
|---|---|---|---|
| BMONI owner key | secp256k1, EIP-191 | `bmoni_embedded_sdk` (native platform storage) | Owns the KYC'd smart wallet; signs BMONI transfer proposals. |
| Offline-protocol device key | ED25519, raw hex | `DeviceKeyService` (SharedPreferences, hook-injectable) | Signs offline optical-handoff payment requests/confirmations — proves device identity, not legal identity. |
| **Stellar key** | ED25519, StrKey (`G...`/`S...`) | `StellarKeyService` (`flutter_secure_storage` — the platform keychain/keystore) | Owns the Stellar account; signs Stellar transactions. |

The Stellar key happens to share ED25519 with the offline-protocol
device key, but they are never reused across each other — different
encoding, different network, different failure blast radius. A
compromise of one must not compromise the other.

**Storage note:** this is the one on-device secret in the app that uses
`flutter_secure_storage` (real Keychain/Keystore) rather than the
SharedPreferences-backed pattern the offline-protocol key uses. The
original build brief for this rail was explicit that the secret needs
real secure storage, not "whatever's easiest" — worth calling out since
it's a deliberate inconsistency with the rest of this codebase's
existing key-storage services, not an oversight.

## Architecture

```
Flutter app (on-device)                  PayFlex backend            Stellar network
┌─────────────────────┐                  ┌──────────────┐          ┌─────────────┐
│ StellarKeyService    │  never leaves    │              │          │             │
│  (secret seed)        │  device          │              │          │             │
│                       │                  │  StellarModule│  proxy   │             │
│ StellarClient ────────┼──────────────────┼──────────────┼─────────>│   Horizon   │
│  (build/sign/submit)  │  GET /stellar/*  │ (read-only,  │  reads   │             │
│                       │  network+account │  rate-limited)│  only    │             │
└───────────┬───────────┘  info only       └──────────────┘          └──────┬──────┘
            │                                                                 │
            └─────────────────── build, sign, submit ────────────────────────┘
                                  (direct to Horizon, on-device)
```

Unlike BMONI — which requires a secret API key and does KYC/custody, so
the app only ever reaches it through PayFlex's backend — Horizon is a
public blockchain API designed for wallet SDKs to call directly. The
backend's `StellarModule` is a **thin, read-only companion**: it proxies
account/history lookups (for its own rate-limiting, same shape as every
other module) and serves network config (which Horizon this build talks
to), but it **never receives, builds, signs, or submits a transaction on
a user's behalf**. Every signature happens on-device via
`StellarKeyService` + `stellar_flutter_sdk`.

## Network configuration

Defaults to **testnet** with zero configuration needed:

```
STELLAR_NETWORK=testnet          # default if unset
STELLAR_HORIZON_URL=             # blank = https://horizon-testnet.stellar.org
STELLAR_FRIENDBOT_URL=           # blank = https://friendbot.stellar.org
```

**Mainnet requires an explicit flag, on purpose:**

```
STELLAR_NETWORK=mainnet
STELLAR_HORIZON_URL=https://horizon.stellar.org
```

If `STELLAR_NETWORK=mainnet` is set without `STELLAR_HORIZON_URL`, the
backend refuses to boot rather than silently defaulting to anything.

> **Enabling mainnet is a deliberate business/compliance decision, not a
> config flip.** Mainnet transactions move real, irreversible funds.
> Turning it on means PayFlex is now responsible for a live cryptocurrency
> rail — consider licensing/compliance exposure (this is a genuinely
> different regulatory surface than BMONI's managed custody) before
> flipping this in any real deployment.

## What's actually implemented

- **Account & key management** — on-device ED25519 keypair generation
  (`StellarKeyService`), secure storage, testnet Friendbot funding.
  Mainnet activation is *not* automated (see below) — a deliberate
  choice, not a gap.
- **Trustlines** — establish (or remove) a trustline to any issued asset
  via the Add Asset screen, with plain-language copy about the XLM
  reserve cost.
- **Payments** — native XLM and trusted-asset payments, built/signed/
  submitted entirely on-device. The send screen checks the recipient's
  trustline for non-native assets *before* submitting (a payment to an
  account without one fails on-chain — this app catches that up front,
  not after a wasted round trip), and requires a separate, explicit
  "this cannot be undone" confirmation naming the exact destination
  address before every send.
- **Transaction history** — pulled live from Horizon, shown in its own
  Stellar-specific view (never merged into BMONI's transaction history —
  users should always know which network a transaction happened on).
- **Error handling** — `StellarErrors` maps Stellar's own protocol result
  codes (`op_underfunded`, `op_no_trust`, `op_no_destination`,
  `op_line_full`, `op_low_reserve`, `tx_bad_seq`, ...) to specific
  messages, never a generic "transfer failed."

## What's deliberately not automated

- **Mainnet account activation.** Testnet uses Friendbot; mainnet needs a
  real minimum-balance payment from an already-funded account. This app
  does not attempt to automate that transfer — it's real money, and
  automating "send myself some XLM to activate this" is exactly the kind
  of shortcut this project avoids elsewhere (see BMONI treasury's own
  "no delegated debit" stance).
- **KYC/AML bridging between BMONI and Stellar.** This rail's account
  isn't gated on the user's BMONI KYC status. If this ships for real,
  that's a compliance decision to make deliberately (see
  `docs/research/safebox-stellar-compliance.md` for the kind of analysis
  that decision needs), not something to bolt on silently.
- **The specific Soroban-contract integration** described in
  `backend/src/stellar-rail/README.md`. That's a narrower, different
  piece of work pending a specific contract reference.

## Verification

- `backend/src/stellar/stellar.service.spec.ts` — Horizon proxy error
  translation (`NotFoundError` → `NotFoundException`), account/history
  mapping.
- `backend/src/config/stellar.config.spec.ts` — network config,
  including a regression test for a real bug this rail's own boot-test
  caught (a blank-but-present `STELLAR_HORIZON_URL=` line crashed the
  app; `??` doesn't treat `''` as "use the default," `||` does).
- `app/test/stellar/stellar_key_service_test.dart` — real ED25519/StrKey
  keypair generation and persistence (no network needed).
- `app/test/stellar/stellar_errors_test.dart` — every mapped Stellar
  result code.
- `backend/scripts/stellar-testnet-walkthrough.ts` — real end-to-end
  verification against live testnet (`npm run stellar:testnet-walkthrough`):
  funds two fresh accounts via Friendbot, sends a native XLM payment,
  establishes a trustline, sends a trusted-asset payment, and confirms
  both transactions appear in both accounts' Horizon history. Uses the
  JS/TS Stellar SDK rather than driving the Flutter app directly — this
  sandbox's `flutter test` engine cannot make real outbound network
  connections (a separate, pre-existing constraint; see the git history
  around the Standing Plans/Admin walkthrough for how that was
  diagnosed). Horizon's wire protocol is identical regardless of which
  official SDK talks to it, so this proves the same mechanics
  `stellar_client.dart` performs with the Dart SDK on a real device.
