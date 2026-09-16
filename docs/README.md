# PayFlex Documentation

This folder is the complete documentation set for PayFlex: a **non-custodial
payments app on Stellar** where every user *is* a Stellar account, the
backend orchestrates and verifies but can never move funds, and every
payment is built, signed, and submitted from the user's device.

> **Honest status:** a real, working **Stellar testnet** application. Not a
> bank, not production-ready. Fiat on/off-ramps and identity verification
> (KYC) are deliberately unimplemented — see
> [`fiat-kyc-gap.md`](fiat-kyc-gap.md) before assuming otherwise.

## Start here

New to the project, read in this order:

1. The [root README](../README.md) — what PayFlex is, what works today, what
   is honestly paused, and how to run it.
2. [`architecture.md`](architecture.md) — the whole system on one page:
   modules, the two on-device keys, the only path money can move, the hard
   gate.
3. [`stellar/README.md`](stellar/README.md) — the SEP-by-SEP deep dives on
   the rail: accounts & keys, login, the payments lifecycle, Safebox, the
   offline protocol, and testnet vs mainnet.

Then jump to whatever you're doing, via the map below.

## The map

| Document | Answers the question… |
|---|---|
| [`../README.md`](../README.md) | What is this project and how do I run it? |
| [`architecture.md`](architecture.md) | How is the system put together, and why can't the backend move money? |
| [`deploy.md`](deploy.md) | How do I deploy the backend (Railway / Render / Fly.io) and point the app at it? |
| [`fiat-kyc-gap.md`](fiat-kyc-gap.md) | What can this app *not* do, and where would a real fiat/KYC provider plug in? |
| [`stellar/README.md`](stellar/README.md) | Index of the Stellar deep-dive set (below). |
| [`stellar/accounts-and-keys.md`](stellar/accounts-and-keys.md) | How are keys generated, stored, and PIN-gated — and what does the server never see? |
| [`stellar/sep-10-auth.md`](stellar/sep-10-auth.md) | How does passwordless login work? |
| [`stellar/payments-lifecycle.md`](stellar/payments-lifecycle.md) | What happens, step by step, when money moves? |
| [`stellar/safebox-soroban.md`](stellar/safebox-soroban.md) | How does the on-chain escrow contract enforce group savings? |
| [`stellar/offline-reserve.md`](stellar/offline-reserve.md) | How do payments work in airplane mode, and how do they settle later? |
| [`stellar/testnet-vs-mainnet.md`](stellar/testnet-vs-mainnet.md) | What would going to mainnet actually require? |
| [`scf-application/`](scf-application/README.md) | Draft materials for a Stellar Community Fund submission (project-specific, not engineering docs). |

## Words this project uses precisely

These terms are load-bearing; the app UI and the docs use them
interchangeably with the code's own states.

- **Non-custodial** — secret keys are generated on-device and live in the
  platform keychain/keystore. The backend holds public keys, never seeds.
  There is no support-restore path: lose the device and the seed, lose the
  account.
- **Verified transfer** — a transfer the backend pulled from Horizon and
  checked field-by-field against the app's claim before storing. Nothing is
  recorded on the word of the client alone.
- **"verified — settlement pending"** — an offline authorization whose
  signatures checked out but which is **not money yet**: no on-chain
  transfer exists. The payee has not been paid.
- **"settled"** — the Stellar transaction is confirmed on the ledger. Only
  then.
- **Safebox** — a per-group Soroban escrow contract; the contract's own
  storage is the ledger, and the backend only renders what the chain says.
- **The hard gate** — `identityVerified` / `fiatCapable` default to `false`
  with no code path that can set them true; gated features fail closed
  server-side.

## Writing documentation here

The honest-status rule is a project rule, not a stylistic preference (see
"Engineering rules" in the root README):

1. **Never** call PayFlex production-ready, launch-ready, or a bank while
   the fiat/KYC gate is closed.
2. Keep the status vocabulary exact: "verified — settlement pending" is not
   "settled", and a pending offline authorization is not "received".
3. Update docs in the same change that changes behavior — an out-of-date
   doc here is a claim the app doesn't back.
4. Testnet is the default network in every example. Anything mainnet is
   documented as a decision, not a config flip.
5. Relative links only between docs in this folder, so the set works on
   GitHub, GitBook, and any markdown renderer.

Where code referenced by docs lives: backend modules are tabulated in
[`architecture.md`](architecture.md#modules); key files are linked inline
throughout the `stellar/` set.
