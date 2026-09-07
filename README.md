# PayFlex

PayFlex is a Flutter microfinance application with a NestJS orchestration API.
It uses **BMONI Embedded** as its only settlement rail for identity, managed
smart wallets, KYC, and money movement.

## Architecture

```
app/       Flutter mobile client (iOS and Android)
backend/   NestJS API, Prisma schema, BMONI client, and sandbox scripts
infra/     Local sandbox recovery and keep-alive helpers
```

BMONI Embedded uses EVM managed wallets, owner-proof challenges, and EIP-191
signatures with regional stablecoins. It is not a Stellar, Horizon, or Soroban
integration. The app calls only the PayFlex backend; on-device wallet key
generation and signing stay in `bmoni_embedded_sdk`.

## BMONI boundary

BMONI provides user identity, owner-wallet proof, managed wallets,
KYC/onboarding, balances, deposits, payouts, and signed wallet-to-wallet
proposals. PayFlex adds PayTags and QR payloads, split bills, claimable-link
escrow, savings goals, credit scoring and loans, agent tracking, and Safebox
group savings. Safebox is an application ledger and permission model, not a
BMONI escrow product. Claimable links use a PayFlex treasury escrow and need
compliance review before production use.

## Safebox and payment safety

Safebox is implemented in `backend/src/safebox` and `app/lib/screens/safebox`.
Members can contribute; only the owner or a designated admin can withdraw; a
Safebox may have at most three designated admins. Those limits are enforced on
the server and covered by backend tests.

Safebox contributions and withdrawals use the shared flow in
`app/lib/widgets/pf_flow.dart`: review, transaction-PIN authentication,
submission, terminal result, then ledger refresh. The shared PayFlex token and
component system is the UI source of truth; it uses restrained elevation only,
never glow or neon effects.

## Development

```bash
cd backend
npm install
cp .env.example .env
docker compose up -d
npx prisma migrate dev
npm run start:dev
```

```bash
cd app
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=BACKEND_BASE_URL=http://10.0.2.2:3000
```

Use `npm run sandbox:safebox` from `backend/` after Postgres and Redis are
running. Other sandbox scripts and confirmed live-integration findings are in
[`backend/README.md`](backend/README.md).

## Current verification status

- Backend unit tests: 47 passing across 7 suites.
- Backend production build: passing.
- Flutter verification requires a Flutter SDK in the current environment;
  install/allocate one before treating mobile validation as complete.
- Production credentials, webhook signing, secret management, and a visual
  device/emulator review remain deployment prerequisites.

Virtual cards, betting funding, and offline mesh transfers are intentionally
out of scope until product and compliance specifications exist.
