import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { IsOptional, IsString } from 'class-validator';
import { PrismaService } from '../prisma/prisma.service';
import { StellarService } from '../stellar/stellar.service';
import { UsersService } from '../users/users.service';

export class RegisterSafeboxDto {
  @IsString()
  contractId!: string;

  @IsString()
  name!: string;

  @IsOptional()
  @IsString()
  description?: string;
}

/**
 * Safebox on Soroban. The CONTRACT (backend/contracts/safebox) is the
 * source of truth: owner/admin-only withdrawal with the 3-admin cap is
 * enforced on-ledger, not here. This service:
 *
 *  - registers deployed contract ids against product metadata (name, etc.),
 *    verifying via a real chain read that the caller IS the contract's owner
 *    before accepting the registration;
 *  - lists the caller's safeboxes with live on-chain state (owner, admins,
 *    closed, balance) re-read from the chain on every view;
 *  - exposes the contract's own contribution/withdrawal ledger for the
 *    shared member view (formerly an app-level Postgres table the backend
 *    could rewrite; now a chain ledger it cannot).
 *
 * Contributions and withdrawals THEMSELVES are on-chain invocations built
 * and signed by the user's app — the backend has no deposit endpoint and
 * no withdraw endpoint, by design.
 */
@Injectable()
export class SafeboxSorobanService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly stellar: StellarService,
    private readonly users: UsersService,
  ) {}

  /**
   * Registers a Safebox contract the user has deployed. VERIFIED: the
   * contract must exist on this network and its on-chain owner must be the
   * caller's registered public key. No trust is placed in the submitted
   * contract id beyond that.
   */
  async register(appUserId: string, dto: RegisterSafeboxDto) {
    const user = await this.users.findById(appUserId);
    if (!user.stellarPublicKey) {
      throw new BadRequestException('Register a Stellar public key before deploying/attaching Safeboxes.');
    }

    const onChainOwner = await this.stellar.safeboxOwner(dto.contractId).catch(() => null);
    if (!onChainOwner) {
      throw new BadRequestException(
        `No Safebox contract found at ${dto.contractId} on ${'this network'} — ` +
          'deploy backend/contracts/safebox first, or check the contract id / network.',
      );
    }
    if (onChainOwner !== user.stellarPublicKey) {
      throw new ForbiddenException('Only the Safebox contract\u2019s on-chain owner can register it.');
    }

    try {
      return await this.prisma.safeboxRegistry.create({
        data: {
          contractId: dto.contractId,
          ownerPublicKey: onChainOwner,
          name: dto.name,
          description: dto.description ?? '',
        },
      });
    } catch {
      const existing = await this.prisma.safeboxRegistry.findUnique({ where: { contractId: dto.contractId } });
      if (existing) return existing;
      throw new BadRequestException('Could not register this Safebox contract.');
    }
  }

  /** All Safeboxes this user owns, with state re-read from the chain. */
  async listForOwner(appUserId: string) {
    const user = await this.users.findById(appUserId);
    if (!user.stellarPublicKey) return [];

    const rows = await this.prisma.safeboxRegistry.findMany({
      where: { ownerPublicKey: user.stellarPublicKey },
      orderBy: { createdAt: 'desc' },
    });

    return Promise.all(
      rows.map(async (row) => ({
        ...row,
        chain: await this.chainState(row.contractId),
      })),
    );
  }

  /** Full detail for one Safebox: registry row + live chain state + ledger. */
  async getDetail(appUserId: string, contractId: string) {
    const user = await this.users.findById(appUserId);
    const row = await this.prisma.safeboxRegistry.findUnique({ where: { contractId } });
    if (!row) throw new NotFoundException(`No registered Safebox with contract id ${contractId}.`);

    // Membership check against the CHAIN, not the registry: admins and the
    // owner can always view; the ledger is also publicly readable by design,
    // so any member with the contract id can audit it.
    const chain = await this.chainState(contractId);
    const isOwner = chain.owner === user.stellarPublicKey;
    const isAdmin = chain.admins.includes(user.stellarPublicKey ?? '');
    if (!isOwner && !isAdmin) {
      // The ledger is public on-chain anyway; this gate only guards the
      // convenience endpoint, not the data.
      return { ...row, chain, note: 'You are not an admin of this Safebox; state shown is public chain state.' };
    }
    return { ...row, chain };
  }

  /** The shared ledger, read from the contract (indexer-visible to all members). */
  async getLedger(appUserId: string, contractId: string) {
    await this.users.findById(appUserId);
    const exists = await this.prisma.safeboxRegistry.findUnique({ where: { contractId }, select: { id: true } });
    if (!exists) throw new NotFoundException(`No registered Safebox with contract id ${contractId}.`);
    return this.stellar.safeboxLedger(contractId);
  }

  private async chainState(contractId: string) {
    const [owner, admins, closed, balance] = await Promise.all([
      this.stellar.safeboxOwner(contractId).catch(() => null),
      this.stellar.safeboxAdmins(contractId).catch(() => [] as string[]),
      this.stellar.safeboxClosed(contractId).catch(() => false),
      this.stellar.safeboxBalance(contractId).catch(() => null),
    ]);
    return { owner, admins, closed, balance: balance?.amount ?? null };
  }
}
