import { Module } from '@nestjs/common';
import { GatedController } from './gated.controller';

/**
 * Endpoints for features that are PAUSED pending real fiat/KYC providers.
 * Every route fails closed through HardGateService — see the controller's
 * doc comment and docs/fiat-kyc-gap.md.
 */
@Module({
  controllers: [GatedController],
})
export class GatedModule {}
