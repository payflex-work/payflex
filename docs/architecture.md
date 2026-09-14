# PayFlex Architecture — Stellar-only

> This document describes the architecture **as it is now**: Stellar is the
> only payment and settlement layer. Status statement: PayFlex is a real,
> working **Stellar testnet** application. It is not a bank, not
> production-ready, and must not be described as either until the fiat/KYC
> gate (see [`fiat-kyc-gap.md`](fiat-kyc-gap.md)) is opened by a real provider.

## The one-paragraph version

Every PayFlex user **is** a Stellar account: the Ed25519 keypair is generated
on-device, the secret seed lives in the platform keychain/keystore and never
leaves the phone, and every payment is built, signed, and submitted from the
device via the official Stellar SDK. The NestJS backend orchestrates
(directory, PayTags, QR tokens, link/split/plan records) and **verifies**
(pulls claimed transactions from Horizon before storing them), but has no
endpoint that can move funds. Group savings are enforced by a real Soroban
escrow contract; send-via-link uses on-chain claimable balances; the offline
optical protocol settles through ordinary Stellar payments on reconnect.

## Modules

| Module | Role |
|---|---|
| `backend/src/stellar/` | Read-only Horizon + Soroban RPC companion: account lookups, payment verification (`verifyPayment`), Safebox contract reads. Never builds or signs. |
| `backend/src/users/` | Account directory; registers each account's Stellar public key once (immutable after). |
| `backend/src/auth/` | Challenge-response login: backend issues a nonce, the app signs it with the device's Stellar key, the backend verifies against the registered key. JWT access/refresh tokens; bootstrap tokens scoped to exactly one call. |
| `backend/src/transfer/` | Resolve (PayTag/public key → destination), QR token generation/decoding (HMAC-signed), and **verified** transfer recording — the app's transaction history source of truth. |
| `backend/src/standing-plans/` | Scheduler marks payments DUE. No delegated debit exists on Stellar; the app refuses to fake one, so a human still signs every due payment on-device. |
| `backend/src/links/` | Claimable-balance payment links: the app creates the CB on-chain, the backend verifies it exists on Horizon and (on claim) that it is gone. |
| `backend/src/split-bill/` | Bill orchestration; contributors pay the creator directly, each payment recorded with `splitBillId`. |
| `backend/src/safebox/` | Registry of deployed Safebox contract ids + live chain state reads. No contribute/withdraw endpoints by design — the chain moves the money. |
| `backend/src/gated/` | Paused-feature endpoints (card, agent, betting, loans) that **fail closed** with explicit "not implemented" errors. |
| `backend/src/providers/` | The unimplemented `IIdentityVerificationProvider` and `IFiatRailProvider` interfaces + the hard-gate service. Docstrings only. |
| `backend/contracts/safebox/` | The Soroban escrow contract (Rust): owner/admin-only withdrawal, 3-admin cap, on-chain ledger + events. |
| `app/lib/stellar/` | On-device Stellar client: key management (`StellarKeyService`), Horizon access, payment building/signing/submitting, claimable balances. |
| `app/lib/protocol/` | The offline optical QR protocol (fountain-coded transport, device-signed requests/confirmations, chained Reserve authorizations). |

## The keys — exactly two on-device identities

| Key | Curve / encoding | Held by | Purpose |
|---|---|---|---|
| Stellar account key | ED25519, StrKey (`G...`/`S...`) | `StellarKeyService` (`flutter_secure_storage` — platform keychain/keystore) | **The account.** Signs every payment, claim, contract invocation, and login challenge. PIN-gated. |
| Offline-protocol device key | ED25519, raw hex | `DeviceKeyService` (SharedPreferences, hook-injectable) | Signs offline optical-handoff messages — proves *device* identity without network. Deliberately independent of the account key. |

They are never reused across each other — different blast radius, different
failure model. The offline key can authorize nothing on-chain; the account
key never signs offline handoff messages.

## Money movement — the only path

```
resolve recipient (PayTag | public key | QR token | link | plan)
  → user confirms + PIN
  → app builds the Stellar transaction on-device
  → WalletService.signTransaction (PIN-gated, secure-storage key)
  → submit straight to Horizon
  → backend verifies the transaction on Horizon, then records it
```

There are no variants of this path that skip signing, skip verification, or
route through a server-held key. The backend's treasury-signing concept from
the previous architecture is **gone**: no server-side signing exists at all.

## The hard gate

`AppUser.identityVerified` and `AppUser.fiatCapable` default to `false` with
**no code path that sets them true** — the setters live behind provider
interfaces no implementation satisfies. Every gated feature checks these
flags server-side; `backend/src/gated/` refuses the paused features outright.
The e2e suite (`backend/test/gated-features.e2e-spec.ts`) proves a
authenticated user hitting the gated endpoints gets blocked, not redirected
or silently allowed.

## Offline protocol

Unchanged cryptographic core (independent device key, chained authorizations,
fountain-coded optical transport), one change of destination: where a queued
offline authorization previously awaited a banking-rail settlement, it now
becomes an ordinary on-device Stellar payment (`kind=OFFLINE_REDEMPTION`,
memo referencing the authorization id) the moment connectivity returns. The
offline signatures prove device provenance; the Stellar payment settles
value; the backend verifies both link up.

## What was deliberately removed

- The former banking-rail module and every derived service (KYC wizard,
  proposal/sign transfers, virtual cards, agent network, betting funding,
  loans, treasury escrow/signing, fiat balance ledgers).
- All server-side signing (treasury keys are no longer part of the system).
- App-level Safebox ledgers the backend could rewrite — replaced by the
  contract's own on-chain ledger.

Historical records from the previous era were archived, not deleted (see
`backend/scripts/export-legacy-archive.ts`), and no new writes go to them.

## Further reading

- [`fiat-kyc-gap.md`](fiat-kyc-gap.md) — what is missing and the two interfaces
  waiting for a real provider
- [`stellar/`](stellar/) — SEP-by-SEP deep dives on the rail
- [`deploy.md`](deploy.md) — environment variables and platform configs
