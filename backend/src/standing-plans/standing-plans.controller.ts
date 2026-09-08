import { Body, Controller, Get, Param, Post, Put } from '@nestjs/common';
import { StandingPlansService } from './standing-plans.service';
import { CreateStandingPlanDto } from './dto/create-standing-plan.dto';

@Controller('users/:id/standing-plans')
export class StandingPlansController {
  constructor(private readonly plans: StandingPlansService) {}

  @Post()
  create(@Param('id') id: string, @Body() dto: CreateStandingPlanDto) {
    return this.plans.createPlan(id, dto);
  }

  @Get()
  list(@Param('id') id: string) {
    return this.plans.listPlans(id);
  }

  @Get('due')
  listDue(@Param('id') id: string) {
    return this.plans.listDuePayments(id);
  }

  @Put(':planId/status')
  setStatus(
    @Param('id') id: string,
    @Param('planId') planId: string,
    @Body('status') status: 'ACTIVE' | 'PAUSED' | 'CANCELLED',
  ) {
    return this.plans.setStatus(id, planId, status);
  }

  /**
   * Returns the same Proposal shape TransferController's endpoints do —
   * the app signs/submits it via the normal
   * /transfers/:proposalId/sign-payload and /sign routes.
   */
  @Post('payments/:paymentId/pay')
  pay(@Param('id') id: string, @Param('paymentId') paymentId: string) {
    return this.plans.pay(id, paymentId);
  }
}
