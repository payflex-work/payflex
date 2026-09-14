# PayFlex — Technical Summary (SCF)

> Companion to [`project-overview.md`](project-overview.md). Everything here
> is verifiable in the public repository and in Stellar's own tooling. Where a
> claim is about verification status, the verification method is stated
> alongside it.

## Architecture (summary)

Full architecture documentation lives in
[`/docs/architecture.md`](../architecture.md); the Stellar deep-dives are the
GitBook-style set under [`/docs/stellar/`](../stellar/README.md). The
load-bearing points:

- **Every user is a Stellar account.** On-device Ed25519 keypair (StrKey
  `G...`/`S...`), seed in the platform keychain (`flutter_secure_storage`),
  PIN-gated signing. The backend never holds a seed and has no endpoint that
  can move funds.
- **The backend is a read-only companion.** NestJS: directory, PayTags, QR
  tokens (HMAC), link/split/plan orchestration — and **Horizon verification**
  of every claimed transaction before it is recorded. No server-side signing
  exists anywhere in the system.
- **Exactly two on-device identities, never crossed.** The Stellar account key
  signs payments/claims/contract invocations/login challenges; an independent
  device key signs offline optical handoffs. Different blast radius, different
  failure model.
- **Money movement has exactly one path:** resolve → confirm + PIN → build
  on-device → PIN-gated signature → submit to Horizon → backend verifies on
  Horizon → record. No variants skip signing or verification.

## What is genuinely built and verified

Each item below lists how it was verified, not merely that it exists:

| Component | Verification |
|---|---|
| Account creation + Friendbot funding | Executed live against Stellar testnet this development cycle (two fresh accounts, real Friendbot calls) |
| Native + issued-asset payments | Live testnet transactions with hashes (e.g. native payment `6b171ab1…`, trustline `765a3a55…`, issued-asset payment `87426d0e…`); balances and history confirmed via Horizon for both parties |
| Verified transfer recording | Backend pulls the claimed transaction from Horizon and checks every field before storing; **negative controls executed**: fabricated transfers, wrong-destination, and self-payment records are all rejected |
| SEP-10-shaped authentication | Full flow exercised with a real Ed25519-signed challenge against the running backend; covered by backend unit + e2e tests |
| **Soroban Safebox escrow contract** | Rust contract with **12/12 contract tests passing**, including on-chain rejection of withdrawals by non-admins and outsiders, owner-only close, and the 3-admin cap |
| Send via link (claimable balances) | On-chain claimable balance creation/claim flow, backend-verified on Horizon |
| Standing plans | DUE-marking orchestration verified via API; execution remains an ordinary on-device payment (no delegated debit is faked) |
| **Offline Reserve + optical QR protocol** | The distinctive component. Fountain-coded transport, device-key-signed requests/confirmations, hash-chained Reserve authorizations, replay + tamper rejection. Full two-device optical loop covered in-app; final live redemption-on-reconnect leg pending a two-device field rehearsal (the sandbox cannot run two physical devices) |
| Flutter app | **47/47 tests passing**; `flutter analyze` fully clean (CI enforces zero findings) |
| Backend | **22/22 unit + 9/9 e2e tests passing**; Docker image build verified locally, including fresh-database migration and health-gated smoke test |

## Why this is more than "another wallet app"

The offline optical protocol is a genuine technical contribution:

- **Fountain coding (LT-style rateless erasure code)** over a camera link: any
  sufficient subset of animated QR frames reconstructs the payload — no
  per-frame ordering or delivery guarantee needed.
- **Independent device key** signs every offline authorization, so a payment
  made in airplane mode still has cryptographic provenance without network.
- **Hash-chained Reserve authorizations** with monotonic sequence numbers:
  offline spends cannot be reordered, replayed, or overspent, and each spend's
  state hash chains to the previous one.
- **Honest settlement semantics**: an offline payment is presented as
  "confirmed — settlement pending" and becomes an ordinary, explorer-visible
  Stellar payment (`kind=OFFLINE_REDEMPTION`) on reconnect. The app never
  claims "settled" before the chain says so.

## Repository and documentation

- **Source:** `github.com/payflex-work/payflex` (app/ Flutter, backend/ NestJS,
  backend/contracts/safebox/ Soroban contract, docs/)
- **Stellar documentation set:** [`/docs/stellar/README.md`](../stellar/README.md)
  — accounts & keys, SEP-10-shaped auth, payments lifecycle, Safebox on
  Soroban, offline Reserve & redemption, testnet-vs-mainnet
- **The fiat/KYC gap, stated honestly:**
  [`/docs/fiat-kyc-gap.md`](../fiat-kyc-gap.md) — the two provider seams and
  what a real implementation plugs into
- CI: backend test workflow + backend Docker build with fresh-DB smoke test;
  Flutter CI requires a fully clean `flutter analyze` and all tests green

**[FOUNDER INPUT NEEDED: confirm the public repo URL and that it should be
linked in the submission; add the GitBook published URL for the Stellar docs
set if/when published publicly.]**
