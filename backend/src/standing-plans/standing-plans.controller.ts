import { Body, Controller, Get, Param, Post, Put } from '@nestjs/common';
import { StandingPlansService } from './standing-plans.service';
import { CreateStandingPlanDto, SetPlanStatusDto, RecordPlanPaymentDto } from './standing-plans.service';

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
    @Body() dto: SetPlanStatusDto,
  ) {
    return this.plans.setStatus(id, planId, dto.status as 'ACTIVE' | 'PAUSED' | 'CANCELLED');
  }

  /**
   * The app reports this due payment was signed and submitted on-chain.
   * Requires a verified TransferRecord referencing this payment
   * (kind=STANDING_PLAN, standingPlanId set) — see StandingPlansService.
   */
  @Post('payments/:paymentId/record')
  recordPayment(
    @Param('id') id: string,
    @Param('paymentId') paymentId: string,
    @Body() dto: RecordPlanPaymentDto,
  ) {
    return this.plans.recordPayment(id, paymentId, dto.stellarTxHash);
  }
}
