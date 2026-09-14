# Offline Reserve & redemption

The offline protocol is PayFlex's most differentiated feature: payments
that work when **both devices have zero connectivity**, using an
animated optical QR channel — and settle on Stellar later. It was built
with its own independent device-key signing from day one; Stellar
integration concerns only the settlement step.

## Payment-time (airplane mode, no network)

```
Payer device                        Payee device
    |  amount entered                     |
    |  HMAC token built from:             |
    |    payer device key, payee device   |
    |    key, amount, nonce, timestamp    |
    |    (QR_SIGNING_SECRET-derived key)  |
    |                                     |
    |   ~~~~ animated optical QR ~~~~     |  frames streamed as
    |   ~~~~ fountain-coded chunks ~~~~   |  video-rate QRs; receiver
    |   ~~~~ ("data fountain") ~~~~       |  reassembles + verifies
    |                                     |
    |                                     |  authorization verified
    |                                     |  → "verified — settlement
    |                                     |     pending" (NOT "settled")
```

- Signatures are made by a **dedicated device key** held in the same
  platform keychain as the Stellar seed (`app/lib/services/device_key_service.dart`),
  with its own verifier — the cryptographic core is independent of the
  payment rail and did not change in the Stellar migration.
- The HMAC binds payer, payee, amount, and a nonce, so an authorization
  cannot be replayed, split, or inflated.
- The protocol is deliberately independent of connectivity *and* of the
  backend: no server sees the payment happen.

## Redemption-time (back online)

A pending authorization is not money yet — it becomes money through
**Stellar settlement** (`app/lib/services/offline_redemption_service.dart`):

1. The payee's app submits the stored authorization payload to the
   backend (`/v1/transfer/offline/redeem`).
2. The backend verifies the device-key signatures and nonce, exactly as
   it verifies the original optical stream — same HMAC key, same
   checks, no trust in the redeemer.
3. It **builds a Stellar payment** (payer → payee, exact amount, memo
   referencing the offline authorization) and returns the XDR.
4. The payer's device signs it through the normal PIN-gated flow and
   submits to the network (the standard
   [payments lifecycle](payments-lifecycle.md) steps 3–5).
5. The indexer confirms; the record flips **"verified — settlement
   pending" → "settled"** with a real transaction hash.

## Honesty rules (non-negotiable)

The status vocabulary is the feature. It is enforced in copy and code:

- **"verified — settlement pending"** means signatures checked out but
  no on-chain transfer exists yet. The payee has *not* been paid.
- **"settled"** means the Stellar transaction is confirmed on the
  ledger. Only then.
- The UI never collapses these two states, never calls a pending
  authorization "received", and shows the pending badge until the hash
  exists. During the migration this vocabulary was preserved exactly —
  polish passes may reword *around* it, never through it.

## What this buys, and what it costs

- **Buys:** payments between two phones with no network, no backend, no
  bank rail — verified cryptographically at the moment of transfer.
- **Costs (honest):** settlement still requires the payer to be online
  eventually, and requires the payer's device to sign at redemption
  time. An offline authorization is a **promise with strong
  cryptographic receipts**, not cleared funds. The docs and the UI both
  say this.

Related docs: [Payments lifecycle](payments-lifecycle.md) ·
[Accounts & keys](accounts-and-keys.md)
