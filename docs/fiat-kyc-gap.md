# The fiat / KYC gap — what this app deliberately does not have

> **Read this before assuming PayFlex can move real-world money or verify
> anyone's identity. It cannot.** This document describes exactly what is
> missing, where a real implementation would plug in, and why the app is
> architecturally incapable of pretending otherwise.

## The situation, stated plainly

PayFlex is a working Stellar testnet application. It has **no fiat rail** and
**no identity verification**:

- No user can deposit naira or dollars. No user can withdraw them. There is
  no bridge between bank accounts / cash agents and this app, anywhere in the
  codebase.
- No user is identity-verified. The app has never run a KYC check and cannot
  claim anyone is verified. There is no BVN collection, no document upload, no
  liveness check — nothing.
- Any feature that fundamentally required one of the two above is **paused**
  (shown as an honest "coming soon" state, gated server-side), not faked.

## Why the gate is architectural, not cosmetic

Every account carries two flags:

```
AppUser.identityVerified: Boolean  @default(false)
AppUser.fiatCapable:      Boolean  @default(false)
```

These flags are **settable only through provider interfaces**:

- `backend/src/providers/identity-verification-provider.ts` — `IIdentityVerificationProvider`
- `backend/src/providers/fiat-rail-provider.ts` — `IFiatRailProvider`

Both interfaces ship as **signatures and docstrings only**. There is no
implementation, no stub that returns fake approvals, no mock provider wired
behind an env flag, no placeholder credentials. Since no class implements the
interfaces, and the flags are only mutated behind them, **there is no code
path in this repository that can set either flag to `true`**. That is the hard
gate. It is enforced by module wiring (no provider is registered), not by
discipline.

The gated endpoints themselves (`backend/src/gated/gated.controller.ts` —
virtual card, agent network, betting funding, loans) fail closed with an
explicit error. The test `backend/test/gated-features.e2e-spec.ts` proves an
authenticated user hitting them is refused.

## What a real implementation would look like

### Identity verification (`IIdentityVerificationProvider`)

The interface is deliberately shaped like a real KYC workflow:

- Create/resume a verification session for an app user.
- Accept the standard document set (ID document, selfie/liveness, proof of
  address where jurisdiction requires) with an explicit status model
  (`pending / approved / declined`) — never a binary fake "approved".
- Expose only the *outcome* to the rest of the app. The rest of the app never
  sees raw verification data; it sees `identityVerified` flip to `true` —
  and only then do identity-gated surfaces unlock.

Reference options when this gets picked up (not a commitment to any):

- **A Stellar anchor implementing SEP-12** (the anchor's own KYC API) — the
  natural fit if the fiat rail below is also an anchor.
- A dedicated identity provider (Sumsub, Persona, Smile ID for African
  markets, etc.) integrated behind the same interface.

### Fiat rail (`IFiatRailProvider`)

Deposit: user pays real NGN/USD to the provider (bank transfer, USSD, card,
agent network) → provider confirms → provider (or its integration) delivers
the matching Stellar asset to the user's account — e.g. a fiat-backed asset
issued by a regulated anchor, with the user's trustline established in-app.
Withdrawal: the same path in reverse, with the asset burned/redeemed and real
money paid out.

Reference options when this gets picked up (not a commitment to any):

- **A regulated Stellar anchor** for NGN (e.g. the LINK/NGNC ecosystems) —
  SEP-6 (deposit/withdraw), SEP-24 (interactive flow), SEP-12 (KYC), SEP-31
  (direct payments) are the relevant standards; an anchor that implements
  these gives both rails and KYC under one roof, which is why the interface
  shapes match them.
- A licensed local partner (payment processor / mobile-money aggregator) that
  holds real balances and settles on-chain.

## Features paused because of this gap

| Feature | Why it cannot exist without the gap being filled |
|---|---|
| Virtual cards | Card issuance requires a processor partnership and a real funding source. |
| Agent cash-in/cash-out | Agents existed to convert physical cash ↔ fiat balances; there are no fiat balances. |
| Betting funding | Moved real fiat to licensed betting operators; requires the fiat rail plus jurisdiction licensing. |
| Loans / credit scoring | Needs a treasury to disburse from and verified history to score. |
| Real (fiat-denominated) balances | Every balance in the app today is a real on-chain Stellar asset — which on testnet has no real-world value. |

These are reachable in the UI as clearly-labeled paused states and blocked
server-side. They are not hidden, and they are not simulated.

## What the app CAN do without the gap being filled

Everything that is genuinely possible on a public blockchain with no
custodian: real on-chain payments in XLM and issued assets (whatever assets a
user's account holds), group escrow via the Safebox contract, claimable-
balance payment links, split bills, standing-plan scheduling (the signing
stays human), and the offline optical protocol with on-chain settlement.

## The rule going forward

The documentation and the app must never claim fiat capability or identity
verification while the gate is closed. When a real provider is chosen, the
implementation lands behind the two interfaces above, the flags become
writable **through it**, the gated surfaces unlock, and this document is
rewritten in the past tense.
