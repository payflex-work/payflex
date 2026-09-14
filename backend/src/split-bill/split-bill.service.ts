import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { IsOptional, IsString } from 'class-validator';
import { PrismaService } from '../prisma/prisma.service';
import { UsersService } from '../users/users.service';

export class CreateSplitBillDto {
  @IsString()
  description!: string;

  @IsString()
  totalAmount!: string;

  @IsString()
  assetCode!: string;

  /** Each contributor: payTag or publicKey; shareAmount is that member's part. */
  @IsOptional()
  @IsString()
  contributorsJson!: string; // [{ payTag?, publicKey?, shareAmount }]
}

/**
 * Split bills — pure orchestration (Stellar has no group-payment primitive,
 * and PayFlex doesn't pretend to): the bill tracks who owes what; each
 * contributor pays with their own on-device Stellar payment and records it
 * via POST /users/:id/transfers/record with kind=SPLIT_BILL and this bill's
 * id. The backend flips the contributor to PAID only when a verified
 * on-chain payment lands. A shared HMAC-signed QR carries the bill id so a
 * scanning contributor's app can look up their own share.
 */
@Injectable()
export class SplitBillService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly users: UsersService,
  ) {}

  async create(creatorAppUserId: string, dto: CreateSplitBillDto) {
    await this.users.findById(creatorAppUserId);

    interface ContributorInput {
      payTag?: string;
      publicKey?: string;
      shareAmount: string;
    }
    let parsed: ContributorInput[];
    try {
      parsed = JSON.parse(dto.contributorsJson);
    } catch {
      throw new BadRequestException('contributorsJson must be a JSON array of { payTag?, publicKey?, shareAmount }.');
    }
    if (!Array.isArray(parsed) || parsed.length === 0) {
      throw new BadRequestException('At least one contributor is required.');
    }

    const bill = await this.prisma.splitBill.create({
      data: {
        creatorAppUserId,
        description: dto.description,
        totalAmount: dto.totalAmount,
        assetCode: dto.assetCode,
      },
    });

    for (const c of parsed) {
      let appUserId: string | null = null;
      if (c.payTag) {
        const tag = await this.prisma.payTag.findUnique({ where: { tag: c.payTag } });
        appUserId = tag?.appUserId ?? null;
      } else if (c.publicKey) {
        const u = await this.prisma.appUser.findUnique({ where: { stellarPublicKey: c.publicKey } });
        appUserId = u?.id ?? null;
      } else {
        throw new BadRequestException('Each contributor needs a payTag or publicKey.');
      }
      if (!appUserId) {
        throw new BadRequestException(`No PayFlex user found for contributor (${c.payTag ?? c.publicKey}).`);
      }
      await this.prisma.splitBillContributor.create({
        data: { splitBillId: bill.id, appUserId, shareAmount: c.shareAmount },
      });
    }

    return this.getDetail(creatorAppUserId, bill.id);
  }

  async listForUser(appUserId: string) {
    await this.users.findById(appUserId);
    const created = await this.prisma.splitBill.findMany({
      where: { creatorAppUserId: appUserId },
      include: { contributors: true },
      orderBy: { createdAt: 'desc' },
    });
    const contributing = await this.prisma.splitBillContributor.findMany({
      where: { appUserId },
      include: { splitBill: { include: { contributors: true } } },
    });
    return { created, contributing };
  }

  async getDetail(appUserId: string, splitBillId: string) {
    await this.users.findById(appUserId);
    const bill = await this.prisma.splitBill.findUnique({
      where: { id: splitBillId },
      include: { contributors: { include: { appUser: { select: { firstName: true, lastName: true, stellarPublicKey: true } } } } },
    });
    if (!bill) throw new NotFoundException(`No split bill with id ${splitBillId}.`);
    return bill;
  }

  /** Called internally when a verified transfer record references this bill. */
  async markContributorPaid(splitBillId: string, appUserId: string, stellarTxHash: string) {
    const contributor = await this.prisma.splitBillContributor.findUnique({
      where: { splitBillId_appUserId: { splitBillId, appUserId } },
    });
    if (!contributor) return null;
    return this.prisma.splitBillContributor.update({
      where: { id: contributor.id },
      data: { status: 'RECORDED', stellarTxHash },
    });
  }
}
