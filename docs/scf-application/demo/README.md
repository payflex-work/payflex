# PayFlex — offline payment demo (SCF submission)

`payflex_offline_demo.mp4` (40s, 1080×1920) shows PayFlex's differentiating
moment end to end: **a payment made in airplane mode, settled for real on
Stellar.**

## What the video shows

1. **The offer** (receiver, "AMINA CAFE") — the app's real `AnimatedOpticalQr`
   widget streaming the signed `PaymentRequest` as fountain-coded QR frames.
2. **The scan** (payer, "BABATUNDE") — frames reconstructed, request
   signature verified, amount shown.
3. **The offline payment** — the payer's `OfflineReserveService` spend (real
   device-key signature, monotonic sequence, hash-chained authorization), and
   the signed `PaymentConfirmation` streamed back over the animated QR.
4. **The receipt** — receiver verifies the confirmation against its own
   request; status reads honestly: *confirmed — settlement pending*.
5. **Reconnect + settle** — a real Stellar testnet payment built and signed
   on-device, submitted to Horizon, with the transaction hash on screen.

## How it was produced (all real code, one honest substitution)

- Every protocol step is the app's production code path: `PaymentProtocol`,
  `OfflineReserveService`, `FountainCoder`, `AnimatedOpticalQr`. No mocked
  crypto, no fake statuses.
- **The one substitution is the transport:** instead of photons between two
  phone cameras, the rendered QR frames were captured as images and decoded
  with jsQR (the same pixels-in/frames-out job a camera scanner does).
- Both devices' Stellar accounts are **real testnet accounts** funded via
  Friendbot; the settlement is a **real transaction**, confirmed by Horizon
  after the fact.
- Harnesses: `app/test/demo/payer_harness_test.dart` and
  `app/test/demo/receiver_harness_test.dart`, orchestrated by
  `app/test/demo/orchestrate.js`. Run with `PF_DEMO=1` (receiver also takes
  `PF_PHASE=1|2`).

## Verify it yourself

- Transaction: `ad4b41bda2aee20261499a6e694965c50ee412abdb262bc5fee93d1f0c4f5407`
- Explorer: https://stellar.expert/explorer/testnet/tx/ad4b41bda2aee20261499a6e694965c50ee412abdb262bc5fee93d1f0c4f5407
- Horizon: https://horizon-testnet.stellar.org/transactions/ad4b41bda2aee20261499a6e694965c50ee412abdb262bc5fee93d1f0c4f5407
- Memo on chain: `offline auth…4a1d` (the offline authorization id, in the
  app's short-reference form) · ledger 4672758 · 1.5 XLM
- `demo_manifest.json` records both accounts, the amount, and the Horizon
  verification fields.
- `sbs_offer_scan.png` / `sbs_payoff.png` are two-device side-by-side stills
  for slides.
