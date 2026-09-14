# PayFlex — Roadmap & The Ask (SCF)

> Companion to [`project-overview.md`](project-overview.md). The use-of-funds
> categories below are real, documented next steps — sourced from
> [`/docs/fiat-kyc-gap.md`](../fiat-kyc-gap.md), `/docs/deploy.md`, and the
> project's own phase discipline. Dollar amounts and dates are founder input.

## What the grant would fund

PayFlex's remaining path to mainnet is narrow and well-defined, because the
hard parts are already built and verified: the non-custodial wallet, the
on-chain escrow, the offline protocol, and the fail-closed honest architecture
all exist and are tested. What remains is opening the fiat/KYC gate with real
partners and hardening for mainnet — the documented gap in
[`/docs/fiat-kyc-gap.md`](../fiat-kyc-gap.md).

### Use of funds

1. **Fiat rail / anchor partnership integration.** Implement
   `IFiatRailProvider` against a real regulated partner (an anchor such as
   LINK/NGNC or equivalent): deposit/withdraw flows for Nigerian users,
   SEP-6/24-shaped, replacing the current empty seam. The gate
   (`fiatCapable`) opens only when a real provider is wired — by design, no
   other path exists.
2. **KYC provider integration.** Implement `IIdentityVerificationProvider`
   (SEP-12-shaped): document + liveness verification with a real vendor,
   exposing only the outcome to the app.
3. **Mainnet security review.** Independent audit of the app's key handling
   (secure storage, PIN-gated signing), the offline authorization protocol,
   and the Safebox contract before mainnet deployment. SCF's Audit Bank
   support would complement — not replace — this for the contract.
4. **Continued Soroban development.** Extend the Safebox contract (e.g.
   contribution schedules, member caps), plus the two-device field-hardening
   of the offline redemption flow.

**[FOUNDER INPUT NEEDED: award amount requested (XLM/USD), and the intended
allocation split across the categories above.]**

## Timeline

The plan below is structured around the phase discipline this project has
actually followed from its first commit: each phase ends with a verification
gate (full test suites green, behavior proven against live testnet) before
the next begins. Dates are founder input; the sequence and scope are real.

| Phase | Scope (real, from the documented gap) | Duration |
|---|---|---|
| **Phase 1 — Partner selection** | Sign anchor/fiat partner and KYC vendor LOIs; finalize integration designs against the existing provider seams | founder input |
| **Phase 2 — Fiat + KYC integration** | Implement both providers; reopen the gate behind real verification; full test coverage for both | founder input |
| **Phase 3 — Mainnet hardening** | Security review + audit remediation; mainnet deployment configuration (the mainnet guard and its implications are already documented in `/docs/stellar/testnet-vs-mainnet.md`) | founder input |
| **Phase 4 — Pilot launch** | Limited Nigerian pilot; two-device offline payment field trials; measure and publish honest metrics | founder input |

Milestone deliverables would map to SCF Build tranches: each tranche closes
with a demonstrable, testable artifact (integration against live partner
sandbox, audit report, mainnet deployment, pilot metrics), matching the
tranche structure in the SCF handbook.

**[FOUNDER INPUT NEEDED: concrete dates/durations per phase, and any
milestone rewording you want before submission.]**
