/**
 * Standing Plans verification harness: create a recurring plan targeting
 * a fixed bmoniUserId, back-date it due, trigger the due-check, and sign
 * the resulting real transfer proposal — end to end against the live
 * BMONI sandbox, using the real StandingPlansService.
 *
 * Same simulated-signer caveat as every other sandbox script (ethers.Wallet
 * standing in for bmoni_embedded_sdk).
 *
 * Run with: npm run sandbox:standing-plans
 */
import { NestFactory } from '@nestjs/core';
import { SigningKey, Wallet } from 'ethers';
import { AppModule } from '../src/app.module';
import { UsersService } from '../src/users/users.service';
import { OnboardingService } from '../src/onboarding/onboarding.service';
import { TransferService } from '../src/transfer/transfer.service';
import { StandingPlansService } from '../src/standing-plans/standing-plans.service';
import { PrismaService } from '../src/prisma/prisma.service';
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

async function main() {
  const app = await NestFactory.createApplicationContext(AppModule);

  try {
    const users = app.get(UsersService);
    const onboarding = app.get(OnboardingService);
    const transfers = app.get(TransferService);
    const plans = app.get(StandingPlansService);
    const prisma = app.get(PrismaService);

    console.log('\n== 1. Provision a payer and a fixed recipient ==');
    const payer = await users.getOrCreate({
      firstName: 'StandingPlan',
      lastName: 'Payer',
      email: `payflex.standingplan.payer.${Date.now()}@payflex.test`,
      phoneNumber: `+2347${String(Date.now()).slice(-8)}${Math.floor(Math.random() * 10)}`,
    });
    const payerWallet = Wallet.createRandom();
    await users.setOwnerAddress(payer.id, payerWallet.address);
    const payerChallenge = await onboarding.requestOwnerProofChallenge(payer.id, 'CNGN');
    const payerSignature = await payerWallet.signMessage(payerChallenge.message);
    await onboarding.createSmartWallet(payer.id, {
      currency: 'CNGN',
      ownerProofChallengeId: payerChallenge.challengeId,
      ownerProofSignature: payerSignature,
    });

    const recipient = await users.getOrCreate({
      firstName: 'StandingPlan',
      lastName: 'Recipient',
      email: `payflex.standingplan.recipient.${Date.now()}@payflex.test`,
      phoneNumber: `+2347${String(Date.now()).slice(-8)}${Math.floor(Math.random() * 10)}`,
    });
    const recipientWallet = Wallet.createRandom();
    await users.setOwnerAddress(recipient.id, recipientWallet.address);
    const recipientChallenge = await onboarding.requestOwnerProofChallenge(recipient.id, 'CNGN');
    const recipientSignature = await recipientWallet.signMessage(recipientChallenge.message);
    await onboarding.createSmartWallet(recipient.id, {
      currency: 'CNGN',
      ownerProofChallengeId: recipientChallenge.challengeId,
      ownerProofSignature: recipientSignature,
    });
    console.log('payer:', payer.id, 'recipient:', recipient.id, recipient.bmoniUserId);

    console.log('\n== 2. Create a standing plan (payer -> recipient) ==');
    const plan = await plans.createPlan(payer.id, {
      name: 'Rent',
      currency: 'NGN',
      amount: '25.00',
      frequency: 'DAILY',
      toBmoniUserId: recipient.bmoniUserId,
    });
    console.log('plan:', { id: plan.id, nextPaymentAt: plan.nextPaymentAt });

    // Test-only: back-date nextPaymentAt so the due-check finds it
    // immediately rather than waiting a day.
    await prisma.standingPlan.update({
      where: { id: plan.id },
      data: { nextPaymentAt: new Date(Date.now() - 1000) },
    });

    console.log('\n== 3. Run the due-check and pay ==');
    const dueCheck = await plans.runDueCheck();
    console.log('due-check result:', dueCheck);
    const due = await plans.listDuePayments(payer.id);
    console.log(`${due.length} payment(s) due`);
    if (due.length !== 1) throw new Error(`Expected 1 due payment, got ${due.length}`);

    const proposal = await plans.pay(payer.id, due[0].id);
    console.log('payment proposal:', { id: proposal.id, toUserId: proposal.toUserId, amount: proposal.amount });

    const signPayload = await waitForSignPayload(transfers, payer.id, proposal.id);
    const signature = signRawDigest(payerWallet.privateKey, signPayload.signingPayloadHash);
    const signResult = await transfers.submitSignature(payer.id, proposal.id, signature);
    console.log('payment signed:', {
      currentSignatures: signResult.proposal?.currentSignatures,
      status: signResult.proposal?.status,
    });

    console.log('\n== 4. Verify totalPaid updated ==');
    const [updatedPlan] = await plans.listPlans(payer.id);
    console.log('totalPaid:', updatedPlan.totalPaid);
    if (updatedPlan.totalPaid !== '25.00') {
      throw new Error(`Expected totalPaid 25.00, got ${updatedPlan.totalPaid}`);
    }

    console.log('\n== 5. Pause and resume the plan ==');
    await plans.setStatus(payer.id, plan.id, 'PAUSED');
    const paused = await prisma.standingPlan.findUniqueOrThrow({ where: { id: plan.id } });
    if (paused.status !== 'PAUSED') throw new Error(`Expected PAUSED, got ${paused.status}`);
    await plans.setStatus(payer.id, plan.id, 'ACTIVE');
    console.log('pause/resume round-trip OK');

    console.log('\n✅ Standing plans verified end-to-end against the live sandbox.');
  } finally {
    await app.close();
  }
}

main().catch((err) => {
  console.error('\n❌ Standing plans sandbox script failed:', err);
  process.exit(1);
});
