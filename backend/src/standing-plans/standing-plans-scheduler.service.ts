import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { StandingPlansService } from './standing-plans.service';

/** Runs StandingPlansService.runDueCheck on a schedule — see its doc comment for what this can and can't do. */
@Injectable()
export class StandingPlansSchedulerService {
  private readonly logger = new Logger(StandingPlansSchedulerService.name);

  constructor(private readonly plans: StandingPlansService) {}

  @Cron(CronExpression.EVERY_HOUR)
  async handleDueCheck() {
    const result = await this.plans.runDueCheck();
    if (result.paymentsCreated > 0) {
      this.logger.log(
        `Standing plans due-check: ${result.paymentsCreated} payment(s) now due ` +
          `across ${result.plansChecked} plan(s).`,
      );
    }
  }
}
