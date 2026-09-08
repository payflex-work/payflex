/**
 * Safebox (group savings) verification harness: create a pool, add
 * members, contribute (member signs, same as SavingsGoal), enforce the
 * 3-admin cap and owner/admin-only withdrawal server-side, withdraw
 * (treasury signs, same as loan disbursement), and run the 2-step
 * ownership-transfer flow — end to end against the live BMONI sandbox,
 * using the real SafeboxService.
 *
 * Same simulated-signer caveat as every other sandbox script (ethers.Wallet
 * standing in for bmoni_embedded_sdk) for member-side signing; withdrawal
 * is treasury-signed server-side, same as loan disbursement.
 *
 * Run with: npm run sandbox:safebox (requires PAYFLEX_TREASURY_* in .env
 * — run `npm run provision:treasury` first if you haven't).
 */
import { NestFactory } from '@nestjs/core';
import { SigningKey, Wallet } from 'ethers';
import { AppModule } from '../src/app.module';
import { UsersService } from '../src/users/users.service';
import { OnboardingService } from '../src/onboarding/onboarding.service';
import { TransferService } from '../src/transfer/transfer.service';
import { SafeboxService } from '../src/safebox/safebox.service';
import { BmoniApiError } from '../src/bmoni/bmoni.errors';

function signRawDigest(privateKey: string, digestHex: string): string {
  return new SigningKey(privateKey).sign(digestHex).serialized;
}

async function waitForSignPayload(transfers: TransferService, appUserId: string, proposalId: string) {
  for (let attempt = 0; attempt < 10; attempt++) {
    try {
      return await transfers.getSignPayload(appUserId, proposalId);
    } catch (err) {
      if (err instanceof BmoniApiError && err.status === 409 && attempt < 9) {
        await new Promise((r) => setTimeout(r, 1500));
        continue;
      }
      throw err;
    }
  }
  throw new Error('sign-payload never became ready');
}

async function provisionNgnWallet(users: UsersService, onboarding: OnboardingService, label: string) {
  const appUser = await users.getOrCreate({
    firstName: 'Safebox',
    lastName: label,
    email: `payflex.safebox.${label}.${Date.now()}@payflex.test`,
    phoneNumber: `+2347${String(Date.now()).slice(-8)}${Math.floor(Math.random() * 10)}`,
  });
  const ownerWallet = Wallet.createRandom();
  await users.setOwnerAddress(appUser.id, ownerWallet.address);
  const challenge = await onboarding.requestOwnerProofChallenge(appUser.id, 'CNGN');
  const signature = await ownerWallet.signMessage(challenge.message);
  await onboarding.createSmartWallet(appUser.id, {
    currency: 'CNGN',
    ownerProofChallengeId: challenge.challengeId,
    ownerProofSignature: signature,
  });
  return { appUser, ownerWallet };
}

async function main() {
  const app = await NestFactory.createApplicationContext(AppModule);

  try {
    const users = app.get(UsersService);
    const onboarding = app.get(OnboardingService);
    const transfers = app.get(TransferService);
    const safebox = app.get(SafeboxService);

    console.log('\n== 1. Provision owner, an admin-to-be, and a regular member ==');
    const owner = await provisionNgnWallet(users, onboarding, 'owner');
    const admin = await provisionNgnWallet(users, onboarding, 'admin');
    const member = await provisionNgnWallet(users, onboarding, 'member');
    console.log('owner:', owner.appUser.id, 'admin:', admin.appUser.id, 'member:', member.appUser.id);

    console.log('\n== 2. Create a safebox (owner) ==');
    const pool = await safebox.createSafebox(owner.appUser.id, {
      name: 'Rent Pool',
      description: 'Shared rent fund',
      targetAmount: 5000,
    });
    console.log('safebox:', { id: pool.id, name: pool.name });

    console.log('\n== 3. Add the other two as members ==');
    await safebox.addMember(pool.id, owner.appUser.id, admin.appUser.id);
    await safebox.addMember(pool.id, owner.appUser.id, member.appUser.id);
    const detail1 = await safebox.getSafeboxDetail(pool.id, owner.appUser.id);
    console.log(`members now: ${detail1.members.length}`);
    if (detail1.members.length !== 3) throw new Error(`Expected 3 members, got ${detail1.members.length}`);

    console.log('\n== 4. Member contributes (real signed transfer, member -> treasury) ==');
    const contribResult = await safebox.contribute(pool.id, member.appUser.id, {
      amount: 500,
      note: 'first contribution',
    });
    const contribSignPayload = await waitForSignPayload(transfers, member.appUser.id, contribResult.proposalId);
    const contribSignature = signRawDigest(member.ownerWallet.privateKey, contribSignPayload.signingPayloadHash);
    await transfers.submitSignature(member.appUser.id, contribResult.proposalId, contribSignature);
    const afterContribution = await safebox.getSafeboxDetail(pool.id, owner.appUser.id);
    console.log('balance after contribution:', afterContribution.safebox.currentBalance);
    if (afterContribution.safebox.currentBalance !== 500) {
      throw new Error(`Expected balance 500, got ${afterContribution.safebox.currentBalance}`);
    }

    console.log('\n== 5. Regular member CANNOT withdraw (expect 403) ==');
    try {
      await safebox.withdraw(pool.id, member.appUser.id, {
        amount: 100,
        note: 'unauthorized attempt',
        recipientAccountId: member.appUser.bmoniUserId,
      });
      throw new Error('Expected withdraw() to reject a regular member — it did not.');
    } catch (err) {
      if (!(err instanceof Error) || !err.message.includes('Owner and designated Admins')) throw err;
      console.log('correctly rejected:', (err as Error).message);
    }

    console.log('\n== 6. Promote member -> admin (owner-only) ==');
    await safebox.updateMemberRole(pool.id, owner.appUser.id, { targetUserId: admin.appUser.id, role: 'ADMIN' });
    const detail2 = await safebox.getSafeboxDetail(pool.id, owner.appUser.id);
    const adminRole = detail2.members.find((m) => m.userId === admin.appUser.id)?.role;
    console.log('promoted role:', adminRole);
    if (adminRole !== 'ADMIN') throw new Error(`Expected ADMIN, got ${adminRole}`);

    console.log('\n== 7. 3-admin cap enforced (promote 3 more, then a 4th should fail) ==');
    const extraMembers = await Promise.all(
      ['extra1', 'extra2', 'extra3'].map((label) => provisionNgnWallet(users, onboarding, label)),
    );
    for (const extra of extraMembers) {
      await safebox.addMember(pool.id, owner.appUser.id, extra.appUser.id);
    }
    await safebox.updateMemberRole(pool.id, owner.appUser.id, { targetUserId: extraMembers[0].appUser.id, role: 'ADMIN' });
    await safebox.updateMemberRole(pool.id, owner.appUser.id, { targetUserId: extraMembers[1].appUser.id, role: 'ADMIN' });
    try {
      await safebox.updateMemberRole(pool.id, owner.appUser.id, { targetUserId: extraMembers[2].appUser.id, role: 'ADMIN' });
      throw new Error('Expected the 4th admin promotion to be rejected — it was not.');
    } catch (err) {
      if (!(err instanceof Error) || !err.message.includes('Admin Limit Exceeded')) throw err;
      console.log('correctly rejected 4th admin:', (err as Error).message);
    }

    console.log('\n== 8. Admin withdraws (treasury signs the release server-side) ==');
    const withdrawResult = await safebox.withdraw(pool.id, admin.appUser.id, {
      amount: 200,
      note: 'approved group expense',
      recipientAccountId: admin.appUser.bmoniUserId,
    });
    console.log('withdrawal proposal:', withdrawResult.proposalId);
    const afterWithdrawal = await safebox.getSafeboxDetail(pool.id, owner.appUser.id);
    console.log('balance after withdrawal:', afterWithdrawal.safebox.currentBalance);
    if (afterWithdrawal.safebox.currentBalance !== 300) {
      throw new Error(`Expected balance 300, got ${afterWithdrawal.safebox.currentBalance}`);
    }

    console.log('\n== 9. Ownership transfer: initiate, wrong code rejected, correct code succeeds ==');
    const initiated = await safebox.initiateOwnershipTransfer(pool.id, owner.appUser.id, {
      newOwnerUserId: member.appUser.id,
    });
    try {
      await safebox.confirmOwnershipTransfer(initiated.transferId, member.appUser.id, '000000');
      throw new Error('Expected a wrong confirmation code to be rejected — it was not.');
    } catch (err) {
      if (!(err instanceof Error) || !err.message.includes('Invalid confirmation code')) throw err;
      console.log('correctly rejected wrong code (transfer must be re-initiated after this)');
    }
    const reinitiated = await safebox.initiateOwnershipTransfer(pool.id, owner.appUser.id, {
      newOwnerUserId: member.appUser.id,
    });
    const code = (
      safebox as unknown as { pendingTransfers: Map<string, { code: string }> }
    ).pendingTransfers.get(reinitiated.transferId)!.code;
    await safebox.confirmOwnershipTransfer(reinitiated.transferId, member.appUser.id, code);
    const detail3 = await safebox.getSafeboxDetail(pool.id, member.appUser.id);
    console.log(
      'new owner:', detail3.safebox.ownerId,
      'former owner role:', detail3.members.find((m) => m.userId === owner.appUser.id)?.role,
    );
    if (detail3.safebox.ownerId !== member.appUser.id) {
      throw new Error('Ownership transfer did not take effect.');
    }

    console.log('\n== 10. Ledger is readable by any member ==');
    const ledger = await safebox.getTransactionLedger(pool.id, admin.appUser.id);
    console.log(`ledger has ${ledger.length} entries`);
    if (ledger.length !== 2) throw new Error(`Expected 2 ledger entries, got ${ledger.length}`);

    console.log('\n✅ Safebox group savings verified end-to-end against the live sandbox.');
  } finally {
    await app.close();
  }
}

main().catch((err) => {
  console.error('\n❌ Safebox sandbox script failed:', err);
  process.exit(1);
});
