import { BadRequestException, ForbiddenException, NotFoundException } from '@nestjs/common';
import { SafeboxService } from './safebox.service';
import { PrismaService } from '../prisma/prisma.service';
import { TransferService } from '../transfer/transfer.service';
import { TreasuryService } from '../treasury/treasury.service';

/**
 * Focused on the server-side permission rules this feature exists to
 * enforce — a prior version of this controller trusted a client-supplied
 * header for identity, which would make every one of these checks
 * meaningless regardless of how well they read. See
 * safebox.controller.ts's doc comment: identity here always comes from
 * AuthGuard's verified `request.user`, never client input.
 */
describe('SafeboxService', () => {
  function buildService(overrides?: {
    safeboxFindUnique?: jest.Mock;
    safeboxMemberFindUnique?: jest.Mock;
    transaction?: jest.Mock;
    createTransfer?: jest.Mock;
  }) {
    const prisma = {
      safebox: {
        create: jest.fn(),
        findUnique: overrides?.safeboxFindUnique ?? jest.fn(),
        update: jest.fn(),
      },
      safeboxMember: {
        findUnique: overrides?.safeboxMemberFindUnique ?? jest.fn(),
        create: jest.fn(),
        update: jest.fn(),
      },
      safeboxTransaction: { create: jest.fn(), findMany: jest.fn() },
      $transaction: overrides?.transaction ?? jest.fn().mockResolvedValue([{}]),
    } as unknown as PrismaService;
    const transfers = {
      createTransfer: overrides?.createTransfer ?? jest.fn(),
      getSignPayload: jest.fn().mockResolvedValue({ signingPayloadHash: '0xhash' }),
      submitSignature: jest.fn(),
    } as unknown as TransferService;
    const treasury = {
      getAppUserId: jest.fn().mockResolvedValue('treasury-user'),
      getWalletId: jest.fn().mockResolvedValue('treasury-wallet'),
      getBmoniUserId: jest.fn().mockReturnValue('treasury-bmoni'),
      signDigest: jest.fn().mockReturnValue('0xsig'),
    } as unknown as TreasuryService;
    return { service: new SafeboxService(prisma, transfers, treasury), prisma, transfers, treasury };
  }

  function safeboxWith(members: { userId: string; role: string }[], currentBalance = 0) {
    return {
      id: 'sb-1',
      name: 'Pool',
      description: 'desc',
      ownerId: members.find((m) => m.role === 'OWNER')?.userId ?? members[0].userId,
      targetAmount: null,
      currentBalance,
      status: 'ACTIVE',
      createdAt: new Date(),
      members: members.map((m) => ({ safeboxId: 'sb-1', joinedAt: new Date(), ...m })),
    };
  }

  describe('getSafeboxDetail', () => {
    it('rejects a non-member trying to view the safebox', async () => {
      const { service } = buildService({
        safeboxFindUnique: jest.fn().mockResolvedValue(safeboxWith([{ userId: 'owner-1', role: 'OWNER' }])),
      });

      await expect(service.getSafeboxDetail('sb-1', 'outsider')).rejects.toBeInstanceOf(ForbiddenException);
    });

    it('rejects viewing a safebox that does not exist', async () => {
      const { service } = buildService({ safeboxFindUnique: jest.fn().mockResolvedValue(null) });

      await expect(service.getSafeboxDetail('nonexistent', 'user-1')).rejects.toBeInstanceOf(NotFoundException);
    });
  });

  describe('withdraw', () => {
    it('rejects a regular member (only owner/admin may withdraw)', async () => {
      const { service } = buildService({
        safeboxFindUnique: jest.fn().mockResolvedValue(
          safeboxWith([{ userId: 'owner-1', role: 'OWNER' }, { userId: 'member-1', role: 'MEMBER' }], 1000),
        ),
      });

      await expect(
        service.withdraw('sb-1', 'member-1', { amount: 100, note: 'n', recipientAccountId: 'acc' }),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });

    it('rejects a withdrawal larger than the current balance', async () => {
      const { service } = buildService({
        safeboxFindUnique: jest.fn().mockResolvedValue(
          safeboxWith([{ userId: 'owner-1', role: 'OWNER' }], 50),
        ),
      });

      await expect(
        service.withdraw('sb-1', 'owner-1', { amount: 100, note: 'n', recipientAccountId: 'acc' }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('allows an admin to withdraw within balance, via a treasury-signed transfer', async () => {
      const createTransfer = jest.fn().mockResolvedValue({ id: 'proposal-1' });
      const { service, transfers } = buildService({
        safeboxFindUnique: jest.fn().mockResolvedValue(
          safeboxWith([{ userId: 'owner-1', role: 'OWNER' }, { userId: 'admin-1', role: 'ADMIN' }], 500),
        ),
        createTransfer,
        transaction: jest.fn().mockResolvedValue([{ id: 'tx-1', type: 'WITHDRAWAL', amount: 100 }]),
      });

      const result = await service.withdraw('sb-1', 'admin-1', {
        amount: 100,
        note: 'approved expense',
        recipientAccountId: 'recipient-bmoni-id',
      });

      expect(result.proposalId).toBe('proposal-1');
      expect(createTransfer).toHaveBeenCalledWith(
        'treasury-user',
        expect.objectContaining({ toBmoniUserId: 'recipient-bmoni-id', amount: '100.00' }),
      );
      expect(transfers.submitSignature).toHaveBeenCalledWith('treasury-user', 'proposal-1', '0xsig');
    });
  });

  describe('updateMemberRole (3-admin cap)', () => {
    it('rejects promoting a 4th admin', async () => {
      const { service } = buildService({
        safeboxFindUnique: jest.fn().mockResolvedValue(
          safeboxWith([
            { userId: 'owner-1', role: 'OWNER' },
            { userId: 'admin-1', role: 'ADMIN' },
            { userId: 'admin-2', role: 'ADMIN' },
            { userId: 'admin-3', role: 'ADMIN' },
            { userId: 'member-1', role: 'MEMBER' },
          ]),
        ),
      });
      expect(SafeboxService.MAX_ADMIN_CAP).toBe(3);

      await expect(
        service.updateMemberRole('sb-1', 'owner-1', { targetUserId: 'member-1', role: 'ADMIN' }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('rejects a non-owner trying to change roles', async () => {
      const { service } = buildService({
        safeboxFindUnique: jest.fn().mockResolvedValue(
          safeboxWith([{ userId: 'owner-1', role: 'OWNER' }, { userId: 'admin-1', role: 'ADMIN' }, { userId: 'member-1', role: 'MEMBER' }]),
        ),
      });

      await expect(
        service.updateMemberRole('sb-1', 'admin-1', { targetUserId: 'member-1', role: 'ADMIN' }),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });

    it('rejects trying to change the owner role directly', async () => {
      const { service } = buildService({
        safeboxFindUnique: jest.fn().mockResolvedValue(safeboxWith([{ userId: 'owner-1', role: 'OWNER' }])),
      });

      await expect(
        service.updateMemberRole('sb-1', 'owner-1', { targetUserId: 'owner-1', role: 'MEMBER' }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  describe('ownership transfer', () => {
    it('rejects a wrong confirmation code, and succeeds with the right one', async () => {
      const { service } = buildService({
        safeboxFindUnique: jest.fn().mockResolvedValue(
          safeboxWith([{ userId: 'owner-1', role: 'OWNER' }, { userId: 'new-owner', role: 'MEMBER' }]),
        ),
      });

      const { transferId } = await service.initiateOwnershipTransfer('sb-1', 'owner-1', {
        newOwnerUserId: 'new-owner',
      });
      expect(transferId).toBe('sb-1');

      await expect(
        service.confirmOwnershipTransfer('sb-1', 'new-owner', '000000'),
      ).rejects.toBeInstanceOf(BadRequestException);

      const code = (service as unknown as { pendingTransfers: Map<string, { code: string }> })
        .pendingTransfers.get('sb-1')!.code;
      const result = await service.confirmOwnershipTransfer('sb-1', 'new-owner', code);
      expect(result.success).toBe(true);
    });

    it('rejects a non-owner trying to initiate a transfer', async () => {
      const { service } = buildService({
        safeboxFindUnique: jest.fn().mockResolvedValue(
          safeboxWith([{ userId: 'owner-1', role: 'OWNER' }, { userId: 'member-1', role: 'MEMBER' }]),
        ),
      });

      await expect(
        service.initiateOwnershipTransfer('sb-1', 'member-1', { newOwnerUserId: 'owner-1' }),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });
  });
});
