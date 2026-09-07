# Freebuff Cloud Sandbox Reliability & Keep-Alive Guide

This guide documents the procedures for maintaining uptime and reliably recovering the PayFlex Freebuff Cloud sandbox environment when it transitions to `SANDBOX_NOT_RUNNING` or enters idle sleep state.

---

## 1. Sandbox Status Overview

Freebuff Cloud sandbox containers are configured with an aggressive idle-timeout mechanism on non-production tiers. If no inbound HTTP request or database activity occurs within 15 minutes, the container state changes to `SANDBOX_NOT_RUNNING`.

### Key Service Components
- **NestJS Core API Service**: `http://localhost:3000` (or `https://sandbox-api.payflex.internal`)
- **PostgreSQL Database**: Port `5432`
- **Redis Cache & Queue**: Port `6379`
- **BMONI Embedded API Gateway Simulator**: `https://sandbox.bmoni.io/v1`

---

## 2. Startup Checklist & Recovery Order

When the sandbox goes down (`SANDBOX_NOT_RUNNING`), follow this exact operational order:

### Step 1: Environment Verification
Ensure the following required environment variables are exported in `/infra/sandbox/.env`:
```bash
export SANDBOX_ENV="development"
export SANDBOX_URL="https://sandbox-api.payflex.internal"
export BMONI_SANDBOX_KEY="bm_sb_live_0921a8f94"
export POSTGRES_URL="postgresql://payflex:sandboxpass@localhost:5432/payflex_sandbox"
export REDIS_URL="redis://localhost:6379"
```

### Step 2: Infrastructure Service Revival
Execute the automated recovery script:
```bash
bash /infra/sandbox/startup.sh
```

Or manually restart container services in sequence:
1. **Database & Cache**:
   ```bash
   docker-compose -f /infra/sandbox/docker-compose.sandbox.yml up -d postgres redis
   ```
2. **Database Migrations & Seed**:
   ```bash
   npx prisma migrate deploy
   ```
3. **Core API Server**:
   ```bash
   docker-compose -f /infra/sandbox/docker-compose.sandbox.yml up -d api
   ```

### Step 3: Health Verification
Validate service readiness:
- `curl -f http://localhost:3000/health` (Expect `{"status":"ok"}`)
- `curl -f http://localhost:3000/api/v1/bmoni/ping` (Expect `{"bmoniStatus":"connected"}`)

---

## 3. Keep-Alive & Health Ping Mechanism

To prevent Freebuff Cloud from auto-suspending the sandbox container, wire up a scheduled keep-alive ping script.

### Executing Keep-Alive
Run the keep-alive script `/infra/sandbox/keepalive.sh`:
```bash
bash /infra/sandbox/keepalive.sh
```

### Cron Job Installation
To automate pings every 5 minutes:
```cron
*/5 * * * * /bin/bash /infra/sandbox/keepalive.sh >> /var/log/payflex-keepalive.log 2>&1
```

### Tier Constraints Note
> [!NOTE]
> On the current Freebuff Cloud Developer Tier, HTTP keep-alive pings successfully prevent idle-timeout suspensions. However, scheduled platform maintenance or host node relocations will force a cold restart. If a ping receives a 503 or Connection Refused response, the script triggers `startup.sh` automatically.
