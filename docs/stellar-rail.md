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

## Custody model — explicitly non-custodial

PayFlex's Stellar rail is **non-custodial**, in Stellar's own terms from
the official [Application Design Considerations]
(https://developers.stellar.org/docs/build/apps/application-design-considerations)
guide: *"the user of the application stores their own secret key"*. This
is the single most important security/compliance fact about the whole
feature, so it is stated here explicitly rather than left implicit:

- The Stellar secret key (`S...`) is generated **on the user's device**
  (`StellarKeyService`), stored in the **platform keychain/keystore**
  via `flutter_secure_storage`, and **never leaves the device** — it is
  never sent to the PayFlex backend, never logged, and never leaves the
  signing code path.
- The backend's `StellarModule` is read-only (public Horizon data only).
  PayFlex **cannot** move a user's Stellar funds, and therefore holds no
  custody, no fiduciary role, and none of the licensing exposure that
  comes with holding users' crypto keys.
- The other three custody models from Stellar's guide were considered
  and rejected: a **custodial** model would make PayFlex the store of
  users' keys (a regulated-custodian role this rail deliberately does
  not take — BMONI already covers the managed-custody use case); a
  **multisig mixture** (non-custodial with recovery) is a possible
  future enhancement but adds key-management UX complexity this phase
  doesn't need; **third-party key-management services** (Ledger,
  StellarGuard, etc.) are out of scope for a mobile-first app.
- The known trade-off is accepted and surfaced to users: a non-custodial
  user who loses their device and secret key loses account access —
  there is no "PayFlex support can restore my wallet" path. Account
  creation follows Stellar's guide's Option 2 (the wallet creates and
  funds the account on sign-up; Friendbot on testnet, a deliberate
  manual step on mainnet — see "What's deliberately not automated").

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

## SDK choice: Stellar Wallet SDK evaluation (September 2026)

Stellar now publishes an official **Wallet SDK** (see the
[Tutorial: Wallet SDK](https://developers.stellar.org/docs/build/apps/wallet/overview))
that bundles wallet flows — SEP-10 anchor auth, SEP-24 deposit/withdrawal,
SEP-38 quotes, SEP-30 recovery — on top of raw transaction building. It
was evaluated for this rail and **not adopted**, for one concrete reason:

- Official SDF Wallet SDKs exist for **TypeScript**
  (`stellar/typescript-wallet-sdk`, active) and **Kotlin**
  (`stellar/kotlin-wallet-sdk`, **archived July 2026**). There is **no
  Dart/Flutter Wallet SDK** — the Wallet SDK tutorial's Flutter (Dart)
  tabs are implemented against the community **Soneso
  `stellar_flutter_sdk`**, which is exactly what this rail already uses
  (`app/lib/stellar/`), and which is the Flutter SDK listed on
  Stellar's official [SDKs page](https://developers.stellar.org/docs/tools/sdks).

Nothing in the current implementation is degraded by staying put: the
wallet flows the Wallet SDK wraps are anchor flows (SEP-10/24/38), and
this rail deliberately has **no anchor integration yet** — it does
direct Horizon account/payment/history operations, which the Soneso SDK
fully covers. The custody-model guidance from the Application Design
Considerations doc (above) is applied without needing the SDK.
**Revisit trigger:** if SDF ships a Dart Wallet SDK, or this rail adds
its first anchor on/off-ramp, re-evaluate then — adopting it for anchor
flows at that point would be a genuine improvement, not a rewrite.

## Anchor Platform & Stellar Disbursement Platform — evaluation notes

Both are SDF-published platforms relevant to PayFlex's cross-border and
agent-network ambitions. **Neither is implemented here** — research
only, per the phase plan; the basic Horizon rail ships first.

**[Anchor Platform](https://developers.stellar.org/docs/build/apps/anchor-platform)** —
SDF's reference implementation of the anchor side of fiat on/off-ramps
(SEP-06 deposit/withdrawal APIs, SEP-24 hosted interactive flows, plus
SEP-10 auth and SEP-38 quotes). This is the standard way Stellar-based
fintech apps connect to bank money, directly comparable to what BMONI
does on the BMONI side.

*Assessment:* worth adopting **when** PayFlex adds real fiat
on/off-ramps for Stellar assets — running an anchor API stack is
exactly the kind of standard, audited infrastructure that should not
be hand-rolled on top of raw Horizon calls, and it would let PayFlex
interoperate with the existing anchor ecosystem instead of building a
private one. But it is a server-side platform (its own database,
Ruby/JS services, KYC integration points), so adopting it is a real
infrastructure decision for the backend, not a client-side change. The
current Horizon-only payment flow is correct for the testnet phase and
remains the right foundation; Anchor Platform would **sit behind** it
(anchors move fiat, Horizon moves value) rather than replace it.

**[Stellar Disbursement Platform](https://github.com/stellar/stellar-disbursement-platform)** —
built for bulk/aid-style payouts: an organization registers recipients
(SEP-12 KYC data) and the platform disburses assets to many Stellar
accounts with verification codes, tracking, and retry semantics.

*Assessment:* potentially relevant to two PayFlex surfaces — Standing
Plans (recurring payments) and the agent network (bulk cash-out
settlements). The honest comparison: PayFlex's standing plans are
scheduler-driven individual payments through its own backend, which is
simpler and sufficient at current scale; SDP earns its complexity when
payouts are *one-to-many with per-recipient verification* (aid
distribution, agent float rebalancing across dozens of recipients). Not
worth adopting now; revisit if agent-network settlement ever becomes
"pay 50 agents tonight" rather than "pay one agent per event" — at that
point SDP's verification-code and tracking machinery beats looping
individual `sendPayment` calls.

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
