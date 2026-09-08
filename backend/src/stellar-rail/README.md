# Stellar Rail — Awaiting Implementation

**Status: NOT IMPLEMENTED — do not add integration code here yet.**

This directory is a placeholder only. The Stellar parallel settlement rail
is correctly not started because the user has not yet provided the specific
Stellar contract/repo reference to build against.

## What to do when the Stellar repo link arrives

1. User provides: the Stellar contract address or repository URL
2. A dedicated prompt will authorize building the integration
3. Only then should any code go into this directory

## When it IS built, this module should handle

- Key management bridge (BMONI on-device key → Stellar signing key derivation,
  or separate Stellar key storage with `bmoni_embedded_sdk`)
- KYC bridging (BMONI KYC status → Stellar account activation gating)
- On-chain transaction submission + polling (Horizon API or Soroban RPC)
- Irreversibility handling (pre-flight checks, user confirmation of finality)
- Fee estimation and display before submission
- Settlement record sync back to PayFlex transaction history

## Current settlement rail

BMONI Embedded is the **only** real settlement rail. Do not change this
until a dedicated prompt explicitly authorizes adding Stellar.

## Contact

Ask the repo owner (bmoni-hack) for the Stellar contract/repo link before
starting any work in this directory.
