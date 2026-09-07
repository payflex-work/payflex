# Handoff & Integration Requirements — Safebox & Payment Step Flow

This document details the additive files created for Sandbox Reliability, Safebox Group Savings, and the Standard Payment Step Flow, along with integration guidance for the parallel workstream.

---

## Additive Components Created

1. **Payment Confirmation Flow**:
   - Component: `lib/components/payment_confirmation_flow.dart`
   - Docs: `docs/payment-flow.md`
   - *Usage*: Wrap money-movement triggers (Transfers, Card Funding, Betting Funding, Safebox Contributions/Withdrawals) using `PaymentConfirmationFlowSheet.show(...)`.

2. **Safebox Group Savings**:
   - Backend Module: `server/src/safebox/` (`safebox.service.ts`, `safebox.controller.ts`, `safebox.module.ts`, DTOs)
   - Backend Schema: `server/prisma/schema.prisma`
   - Flutter Models: `lib/models/safebox_model.dart`
   - Flutter Service: `lib/services/safebox_service.dart`
   - Flutter Screens:
     - `lib/screens/safebox_list_screen.dart`
     - `lib/screens/safebox_create_screen.dart`
     - `lib/screens/safebox_detail_screen.dart`
     - `lib/screens/safebox_manage_members_screen.dart`

3. **Sandbox Reliability**:
   - Guide: `infra/sandbox/README.md`
   - Recovery Script: `infra/sandbox/startup.sh`
   - Keep-Alive Ping: `infra/sandbox/keepalive.sh`

---

## Server-Side Permission Verification Summary

- **3-Admin Cap**: Enforced in `server/src/safebox/safebox.service.ts` (`updateMemberRole`) and `lib/services/safebox_service.dart`. Attempts to assign a 4th admin are rejected with HTTP 400 (`BadRequestException`).
- **Withdrawal Permissions**: Enforced in `server/src/safebox/safebox.service.ts` (`withdraw`) and `lib/services/safebox_service.dart`. Regular members attempting withdrawals are blocked with HTTP 403 (`ForbiddenException`).
- **Ownership Transfer**: Implemented as a deliberate 2-step confirmation workflow requiring dual authorization.

---

## Integration Recommendations for Main Navigation

To link the Safebox feature into the main navigation without modifying `lib/screens/wallet_home_screen.dart` or `lib/core/router.dart`:
- Add a route entry:
  ```dart
  '/safebox': (context) => const SafeboxListScreen()
  ```
- Add a Safebox shortcut tile or quick-action button on the Wallet Home dashboard pointing to `SafeboxListScreen()`.
