import { Module } from '@nestjs/common';
import { SavingsService } from './savings.service';
import { SavingsSchedulerService } from './savings-scheduler.service';
import { SavingsController } from './savings.controller';
import { SavingsAdminController } from './savings-admin.controller';
import { TransferModule } from '../transfer/transfer.module';
import { TreasuryModule } from '../treasury/treasury.module';
import { AdminModule } from '../admin/admin.module';

@Module({
  imports: [TransferModule, TreasuryModule, AdminModule],
  providers: [SavingsService, SavingsSchedulerService],
  controllers: [SavingsController, SavingsAdminController],
})
export class SavingsModule {}
