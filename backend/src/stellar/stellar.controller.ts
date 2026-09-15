import { Controller, Get, Param, Query } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { Public } from '../auth/public.decorator';
import { StellarService } from './stellar.service';

/**
 * Read-only. All Stellar signing happens on-device (see
 * app/lib/stellar/stellar_client.dart) — this backend never receives or
 * builds a transaction on a user's behalf. Throttled tighter than the
 * app-wide default since every route here fans out to Horizon, a shared
 * public resource this app shouldn't be able to hammer through repeated
 * client polling.
 */
@Controller('stellar')
@Throttle({ default: { limit: 30, ttl: 60_000 } })
export class StellarController {
  constructor(private readonly stellar: StellarService) {}

  // Static config, same reasoning as GET /onboarding/supported-currencies:
  // needed before a session exists (the app may check this pre-login).
  @Public()
  @Get('network')
  getNetwork() {
    return this.stellar.getNetworkInfo();
  }

  @Get('accounts/:publicKey')
  getAccount(@Param('publicKey') publicKey: string) {
    return this.stellar.getAccount(publicKey);
  }

  @Get('accounts/:publicKey/transactions')
  getTransactions(@Param('publicKey') publicKey: string, @Query('limit') limit?: string) {
    // Clamp to a sane window; garbage/absent falls back to the service default.
    const parsed = Number(limit);
    const safe = Number.isInteger(parsed) && parsed > 0 ? Math.min(parsed, 200) : undefined;
    return this.stellar.getTransactions(publicKey, safe);
  }
}
