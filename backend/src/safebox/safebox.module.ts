import { Module } from '@nestjs/common';
import { SafeboxController } from './safebox.controller';
import { SafeboxService } from './safebox.service';
import { TransferModule } from '../transfer/transfer.module';
import { TreasuryModule } from '../treasury/treasury.module';

@Module({
  imports: [TransferModule, TreasuryModule],
  controllers: [SafeboxController],
  providers: [SafeboxService],
  exports: [SafeboxService],
})
export class SafeboxModule {}
