import {
  Injectable,
  ForbiddenException,
  BadRequestException,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { TransferService } from '../transfer/transfer.service';
import { TreasuryService } from '../treasury/treasury.service';
import { BmoniApiError } from '../bmoni/bmoni.errors';
import {
  CreateSafeboxDto,
  ContributeSafeboxDto,
  WithdrawSafeboxDto,
  UpdateMemberRoleDto,
  InitiateOwnershipTransferDto,
} from './dto/safebox.dto';

export interface SafeboxMemberRecord {
  safeboxId: string;
  userId: string;
  role: 'OWNER' | 'ADMIN' | 'MEMBER';
  joinedAt: Date;
}

export interface SafeboxRecord {
  id: string;
  name: string;
  description: string;
  ownerId: string;
  targetAmount?: number | null;
  currentBalance: number;
  status: 'ACTIVE' | 'CLOSED';
  createdAt: Date;
}

export interface SafeboxTxRecord {
  id: string;
  safeboxId: string;
  userId: string;
  type: 'CONTRIBUTION' | 'WITHDRAWAL';
  amount: number;
  note?: string | null;
  status: 'PENDING' | 'COMPLETED' | 'FAILED';
  createdAt: Date;
}

// No currency field exists on this model yet (schema/DTO limitation
// inherited as-is) — every safebox settles in NGN, matching the app's
// primary/priority rail (build brief section 2.3). Add a currency column
// before offering this feature on any other rail.
const SAFEBOX_CURRENCY = 'NGN';

/**
 * Group savings pool. Contributions are real signed TRANSFER proposals
 * (member -> PayFlex treasury), same pattern as SavingsGoal.contribute;
 * withdrawals are treasury-signed releases server-side, same pattern as
 * loan disbursement — a shared pool has no single member whose on-device
 * key can sign on its behalf. `currentBalance` is optimistic bookkeeping
 * only (updated on proposal creation, not confirmed settlement) — this
 * build has no way to observe real on-chain settlement, same honest
 * limitation as SavingsGoal.totalContributed.
 */
@Injectable()
export class SafeboxService {
  public static readonly MAX_ADMIN_CAP = 3;

  constructor(
    private readonly prisma: PrismaService,
    private readonly transfers: TransferService,
    private readonly treasury: TreasuryService,
  ) {}

  async createSafebox(ownerId: string, dto: CreateSafeboxDto): Promise<SafeboxRecord> {
    return this.prisma.safebox.create({
      data: {
        name: dto.name,
        description: dto.description,
        ownerId,
        targetAmount: dto.targetAmount,
        members: { create: { userId: ownerId, role: 'OWNER' } },
      },
    });
  }

  async getUserSafeboxes(userId: string): Promise<{ safebox: SafeboxRecord; role: string }[]> {
    const memberships = await this.prisma.safeboxMember.findMany({
      where: { userId },
      include: { safebox: true },
      orderBy: { joinedAt: 'desc' },
    });
    return memberships.map((m) => ({ safebox: m.safebox, role: m.role }));
  }

  /** Any member can view — group savings is deliberately transparent to its own members. */
  async getSafeboxDetail(
    safeboxId: string,
    userId: string,
  ): Promise<{ safebox: SafeboxRecord; members: SafeboxMemberRecord[]; role: string }> {
    const safebox = await this.prisma.safebox.findUnique({
      where: { id: safeboxId },
      include: { members: true },
    });
    if (!safebox) throw new NotFoundException('Safebox not found');

    const userMember = safebox.members.find((m) => m.userId === userId);
    if (!userMember) {
      throw new ForbiddenException('Access Denied: You are not a member of this Safebox');
    }

    return { safebox, members: safebox.members, role: userMember.role };
  }

  async getTransactionLedger(safeboxId: string, userId: string): Promise<SafeboxTxRecord[]> {
    await this.getSafeboxDetail(safeboxId, userId);
    return this.prisma.safeboxTransaction.findMany({
      where: { safeboxId },
      orderBy: { createdAt: 'desc' },
    });
  }

  /** Creates the signable TRANSFER proposal; caller signs/submits it through the normal transfer endpoints. */
  async contribute(safeboxId: string, userId: string, dto: ContributeSafeboxDto): Promise<SafeboxTxRecord & { proposalId: string }> {
    const { safebox } = await this.getSafeboxDetail(safeboxId, userId);
    await this.treasury.getWalletId(SAFEBOX_CURRENCY);

    const proposal = await this.transfers.createTransfer(userId, {
      toBmoniUserId: this.treasury.getBmoniUserId(),
      amount: dto.amount.toFixed(2),
      currency: SAFEBOX_CURRENCY,
      description: `Safebox contribution: ${safebox.name}`,
    });

    const [tx] = await this.prisma.$transaction([
      this.prisma.safeboxTransaction.create({
        data: {
          safeboxId,
          userId,
          type: 'CONTRIBUTION',
          amount: dto.amount,
          note: dto.note || 'Contribution to pool',
          status: 'PENDING',
        },
      }),
      this.prisma.safebox.update({
        where: { id: safeboxId },
        data: { currentBalance: { increment: dto.amount } },
      }),
    ]);

    return { ...tx, proposalId: proposal.id };
  }

  /**
   * Owner/admin-only. The treasury signs the release server-side — a
   * shared pool has no single member whose on-device key can sign on
   * its behalf, same reasoning as loan disbursement.
   */
  async withdraw(safeboxId: string, userId: string, dto: WithdrawSafeboxDto): Promise<SafeboxTxRecord & { proposalId: string }> {
    const { safebox, role } = await this.getSafeboxDetail(safeboxId, userId);

    // SERVER-SIDE PERMISSION ENFORCEMENT:
    // Only owner and designated admins can withdraw!
    if (role !== 'OWNER' && role !== 'ADMIN') {
      throw new ForbiddenException(
        'Access Denied: Only the Safebox Owner and designated Admins are authorized to initiate withdrawals',
      );
    }

    if (safebox.currentBalance < dto.amount) {
      throw new BadRequestException('Insufficient balance in Safebox pool');
    }

    const treasuryAppUserId = await this.treasury.getAppUserId();
    await this.treasury.getWalletId(SAFEBOX_CURRENCY);

    const proposal = await this.transfers.createTransfer(treasuryAppUserId, {
      toBmoniUserId: dto.recipientAccountId,
      amount: dto.amount.toFixed(2),
      currency: SAFEBOX_CURRENCY,
      description: `Safebox withdrawal: ${safebox.name} (${dto.note})`,
    });

    const signPayload = await this.waitForSignPayload(treasuryAppUserId, proposal.id);
    const signature = this.treasury.signDigest(signPayload.signingPayloadHash);
    await this.transfers.submitSignature(treasuryAppUserId, proposal.id, signature);

    const [tx] = await this.prisma.$transaction([
      this.prisma.safeboxTransaction.create({
        data: {
          safeboxId,
          userId,
          type: 'WITHDRAWAL',
          amount: dto.amount,
          note: dto.note,
          status: 'COMPLETED',
        },
      }),
      this.prisma.safebox.update({
        where: { id: safeboxId },
        data: { currentBalance: { decrement: dto.amount } },
      }),
    ]);

    return { ...tx, proposalId: proposal.id };
  }

  async updateMemberRole(safeboxId: string, actorUserId: string, dto: UpdateMemberRoleDto): Promise<SafeboxMemberRecord> {
    const { role: actorRole, members } = await this.getSafeboxDetail(safeboxId, actorUserId);
    if (actorRole !== 'OWNER') {
      throw new ForbiddenException('Only the Safebox Owner can promote or demote admins');
    }

    const targetMember = members.find((m) => m.userId === dto.targetUserId);
    if (!targetMember) throw new NotFoundException('Member not found in Safebox');

    if (targetMember.role === 'OWNER') {
      throw new BadRequestException('Owner role cannot be changed via role update. Use transfer ownership workflow.');
    }

    if (dto.role === 'ADMIN' && targetMember.role !== 'ADMIN') {
      const currentAdminsCount = members.filter((m) => m.role === 'ADMIN').length;
      if (currentAdminsCount >= SafeboxService.MAX_ADMIN_CAP) {
        throw new BadRequestException(
          `Admin Limit Exceeded: Safebox is capped at maximum ${SafeboxService.MAX_ADMIN_CAP} designated admins (in addition to the 1 owner).`,
        );
      }
    }

    return this.prisma.safeboxMember.update({
      where: { safeboxId_userId: { safeboxId, userId: dto.targetUserId } },
      data: { role: dto.role },
    });
  }

  async addMember(safeboxId: string, actorUserId: string, newUserId: string): Promise<SafeboxMemberRecord> {
    const { role: actorRole } = await this.getSafeboxDetail(safeboxId, actorUserId);
    if (actorRole !== 'OWNER' && actorRole !== 'ADMIN') {
      throw new ForbiddenException('Only Owner or Admins can invite new members');
    }

    const existing = await this.prisma.safeboxMember.findUnique({
      where: { safeboxId_userId: { safeboxId, userId: newUserId } },
    });
    if (existing) throw new BadRequestException('User is already a member of this Safebox');

    return this.prisma.safeboxMember.create({
      data: { safeboxId, userId: newUserId, role: 'MEMBER' },
    });
  }

  /**
   * 2-step ownership transfer. Keyed by `safeboxId` rather than a
   * separate transfer id: the confirm route only ever carries
   * `:safeboxId` in its URL (see SafeboxController), so a transferId
   * returned from initiate would never actually reach confirm — keying
   * by safeboxId is what the route shape can actually deliver, and a
   * safebox only ever has one pending transfer at a time regardless.
   * The confirmation code is only known to the current owner after
   * initiating — they're responsible for relaying it to the intended new
   * owner out of band before it expires. In-memory (not persisted) since
   * it's short-lived and this process isn't horizontally scaled; a
   * multi-instance deployment would need this in Redis instead (see
   * AuthService's login challenge for that exact pattern).
   */
  private pendingTransfers = new Map<
    string,
    { currentOwner: string; newOwner: string; code: string }
  >();

  async initiateOwnershipTransfer(
    safeboxId: string,
    ownerUserId: string,
    dto: InitiateOwnershipTransferDto,
  ): Promise<{ transferId: string; confirmationRequired: boolean }> {
    const { role, members } = await this.getSafeboxDetail(safeboxId, ownerUserId);
    if (role !== 'OWNER') {
      throw new ForbiddenException('Only the current owner can initiate ownership transfer');
    }

    const target = members.find((m) => m.userId === dto.newOwnerUserId);
    if (!target) throw new BadRequestException('New owner must already be a member of the Safebox');

    this.pendingTransfers.set(safeboxId, {
      currentOwner: ownerUserId,
      newOwner: dto.newOwnerUserId,
      code: Math.floor(100000 + Math.random() * 900000).toString(),
    });

    return { transferId: safeboxId, confirmationRequired: true };
  }

  async confirmOwnershipTransfer(
    safeboxId: string,
    newOwnerUserId: string,
    confirmationCode: string,
  ): Promise<{ success: boolean }> {
    const transfer = this.pendingTransfers.get(safeboxId);
    if (!transfer) throw new NotFoundException('Ownership transfer request expired or invalid');
    if (transfer.newOwner !== newOwnerUserId) {
      throw new ForbiddenException('You are not the designated recipient of this ownership transfer');
    }
    if (transfer.code !== confirmationCode) throw new BadRequestException('Invalid confirmation code');

    await this.prisma.$transaction([
      this.prisma.safebox.update({ where: { id: safeboxId }, data: { ownerId: transfer.newOwner } }),
      this.prisma.safeboxMember.update({
        where: { safeboxId_userId: { safeboxId, userId: transfer.currentOwner } },
        data: { role: 'ADMIN' },
      }),
      this.prisma.safeboxMember.update({
        where: { safeboxId_userId: { safeboxId, userId: transfer.newOwner } },
        data: { role: 'OWNER' },
      }),
    ]);
    this.pendingTransfers.delete(safeboxId);

    return { success: true };
  }

  /** Sign payload is prepared asynchronously — it can 409 briefly after proposal creation; poll. */
  private async waitForSignPayload(appUserId: string, proposalId: string) {
    for (let attempt = 0; attempt < 8; attempt++) {
      try {
        return await this.transfers.getSignPayload(appUserId, proposalId);
      } catch (err) {
        if (err instanceof BmoniApiError && err.status === 409 && attempt < 7) {
          await new Promise((r) => setTimeout(r, 1500));
          continue;
        }
        throw err;
      }
    }
    throw new Error(`Sign payload for proposal ${proposalId} never became ready.`);
  }
}
