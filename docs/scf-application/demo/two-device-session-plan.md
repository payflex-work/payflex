# Two-device recording session plan

The repo already contains a real-code capture of the offline loop
(`demo/payflex_offline_demo.mp4`) whose only substitution is the transport
(rendered frames instead of photons). This plan upgrades that to **literal
two-physical-device footage** — phones, airplane mode, camera-to-camera — for
the SCF submission. Nothing needs rewriting: the same production code paths
run, just on hardware.

## Goal

One continuous, believable take per act, then a final edit that mirrors the
repo demo: **request → scan → offline pay → confirmation → reconnect →
"Settled on Stellar"** with a real, viewer-checkable transaction hash.

## Pre-flight checklist (before anyone enters airplane mode)

1. **Builds:** `flutter build apk --debug` on both devices from the same
   commit; install and launch once each to confirm the app runs.
2. **Backend reachable:** point both apps at a deployed backend (or a
   tunnel to a dev machine). A transfer against it must succeed *before*
   going offline — that is also the payer's reserve-provisioning moment.
3. **Accounts funded:** payer's testnet account funded via Friendbot;
   provision the Offline Reserve for ~₦20,000 so the ₦5,000 spend leaves
   visible headroom.
4. **Backends of both phones:** testnet by default — verify the app's
   network badge/URL shows testnet before recording. Record the network
   setting on camera for honesty.
5. **Permissions:** camera + storage granted on both devices (first-run
   dialogs kill takes).
6. **Framing:** two phones side by side on a matte dark surface (the UI is
   navy; a mid-grey desk cloth avoids glare better than black), fixed phone
   tripod or overhead mount above them, two LED lamps at 45° — *no overhead
   light directly above the QR* (specular glare kills decodes).
7. **QR legibility test:** with the receiver's request QR on screen, stand
   where the payer phone's camera will be and scan — if it doesn't lock in
   <2s, increase QR screen brightness to max and move the lights.
8. **Fresh hashes:** note in the shot log that every take generates a NEW
   authorization id and transaction hash — never reuse the repo demo's hash
   in on-screen overlays.

## The take(s)

| # | Shot | Devices on camera | Watch for |
|---|---|---|---|
| 1 | Both phones show wallet home; toggle airplane mode **on camera** | both | the network badge flips honestly |
| 2 | Receiver: "Receive offline" → request QR animating | receiver | scan-line sweep visible; no glare |
| 3 | Payer: "Scan to pay" locks on, frames count up, amount + signature-verified screen | payer | hold ~3s on the verified request |
| 4 | Payer: confirm + PIN → reserve spend → animated confirmation QR | payer | honest copy: "will settle when you're back online" |
| 5 | Receiver: confirmation received → "Settlement pending" | receiver | verified receipt, honest status |
| 6 | Payer: toggle airplane mode off → sync → **"Settled on Stellar"** with hash | payer | let the hash dwell ≥5s, legible |
| 7 | (Optional credibility beat) open the explorer on a third device/laptop showing the same hash | none/laptop | the "you can check this yourself" moment |

Takes 2–5 are the offline acts; if a step fails (decode too slow, typo,
PIN flub), just restart that take — each take is independent because each
run generates a fresh request/authorization.

**If optical transfer is flaky on hardware:** increase the receiver's screen
brightness to 100%, set both phones' auto-brightness off, and hold steady
2–3 seconds longer than feels natural. The fountain code tolerates lost
frames — a longer scan is authentic, not a failure.

## After the take

1. Grab the payer's settled transaction hash from the receipt screen (or the
   app's history) and fetch it from Horizon to confirm `successful: true`.
2. Re-record or patch only if the hash is unreadable on camera.
3. Edit (any editor): acts 1–7 in order, ~35–45s total; overlay text only
   for the settlement hash; background music optional and quiet.
4. Replace or complement `demo/payflex_offline_demo.mp4` with the hardware
   cut; keep the software-capture version as `*_studio_capture.mp4` — it is
   honest evidence of the same code path and useful in the technical
   summary.
5. Update `demo/README.md` "how it was produced" to describe the hardware
   session, and add the hosted video URL to `team-and-links.md`.

## Estimated effort

- Setup + pre-flight: ~45–60 min (mostly build/install and lighting)
- Recording: ~20–30 min for all takes with a couple of retries
- Horizon check + edit: ~30–45 min
- **Total: ~2–2.5 hours**, one operator.
