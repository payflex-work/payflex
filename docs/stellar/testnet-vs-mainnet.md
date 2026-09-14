# Testnet vs mainnet

PayFlex currently runs on **Stellar testnet**. This page records what
that means, what mainnet would require, and why the app makes flipping
the flag deliberately hard.

## Current default: testnet

| Setting | Value |
| --- | --- |
| Network | `STELLAR_NETWORK=testnet` (default — unset is testnet) |
| Horizon | `https://horizon-testnet.stellar.org` (SDF default when blank) |
| Friendbot | `https://friendbot.stellar.org` (funds new accounts with 10,000 XLM) |
| Passphrase | `Test SDF Network ; September 2015` |

On testnet, XLM and assets have **no value**. Every demo, walkthrough,
and CI run uses it. There is no credential to obtain — which is exactly
why nothing here is pretending to be production.

## Mainnet: what the code does

The network guard lives in `backend/src/config/stellar.config.ts`:

- `STELLAR_NETWORK=mainnet` **without** an explicit
  `STELLAR_HORIZON_URL` refuses to boot with a loud error. This is a
  business/compliance decision encoded as code, because silently
  pointing unmediated value at the wrong network is not a recoverable
  mistake.
- Friendbot is **disabled** on mainnet (it does not exist there).
- The passphrase switches to `Public Global Stellar Network ; September 2015`.

## Mainnet: what is NOT built (be honest)

Going to mainnet is not a config flip. These are real gaps, not TODOs:

1. **Account creation sponsorship.** No Friendbot means a new user with
   zero XLM cannot activate an account. Someone must fund creation —
   a sponsorship pool, SEP-29 sponsored reserves, or an on-ramp. Not
   designed, not built.
2. **Reserve accounting in the UX.** Every account locks the base
   reserve (1 XLM at time of writing — must be read live, never
   hardcoded); every trustline locks another. Balances shown to users
   must distinguish *spendable* from *locked* or users will see
   phantom money. Not built.
3. **Fee/bump strategy.** Fee-bump transactions to rescue stuck
   submissions, and fee spikes at network congestion, have no UX. Not
   built.
4. **Key recovery story.** There is no cloud backup or social recovery
   by design. On mainnet, "lose your seed = lose your money" needs an
   explicit, legally-reviewed user agreement and probably an optional,
   clearly-labeled recovery product. Not built.
5. **Real assets and trustlines.** Contributing a real asset (e.g.
   USDC) requires trustline establishment UX and issuer due diligence.
   The SAC derivation math already works for any asset, but the
   issuance/trust UX does not exist.

None of these are faked or stubbed. See
[`../fiat-kyc-gap.md`](../fiat-kyc-gap.md) for the plug-in interfaces
waiting for a real provider, and
[`../deploy.md`](../deploy.md) for the env-var contract.

## The one-sentence version

Testnet is a working payments product with play-money; mainnet is a
different product with real obligations, and the codebase refuses to
pretend the second exists.
