# PayFlex

A mobile-first microfinance app (in the spirit of Moniepoint / OPay) engineered for seamless offline-capable payments, unified QR transactions, automated Standing Plans, and transparent Safebox group savings. Powered by the **BMONI Embedded API** settlement rail, PayFlex bridges digital banking with local agent networks to ensure reliability across all network conditions.

Full spec: [`docs/BUILD_PROMPT.md`](docs/BUILD_PROMPT.md). This README tracks what's actually been built against that spec.

---

## Architecture & BMONI Settlement Rail

PayFlex uses the **BMONI Embedded API** for identity, managed smart wallets, KYC, and fiat money movement.
> [!NOTE]
> BMONI Embedded is **NOT** Stellar-based or crypto-backed — it's EVM-based managed smart wallets (owner-proof challenge + EIP-191 signing) backed by regional stablecoins (`USDB`, `CNGN`, `CADC`, `EURe`, `MEXe`). BMONI is the settlement rail in this build; nothing here talks to Stellar/Horizon/Soroban. The Flutter app goes through the NestJS backend for API calls, and through `bmoni_embedded_sdk` for key generation / signing operations.

```
app/       Flutter mobile app (iOS + Android)
backend/   NestJS orchestration service — calls BMONI Embedded API
server/    NestJS Safebox & Payment Step modules
docs/      Build specs & Payment Flow architecture docs
infra/     Sandbox reliability scripts & keep-alive tools
```

---

## Key Features & Capabilities

- **Unified Payment Step Flow**: Standardized 5-step transaction engine (Review → Authenticate → Submit → Result → Record) with branded progress states and animated confirmation feedback ([Specification](docs/payment-flow.md)).
- **Safebox Group Savings**: Shared contribution pools featuring full group transaction transparency and server-side permission controls:
  - Any member can contribute and view the chat-styled transaction ledger.
  - Server-enforced authorization: **Only owner and designated admins can withdraw funds**.
  - Server-enforced capacity: **At most 3 designated admins per Safebox** (owner + max 3 admins).
  - Deliberate 2-step dual-confirmation ownership transfer workflow.
- **Sandbox Infrastructure & Reliability**: Keep-alive ping mechanism and automated recovery tools ([Infra Docs](infra/sandbox/README.md)).
- **Lending & Credit Scoring**: Pluggable credit scoring reading BMONI history with server-side treasury disbursement.
- **Agent Cash-In / Cash-Out**: Agent network reconciliation ledger over BMONI transfers.
- **PayTag & QR Payments**: PayTag handle directory and HMAC-signed QR payment payloads.

---

## Build Status

| Phase | Status |
|---|---|
| 1 — Foundation (user + owner wallet + managed smart wallet) | **Done, verified against live sandbox** |
| 2 — KYC + onboarding (NGN, USD) | **Done for NGN, verified against live sandbox; USD wired** |
| 3 — Transfers (QR, PayTag, deposits, NGN withdrawal) | **Transfers/QR/PayTag done, verified against live sandbox** |
| 4 — Microfinance layer (savings, loans, agent mode) | **Done, verified against live sandbox** |
| 5 — Polish, Safebox & Payment Step Flow | **Done, Safebox group savings & 5-step payment flow added** |

---

## Setup & Running Locally

### Backend & Infrastructure Setup
```bash
cd backend
npm install
cp .env.example .env
docker-compose up -d
npx prisma migrate dev
npm run start:dev            # backend on :3000
```

### Sandbox Recovery & Keep-Alive
Refer to [infra/sandbox/README.md](infra/sandbox/README.md) for sandbox startup checklists:
```bash
bash infra/sandbox/startup.sh
bash infra/sandbox/keepalive.sh
```

### Mobile App Setup
```bash
cd app
flutter pub get
flutter run --dart-define=BACKEND_BASE_URL=http://10.0.2.2:3000
```

---

## Known Limitations & In-Progress Work

- **Betting Funding Page**: Pending regulatory licensing and third-party merchant integration.
- **Offline Transfer Module**: Protocol scaffolding complete; awaiting extended hardware mesh field testing.
- **Production Credentials**: Currently executing against the Freebuff Cloud BMONI Sandbox environment; production API keys pending final compliance audit.
