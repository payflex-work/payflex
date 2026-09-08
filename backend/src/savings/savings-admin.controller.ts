import { Controller, Post, UseGuards } from '@nestjs/common';
import { SavingsService } from './savings.service';
import { AdminGuard } from '../admin/admin.guard';

/**
 * Manual trigger for the due-contribution check, so this can be verified
 * (and demoed) without waiting for the hourly cron in
 * SavingsSchedulerService. Admin-gated — any authenticated user could
 * trigger this before AdminGuard existed, which wasn't right even though
 * it's low-severity (it only makes contributions due sooner).
 */
@Controller('savings')
@UseGuards(AdminGuard)
export class SavingsAdminController {
  constructor(private readonly savings: SavingsService) {}

  @Post('run-due-check')
  runDueCheck() {
    return this.savings.runDueCheck();
  }
}
