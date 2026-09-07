# PayFlex — Handoff / Next Steps

Written at a stopping point after a long session of auth + design-brief
integration work, right after a second parallel session's Safebox/payment-flow
commit landed on `main` with a structural problem that needs fixing before
anything else continues. Read the "Immediate blocker" section first — it's
the actual next thing to do, not the feature list below it.

---

## 1. What's solid and working right now (don't redo this)

Verified end-to-end against the live BMONI sandbox and/or with real unit
tests, all merged into `main`:

- **Phases 1–5** (`app/`, `backend/`): user + owner wallet + managed smart
  wallet, KYC + NGN/USD onboarding, transfers/QR/PayTag, savings/loans/
  agent mode, split-bill/send-via-link/escrow/CAD-EUR-MXN stubs. See
  `backend/README.md` and `app/README.md` for phase-by-phase findings —
  they're accurate and detailed, don't take the (now-overwritten) root
  README's summary as more authoritative than those.
- **Authentication** (`backend/src/auth/`, `backend/src/token/`,
  `backend/src/redis/`, `app/lib/services/session_manager.dart`,
  `app/lib/services/api_client.dart`): JWT + challenge-response login
  reusing the on-device EVM owner key, a global `AuthGuard` enforcing
  auth + per-user ownership by default (`@Public()` opts a route out),
  one-time bootstrap tokens, refresh rotation. Verified live over HTTP
  (unauthenticated rejection, cross-user ownership rejection, bootstrap
  scope/set-once enforcement, refresh reuse rejection) and via 41 unit
  tests (`backend/src/auth/*.spec.ts`).
- **A real IDOR was found and fixed**: `LoansService.listRepayments`/
  `payRepayment` now check the resource actually belongs to the caller,
  not just that the caller is who they say they are. Regression-tested
  in `backend/src/loans/loans.service.spec.ts`.
- **Rate limiting** (`@nestjs/throttler`, `backend/src/app.module.ts`):
  60 req/min global default, 5/min on `/auth/login`, 10/min on
  `/auth/challenge` and `/auth/refresh`. Verified live.
- **The full UI/UX & Motion Design Brief** (`docs/DESIGN_BRIEF.md`,
  `app/lib/theme/`, `app/lib/widgets/pf_*.dart`): built by a separate
  parallel session, merged in cleanly, `flutter analyze` clean (0 errors,
  0 warnings — a handful of pre-existing `info`-level lints only). **Never
  visually verified on a real device or emulator** — this environment has
  no display. Someone needs to actually look at it before calling the
  visual pass done.
- `flutter analyze`: 0 errors/warnings. `tsc --noEmit`: clean.
  `npm run sandbox:*` (all 6 scripts): all pass against the live sandbox.

---

## 2. Immediate blocker: the Safebox/payment-flow commit needs relocating

Commit `481849c` ("Add Sandbox reliability, Payment Step Flow, Safebox
Group Savings, and README update") landed directly on `main` from a
different session while this one was working. **It was built from the
wrong working directory** — it created a second, fully disconnected
project structure at the repo root instead of inside the real `app/` and
`backend/` trees:

- `lib/`, `pubspec.yaml` (root) — a **second, separate Flutter project**
  (`name: payflex`, `version: 1.0.0+1`) sitting next to the real one at
  `app/` (`version: 0.1.0`). Running the app the documented way (`cd app
  && flutter run`) never loads any of this code. `docs/payment-flow.md`
  even hardcodes the wrong path in its own usage example:
  `file:///home/gamp/bpay/lib/components/payment_confirmation_flow.dart`
  — proof it was written assuming the repo root is the Flutter root.
- `server/` — a NestJS-shaped Safebox module (`safebox.controller.ts`,
  `safebox.service.ts`, `safebox.module.ts`, DTOs) with **no
  `package.json`** — it cannot be installed, built, or run as committed.
  It also has its own **separate** `server/prisma/schema.prisma`,
  disconnected from `backend/prisma/schema.prisma` (so it can't even
  reference the real `AppUser`/`SmartWallet` models it would need).
- The root `README.md` was rewritten and lost real content in the
  process (198 lines removed, 58 added) — the old version's detailed
  "Where the BMONI API boundary actually is" section (what's real BMONI
  vs. what PayFlex built) is gone, replaced with a shorter summary that
  also now inaccurately implies `server/` is a working part of the
  architecture. `git show 2f03054:README.md` has the old, accurate
  version if it's worth partially restoring.

**Nothing in `app/` or `backend/` was touched or damaged** — this is
purely an orphaned addition sitting alongside the real code, not a
regression in anything that was working.

**What the Safebox spec itself actually says** (this part is coherent
and worth keeping, just needs to move): a group-savings feature with
owner/admin/member roles, a 3-admin cap, owner-or-admin-only withdrawal,
a 2-step ownership-transfer confirmation, and a standardized 5-step
payment confirmation flow (Review → Authenticate → Submit → Result →
Record) meant to wrap every money-movement feature. See
`docs/payment-flow.md` and `docs/handoff-safebox-requires.md` for the
full spec as written (ignore the file paths in those docs — they point
at the wrong tree).

**Recommended next step** (my default — reasonable to just proceed with
this rather than re-litigate it): relocate rather than discard.
1. Move `server/src/safebox/` into `backend/src/safebox/`, wire it into
   `backend/src/app.module.ts`. It'll automatically inherit the global
   `AuthGuard` and rate limiting once it's actually inside `backend/`.
2. Merge `server/prisma/schema.prisma`'s models into
   `backend/prisma/schema.prisma` (connect `ownerId` to the real
   `AppUser` relation), run a real migration the same way every other
   phase did (`npx prisma migrate dev`).
3. Move `lib/models/safebox_model.dart`, `lib/services/safebox_service.dart`,
   and the four `lib/screens/safebox_*.dart` files into `app/lib/`,
   fixing imports to match `app/lib/services/api_client.dart`'s pattern
   (auth headers, real endpoints) rather than whatever the disconnected
   version assumed. Delete the orphaned root `lib/`, `pubspec.yaml`,
   `server/` once the useful parts are moved — don't leave a dead second
   copy sitting in the repo.
4. Apply the already-established design system (`app/lib/theme/`,
   `pf_*` widgets) to the Safebox screens rather than whatever styling
   the disconnected `app_theme.dart`/component files used — there are
   now two competing theme systems (`app/lib/theme/payflex_theme.dart`
   vs. the orphaned `lib/theme/app_theme.dart`); only one should survive.
5. Verify live against the sandbox the same way every other feature in
   this build was (a `sandbox:safebox` script mirroring the existing
   `scripts/sandbox-lifecycle-phase*.ts` pattern), then `flutter analyze`
   + `tsc --noEmit` + the existing test suite, before merging back.
6. Reconcile the root `README.md` — restore the architectural detail
   that was lost, or at minimum fix the `server/` line in its directory
   diagram once `server/` no longer exists.

If the answer is actually "discard the Safebox feature entirely, we
don't want it" — that's a fine call too, just say so explicitly; don't
let the orphaned files linger either way.

---

## 3. Other open items (not blocking, ranked)

1. **Secrets in plain env vars** — `JWT_SECRET` and
   `PAYFLEX_TREASURY_OWNER_PRIVATE_KEY` need a real KMS/secrets manager
   before production. Needs actual cloud credentials/infrastructure this
   dev environment doesn't have — can't be done end-to-end here.
2. **No production BMONI key or webhook secret** — needs a request to
   BMONI (`developers@bkey.me`), not something to build around.
3. **Design layer unverified on a real device** — `flutter analyze` is
   clean but nobody has looked at the rendered result.
4. **No CI pipeline, no monitoring/error tracking, no reverse-proxy/TLS
   setup documented.**
5. **Backend `eslint` is broken** (missing/incompatible config,
   pre-existing — not introduced this session). `npm run lint` fails
   immediately with "ESLint couldn't find a configuration file." Low
   priority but worth a real fix at some point since it means lint
   currently catches nothing at all.

---

## 4. Explicitly out of scope / need a real spec before touching

- **"Virtual card"** and **"betting page"** were mentioned in a pasted
  continuation prompt this session, and "Betting Funding Page" appears
  in the new (disconnected) README's "Known Limitations" as "pending
  regulatory licensing" — but there is still no actual spec for either
  anywhere in this repo. Both carry real compliance weight (card
  issuance, gambling regulation) that shouldn't be guessed at. Don't
  start building either without an explicit spec — ask first.
- **Admin access model** — same situation, no spec found. The Safebox
  feature has its own owner/admin/member role model (see above), which
  may or may not be what "admin access" was meant to refer to — worth
  clarifying rather than assuming they're the same thing.
