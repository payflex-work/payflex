# PayFlex on Stellar — documentation set

This set documents the one payment architecture PayFlex has: **Stellar,
non-custodial, user-signed**. There is no second rail. Start here and
follow the links in reading order.

> **Status:** real, working **testnet** application. Not a bank, not
> production-ready. Fiat and identity verification are intentionally
> unimplemented — see [`../fiat-kyc-gap.md`](../fiat-kyc-gap.md).

## In this set

1. **[Accounts & keys](accounts-and-keys.md)** — how every user *is* a
   Stellar account: on-device Ed25519 keypairs, the keychain, PIN-gated
   signing, and why the server never sees a secret.
2. **[SEP-10 authentication](sep-10-auth.md)** — how login works:
   challenge → on-device signature → JWT, with no passwords anywhere.
3. **[Payments lifecycle](payments-lifecycle.md)** — build → sign →
   submit → confirm: what happens on the device, on the server, and on
   the network for transfers, QR Pay, PayTags, split bills, and links.
4. **[Safebox (Soroban)](safebox-soroban.md)** — the on-chain escrow
   contract: owner/admin roles, the 3-admin cap, and how contributions
   become visible to all members via the indexer.
5. **[Offline Reserve & redemption](offline-reserve.md)** — the optical
   QR protocol: device-key-signed authorizations that work with zero
   connectivity, and how redemption settles them on Stellar later.
6. **[Testnet vs mainnet](testnet-vs-mainnet.md)** — defaults, the
   mainnet guard, account reserves, and what flipping the flag really
   means.

## Cross-cutting rules

- **Non-custodial, always.** Secret keys are generated on-device and
  stored in the platform keychain/keystore. The backend holds public
  keys, never seeds. Any design that would put a seed on the server is
  rejected on sight.
- **The indexer is the source of truth.** Balances and history come from
  Stellar's own ledger (via the backend indexer), not from an app-side
  bookkeeping copy.
- **Honest language.** A payment is "confirmed" when the network says so,
  and "settled" only when it is. Offline authorizations are "verified —
  settlement pending" until redemption puts them on-chain.
