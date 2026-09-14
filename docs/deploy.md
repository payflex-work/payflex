# Deploying the PayFlex backend

The backend ships as a Docker image (`backend/Dockerfile`) that runs
`prisma migrate deploy` before the server starts — on a fresh database it
applies every migration; on an existing one, only what is pending. All
three platform configs below rely on that image plus the public health
endpoint `GET /v1/health` (does a Prisma `SELECT 1`, no auth).

The app listens on `PORT` (defaults to 3000). Set the service root /
Docker context to `backend/` on every platform.

> **Status note:** this deployment runs the Stellar-testnet payment app.
> There is no fiat rail and no identity-verification provider in this
> build — nothing to paste a key into yet. See
> [`fiat-kyc-gap.md`](fiat-kyc-gap.md) before planning a production
> launch, and do not describe a deployment of this build as
> "production-ready" in any user-facing material.

## Environment variables

Set these in each platform's secrets/dashboard — never in a committed file.

**Required at boot** (the process exits without them):

| Variable | Notes |
| --- | --- |
| `DATABASE_URL` | Postgres connection string (usually injected by the platform). The single managed dependency — app data **and** the login challenge store |
| `JWT_SECRET` | `openssl rand -hex 32`; rotating it logs every user out |
| `QR_SIGNING_SECRET` | `openssl rand -hex 32`; rotating it invalidates in-flight QR codes |

**Optional (Stellar network):**

| Variable | Notes |
| --- | --- |
| `STELLAR_NETWORK` | `testnet` (default) or `mainnet` |
| `STELLAR_HORIZON_URL` | Blank on testnet uses the SDF default; **required** on mainnet |
| `STELLAR_FRIENDBOT_URL` | Blank on testnet uses the SDF default; no mainnet equivalent |

The mainnet guard is deliberate, not a default: `STELLAR_NETWORK=mainnet`
without an explicit `STELLAR_HORIZON_URL` refuses to boot
(`backend/src/config/stellar.config.ts`), because pointing unmediated,
on-chain value at the wrong network is not a mistake the app should be
able to make quietly.

There are no provider/anchor/treasury credentials in this contract. When
a real fiat or KYC provider is plugged in later, its credentials belong
here as clearly-named variables — never hardcoded anywhere else.

## Railway

`backend/railway.json` (builds the Dockerfile, health check on
`/v1/health`, restart on failure). No `startCommand` is set on purpose —
the container entrypoint owns migrate-then-serve.

1. Railway → New Project → Deploy from GitHub repo.
2. On the backend service, set **Root Directory = `backend`** (it will
   pick up `Dockerfile` and `railway.json`).
3. Provision infra: New → Database → **PostgreSQL** (or plug in a Neon
   connection string as `DATABASE_URL`).
4. Add the required variables from the table above.
5. Settings → Networking → **Generate Domain** for public traffic.

## Render

`render.yaml` (blueprint) defines the web service and Postgres 16, with
`DATABASE_URL` wired automatically. A Neon connection string can be used
instead of the blueprint database — the backend only needs `DATABASE_URL`.

1. Render Dashboard → New → **Blueprint** → select this repo.
2. Fill the `sync: false` variables in the dashboard when prompted;
   `JWT_SECRET` / `QR_SIGNING_SECRET` are generated for you.
3. `preDeployCommand` runs `npx prisma migrate deploy` before the new
   build goes live (the entrypoint also migrates; both are idempotent).
4. The health check path is preconfigured; upgrade the DB/web plans
   before production.

## Fly.io

`backend/fly.toml` (single always-on shared-cpu-1x machine,
`release_command` migrates before rollout).

```sh
cd backend
fly apps create payflex-backend          # or: fly launch --no-deploy
fly postgres create --name payflex-db
fly postgres attach payflex-db --app payflex-backend   # sets DATABASE_URL
fly secrets set JWT_SECRET="$(openssl rand -hex 32)" \
  QR_SIGNING_SECRET="$(openssl rand -hex 32)"
fly deploy
```

`STELLAR_NETWORK` can be left unset (testnet default) or set explicitly.
Traffic is only routed to machines passing `/v1/health` (60s grace period
covers migration time).

## Platform-agnostic notes

- **Migrations are never skipped**: entrypoint migrates before serving;
  a migration failure exits the container so the orchestrator restarts it
  instead of serving against a broken schema.
- **Mainnet checklist** (when this is ever flipped): set
  `STELLAR_NETWORK=mainnet` AND `STELLAR_HORIZON_URL` together — the boot
  check refuses one without the other. Mainnet means real, irreversible
  funds with no custodian and no recovery path; treat it as a
  business/compliance decision, not a config change.
- The old Vercel deploy path (`/vercel.json`) was removed — Vercel has no
  long-running Postgres story for this service.

## Point the Flutter app at the deployed backend

The app reads its backend origin from the compile-time constant
`Env.backendBaseUrl` (`app/lib/config/env.dart`), which defaults to
`http://localhost:3000` for emulator/simulator development. It is set at
build time via `--dart-define`, not at runtime:

```sh
# dev against a local backend (Android emulator aliases host localhost
# as 10.0.2.2; iOS simulator can use localhost directly)
flutter run --dart-define=BACKEND_BASE_URL=http://10.0.2.2:3000

# release build against the deployed backend
flutter build apk --release \
  --dart-define=BACKEND_BASE_URL=https://<your-backend-domain>
```

- **HTTPS is required in release builds** — Android (API 28+) and iOS
  (ATS) block cleartext http://. `Env.assertSafeConfig()` runs at launch
  and fails fast with an explanatory error if a release build still
  points at an http:// origin, instead of dying on the first API call
  with an opaque socket error.
- **No trailing slash** — `ApiClient` joins paths as `$baseUrl$path`.
- **Sanity check before shipping a build**: the app's first API calls
  (user creation, login challenge) hit the same backend as
  `curl https://<your-backend-domain>/v1/health` → `{"status":"ok"}`.
