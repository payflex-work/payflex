# Accounts & keys

Every PayFlex user **is** a Stellar account. There is no separate wallet
signup, no custodial balance, and no "connect later" step: creating a
PayFlex identity and creating a Stellar keypair are the same event.

## Key generation and storage

- A fresh **Ed25519 keypair** (the Stellar `G...` account) is generated
  on the user's device during onboarding — never on the server, never in
  a browser, never logged.
- The **secret seed** lives in the platform-secured keystore:
  - iOS: Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`)
  - Android: Keystore-backed EncryptedSharedPreferences
- The app stores only the **public key** (`G...`) in ordinary preferences
  and in local profile state; the backend receives only the public key.

## What the server knows

| Data | Stored? |
| --- | --- |
| Public key (`G...`) | Yes — it is the user's identity |
| Secret seed (`S...`) | **Never** |
| PIN | **Never** — not even a hash |
| Transaction signatures | No — used to verify, then discarded |

The backend can identify users, verify signatures, and index their
on-chain activity. It cannot move funds. There is no code path, endpoint,
or script in this repository that can spend from a user account.

## PIN-gated signing

Signing is gated by a device-local PIN flow, not by the server:

1. The user sets a PIN during onboarding. Only a **SHA-256 verifier** is
   persisted locally (in `SharedPreferences`), never the PIN itself.
2. Every signing operation first checks the verifier; a wrong PIN aborts
   before any key material is touched.
3. The seed never leaves the keychain — operations are:
   `load seed → build transaction → sign in-memory → wipe`.

Changing the PIN re-arms the gate but never touches the keys. There is
deliberately **no cloud backup or social recovery** in this build; losing
the device seed means losing the account. That tradeoff is stated in the
onboarding copy rather than hidden.

## Account creation on testnet

On testnet, onboarding funds the new account through **Friendbot**
(`https://friendbot.stellar.org`), which creates the account on-chain and
tops it up with 10,000 XLM. This is a testnet convenience only — it does
not exist on mainnet.

## Mainnet activation (documented, not implemented)

On mainnet there is no Friendbot. An account must be **created by an
existing funded account**, which costs the **base reserve** (currently
1 XLM, subject to ledger-wide change) plus the transaction fee. Practical
consequences for a future mainnet build:

- A new user cannot self-fund from nothing — the app would need a
  sponsorship flow (e.g. a pooled creation account, SEP-29 sponsored
  reserves, or an on-ramp partner). That flow is **not built** and is
  not faked.
- Every trustline, offer, and data entry on an account also locks one
  base reserve — a wallet with several assets needs several XLM locked
  before any of it is spendable.
- These numbers must be re-read from the live network at build time;
  they are **not** constants to hardcode.

Related docs: [SEP-10 authentication](sep-10-auth.md) ·
[Payments lifecycle](payments-lifecycle.md)
