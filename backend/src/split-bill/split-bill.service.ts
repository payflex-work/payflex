import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import {
  IsStellarAmount,
  IsStellarAssetCode,
  SanitizedText,
} from '../common/validation/validators';
import { StrKey } from '@stellar/stellar-sdk';
import { PrismaService } from '../prisma/prisma.service';
import { UsersService } from '../users/users.service';

export class CreateSplitBillDto {
  @SanitizedText({ max: 140, min: 1 })
  description!: string;

  @IsStellarAmount()
  totalAmount!: string;

  @IsStellarAssetCode()
  assetCode!: string;

  /** Each contributor: payTag or publicKey; shareAmount is that member's part. */
  @SanitizedText({ max: 20_000, min: 1 })
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
    if (parsed.length > 50) {
      throw new BadRequestException('A split bill can have at most 50 contributors.');
    }

    // Per-contributor validation BEFORE any rows are written: a malformed
    // or duplicate entry must fail the whole request, not leave a
    // half-created bill behind.
    const seen = new Set<string>();
    for (const [i, c] of parsed.entries()) {
      if (typeof c.shareAmount !== 'string' || !/^\d+(\.\d{1,7})?$/.test(c.shareAmount) || Number(c.shareAmount) <= 0) {
        throw new BadRequestException(
          `contributorsJson[${i}].shareAmount must be a positive decimal string with at most 7 decimal places (e.g. "12.50").`,
        );
      }
      if (Number(c.shareAmount) > 1_000_000_000_000) {
        throw new BadRequestException(`contributorsJson[${i}].shareAmount exceeds the maximum amount (1e12).`);
      }
      if (c.payTag != null && c.publicKey != null) {
        throw new BadRequestException(`contributorsJson[${i}]: provide either payTag or publicKey, not both.`);
      }
      if (typeof c.payTag === 'string' && c.payTag.length > 0) {
        if (!/^[a-z0-9_]{3,20}$/.test(c.payTag)) {
          throw new BadRequestException(`contributorsJson[${i}].payTag must be 3-20 characters: lowercase letters, digits, underscore.`);
        }
        seen.add(`tag:${c.payTag}`);
      } else if (typeof c.publicKey === 'string' && c.publicKey.length > 0) {
        if (!/^G[A-Z2-7]{55}$/.test(c.publicKey)) {
          throw new BadRequestException(`contributorsJson[${i}].publicKey must be a valid Ed25519 account strkey (G…).`);
        }
        seen.add(`key:${c.publicKey}`);
      } else {
        throw new BadRequestException(`contributorsJson[${i}] needs a payTag or publicKey.`);
      }
    }
    if (seen.size < parsed.length) {
      throw new BadRequestException('Duplicate contributors are not allowed.');
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
        // Sanity: never hand a checksum-broken key to a unique lookup.
        if (!StrKey.isValidEd25519PublicKey(c.publicKey)) {
          throw new BadRequestException(`contributorsJson publicKey is not a valid Ed25519 account strkey.`);
        }
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
