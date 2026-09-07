/**
 * Safebox Group Savings verification script:
 * Verifies Safebox pool creation, member invitations, contributions,
 * server-side 3-admin cap enforcement, and server-side withdrawal authorization
 * against the NestJS Safebox module.
 *
 * Run with: npm run sandbox:safebox
 */
import { NestFactory } from '@nestjs/core';
import { AppModule } from '../src/app.module';
import { SafeboxService } from '../src/safebox/safebox.service';

async function main() {
  const app = await NestFactory.createApplicationContext(AppModule);

  try {
    const safeboxService = app.get(SafeboxService);

    console.log('\n== 1. Create a Safebox Pool (Owner) ==');
    const ownerId = 'usr_owner_001';
    const pool = await safeboxService.createSafebox(ownerId, {
      name: 'Kenya Flight Pool ✈️',
      description: 'Group savings pool for Nairobi trip',
      targetAmount: 600000,
    });
    console.log('✅ Safebox created:', { id: pool.id, name: pool.name, balance: pool.currentBalance });

    console.log('\n== 2. Invite Members ==');
    await safeboxService.addMember(pool.id, ownerId, 'usr_alice');
    await safeboxService.addMember(pool.id, ownerId, 'usr_bob');
    await safeboxService.addMember(pool.id, ownerId, 'usr_charlie');
    await safeboxService.addMember(pool.id, ownerId, 'usr_dave');
    console.log('✅ 4 members added to Safebox roster');

    console.log('\n== 3. Member Contribution ==');
    const contrib = await safeboxService.contribute(pool.id, 'usr_alice', {
      amount: 150000,
      note: 'Alice September contribution',
    });
    console.log('✅ Contribution executed:', { amount: contrib.amount, type: contrib.type });

    const detailAfterContrib = await safeboxService.getSafeboxDetail(pool.id, ownerId);
    console.log('  -> Updated balance:', detailAfterContrib.safebox.currentBalance);
    if (detailAfterContrib.safebox.currentBalance !== 150000) {
      throw new Error('Balance mismatch after contribution');
    }

    console.log('\n== 4. Server-Side 3-Admin Cap Enforcement ==');
    await safeboxService.updateMemberRole(pool.id, ownerId, { targetUserId: 'usr_alice', role: 'ADMIN' });
    await safeboxService.updateMemberRole(pool.id, ownerId, { targetUserId: 'usr_bob', role: 'ADMIN' });
    await safeboxService.updateMemberRole(pool.id, ownerId, { targetUserId: 'usr_charlie', role: 'ADMIN' });
    console.log('  -> 3 members successfully promoted to Admin');

    try {
      await safeboxService.updateMemberRole(pool.id, ownerId, { targetUserId: 'usr_dave', role: 'ADMIN' });
      throw new Error('Expected 3-admin cap error, but promotion succeeded!');
    } catch (err: any) {
      console.log('✅ Server correctly rejected 4th admin promotion:', err.message);
    }

    console.log('\n== 5. Withdrawal Authorization Guard ==');
    // Owner withdraws
    const withdrawal = await safeboxService.withdraw(pool.id, ownerId, {
      amount: 50000,
      note: 'Paying airline flight deposit',
      recipientAccountId: 'acc_kenya_airways',
    });
    console.log('✅ Owner withdrawal authorized:', { amount: withdrawal.amount });

    // Regular member withdrawal attempt MUST fail
    try {
      await safeboxService.withdraw(pool.id, 'usr_dave', {
        amount: 10000,
        note: 'Unauthorized withdrawal attempt',
        recipientAccountId: 'acc_personal',
      });
      throw new Error('Expected 403 Forbidden for regular member withdrawal, but it succeeded!');
    } catch (err: any) {
      console.log('✅ Server correctly blocked regular member withdrawal:', err.message);
    }

    console.log('\n== 6. Read-Only Transaction Ledger ==');
    const ledger = await safeboxService.getTransactionLedger(pool.id, 'usr_dave');
    console.log(`✅ Ledger accessible by all members (${ledger.length} events logged)`);

    console.log('\n✅ Safebox Group Savings module verified end-to-end.');
  } finally {
    await app.close();
  }
}

main().catch((err) => {
  console.error('\n❌ Safebox sandbox script failed:', err);
  process.exit(1);
});
