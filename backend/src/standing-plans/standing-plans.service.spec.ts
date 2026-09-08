import { BadRequestException, NotFoundException } from '@nestjs/common';
import { StandingPlansService } from './standing-plans.service';
import { PrismaService } from '../prisma/prisma.service';
import { TransferService } from '../transfer/transfer.service';
import { PayTagService } from '../transfer/paytag.service';

describe('StandingPlansService', () => {
  function buildService(overrides?: {
    paymentFindUnique?: jest.Mock;
    createTransfer?: jest.Mock;
    payTagResolve?: jest.Mock;
    transaction?: jest.Mock;
  }) {
    const prisma = {
      standingPlan: { create: jest.fn(), findUnique: jest.fn(), update: jest.fn(), findMany: jest.fn() },
      standingPlanPayment: {
        findUnique: overrides?.paymentFindUnique ?? jest.fn(),
        update: jest.fn(),
        findMany: jest.fn(),
      },
      $transaction: overrides?.transaction ?? jest.fn().mockResolvedValue(undefined),
    } as unknown as PrismaService;
    const transfers = {
      createTransfer: overrides?.createTransfer ?? jest.fn(),
    } as unknown as TransferService;
    const payTags = {
      resolve: overrides?.payTagResolve ?? jest.fn(),
    } as unknown as PayTagService;
    return { service: new StandingPlansService(prisma, transfers, payTags), prisma, transfers, payTags };
  }

  describe('createPlan', () => {
    it('rejects a plan with neither a bmoniUserId nor a PayTag recipient', async () => {
      const { service } = buildService();

      await expect(
        service.createPlan('user-1', {
          name: 'Rent',
          currency: 'NGN',
          amount: '100.00',
          frequency: 'MONTHLY',
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  describe('pay', () => {
    it('rejects paying a payment that belongs to a different user', async () => {
      const { service } = buildService({
        paymentFindUnique: jest.fn().mockResolvedValue({
          id: 'payment-1',
          status: 'DUE',
          standingPlan: { appUserId: 'victim' },
        }),
      });

      await expect(service.pay('attacker', 'payment-1')).rejects.toBeInstanceOf(NotFoundException);
    });

    it('rejects paying a payment that no longer exists', async () => {
      const { service } = buildService({ paymentFindUnique: jest.fn().mockResolvedValue(null) });

      await expect(service.pay('user-1', 'nonexistent')).rejects.toBeInstanceOf(NotFoundException);
    });

    it('rejects paying an already-processed payment', async () => {
      const { service } = buildService({
        paymentFindUnique: jest.fn().mockResolvedValue({
          id: 'payment-1',
          status: 'PROPOSED',
          standingPlan: { appUserId: 'user-1' },
        }),
      });

      await expect(service.pay('user-1', 'payment-1')).rejects.toBeInstanceOf(BadRequestException);
    });

    it('resolves a PayTag recipient before creating the transfer', async () => {
      const createTransfer = jest.fn().mockResolvedValue({ id: 'proposal-1' });
      const payTagResolve = jest.fn().mockResolvedValue({ bmoniUserId: 'resolved-bmoni-id' });
      const { service } = buildService({
        paymentFindUnique: jest.fn().mockResolvedValue({
          id: 'payment-1',
          amount: '25.00',
          status: 'DUE',
          standingPlan: {
            id: 'plan-1',
            appUserId: 'user-1',
            name: 'Sister allowance',
            currency: 'NGN',
            toPayTag: 'sis',
            toBmoniUserId: null,
            totalPaid: '0',
          },
        }),
        createTransfer,
        payTagResolve,
      });

      const result = await service.pay('user-1', 'payment-1');

      expect(payTagResolve).toHaveBeenCalledWith('sis');
      expect(createTransfer).toHaveBeenCalledWith(
        'user-1',
        expect.objectContaining({ toBmoniUserId: 'resolved-bmoni-id', amount: '25.00', currency: 'NGN' }),
      );
      expect(result).toEqual({ id: 'proposal-1' });
    });

    it('uses the stored bmoniUserId directly when no PayTag is set', async () => {
      const createTransfer = jest.fn().mockResolvedValue({ id: 'proposal-2' });
      const payTagResolve = jest.fn();
      const { service } = buildService({
        paymentFindUnique: jest.fn().mockResolvedValue({
          id: 'payment-2',
          amount: '10.00',
          status: 'DUE',
          standingPlan: {
            id: 'plan-2',
            appUserId: 'user-1',
            name: 'Landlord',
            currency: 'NGN',
            toPayTag: null,
            toBmoniUserId: 'fixed-bmoni-id',
            totalPaid: '0',
          },
        }),
        createTransfer,
        payTagResolve,
      });

      await service.pay('user-1', 'payment-2');

      expect(payTagResolve).not.toHaveBeenCalled();
      expect(createTransfer).toHaveBeenCalledWith(
        'user-1',
        expect.objectContaining({ toBmoniUserId: 'fixed-bmoni-id' }),
      );
    });
  });
});
