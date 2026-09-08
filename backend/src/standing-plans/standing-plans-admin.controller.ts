import { Controller, Post, UseGuards } from '@nestjs/common';
import { StandingPlansService } from './standing-plans.service';
import { AdminGuard } from '../admin/admin.guard';

/** Manual trigger for the due-payment check, same role as SavingsAdminController. */
@Controller('standing-plans')
@UseGuards(AdminGuard)
export class StandingPlansAdminController {
  constructor(private readonly plans: StandingPlansService) {}

  @Post('run-due-check')
  runDueCheck() {
    return this.plans.runDueCheck();
  }
}
