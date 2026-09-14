# SEP-10 authentication

PayFlex has **no passwords**. Login proves control of the account's
Stellar key using the SEP-10 challenge pattern (web-auth-for-wallets),
adapted to PayFlex's own backend as the issuing server.

## The flow

```
Flutter app                         PayFlex backend
    |                                      |
    |  POST /v1/auth/challenge             |
    |  body: { publicKey }                 |
    |------------------------------------->|
    |                                      | builds a challenge tx:
    |                                      |   op: manageData "payflex auth"
    |                                      |   value: 64-byte server nonce
    |                                      |   timeBounds: ~5 minutes
    |<-- { challengeXdr, serverNonce } ----|
    |                                      |
    | device verifies the server's         |
    | signature on the challenge, then     |
    | signs it with the on-device seed     |
    | (PIN-gated, keychain-only)           |
    |                                      |
    |  POST /v1/auth/verify                |
    |  body: { challengeXdr, signedXdr }   |
    |------------------------------------->|
    |                                      | verifies BOTH signatures,
    |                                      | checks timeBounds + nonce,
    |                                      | resolves publicKey → appUser
    |<-- { accessToken, refreshToken } ----|
    |                                      |
    |  all subsequent requests:            |
    |  Authorization: Bearer <jwt>         |
```

## Why this is safe

- **The challenge is single-use and short-lived.** A captured challenge
  cannot be replayed: the nonce is stored server-side and burned on
  first verification, and timeBounds expire it within minutes.
- **The client verifies the server first.** The challenge transaction is
  signed by the server's key; the app checks that signature before
  countersigning, so a phishing server cannot harvest a signature over
  attacker-chosen content.
- **The signature never authorizes value.** SEP-10 challenges are
  `manageData` operations with no payment — a stolen signature authorizes
  nothing but the login itself.
- **The JWT is ordinary bearer auth.** Access tokens are short-lived;
  refresh tokens rotate. JWTs say who you are on the API; they are not
  spending authority on-chain.

## Relationship to Stellar SEP-10

This is the SEP-10 *shape* — challenge transaction, dual signatures,
time bounds — issued by PayFlex's own backend rather than by a Stellar
anchor, because PayFlex is its own identity provider. If a future fiat
provider (see [`../fiat-kyc-gap.md`](../fiat-kyc-gap.md)) brings a real
anchor, its own SEP-10 can coexist: the anchor auths against the anchor,
PayFlex auth stays for the app.

## Where it lives in the code

| Piece | File |
| --- | --- |
| Challenge/verify endpoints | `backend/src/auth/auth.controller.ts` |
| Signature verification + JWT issuing | `backend/src/auth/auth.service.ts` |
| JWT guard on every route | `backend/src/auth/auth.guard.ts` |
| On-device challenge signing | `app/lib/services/wallet_service.dart` |
| App-side client calls | `app/lib/services/api_client.dart` |

Related docs: [Accounts & keys](accounts-and-keys.md) ·
[Payments lifecycle](payments-lifecycle.md)
