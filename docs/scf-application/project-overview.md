# PayFlex — SCF Project Overview

> Draft for the Stellar Community Fund application. Every technical claim in
> this document is sourced from the current codebase and the verification work
> recorded against it (see [`technical-summary.md`](technical-summary.md) for
> what "verified" means here). Anything the SCF team needs from the founders
> that is not yet written is marked **[FOUNDER INPUT NEEDED]**.

## What PayFlex is

PayFlex is a **non-custodial payments app on Stellar**, built for the real
conditions of Nigerian microfinance users: unreliable connectivity, cash-heavy
commerce, and deep distrust of intermediaries. Every PayFlex user *is* a
Stellar account — the Ed25519 keypair is generated on-device, the secret seed
lives in the phone's platform keychain and never leaves it, and every payment
is built, signed, and submitted from the device.

The product differentiator, and the reason this project exists: **the wallet
keeps working when the network doesn't.** Two devices can complete a payment
in airplane mode over an animated optical QR channel (fountain-coded, signed
by an independent device key), and the payment settles as an ordinary Stellar
transaction the moment either device reconnects. No other mobile wallet does
this; it is PayFlex's most distinctive technical contribution to the ecosystem.

## The problem

Nigeria's underbanked majority transacts daily in physical cash over flaky
data connections. Existing mobile wallets fail them in two specific ways:

1. **Custody.** Phone-number-bound wallets are custodial: the operator holds
   the keys, can freeze funds, and stands between the user and their money.
2. **Connectivity dependence.** A payment at the market stall fails when the
   network does — exactly when the transaction matters most.

PayFlex attacks both: keys live on the user's device (the backend has no
endpoint that can move funds), and the offline protocol makes connectivity
optional for the payment itself, with Stellar settling the value on reconnect.

## What is built and verified today (Stellar testnet)

| Capability | How it works |
|---|---|
| **Transfers, PayTags, QR Pay** | resolve → user confirms + PIN → transaction built and signed on-device → submitted to Horizon → backend verifies the real on-chain transaction before recording it |
| **Safebox group savings** | a deployed **Soroban escrow contract**: owner/admin-only withdrawal and a 3-admin cap enforced **on-chain**, with the contract's own ledger and events visible to all members |
| **Send via link** | non-custodial **claimable balances** — funds escrowed by the chain itself, never by PayFlex |
| **Standing plans** | scheduler marks payments DUE; the human still signs every due payment on-device (Stellar has no delegated debit, and PayFlex refuses to fake one) |
| **Split bills** | orchestration only; each contributor pays the creator with an independent on-device payment |
| **Offline Reserve + optical QR** | device-key-signed, hash-chained authorizations transferred by fountain-coded QR; **redemption settles as a real Stellar payment on reconnect** |
| **Login** | challenge signed with the user's own Stellar key (SEP-10-shaped) — no passwords anywhere |
| **Backend** | NestJS companion that resolves, orchestrates, and **verifies against Horizon** — deliberately read-only with respect to funds |

Paused by design (gated server-side, honestly labeled in the UI — not faked):
virtual cards, agent cash-in/out, betting funding, loans. These have no
function without a fiat rail, and the gate (`identityVerified`/`fiatCapable`,
with **no code path that can set them true**) is enforced by an empty,
deliberately-unimplemented provider seam, proven fail-closed by the e2e suite.

## Current stage — stated plainly

PayFlex is a **working Stellar testnet application**. It is not a bank, and it
is not described as production-ready anywhere in its own materials. Fiat
on/off-ramps and identity verification are intentionally unimplemented: the
provider interfaces exist as clean seams (`IIdentityVerificationProvider`,
`IFiatRailProvider` — SEP-12- and SEP-6/24-shaped), and opening that gate is a
documented partnership decision, not missing code. We consider this honesty a
feature: an SCF reviewer can verify every claim in this document against the
public repository, the test suites, and Stellar's own explorer.

## Why Stellar (a deliberate, informed choice)

- **The account model fits the product.** A Stellar account *is* the user:
  on-device keys, non-custodial from the first screen, no mapping layer to a
  phone number or a custodial balance sheet.
- **Settlement characteristics fit microfinance.** Sub-penny fees and ~5-second
  finality make small-value, high-frequency payments economically sane.
- **Claimable balances give us escrowed payment links** with no custodian —
  the chain holds the funds until the recipient claims.
- **Soroban adds genuine value where it is used.** Safebox group savings need
  permissioned escrow with shared visibility; that is enforced by the contract
  on-chain, not by our database. We deliberately do not use Soroban where a
  plain payment is the right tool.
- **Official SDKs on both sides** (`stellar_flutter_sdk` on mobile,
  `@stellar/stellar-sdk` for backend verification) keep us on the maintained
  path.
- **SEP-10-shaped challenge auth** means our login is the same pattern the
  anchors already know.

## Award track fit — a judgment call for the founders to confirm

The current SCF 7.0 process routes new projects through the Interest Form on
[communityfund.stellar.org](https://communityfund.stellar.org), with invited
submissions going to one of three **Build Award** tracks (up to $150,000 in
XLM, tranche-funded, typically 3–6 months):

- **Open Track** is the natural fit on paper: PayFlex is a novel consumer
  application ("something brand-new on Stellar"), and the offline
  fountain-coded optical protocol is a genuinely new contribution — not a
  re-skin of an existing wallet pattern. Note the Open Track includes a
  community vote, which rewards demonstrable, testable work — PayFlex's
  public repo and testnet demo are assets there.
- **Kickstart** (where offered as a supporting program) could suit a
  smaller early-stage ask, but the current handbook routes all new entrants
  through the Interest Form first; teams are then invited to the track that
  fits.

**[FOUNDER INPUT NEEDED: confirm track choice — Open Track Build Award is the
draft recommendation; confirm with the SCF team via the Interest Form before
committing, and note any referral code you hold, since referrals weigh heavily
in eligibility review.]**
