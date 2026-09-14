import { Global, Module } from '@nestjs/common';
import { HardGateService } from './hard-gate.service';
import { NoIdentityVerificationProvider } from './identity-verification-provider';
import { NoFiatRailProvider } from './fiat-rail-provider';

/**
 * The plug-in gap module: honest, unimplemented provider interfaces plus the
 * hard gate that keeps every gated feature closed until real providers are
 * wired in. See docs/fiat-kyc-gap.md. Global so any feature module can
 * inject HardGateService without ceremony.
 */
@Global()
@Module({
  providers: [HardGateService, NoIdentityVerificationProvider, NoFiatRailProvider],
  exports: [HardGateService, NoIdentityVerificationProvider, NoFiatRailProvider],
})
export class ProvidersModule {}
