import {
  Injectable,
  ForbiddenException,
  BadRequestException,
  NotFoundException,
} from '@nestjs/common';
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
  targetAmount?: number;
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
  note?: string;
  status: 'PENDING' | 'COMPLETED' | 'FAILED';
  createdAt: Date;
}

@Injectable()
export class SafeboxService {
  // In-memory backing store for demo/sandbox execution
  private safeboxes = new Map<string, SafeboxRecord>();
  private members = new Map<string, SafeboxMemberRecord[]>(); // safeboxId -> members
  private transactions = new Map<string, SafeboxTxRecord[]>(); // safeboxId -> transactions
  private pendingTransfers = new Map<string, { safeboxId: string; currentOwner: string; newOwner: string; code: string }>();

  // Maximum allowed designated admins per Safebox (excluding owner)
  public static readonly MAX_ADMIN_CAP = 3;

  async createSafebox(ownerId: string, dto: CreateSafeboxDto): Promise<SafeboxRecord> {
    const id = `sb_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
    const safebox: SafeboxRecord = {
      id,
      name: dto.name,
      description: dto.description,
      ownerId,
      targetAmount: dto.targetAmount,
      currentBalance: 0.0,
      status: 'ACTIVE',
      createdAt: new Date(),
    };

    const ownerMember: SafeboxMemberRecord = {
      safeboxId: id,
      userId: ownerId,
      role: 'OWNER',
      joinedAt: new Date(),
    };

    this.safeboxes.set(id, safebox);
    this.members.set(id, [ownerMember]);
    this.transactions.set(id, []);

    return safebox;
  }

  async getUserSafeboxes(userId: string): Promise<{ safebox: SafeboxRecord; role: string }[]> {
    const results: { safebox: SafeboxRecord; role: string }[] = [];
    for (const [safeboxId, memberList] of this.members.entries()) {
      const userMember = memberList.find((m) => m.userId === userId);
      if (userMember) {
        const safebox = this.safeboxes.get(safeboxId);
        if (safebox) {
          results.push({ safebox, role: userMember.role });
        }
      }
    }
    return results;
  }

  async getSafeboxDetail(safeboxId: string, userId: string): Promise<{ safebox: SafeboxRecord; members: SafeboxMemberRecord[]; role: string }> {
    const safebox = this.safeboxes.get(safeboxId);
    if (!safebox) throw new NotFoundException('Safebox not found');

    const memberList = this.members.get(safeboxId) || [];
    const userMember = memberList.find((m) => m.userId === userId);

    // Enforce transparency: any member can view
    if (!userMember) {
      throw new ForbiddenException('Access Denied: You are not a member of this Safebox');
    }

    return { safebox, members: memberList, role: userMember.role };
  }

  async getTransactionLedger(safeboxId: string, userId: string): Promise<SafeboxTxRecord[]> {
    await this.getSafeboxDetail(safeboxId, userId); // Validates membership & transparency
    return this.transactions.get(safeboxId) || [];
  }

  async contribute(safeboxId: string, userId: string, dto: ContributeSafeboxDto): Promise<SafeboxTxRecord> {
    const { safebox } = await this.getSafeboxDetail(safeboxId, userId); // Ensures user is member

    const tx: SafeboxTxRecord = {
      id: `tx_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`,
      safeboxId,
      userId,
      type: 'CONTRIBUTION',
      amount: dto.amount,
      note: dto.note || 'Contribution to pool',
      status: 'COMPLETED',
      createdAt: new Date(),
    };

    safebox.currentBalance += dto.amount;
    const txList = this.transactions.get(safeboxId) || [];
    txList.unshift(tx);

    // Trigger notification to all members
    await this.notifyMembers(safeboxId, `New Contribution: User ${userId} contributed ₦${dto.amount} to "${safebox.name}"`);

    return tx;
  }

  async withdraw(safeboxId: string, userId: string, dto: WithdrawSafeboxDto): Promise<SafeboxTxRecord> {
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

    const tx: SafeboxTxRecord = {
      id: `tx_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`,
      safeboxId,
      userId,
      type: 'WITHDRAWAL',
      amount: dto.amount,
      note: dto.note,
      status: 'COMPLETED',
      createdAt: new Date(),
    };

    safebox.currentBalance -= dto.amount;
    const txList = this.transactions.get(safeboxId) || [];
    txList.unshift(tx);

    // Trigger notification to all members
    await this.notifyMembers(
      safeboxId,
      `Withdrawal Executed: ${role} (${userId}) withdrew ₦${dto.amount} from "${safebox.name}". Reason: ${dto.note}`,
    );

    return tx;
  }

  async updateMemberRole(safeboxId: string, actorUserId: string, dto: UpdateMemberRoleDto): Promise<SafeboxMemberRecord> {
    const { role: actorRole } = await this.getSafeboxDetail(safeboxId, actorUserId);
    if (actorRole !== 'OWNER') {
      throw new ForbiddenException('Only the Safebox Owner can promote or demote admins');
    }

    const memberList = this.members.get(safeboxId) || [];
    const targetMember = memberList.find((m) => m.userId === dto.targetUserId);
    if (!targetMember) throw new NotFoundException('Member not found in Safebox');

    if (targetMember.role === 'OWNER') {
      throw new BadRequestException('Owner role cannot be changed via role update. Use transfer ownership workflow.');
    }

    // SERVER-SIDE ENFORCEMENT OF 3-ADMIN CAP
    if (dto.role === 'ADMIN' && targetMember.role !== 'ADMIN') {
      const currentAdminsCount = memberList.filter((m) => m.role === 'ADMIN').length;
      if (currentAdminsCount >= SafeboxService.MAX_ADMIN_CAP) {
        throw new BadRequestException(
          `Admin Limit Exceeded: Safebox is capped at maximum ${SafeboxService.MAX_ADMIN_CAP} designated admins (in addition to the 1 owner).`,
        );
      }
    }

    targetMember.role = dto.role;
    return targetMember;
  }

  async addMember(safeboxId: string, actorUserId: string, newUserId: string): Promise<SafeboxMemberRecord> {
    const { role: actorRole } = await this.getSafeboxDetail(safeboxId, actorUserId);
    if (actorRole !== 'OWNER' && actorRole !== 'ADMIN') {
      throw new ForbiddenException('Only Owner or Admins can invite new members');
    }

    const memberList = this.members.get(safeboxId) || [];
    if (memberList.some((m) => m.userId === newUserId)) {
      throw new BadRequestException('User is already a member of this Safebox');
    }

    const newMember: SafeboxMemberRecord = {
      safeboxId,
      userId: newUserId,
      role: 'MEMBER',
      joinedAt: new Date(),
    };

    memberList.push(newMember);
    return newMember;
  }

  async initiateOwnershipTransfer(safeboxId: string, ownerUserId: string, dto: InitiateOwnershipTransferDto): Promise<{ transferId: string; confirmationRequired: boolean }> {
    const { safebox, role } = await this.getSafeboxDetail(safeboxId, ownerUserId);
    if (role !== 'OWNER') {
      throw new ForbiddenException('Only the current owner can initiate ownership transfer');
    }

    const memberList = this.members.get(safeboxId) || [];
    const target = memberList.find((m) => m.userId === dto.newOwnerUserId);
    if (!target) throw new BadRequestException('New owner must already be a member of the Safebox');

    const transferId = `ot_${Date.now()}`;
    this.pendingTransfers.set(transferId, {
      safeboxId,
      currentOwner: ownerUserId,
      newOwner: dto.newOwnerUserId,
      code: Math.floor(100000 + Math.random() * 900000).toString(),
    });

    return { transferId, confirmationRequired: true };
  }

  async confirmOwnershipTransfer(transferId: string, newOwnerUserId: string, confirmationCode: string): Promise<{ success: boolean }> {
    const transfer = this.pendingTransfers.get(transferId);
    if (!transfer) throw new NotFoundException('Ownership transfer request expired or invalid');
    if (transfer.newOwner !== newOwnerUserId) throw new ForbiddenException('You are not the designated recipient of this ownership transfer');
    if (transfer.code !== confirmationCode) throw new BadRequestException('Invalid confirmation code');

    const safebox = this.safeboxes.get(transfer.safeboxId);
    if (!safebox) throw new NotFoundException('Safebox missing');

    const memberList = this.members.get(transfer.safeboxId) || [];
    const oldOwnerMember = memberList.find((m) => m.userId === transfer.currentOwner);
    const newOwnerMember = memberList.find((m) => m.userId === transfer.newOwner);

    if (oldOwnerMember) oldOwnerMember.role = 'ADMIN'; // Demotes former owner to admin
    if (newOwnerMember) newOwnerMember.role = 'OWNER';

    safebox.ownerId = transfer.newOwner;
    this.pendingTransfers.delete(transferId);

    return { success: true };
  }

  private async notifyMembers(safeboxId: string, message: string): Promise<void> {
    const memberList = this.members.get(safeboxId) || [];
    // Dispatches notifications to all members of the pool
    console.log(`[SAFEBOX NOTIFICATION] [${safeboxId}] (${memberList.length} members): ${message}`);
  }
}
