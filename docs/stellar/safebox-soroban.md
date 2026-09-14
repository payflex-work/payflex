# Safebox (Soroban)

Safebox is PayFlex's shared savings vault, enforced **on-chain** by a
Soroban contract rather than by backend permissions. The contract is the
law; the backend only mirrors what the ledger says.

## The contract

Source: [`backend/contracts/safebox/src/lib.rs`](../../backend/contracts/safebox/src/lib.rs)

State held on-chain, one contract instance per safebox:

| Field | Meaning |
| --- | --- |
| `owner` | The creator's Stellar address. Sole withdrawal authority while admins exist. |
| `admins` | Set of additional admin addresses. **Hard cap: 3.** The contract rejects a 4th. |
| `balance` | Contributions held by the contract instance. |
| `closed` | Set true on owner withdrawal; terminal state. |

## What the contract enforces

- **Contribute** — anyone may contribute any asset amount. The transfer
  moves tokens from contributor → contract instance; the contribution
  and running balance are recorded in contract storage.
- **Withdraw** — **owner only.** Any non-owner signature is rejected by
  the contract, not by PayFlex. On success the vault balance transfers
  to the owner and the safebox is marked `closed` (terminal — no further
  contributions or withdrawals).
- **Admin cap** — `add_admin` fails once the set holds 3 admins; the
  owner cannot be added as their own admin; duplicates are rejected.
- **Removal** — the owner may remove an admin (never themselves).

The backend **cannot** do any of these things. There is no admin
endpoint that mints, moves, or unlocks safebox value; the server's admin
dashboard reads chain state through the indexer, full stop.

## How the app drives it

The Flutter app talks to Soroban **directly** via
`app/lib/services/safebox_service.dart`:

1. **Deploy** — one fresh contract instance per safebox, installed from
   the built WASM; the resulting contract id is stored in the safebox
   record.
2. **Invoke** — `contribute` / `add_admin` / `remove_admin` /
   `withdraw` are `invokeContractFunction` operations assembled with
   the client SDK, **signed on-device** (PIN-gated, same keychain seed
   as every other PayFlex payment), and submitted to the Soroban RPC.
3. **Simulate first** — invocations are simulated before submission, so
   contract reverts (wrong role, closed vault, admin cap) surface as
   readable errors before anything is signed.

## Token accounting (SAC)

Contributions are in a Stellar asset whose contract id is derived per
CAP-46 (the asset's **Stellar Asset Contract**, SAC). The app derives
this id locally so balances shown in the safebox UI match what the
contract actually holds. On testnet the demo asset is issued by the
backend's configured issuer key; the derivation math is identical on
mainnet for real assets (e.g. USDC's issuer).

## Visibility for members

Contributions and withdrawals are **on-chain**, so every member sees the
same truth. The Safebox ledger feed is built from:

- the contract's storage (read via RPC query by the backend indexer),
- the ledger effects of the contract's invocations, and
- the running balance, recomputed from the chain — not from a private
  backend counter.

This is why the ledger can be chat-style and real-time without trusting
the server: the server is rendering the chain, not keeping a competing
set of books.

## Test walkthrough

`backend/scripts/stellar-testnet-walkthrough.ts` exercises deploy →
contribute → admin add/remove → owner withdraw on testnet, including
asserting that a non-owner withdraw is rejected by the contract.

Related docs: [Payments lifecycle](payments-lifecycle.md) ·
[Testnet vs mainnet](testnet-vs-mainnet.md)
