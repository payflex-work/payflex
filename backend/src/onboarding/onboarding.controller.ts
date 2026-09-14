import { Controller, Get, Param, Post } from '@nestjs/common';
import { OnboardingService } from './onboarding.service';

@Controller()
export class OnboardingController {
  constructor(private readonly onboarding: OnboardingService) {}

  @Get('users/:id/onboarding/status')
  status(@Param('id') id: string) {
    return this.onboarding.getStatus(id);
  }

  /**
   * Server-side verification that the user's account really exists
   * on-ledger (funded). Does NOT fund anything: testnet funding happens
   * via Friendbot from the app; mainnet funding is a deliberate business
   * decision, not a code path (see docs/fiat-kyc-gap.md).
   */
  @Post('users/:id/onboarding/confirm-activation')
  confirmActivation(@Param('id') id: string) {
    return this.onboarding.confirmActivation(id);
  }
}
