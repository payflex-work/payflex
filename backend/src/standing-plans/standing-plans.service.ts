import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { TransferService } from '../transfer/transfer.service';
import { PayTagService } from '../transfer/paytag.service';
import { CreateStandingPlanDto } from './dto/create-standing-plan.dto';

const FREQUENCY_MS: Record<string, number> = {
  DAILY: 24 * 60 * 60 * 1000,
  WEEKLY: 7 * 24 * 60 * 60 * 1000,
  MONTHLY: 30 * 24 * 60 * 60 * 1000,
};

/**
 * Recurring transfers to a chosen recipient — PayFlex's own scheduled-
 * payment layer, since BMONI has no recurring-payment or delegated-debit
 * primitive (see the doc comment on StandingPlan in schema.prisma). Same
 * structure as SavingsService, and the same honest limitation: the
 * scheduler can only ever mark a payment DUE, never execute it
 * unattended, because every transfer needs the user's live on-device
 * signature.
 */
@Injectable()
export class StandingPlansService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly transfers: TransferService,
    private readonly payTags: PayTagService,
  ) {}

  async createPlan(appUserId: string, dto: CreateStandingPlanDto) {
    if (!dto.toBmoniUserId && !dto.toPayTag) {
      throw new BadRequestException('Exactly one of toBmoniUserId or toPayTag is required.');
    }
    const nextPaymentAt = new Date(Date.now() + FREQUENCY_MS[dto.frequency]);
    return this.prisma.standingPlan.create({
      data: {
        appUserId,
        name: dto.name,
        currency: dto.currency,
        amount: dto.amount,
        frequency: dto.frequency,
        toBmoniUserId: dto.toBmoniUserId,
        toPayTag: dto.toPayTag,
        description: dto.description,
        nextPaymentAt,
      },
    });
  }

  listPlans(appUserId: string) {
    return this.prisma.standingPlan.findMany({
      where: { appUserId },
      include: { payments: { orderBy: { dueAt: 'desc' }, take: 10 } },
      orderBy: { createdAt: 'desc' },
    });
  }

  async listDuePayments(appUserId: string) {
    return this.prisma.standingPlanPayment.findMany({
      where: { status: 'DUE', standingPlan: { appUserId } },
      include: { standingPlan: true },
      orderBy: { dueAt: 'asc' },
    });
  }

  async setStatus(appUserId: string, planId: string, status: 'ACTIVE' | 'PAUSED' | 'CANCELLED') {
    const plan = await this.prisma.standingPlan.findUnique({ where: { id: planId } });
    if (!plan || plan.appUserId !== appUserId) {
      throw new NotFoundException(`No standing plan ${planId} for this user.`);
    }
    return this.prisma.standingPlan.update({ where: { id: planId }, data: { status } });
  }

  /**
   * The scheduler's only job: for every ACTIVE plan whose nextPaymentAt
   * has passed, create a DUE payment row and advance nextPaymentAt.
   * Nothing here touches BMONI — see `pay()` for the step that actually
   * creates a signable proposal, which only happens when the user is
   * present in the app to trigger it.
   */
  async runDueCheck(): Promise<{ plansChecked: number; paymentsCreated: number }> {
    const now = new Date();
    const duePlans = await this.prisma.standingPlan.findMany({
      where: { status: 'ACTIVE', nextPaymentAt: { lte: now } },
    });

    for (const plan of duePlans) {
      await this.prisma.$transaction([
        this.prisma.standingPlanPayment.create({
          data: { standingPlanId: plan.id, amount: plan.amount, dueAt: now },
        }),
        this.prisma.standingPlan.update({
          where: { id: plan.id },
          data: { nextPaymentAt: new Date(now.getTime() + FREQUENCY_MS[plan.frequency]) },
        }),
      ]);
    }

    return { plansChecked: duePlans.length, paymentsCreated: duePlans.length };
  }

  /**
   * Creates the actual signable TRANSFER proposal for a due payment —
   * the caller signs/submits it through the normal transfer endpoints
   * (/users/:id/transfers/:proposalId/sign-payload then /sign), same as
   * any other transfer; this just resolves "who, how much."
   */
  async pay(appUserId: string, paymentId: string) {
    const payment = await this.prisma.standingPlanPayment.findUnique({
      where: { id: paymentId },
      include: { standingPlan: true },
    });
    if (!payment || payment.standingPlan.appUserId !== appUserId) {
      throw new NotFoundException(`No due payment ${paymentId} for this user.`);
    }
    if (payment.status !== 'DUE') {
      throw new BadRequestException(`Payment ${paymentId} is already ${payment.status}.`);
    }

    const plan = payment.standingPlan;
    const toBmoniUserId = plan.toPayTag
      ? (await this.payTags.resolve(plan.toPayTag)).bmoniUserId
      : plan.toBmoniUserId!;

    const proposal = await this.transfers.createTransfer(appUserId, {
      toBmoniUserId,
      amount: payment.amount,
      currency: plan.currency,
      description: `Standing plan: ${plan.name}`,
    });

    await this.prisma.$transaction([
      this.prisma.standingPlanPayment.update({
        where: { id: paymentId },
        data: { status: 'PROPOSED', bmoniProposalId: proposal.id },
      }),
      this.prisma.standingPlan.update({
        where: { id: plan.id },
        data: { totalPaid: (Number(plan.totalPaid) + Number(payment.amount)).toFixed(2) },
      }),
    ]);

    return proposal;
  }
}
