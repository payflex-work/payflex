import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import stellarConfig from '../config/stellar.config';
import { StellarService } from './stellar.service';
import { StellarController } from './stellar.controller';

/**
 * PayFlex's Stellar rail — additive and self-contained, parallel to
 * BMONI, never routed through it. See docs/stellar-rail.md.
 */
@Module({
  imports: [ConfigModule.forFeature(stellarConfig)],
  providers: [StellarService],
  controllers: [StellarController],
  exports: [StellarService],
})
export class StellarModule {}
