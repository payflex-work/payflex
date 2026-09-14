# Payments lifecycle

Every PayFlex payment — typed transfer, QR scan, PayTag, split-bill
share, or link claim — follows the same five steps. The server builds;
the device signs; Stellar settles; the indexer remembers.

## The five steps

```
1. RESOLVE   app → backend:  who is "paytag/alice", this QR, or this
             link token? Backend returns destination publicKey, amount
             context, and an HMAC-signed token binding the specifics.
2. BUILD     app → backend:  submit the signed token; backend builds an
             unsigned payment XDR (correct asset, amount in stroops,
             memo) and returns it. Backend CANNOT spend: building is
             not signing, and the XDR is inert until signed.
3. SIGN      on-device:     PIN gate → load seed from keychain → sign
             the exact XDR the backend built → wipe. The user approves
             amount + destination in the same step.
4. SUBMIT    app → Stellar:  the signed envelope goes directly to the
             network (Horizon/Soroban RPC), not through the backend.
             Result: a real transaction hash.
5. RECORD    app → backend:  the hash + context go to the backend,
             which stores a TransferRecord and lets the indexer attach
             ledger effects. History = what Stellar says happened.
```

## Why this split

- The **backend can build but never sign** — it holds no secrets with
  spending power, so a full backend compromise yields no funds.
- The **device signs but never submits blindly** — it signs the exact
  XDR it displayed to the user.
- **Stellar is the arbiter** — a payment exists when the network says
  it exists, and its hash is verifiable by anyone on an explorer.

## Feature mapping

| Feature | Resolve | Build | Confirm |
| --- | --- | --- | --- |
| Send money (paytag/G-address) | `/v1/transfer/resolve` | `/v1/transfer/build` | hash → `/v1/transfer/record` |
| QR Pay (online) | QR carries HMAC token → `/v1/transfer/qr/...` | same pipeline | same |
| Split bill share | bill QR token → resolve | pay creator directly | same |
| Send via link | share token → `/v1/links/preview` | backend creates a **claimable balance** escrow on-chain | claimant signs claim op |
| Safebox contribution | safebox contract id | Soroban invoke (client-side) | indexer / `getTransaction` |
| Standing Plan (manual) | plan → resolve payee | same payment pipeline | same |

## Claimable balances (send-via-link)

Links use Stellar's native escrow primitive instead of a database row:
the sender's signed transaction **creates a claimable balance** with an
unconditional predicate, and the recipient claims it from their own
device. The backend tracks only the link metadata (id, share token,
status) — the money itself is on-chain under a balance id, visible to
anyone. Unclaimed links are recoverable on-chain by the creator; there
is no backend "cancel" that moves money, because the backend cannot.

## Memos and references

Payments carry a memo so the indexer can attribute transfers to app
objects (transfer id, link id, safebox id). Memos are included when the
XDR is built, so what the user signed is exactly what settles.

## Failure modes

| Step fails | User sees | Money is |
| --- | --- | --- |
| Resolve (offline/unreachable) | clear retry error | untouched |
| Build | retry error | untouched |
| Sign (wrong PIN / cancel) | back to form | untouched |
| Submit (network drop) | "not submitted — retry safely" | untouched |
| Submit accepted, response lost | fetch tx by hash before ever retrying | safe — idempotent check |

The double-submit question is settled by hash, not by hope: before any
retry, the app looks up the previous hash; a found transaction means
already-submitted, and the flow records it instead of resending.

Related docs: [Accounts & keys](accounts-and-keys.md) ·
[Offline Reserve & redemption](offline-reserve.md)
