import { Module } from '@nestjs/common';
import { StandingPlansService } from './standing-plans.service';
import { StandingPlansSchedulerService } from './standing-plans-scheduler.service';
import { StandingPlansController } from './standing-plans.controller';
import { StandingPlansAdminController } from './standing-plans-admin.controller';
import { AdminModule } from '../admin/admin.module';

@Module({
  imports: [AdminModule],
  providers: [StandingPlansService, StandingPlansSchedulerService],
  controllers: [StandingPlansController, StandingPlansAdminController],
})
export class StandingPlansModule {}
