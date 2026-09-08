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
import { RedisService } from '../src/redis/redis.service';
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
  const smartWallet = await onboarding.createSmartWallet(appUser.id, {
    currency: 'CNGN',
    ownerProofChallengeId: challenge.challengeId,
    ownerProofSignature: signature,
  });
  return { appUser, ownerWallet, smartWallet };
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
    const created = await safebox.createSafebox(owner.appUser.id, {
      name: 'Rent Pool',
      description: 'Shared rent fund',
      currency: 'NGN',
      targetAmount: '5000.00',
    });
    console.log('safebox:', { id: created.id, name: created.name, members: created.members.length });

    console.log('\n== 3. Add the other two as members ==');
    await safebox.addMember(owner.appUser.id, created.id, admin.appUser.id);
    await safebox.addMember(owner.appUser.id, created.id, member.appUser.id);
    const detail1 = await safebox.getDetail(owner.appUser.id, created.id);
    console.log(`members now: ${detail1.members.length}`);
    if (detail1.members.length !== 3) throw new Error(`Expected 3 members, got ${detail1.members.length}`);

    console.log('\n== 4. Member contributes (real signed transfer, member -> treasury) ==');
    const contribProposal = await safebox.contribute(member.appUser.id, created.id, {
      amount: '500.00',
      note: 'first contribution',
    });
    const contribSignPayload = await waitForSignPayload(transfers, member.appUser.id, contribProposal.id);
    const contribSignature = signRawDigest(member.ownerWallet.privateKey, contribSignPayload.signingPayloadHash);
    await transfers.submitSignature(member.appUser.id, contribProposal.id, contribSignature);
    const afterContribution = await safebox.getDetail(owner.appUser.id, created.id);
    console.log('balance after contribution:', afterContribution.safebox.currentBalance);
    if (afterContribution.safebox.currentBalance !== '500.00') {
      throw new Error(`Expected balance 500.00, got ${afterContribution.safebox.currentBalance}`);
    }

    console.log('\n== 5. Regular member CANNOT withdraw (expect 403) ==');
    try {
      await safebox.withdraw(member.appUser.id, created.id, {
        amount: '100.00',
        toBmoniUserId: member.appUser.bmoniUserId,
        note: 'unauthorized attempt',
      });
      throw new Error('Expected withdraw() to reject a regular member — it did not.');
    } catch (err) {
      if (!(err instanceof Error) || !err.message.includes('owner and admins')) throw err;
      console.log('correctly rejected:', (err as Error).message);
    }

    console.log('\n== 6. Promote member -> admin (owner-only) ==');
    await safebox.updateMemberRole(owner.appUser.id, created.id, {
      targetAppUserId: admin.appUser.id,
      role: 'ADMIN',
    });
    const detail2 = await safebox.getDetail(owner.appUser.id, created.id);
    const adminRole = detail2.members.find((m) => m.appUserId === admin.appUser.id)?.role;
    console.log('promoted role:', adminRole);
    if (adminRole !== 'ADMIN') throw new Error(`Expected ADMIN, got ${adminRole}`);

    console.log('\n== 7. 3-admin cap enforced (promote 3 more, then a 4th should fail) ==');
    const extraMembers = await Promise.all(
      ['extra1', 'extra2', 'extra3'].map((label) => provisionNgnWallet(users, onboarding, label)),
    );
    for (const extra of extraMembers) {
      await safebox.addMember(owner.appUser.id, created.id, extra.appUser.id);
    }
    // admin.appUser is already an admin (1); promote two of the three extras to reach the cap of 3.
    await safebox.updateMemberRole(owner.appUser.id, created.id, {
      targetAppUserId: extraMembers[0].appUser.id,
      role: 'ADMIN',
    });
    await safebox.updateMemberRole(owner.appUser.id, created.id, {
      targetAppUserId: extraMembers[1].appUser.id,
      role: 'ADMIN',
    });
    try {
      await safebox.updateMemberRole(owner.appUser.id, created.id, {
        targetAppUserId: extraMembers[2].appUser.id,
        role: 'ADMIN',
      });
      throw new Error('Expected the 4th admin promotion to be rejected — it was not.');
    } catch (err) {
      if (!(err instanceof Error) || !err.message.includes('at most')) throw err;
      console.log('correctly rejected 4th admin:', (err as Error).message);
    }

    console.log('\n== 8. Admin withdraws (treasury signs the release server-side) ==');
    const withdrawProposal = await safebox.withdraw(admin.appUser.id, created.id, {
      amount: '200.00',
      toBmoniUserId: admin.appUser.bmoniUserId,
      note: 'approved group expense',
    });
    console.log('withdrawal proposal:', withdrawProposal.id);
    const afterWithdrawal = await safebox.getDetail(owner.appUser.id, created.id);
    console.log('balance after withdrawal:', afterWithdrawal.safebox.currentBalance);
    if (afterWithdrawal.safebox.currentBalance !== '300.00') {
      throw new Error(`Expected balance 300.00, got ${afterWithdrawal.safebox.currentBalance}`);
    }

    console.log('\n== 9. Ownership transfer: initiate, wrong code rejected, correct code succeeds ==');
    await safebox.initiateOwnershipTransfer(owner.appUser.id, created.id, {
      newOwnerAppUserId: member.appUser.id,
    });
    try {
      await safebox.confirmOwnershipTransfer(member.appUser.id, created.id, '000000');
      throw new Error('Expected a wrong confirmation code to be rejected — it was not.');
    } catch (err) {
      if (!(err instanceof Error) || !err.message.includes('Invalid confirmation code')) throw err;
      console.log('correctly rejected wrong code (transfer must be re-initiated after this)');
    }
    // Re-initiate since confirming (even a failed attempt past the getAndDelete point) consumes the one-time code.
    await safebox.initiateOwnershipTransfer(owner.appUser.id, created.id, {
      newOwnerAppUserId: member.appUser.id,
    });
    const redis = app.get(RedisService);
    const raw = await redis.client.get(`safebox:ownership-transfer:${created.id}`);
    const { code } = JSON.parse(raw!);
    await safebox.confirmOwnershipTransfer(member.appUser.id, created.id, code);
    const detail3 = await safebox.getDetail(member.appUser.id, created.id);
    console.log('new owner:', detail3.safebox.ownerAppUserId, 'former owner role:',
      detail3.members.find((m) => m.appUserId === owner.appUser.id)?.role);
    if (detail3.safebox.ownerAppUserId !== member.appUser.id) {
      throw new Error('Ownership transfer did not take effect.');
    }

    console.log('\n✅ Safebox group savings verified end-to-end against the live sandbox.');
  } finally {
    await app.close();
  }
}

main().catch((err) => {
  console.error('\n❌ Safebox sandbox script failed:', err);
  process.exit(1);
});
