import { NotFoundException } from '@nestjs/common';
import { LoansService } from './loans.service';
import { PrismaService } from '../prisma/prisma.service';
import { BmoniClientService } from '../bmoni/bmoni-client.service';
import { UsersService } from '../users/users.service';
import { TransferService } from '../transfer/transfer.service';
import { TreasuryService } from '../treasury/treasury.service';
import { CreditScoringStrategy } from './credit-scoring/credit-scoring-strategy.interface';

/**
 * Regression coverage for a real IDOR caught during the auth sweep:
 * GET /users/:id/loans/:loanId/repayments only checked the caller *was*
 * :id (via AuthGuard), never that :loanId actually belonged to them — a
 * user could read another user's loan repayments by pairing their own
 * :id with someone else's :loanId. AuthGuard can't catch this itself
 * since it only knows about the URL's first id-like param; the fix has
 * to live in the service.
 */
describe('LoansService ownership checks', () => {
  function buildService(overrides?: {
    loanApplicationFindUnique?: jest.Mock;
    loanRepaymentFindMany?: jest.Mock;
    loanRepaymentFindUnique?: jest.Mock;
  }) {
    const prisma = {
      loanApplication: {
        findUnique: overrides?.loanApplicationFindUnique ?? jest.fn(),
      },
      loanRepayment: {
        findMany: overrides?.loanRepaymentFindMany ?? jest.fn(),
        findUnique: overrides?.loanRepaymentFindUnique ?? jest.fn(),
      },
    } as unknown as PrismaService;
    const service = new LoansService(
      prisma,
      {} as BmoniClientService,
      {} as UsersService,
      {} as TransferService,
      {} as TreasuryService,
      {} as CreditScoringStrategy,
    );
    return { service, prisma };
  }

  describe('listRepayments', () => {
    it("returns repayments when the loan belongs to the requesting user", async () => {
      const loanRepaymentFindMany = jest.fn().mockResolvedValue([{ id: 'repayment-1' }]);
      const { service } = buildService({
        loanApplicationFindUnique: jest.fn().mockResolvedValue({ id: 'loan-1', appUserId: 'user-1' }),
        loanRepaymentFindMany,
      });

      const result = await service.listRepayments('user-1', 'loan-1');

      expect(result).toEqual([{ id: 'repayment-1' }]);
      expect(loanRepaymentFindMany).toHaveBeenCalledWith({ where: { loanApplicationId: 'loan-1' } });
    });

    it("rejects with 404 (not 200-with-someone-else's-data) when the loan belongs to a different user", async () => {
      const { service } = buildService({
        loanApplicationFindUnique: jest.fn().mockResolvedValue({ id: 'loan-1', appUserId: 'victim' }),
      });

      await expect(service.listRepayments('attacker', 'loan-1')).rejects.toBeInstanceOf(
        NotFoundException,
      );
    });

    it('rejects with 404 when the loan does not exist at all', async () => {
      const { service } = buildService({
        loanApplicationFindUnique: jest.fn().mockResolvedValue(null),
      });

      await expect(service.listRepayments('user-1', 'nonexistent')).rejects.toBeInstanceOf(
        NotFoundException,
      );
    });
  });

  describe('payRepayment', () => {
    it('rejects with 404 when the repayment belongs to a different user', async () => {
      const { service } = buildService({
        loanRepaymentFindUnique: jest.fn().mockResolvedValue({
          id: 'repayment-1',
          status: 'DUE',
          loanApplication: { appUserId: 'victim' },
        }),
      });

      await expect(service.payRepayment('attacker', 'repayment-1')).rejects.toBeInstanceOf(
        NotFoundException,
      );
    });

    it('rejects with 404 when the repayment does not exist at all', async () => {
      const { service } = buildService({
        loanRepaymentFindUnique: jest.fn().mockResolvedValue(null),
      });

      await expect(service.payRepayment('user-1', 'nonexistent')).rejects.toBeInstanceOf(
        NotFoundException,
      );
    });
  });
});
