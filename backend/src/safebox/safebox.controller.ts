import { Body, Controller, Get, Param, Post } from '@nestjs/common';
import { SafeboxSorobanService, RegisterSafeboxDto } from './safebox-soroban.service';

/**
 * Safebox against the Soroban escrow contract. There are deliberately NO
 * contribute/withdraw endpoints: those are on-chain invocations built and
 * signed by the member's app (enforcement lives in the contract — owner/
 * admin-only withdrawal, 3-admin cap). The backend registers, lists, and
 * reads; the chain moves the money.
 */
@Controller('safebox')
export class SafeboxController {
  constructor(private readonly safeboxes: SafeboxSorobanService) {}

  @Post()
  register(@Param('id') appUserId: string, @Body() dto: RegisterSafeboxDto) {
    return this.safeboxes.register(appUserId, dto);
  }

  @Get()
  list(@Param('id') appUserId: string) {
    return this.safeboxes.listForOwner(appUserId);
  }

  @Get(':contractId')
  detail(@Param('id') appUserId: string, @Param('contractId') contractId: string) {
    return this.safeboxes.getDetail(appUserId, contractId);
  }

  @Get(':contractId/ledger')
  ledger(@Param('id') appUserId: string, @Param('contractId') contractId: string) {
    return this.safeboxes.getLedger(appUserId, contractId);
  }
}
