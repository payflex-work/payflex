# Deploying the PayFlex backend

The backend ships as a Docker image (`backend/Dockerfile`) that runs
`prisma migrate deploy` before the server starts — on a fresh database it
applies every migration; on an existing one, only what is pending. All
three platform configs below rely on that image plus the public health
endpoint `GET /v1/health` (does a Prisma `SELECT 1`, no auth).

The app listens on `PORT` (defaults to 3000). Set the service root /
Docker context to `backend/` on every platform.

## Environment variables

Set these in each platform's secrets/dashboard — never in a committed file.

**Required at boot** (the process exits without them):

| Variable | Notes |
| --- | --- |
| `DATABASE_URL` | Postgres connection string (usually injected by the platform) |
| `REDIS_URL` | e.g. `redis://...` (usually injected by the platform) |
| `BMONI_ENV` | `sandbox` or `production` |
| `BMONI_BASE_URL_SANDBOX` / `BMONI_BASE_URL_PRODUCTION` | Origin only — never append `/v1` (see `backend/src/config/bmoni.config.ts`) |
| `BMONI_API_KEY_SANDBOX` / `BMONI_API_KEY_PRODUCTION` | The production key must be requested from developers@bkey.me — never use the sandbox key for real money movement |
| `JWT_SECRET` | `openssl rand -hex 32`; rotating it logs every user out |
| `QR_SIGNING_SECRET` | `openssl rand -hex 32`; rotating it invalidates in-flight QR codes |

**Optional:**

| Variable | Notes |
| --- | --- |
| `BMONI_WEBHOOK_SECRET` | Blank until BMONI confirms its webhook signing scheme |
| `PAYFLEX_TREASURY_BMONI_USER_ID` / `PAYFLEX_TREASURY_OWNER_PRIVATE_KEY` | Loan disbursement only; in production this key belongs in a KMS/HSM, not a plain env var |
| `STELLAR_NETWORK` / `STELLAR_HORIZON_URL` / `STELLAR_FRIENDBOT_URL` | Testnet defaults; mainnet requires setting network AND Horizon URL explicitly |

## Railway

`backend/railway.json` (builds the Dockerfile, health check on
`/v1/health`, restart on failure). No `startCommand` is set on purpose —
the container entrypoint owns migrate-then-serve.

1. Railway → New Project → Deploy from GitHub repo.
2. On the backend service, set **Root Directory = `backend`** (it will
   pick up `Dockerfile` and `railway.json`).
3. Provision infra: New → Database → **PostgreSQL** and **Redis**.
   Railway injects `DATABASE_URL` / `REDIS_URL` automatically.
4. Add the required variables from the table above.
5. Settings → Networking → **Generate Domain** for public traffic.

## Render

`render.yaml` (blueprint) defines the web service, Postgres 16, and an
internal-only Redis, with `DATABASE_URL` / `REDIS_URL` wired automatically.

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
fly redis create --name payflex-redis
fly redis status payflex-redis           # copy the private connection URL
fly secrets set REDIS_URL="redis://..."  # from the previous step
fly secrets set BMONI_ENV=sandbox \
  BMONI_BASE_URL_SANDBOX="https://embedded-dev.bmoni.com" \
  BMONI_API_KEY_SANDBOX="<sandbox key>" \
  JWT_SECRET="$(openssl rand -hex 32)" \
  QR_SIGNING_SECRET="$(openssl rand -hex 32)"
fly deploy
```

Traffic is only routed to machines passing `/v1/health` (60s grace period
covers migration time).

## Platform-agnostic notes

- **Migrations are never skipped**: entrypoint migrates before serving;
  a migration failure exits the container so the orchestrator restarts it
  instead of serving against a broken schema.
- **Production BMONI checklist**: `BMONI_ENV=production` requires
  `BMONI_BASE_URL_PRODUCTION` + `BMONI_API_KEY_PRODUCTION` (from
  developers@bkey.me); the boot check refuses to start otherwise.
- The old Vercel deploy path (`/vercel.json`) was removed — Vercel has no
  long-running Postgres/Redis story for this service.
