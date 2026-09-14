import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { StellarService } from '../stellar/stellar.service';
import { UsersService } from '../users/users.service';
import { CreateTransferDto } from './dto/create-transfer.dto';
import { RecordTransferDto } from './dto/record-transfer.dto';

const VALID_KINDS = ['TRANSFER', 'QR_PAY', 'OFFLINE_REDEMPTION', 'SPLIT_BILL', 'STANDING_PLAN', 'LINK_CLAIM'];

/**
 * Stellar-native transfers. The backend's role is deliberately small:
 *
 *  - resolve WHO a PayTag points at (directory),
 *  - show the recipient's name before the app builds a payment,
 *  - RECORD and VERIFY what the app already submitted to Horizon.
 *
 * It cannot move money: every payment is built and signed on the user's
 * device with their own Stellar key and submitted to the network by them.
 */
@Injectable()
export class TransferService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly stellar: StellarService,
    private readonly users: UsersService,
  ) {}

  /**
   * Resolves a transfer target to a Stellar public key + display name.
   * The app uses this before building the payment (to show "sending to
   * Ada" and embed the right destination). No chain interaction here.
   */
  async resolveTarget(appUserId: string, dto: CreateTransferDto) {
    await this.users.findById(appUserId);

    if (dto.toPayTag) {
      const recipient = await this.prisma.payTag.findUnique({
        where: { tag: dto.toPayTag },
        include: { appUser: true },
      });
      if (!recipient?.appUser.stellarPublicKey) {
        throw new NotFoundException(`No PayFlex user with PayTag @${dto.toPayTag}, or they have no Stellar key yet.`);
      }
      return {
        toPublicKey: recipient.appUser.stellarPublicKey,
        firstName: recipient.appUser.firstName,
        lastName: recipient.appUser.lastName,
      };
    }

    if (dto.toPublicKey) {
      const known = await this.prisma.appUser.findUnique({ where: { stellarPublicKey: dto.toPublicKey } });
      return {
        toPublicKey: dto.toPublicKey,
        firstName: known?.firstName ?? 'Unknown',
        lastName: known?.lastName ?? 'recipient',
      };
    }

    throw new BadRequestException('Exactly one of toPublicKey or toPayTag is required.');
  }

  /**
   * Records a payment the app claims it submitted. The transaction is
   * pulled from Horizon and verified field-by-field; a record is only
   * written for payments that really exist and match the claim exactly.
   * Idempotent on stellarTxHash (unique index).
   */
  async recordTransfer(appUserId: string, dto: RecordTransferDto) {
    const user = await this.users.findById(appUserId);
    if (dto.kind && !VALID_KINDS.includes(dto.kind)) {
      throw new BadRequestException(`kind must be one of: ${VALID_KINDS.join(', ')}.`);
    }

    const verification = await this.stellar.verifyPayment({
      txHash: dto.stellarTxHash,
      fromPublicKey: dto.fromPublicKey,
      toPublicKey: dto.toPublicKey,
      amount: dto.amount,
      assetCode: dto.assetCode,
      assetIssuer: dto.assetIssuer,
    });

    if (!verification.ok) {
      throw new BadRequestException(`Payment verification failed: ${verification.reason}`);
    }

    if (dto.fromPublicKey !== user.stellarPublicKey) {
      throw new BadRequestException(
        'fromPublicKey does not match the authenticated user\u2019s registered Stellar public key.',
      );
    }

    try {
      return await this.prisma.transferRecord.create({
        data: {
          appUserId,
          stellarTxHash: dto.stellarTxHash,
          fromPublicKey: dto.fromPublicKey,
          toPublicKey: dto.toPublicKey,
          amount: dto.amount,
          assetCode: dto.assetCode,
          assetIssuer: dto.assetIssuer,
          kind: dto.kind ?? 'TRANSFER',
          qrTokenRef: dto.qrTokenRef,
          splitBillId: dto.splitBillId,
          standingPlanId: dto.standingPlanId,
          offlineAuthorizationId: dto.offlineAuthorizationId,
          memo: verification.memo ?? dto.memo,
        },
      });
    } catch (err) {
      // Unique violation on stellarTxHash = already recorded; return the
      // existing row so retries are harmless. Anything else is real.
      if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002') {
        const existing = await this.prisma.transferRecord.findUnique({
          where: { stellarTxHash: dto.stellarTxHash },
        });
        if (existing) return existing;
      }
      throw new BadRequestException('Could not record this payment (invalid reference).');
    }
  }

  async listTransfers(appUserId: string, limit = 50) {
    await this.users.findById(appUserId);
    return this.prisma.transferRecord.findMany({
      where: { appUserId },
      orderBy: { createdAt: 'desc' },
      take: limit,
    });
  }
}
