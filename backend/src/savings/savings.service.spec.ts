import { BadRequestException, NotFoundException } from '@nestjs/common';
import { SavingsService } from './savings.service';
import { PrismaService } from '../prisma/prisma.service';
import { TransferService } from '../transfer/transfer.service';
import { TreasuryService } from '../treasury/treasury.service';

describe('SavingsService', () => {
  function buildService(overrides?: {
    contributionFindUnique?: jest.Mock;
    goalFindMany?: jest.Mock;
    createTransfer?: jest.Mock;
    getWalletId?: jest.Mock;
    getBmoniUserId?: jest.Mock;
    transaction?: jest.Mock;
  }) {
    const prisma = {
      savingsGoal: {
        create: jest.fn(),
        findMany: overrides?.goalFindMany ?? jest.fn().mockResolvedValue([]),
        update: jest.fn(),
      },
      savingsContribution: {
        findUnique: overrides?.contributionFindUnique ?? jest.fn(),
        create: jest.fn(),
        update: jest.fn(),
        findMany: jest.fn(),
      },
      $transaction: overrides?.transaction ?? jest.fn().mockResolvedValue(undefined),
    } as unknown as PrismaService;
    const transfers = {
      createTransfer: overrides?.createTransfer ?? jest.fn(),
    } as unknown as TransferService;
    const treasury = {
      getWalletId: overrides?.getWalletId ?? jest.fn().mockResolvedValue('treasury-wallet-1'),
      getBmoniUserId: overrides?.getBmoniUserId ?? jest.fn().mockReturnValue('treasury-bmoni-id'),
    } as unknown as TreasuryService;
    return { service: new SavingsService(prisma, transfers, treasury), prisma, transfers, treasury };
  }

  describe('createGoal', () => {
    it.each([
      ['DAILY', 24 * 60 * 60 * 1000],
      ['WEEKLY', 7 * 24 * 60 * 60 * 1000],
      ['MONTHLY', 30 * 24 * 60 * 60 * 1000],
    ] as const)('schedules the first contribution one %s period out', async (frequency, expectedMs) => {
      const { service, prisma } = buildService();
      const before = Date.now();

      await service.createGoal('user-1', {
        name: 'Rent deposit',
        currency: 'NGN',
        targetAmount: '1000.00',
        contributionAmount: '100.00',
        frequency,
      });

      const createCall = (prisma.savingsGoal.create as jest.Mock).mock.calls[0][0];
      const scheduledMs = (createCall.data.nextContributionAt as Date).getTime();
      expect(scheduledMs).toBeGreaterThanOrEqual(before + expectedMs);
      expect(scheduledMs).toBeLessThan(before + expectedMs + 5000); // generous slack for test runtime
    });
  });

  describe('runDueCheck', () => {
    it('creates a DUE contribution and advances nextContributionAt for each due ACTIVE goal', async () => {
      const dueGoal = {
        id: 'goal-1',
        status: 'ACTIVE',
        contributionAmount: '50.00',
        frequency: 'WEEKLY',
        nextContributionAt: new Date(Date.now() - 1000),
      };
      const transaction = jest.fn().mockResolvedValue(undefined);
      const { service, prisma } = buildService({
        goalFindMany: jest.fn().mockResolvedValue([dueGoal]),
        transaction,
      });

      const result = await service.runDueCheck();

      expect(result).toEqual({ goalsChecked: 1, contributionsCreated: 1 });
      expect(transaction).toHaveBeenCalledTimes(1);
      expect(prisma.savingsContribution.create).toHaveBeenCalledWith(
        expect.objectContaining({ data: expect.objectContaining({ savingsGoalId: 'goal-1', amount: '50.00' }) }),
      );
      expect(prisma.savingsGoal.update).toHaveBeenCalledWith(
        expect.objectContaining({ where: { id: 'goal-1' } }),
      );
    });

    it('touches nothing when no goal is due', async () => {
      const transaction = jest.fn();
      const { service } = buildService({ goalFindMany: jest.fn().mockResolvedValue([]), transaction });

      const result = await service.runDueCheck();

      expect(result).toEqual({ goalsChecked: 0, contributionsCreated: 0 });
      expect(transaction).not.toHaveBeenCalled();
    });
  });

  describe('contribute', () => {
    it('rejects a contribution that belongs to a different user', async () => {
      const { service } = buildService({
        contributionFindUnique: jest.fn().mockResolvedValue({
          id: 'contribution-1',
          status: 'DUE',
          savingsGoal: { appUserId: 'victim' },
        }),
      });

      await expect(service.contribute('attacker', 'contribution-1')).rejects.toBeInstanceOf(NotFoundException);
    });

    it('rejects a contribution that no longer exists', async () => {
      const { service } = buildService({ contributionFindUnique: jest.fn().mockResolvedValue(null) });

      await expect(service.contribute('user-1', 'nonexistent')).rejects.toBeInstanceOf(NotFoundException);
    });

    it('rejects an already-processed contribution', async () => {
      const { service } = buildService({
        contributionFindUnique: jest.fn().mockResolvedValue({
          id: 'contribution-1',
          status: 'PROPOSED',
          savingsGoal: { appUserId: 'user-1' },
        }),
      });

      await expect(service.contribute('user-1', 'contribution-1')).rejects.toBeInstanceOf(BadRequestException);
    });

    it('fails fast when the treasury has no wallet in the goal currency, before calling BMONI', async () => {
      const createTransfer = jest.fn();
      const getWalletId = jest.fn().mockRejectedValue(new Error('PayFlex treasury has no EUR smart wallet'));
      const { service } = buildService({
        contributionFindUnique: jest.fn().mockResolvedValue({
          id: 'contribution-1',
          amount: '50.00',
          status: 'DUE',
          savingsGoal: { appUserId: 'user-1', currency: 'EUR', name: 'Trip' },
        }),
        createTransfer,
        getWalletId,
      });

      await expect(service.contribute('user-1', 'contribution-1')).rejects.toThrow(
        'PayFlex treasury has no EUR smart wallet',
      );
      expect(createTransfer).not.toHaveBeenCalled();
    });

    it('creates a transfer to the treasury and marks the contribution PROPOSED', async () => {
      const createTransfer = jest.fn().mockResolvedValue({ id: 'proposal-1' });
      const { service, prisma } = buildService({
        contributionFindUnique: jest.fn().mockResolvedValue({
          id: 'contribution-1',
          amount: '50.00',
          status: 'DUE',
          savingsGoal: { appUserId: 'user-1', currency: 'NGN', name: 'Rent deposit' },
        }),
        createTransfer,
      });

      const result = await service.contribute('user-1', 'contribution-1');

      expect(createTransfer).toHaveBeenCalledWith(
        'user-1',
        expect.objectContaining({
          toBmoniUserId: 'treasury-bmoni-id',
          amount: '50.00',
          currency: 'NGN',
          description: expect.stringContaining('Rent deposit'),
        }),
      );
      expect(prisma.savingsContribution.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: 'contribution-1' },
          data: { status: 'PROPOSED', bmoniProposalId: 'proposal-1' },
        }),
      );
      expect(result).toEqual({ id: 'proposal-1' });
    });
  });
});
