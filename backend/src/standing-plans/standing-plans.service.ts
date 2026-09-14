import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { IsNotEmpty, IsOptional, IsString } from 'class-validator';
import { PrismaService } from '../prisma/prisma.service';

const FREQUENCY_MS: Record<string, number> = {
  DAILY: 24 * 60 * 60 * 1000,
  WEEKLY: 7 * 24 * 60 * 60 * 1000,
  MONTHLY: 30 * 24 * 60 * 60 * 1000,
};

export class CreateStandingPlanDto {
  @IsString()
  @IsNotEmpty()
  name!: string;

  @IsString()
  @IsNotEmpty()
  amount!: string;

  @IsString()
  @IsNotEmpty()
  assetCode!: string;

  @IsOptional()
  @IsString()
  assetIssuer?: string;

  @IsString()
  frequency!: string;

  @IsOptional()
  @IsString()
  toPublicKey?: string;

  @IsOptional()
  @IsString()
  toPayTag?: string;

  @IsOptional()
  @IsString()
  description?: string;
}

/**
 * Recurring payments — PayFlex's own scheduled-payment layer. Stellar has
 * no delegated-debit primitive either, and this app deliberately does not
 * pretend otherwise (the pre-authorization question from the original
 * design stays open and stays HONEST): the scheduler can only mark a
 * payment DUE and advance the schedule. Execution always requires the
 * user's live on-device signature — the app surfaces due payments, the
 * user signs, the payment is recorded via the verified transfer-record
 * endpoint with kind=STANDING_PLAN.
 */
@Injectable()
export class StandingPlansService {
  constructor(private readonly prisma: PrismaService) {}

  async createPlan(appUserId: string, dto: CreateStandingPlanDto) {
    if (!dto.toPublicKey && !dto.toPayTag) {
      throw new BadRequestException('Exactly one of toPublicKey or toPayTag is required.');
    }
    if (!FREQUENCY_MS[dto.frequency]) {
      throw new BadRequestException('frequency must be one of DAILY, WEEKLY, MONTHLY.');
    }

    // Resolve the PayTag to a public key at creation time so the stored
    // plan is chain-actionable; the tag's owner can't be silently swapped.
    let toPublicKey = dto.toPublicKey;
    if (dto.toPayTag) {
      const tag = await this.prisma.payTag.findUnique({
        where: { tag: dto.toPayTag },
        include: { appUser: { select: { stellarPublicKey: true } } },
      });
      if (!tag?.appUser.stellarPublicKey) {
        throw new BadRequestException(`No PayFlex user with PayTag @${dto.toPayTag} (or they have no key yet).`);
      }
      toPublicKey = tag.appUser.stellarPublicKey;
    }

    const nextPaymentAt = new Date(Date.now() + FREQUENCY_MS[dto.frequency]);
    return this.prisma.standingPlan.create({
      data: {
        appUserId,
        name: dto.name,
        assetCode: dto.assetCode,
        assetIssuer: dto.assetIssuer,
        amount: dto.amount,
        frequency: dto.frequency,
        toPublicKey,
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
   * It can NEVER execute a payment — that needs the user's on-device
   * signature, which nothing server-side may hold.
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
   * The app reports a due payment was signed and submitted on-chain; the
   * referenced transfer record (already verified) confirms it.
   */
  async recordPayment(appUserId: string, paymentId: string, stellarTxHash: string) {
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

    const record = await this.prisma.transferRecord.findUnique({ where: { stellarTxHash } });
    if (!record || record.appUserId !== appUserId || record.standingPlanId !== paymentId) {
      throw new BadRequestException(
        'No verified on-chain payment references this standing-plan payment. Record it via ' +
          'POST /users/:id/transfers/record with kind=STANDING_PLAN and standingPlanId set first.',
      );
    }

    return this.prisma.$transaction([
      this.prisma.standingPlanPayment.update({
        where: { id: paymentId },
        data: { status: 'RECORDED', stellarTxHash, completedAt: new Date() },
      }),
      this.prisma.standingPlan.update({
        where: { id: payment.standingPlan.id },
        data: { totalPaid: (Number(payment.standingPlan.totalPaid) + Number(payment.amount)).toFixed(7) },
      }),
    ]);
  }
}
