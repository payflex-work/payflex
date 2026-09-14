import { Module } from '@nestjs/common';
import { TransferService } from './transfer.service';
import { PayTagService } from './paytag.service';
import { QrPayService } from './qr-pay.service';
import { TransferController } from './transfer.controller';
import { QrPayController, QrDecodeController } from './qr-pay.controller';
import { UsersModule } from '../users/users.module';
import { StellarModule } from '../stellar/stellar.module';

@Module({
  imports: [UsersModule, StellarModule],
  providers: [TransferService, PayTagService, QrPayService],
  controllers: [TransferController, QrPayController, QrDecodeController],
  exports: [TransferService, PayTagService],
})
export class TransferModule {}
