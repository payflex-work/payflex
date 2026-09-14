import { Global, Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import stellarConfig from '../config/stellar.config';
import { StellarService } from './stellar.service';
import { StellarController } from './stellar.controller';

/**
 * PayFlex's Stellar gateway — the ONLY blockchain/payment/settlement rail
 * in the app. Global so every feature module can verify payments and read
 * balances without re-import ceremony.
 */
@Global()
@Module({
  imports: [ConfigModule.forFeature(stellarConfig)],
  providers: [StellarService],
  controllers: [StellarController],
  exports: [StellarService],
})
export class StellarModule {}
