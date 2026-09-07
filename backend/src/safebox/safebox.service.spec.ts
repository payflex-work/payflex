import {
  SafeboxService,
} from './safebox.service';
import {
  ForbiddenException,
  BadRequestException,
} from '@nestjs/common';

describe('SafeboxService', () => {
  let service: SafeboxService;

  beforeEach(() => {
    service = new SafeboxService();
  });

  describe('createSafebox', () => {
    it('should initialize a new safebox with owner role', async () => {
      const box = await service.createSafebox('owner_1', {
        name: 'Kenya Trip 2026',
        description: 'Flight pool',
        targetAmount: 500000,
      });

      expect(box.id).toBeDefined();
      expect(box.name).toBe('Kenya Trip 2026');
      expect(box.ownerId).toBe('owner_1');
      expect(box.currentBalance).toBe(0);

      const detail = await service.getSafeboxDetail(box.id, 'owner_1');
      expect(detail.role).toBe('OWNER');
      expect(detail.members).toHaveLength(1);
    });
  });

  describe('contribute', () => {
    it('should allow any member to contribute to the pool balance', async () => {
      const box = await service.createSafebox('owner_1', {
        name: 'Rent Pool',
        description: 'Monthly rent',
      });

      await service.addMember(box.id, 'owner_1', 'member_1');

      const tx = await service.contribute(box.id, 'member_1', {
        amount: 25000,
        note: 'September contribution',
      });

      expect(tx.type).toBe('CONTRIBUTION');
      expect(tx.amount).toBe(25000);

      const detail = await service.getSafeboxDetail(box.id, 'member_1');
      expect(detail.safebox.currentBalance).toBe(25000);
    });
  });

  describe('withdraw permissions & enforcement', () => {
    it('should allow owner and designated admins to withdraw funds', async () => {
      const box = await service.createSafebox('owner_1', {
        name: 'Rent Pool',
        description: 'Monthly rent',
      });

      await service.contribute(box.id, 'owner_1', { amount: 50000 });

      // Owner withdraws
      const tx = await service.withdraw(box.id, 'owner_1', {
        amount: 10000,
        note: 'Paying landlord deposit',
        recipientAccountId: 'acc_landlord',
      });

      expect(tx.type).toBe('WITHDRAWAL');
      expect(tx.amount).toBe(10000);

      const detail = await service.getSafeboxDetail(box.id, 'owner_1');
      expect(detail.safebox.currentBalance).toBe(40000);
    });

    it('should REJECT withdrawal attempts by regular members with 403 Forbidden', async () => {
      const box = await service.createSafebox('owner_1', {
        name: 'Rent Pool',
        description: 'Monthly rent',
      });

      await service.addMember(box.id, 'owner_1', 'regular_member');
      await service.contribute(box.id, 'owner_1', { amount: 50000 });

      await expect(
        service.withdraw(box.id, 'regular_member', {
          amount: 5000,
          note: 'Unauthorized attempt',
          recipientAccountId: 'acc_hacker',
        }),
      ).rejects.toThrow(ForbiddenException);
    });
  });

  describe('3-Admin Cap Enforcement', () => {
    it('should enforce maximum 3 designated admins limit per Safebox', async () => {
      const box = await service.createSafebox('owner_1', {
        name: 'Group Savings',
        description: 'Cap test',
      });

      // Add 4 members
      await service.addMember(box.id, 'owner_1', 'user_a');
      await service.addMember(box.id, 'owner_1', 'user_b');
      await service.addMember(box.id, 'owner_1', 'user_c');
      await service.addMember(box.id, 'owner_1', 'user_d');

      // Promote first 3 members to Admin
      await service.updateMemberRole(box.id, 'owner_1', { targetUserId: 'user_a', role: 'ADMIN' });
      await service.updateMemberRole(box.id, 'owner_1', { targetUserId: 'user_b', role: 'ADMIN' });
      await service.updateMemberRole(box.id, 'owner_1', { targetUserId: 'user_c', role: 'ADMIN' });

      // Attempt to promote 4th member to Admin -> MUST throw BadRequestException
      await expect(
        service.updateMemberRole(box.id, 'owner_1', { targetUserId: 'user_d', role: 'ADMIN' }),
      ).rejects.toThrow(BadRequestException);
    });
  });

  describe('Ownership Transfer', () => {
    it('should execute deliberate 2-step ownership transfer', async () => {
      const box = await service.createSafebox('owner_1', {
        name: 'Ownership Pool',
        description: 'Transfer test',
      });

      await service.addMember(box.id, 'owner_1', 'new_owner');

      const transfer = await service.initiateOwnershipTransfer(box.id, 'owner_1', {
        newOwnerUserId: 'new_owner',
      });

      expect(transfer.transferId).toBeDefined();

      const code = (service as any).pendingTransfers.get(transfer.transferId).code;

      const confirm = await service.confirmOwnershipTransfer(transfer.transferId, 'new_owner', code);
      expect(confirm.success).toBe(true);

      const detail = await service.getSafeboxDetail(box.id, 'new_owner');
      expect(detail.safebox.ownerId).toBe('new_owner');
      expect(detail.role).toBe('OWNER');
    });
  });
});
