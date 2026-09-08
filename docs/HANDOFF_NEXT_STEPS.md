# PayFlex — Handoff / Next Steps

Written at a stopping point after a long session of auth + design-brief
integration, followed by properly relocating and rebuilding a Safebox
group-savings feature that had landed disconnected from the real app.
This is the current, up-to-date picture — nothing here needs re-deciding.

---

## 1. What's solid and working right now (don't redo this)

Verified end-to-end against the live BMONI sandbox and/or with real unit
tests, all merged into `main`:

- **Phases 1–5** (`app/`, `backend/`): user + owner wallet + managed smart
  wallet, KYC + NGN/USD onboarding, transfers/QR/PayTag, savings/loans/
  agent mode, split-bill/send-via-link/escrow/CAD-EUR-MXN stubs. See
  `backend/README.md` and `app/README.md` for phase-by-phase findings.
- **Authentication** (`backend/src/auth/`, `backend/src/token/`,
  `backend/src/redis/`, `app/lib/services/session_manager.dart`,
  `app/lib/services/api_client.dart`): JWT + challenge-response login
  reusing the on-device EVM owner key, a global `AuthGuard` enforcing
  auth + per-user ownership by default (`@Public()` opts a route out),
  one-time bootstrap tokens, refresh rotation. Verified live over HTTP
  and via unit tests.
- **Rate limiting** (`@nestjs/throttler`, `backend/src/app.module.ts`):
  60 req/min global default, 5/min on `/auth/login`, 10/min on
  `/auth/challenge` and `/auth/refresh`. Verified live.
- **The full UI/UX & Motion Design Brief** (`docs/DESIGN_BRIEF.md`,
  `app/lib/theme/`, `app/lib/widgets/pf_*.dart`): merged in cleanly.
- **Safebox group savings** (`backend/src/safebox/`,
  `app/lib/screens/safebox/`, `app/lib/models/safebox.dart`) — see
  section 2 below for the full story of how this landed and was fixed.
- Two real IDOR-class findings were caught and fixed this session, both
  regression-tested: `LoansService.listRepayments`/`payRepayment` (didn't
  check the resource belonged to the caller) and the original Safebox
  scaffold's spoofable `x-user-id` header (see section 2).
- `flutter analyze`: 0 errors/warnings (a handful of pre-existing `info`
  lints only). `tsc --noEmit`: clean. `npm test` (backend): 49 tests
  passing. `npm run sandbox:*` (all 7 scripts, including
  `sandbox:safebox`): all pass against the live sandbox.

---

## 2. Safebox: what happened, and what's actually there now

A second, parallel session's commit (`481849c`) added a Safebox
group-savings feature, but built it from the wrong working directory —
it created a second, disconnected Flutter project at the repo root
(`lib/`, `pubspec.yaml`) and a NestJS module with no `package.json`
(`server/`), neither wired into the real `app/`/`backend/` trees. On
inspection it also turned out to have a real security hole: the
controller trusted a client-supplied `x-user-id` header (defaulting to
`'usr_default'` if absent) for identity, which made every "server-side
permission check" (the 3-admin cap, owner/admin-only withdrawal) moot —
anyone could claim to be anyone. The service also stored everything in
in-memory `Map`s despite a Prisma schema existing for it (never wired
up), and contributions/withdrawals never touched BMONI at all — just an
in-memory number. `infra/sandbox/README.md` (also from that commit)
described a fabricated "Freebuff Cloud" platform, a
`docker-compose.sandbox.yml` that doesn't exist, and API
endpoints/keys that don't exist anywhere in this codebase.

**What was done about it:** the orphaned `lib/`, `server/`,
`pubspec.yaml`, and `infra/` were deleted entirely (nothing in them was
salvageable as committed), and the feature was rebuilt properly from the
spec's actual permission model (which was sound):

- `backend/src/safebox/` — real Prisma persistence (`Safebox`,
  `SafeboxMember`, `SafeboxTransaction` models in
  `backend/prisma/schema.prisma`), mounted at `/users/:id/safeboxes/...`
  so the existing `AuthGuard` enforces real identity and ownership for
  free. Contributions are real signed TRANSFER proposals (member →
  treasury, same pattern as `SavingsGoal`); withdrawals are
  treasury-signed releases (same pattern as loan disbursement), since a
  shared pool has no single member whose key can sign on its behalf. The
  3-admin cap, owner/admin-only withdrawal, and 2-step ownership transfer
  (via `RedisService`, same ephemeral-code pattern as the login
  challenge) are all enforced server-side against the real authenticated
  caller.
- `app/lib/screens/safebox/` (`safebox_list_screen.dart`,
  `safebox_detail_screen.dart`) and `app/lib/models/safebox.dart`, built
  against the real design system (`PfPanel`, `PfPrimaryButton`, etc.),
  wired into `WalletHomeScreen`'s "more" menu. Contribution uses the
  existing `signAndSubmitTransfer` helper (same as every other transfer
  in this app); withdrawal doesn't need client-side signing since the
  treasury already signed it server-side by the time the call returns.
- `backend/scripts/sandbox-safebox.ts` (`npm run sandbox:safebox`)
  verifies the whole thing live: pool creation, membership, a real
  signed contribution, a regular member's withdrawal correctly rejected,
  the 3-admin cap correctly rejected on the 4th promotion, an admin's
  treasury-signed withdrawal, and the ownership-transfer flow (wrong
  code rejected, correct code succeeds). `backend/src/safebox/
  safebox.service.spec.ts` unit-tests the permission logic directly.
- The root `README.md` was reconciled (it had also been overwritten by
  the same commit, losing real architectural detail and adding the same
  fabricated "Freebuff Cloud" references) — restored to the accurate
  version plus a real Safebox section.
- `docs/payment-flow.md` and `docs/handoff-safebox-requires.md` (from
  the same commit) were deleted rather than kept as stale specs — they
  described the wrong file paths and a different UI pattern
  (a bespoke `PaymentConfirmationFlow` widget) than what was actually
  built, which reuses this codebase's existing, already-consistent
  sign/submit + confirmation pattern instead. Nothing of value was lost:
  the actual permission model (3-admin cap, owner/admin withdrawal,
  2-step transfer) is now real code, not a doc describing hypothetical
  code.

**One known gap, left as-is deliberately:** `Safebox.currentBalance` is
optimistic bookkeeping only, updated when a proposal is *created*, not
when it's confirmed settled — this build has no way to observe real
on-chain settlement anywhere (same honest limitation
`SavingsGoal.totalContributed` already has, and it's never updated
either). Don't treat `currentBalance` as authoritative without building
real settlement confirmation first (would need a BMONI webhook handler
that doesn't exist yet — see `backend/src/webhooks/`, which currently
just logs events).

**One known UX gap:** the ownership-transfer confirmation code has no
real delivery channel — `initiateOwnershipTransfer` never returns the
code to anyone (correctly, since only the recipient should have it), but
nothing in this app can push it to them either (no SMS/notification
infrastructure exists anywhere in this build). The current UI just tells
the initiator to "share it securely." Fine for a sandbox demo, not for
production — needs a real out-of-band delivery mechanism.

---

## 3. Other open items (not blocking, ranked)

1. **Secrets in plain env vars** — `JWT_SECRET` and
   `PAYFLEX_TREASURY_OWNER_PRIVATE_KEY` need a real KMS/secrets manager
   before production. Needs actual cloud credentials/infrastructure this
   dev environment doesn't have — can't be done end-to-end here.
2. **No production BMONI key or webhook secret** — needs a request to
   BMONI (`developers@bkey.me`), not something to build around.
3. **Design layer (including the new Safebox screens) unverified on a
   real device** — `flutter analyze` is clean but nobody has looked at
   the rendered result. No display/emulator exists in this environment.
4. **No CI pipeline, no monitoring/error tracking, no reverse-proxy/TLS
   setup documented.**
5. **Backend `eslint` is broken** (missing/incompatible config,
   pre-existing, unrelated to anything built this session). `npm run
   lint` fails immediately with "ESLint couldn't find a configuration
   file." Low priority but worth a real fix at some point.

---

## 4. Explicitly out of scope / need a real spec before touching

- **"Virtual card"** and **"betting page"** were mentioned in a pasted
  continuation prompt this session, and "Betting Funding Page" appeared
  in the (now-deleted) fabricated README as "pending regulatory
  licensing" — but there is no actual spec for either anywhere in this
  repo. Both carry real compliance weight (card issuance, gambling
  regulation) that shouldn't be guessed at. Don't start building either
  without an explicit spec — ask first.
- **"Admin access"** — same situation, no spec found. Safebox's own
  owner/admin/member role model (section 2 above) may or may not be what
  that referred to — worth clarifying rather than assuming they're the
  same thing.
