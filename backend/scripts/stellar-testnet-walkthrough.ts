/**
 * Real end-to-end verification of PayFlex's Stellar rail against the
 * live Stellar testnet — no mocks, no local blockchain.
 *
 * Uses the official JS/TS Stellar SDK (@stellar/stellar-sdk) rather than
 * driving the Flutter app directly: this sandbox's `flutter test` engine
 * (flutter_tester) cannot make real outbound network connections — a
 * separate, unrelated constraint discovered and documented earlier in
 * this project's history (see git log for the Standing Plans/Admin
 * walkthrough). A plain Node process has no such restriction, and
 * Horizon's wire protocol is identical regardless of which official SDK
 * talks to it — the mechanics this proves (funding, trustlines, native
 * and issued-asset payments, history visibility) are exactly what
 * app/lib/stellar/stellar_client.dart does with the Dart SDK on a real
 * device, which has no such sandbox restriction either.
 *
 * What this verifies:
 *  1. Two fresh accounts funded via Friendbot.
 *  2. A native XLM payment between them.
 *  3. A trustline + issued-asset payment (a self-issued "TESTUSD" asset,
 *     not a third-party issuer — see the note below on why).
 *  4. Both transactions visible in both accounts' Horizon history.
 *
 * Note on using a self-issued asset rather than Circle's real testnet
 * USDC issuer: the trustline/payment mechanism this proves is identical
 * for any issuer — self-issuing here means this script's correctness
 * doesn't depend on correctly remembering a third party's issuer
 * address. The app's Add Asset screen accepts any asset code + issuer
 * the user enters, including a real USDC issuer.
 *
 * Run with: npm run stellar:testnet-walkthrough
 */
import { Horizon, Keypair, TransactionBuilder, Asset, Operation, Networks, BASE_FEE } from '@stellar/stellar-sdk';

const HORIZON_URL = 'https://horizon-testnet.stellar.org';
const FRIENDBOT_URL = 'https://friendbot.stellar.org';

async function fundViaFriendbot(publicKey: string) {
  const res = await fetch(`${FRIENDBOT_URL}?addr=${encodeURIComponent(publicKey)}`);
  if (!res.ok) {
    throw new Error(`Friendbot funding failed for ${publicKey}: ${res.status} ${await res.text()}`);
  }
}

async function submit(server: Horizon.Server, txBuilder: TransactionBuilder, signer: Keypair) {
  const tx = txBuilder.setTimeout(60).build();
  tx.sign(signer);
  const response = await server.submitTransaction(tx);
  return response;
}

async function main() {
  const server = new Horizon.Server(HORIZON_URL);

  console.log('\n== 1. Provision two fresh testnet accounts ==');
  const payer = Keypair.random();
  const recipient = Keypair.random();
  console.log('payer:', payer.publicKey());
  console.log('recipient:', recipient.publicKey());

  await fundViaFriendbot(payer.publicKey());
  await fundViaFriendbot(recipient.publicKey());
  console.log('both accounts funded via Friendbot');

  const payerBalanceBefore = (await server.loadAccount(payer.publicKey())).balances;
  const recipientBalanceBefore = (await server.loadAccount(recipient.publicKey())).balances;
  console.log('payer balances before:', payerBalanceBefore);
  console.log('recipient balances before:', recipientBalanceBefore);

  console.log('\n== 2. Native XLM payment: payer -> recipient ==');
  const payerAccount1 = await server.loadAccount(payer.publicKey());
  const xlmPaymentTx = new TransactionBuilder(payerAccount1, {
    fee: BASE_FEE,
    networkPassphrase: Networks.TESTNET,
  }).addOperation(
    Operation.payment({ destination: recipient.publicKey(), asset: Asset.native(), amount: '50' }),
  );
  const xlmResult = await submit(server, xlmPaymentTx, payer);
  if (!xlmResult.successful) throw new Error(`Native payment failed: ${JSON.stringify(xlmResult)}`);
  console.log('native XLM payment confirmed, hash:', xlmResult.hash);

  console.log('\n== 3. Trustline: recipient trusts a self-issued TESTUSD from payer ==');
  const testUsd = new Asset('TESTUSD', payer.publicKey());
  const recipientAccount1 = await server.loadAccount(recipient.publicKey());
  const trustlineTx = new TransactionBuilder(recipientAccount1, {
    fee: BASE_FEE,
    networkPassphrase: Networks.TESTNET,
  }).addOperation(Operation.changeTrust({ asset: testUsd, limit: '1000000' }));
  const trustlineResult = await submit(server, trustlineTx, recipient);
  if (!trustlineResult.successful) throw new Error(`Trustline failed: ${JSON.stringify(trustlineResult)}`);
  console.log('trustline established, hash:', trustlineResult.hash);

  console.log('\n== 4. Issued-asset payment: payer -> recipient (TESTUSD) ==');
  const payerAccount2 = await server.loadAccount(payer.publicKey());
  const assetPaymentTx = new TransactionBuilder(payerAccount2, {
    fee: BASE_FEE,
    networkPassphrase: Networks.TESTNET,
  }).addOperation(
    Operation.payment({ destination: recipient.publicKey(), asset: testUsd, amount: '250' }),
  );
  const assetResult = await submit(server, assetPaymentTx, payer);
  if (!assetResult.successful) throw new Error(`Asset payment failed: ${JSON.stringify(assetResult)}`);
  console.log('TESTUSD payment confirmed, hash:', assetResult.hash);

  console.log('\n== 5. Confirm final balances and history on both accounts ==');
  const payerBalanceAfter = (await server.loadAccount(payer.publicKey())).balances;
  const recipientBalanceAfter = (await server.loadAccount(recipient.publicKey())).balances;
  console.log('payer balances after:', payerBalanceAfter);
  console.log('recipient balances after:', recipientBalanceAfter);

  const payerHistory = await server.payments().forAccount(payer.publicKey()).order('desc').limit(5).call();
  const recipientHistory = await server
    .payments()
    .forAccount(recipient.publicKey())
    .order('desc')
    .limit(5)
    .call();

  const payerHashes = payerHistory.records.map((r) => r.transaction_hash);
  const recipientHashes = recipientHistory.records.map((r) => r.transaction_hash);

  if (!payerHashes.includes(xlmResult.hash) || !payerHashes.includes(assetResult.hash)) {
    throw new Error('Payer history is missing an expected transaction hash.');
  }
  if (!recipientHashes.includes(xlmResult.hash) || !recipientHashes.includes(assetResult.hash)) {
    throw new Error('Recipient history is missing an expected transaction hash.');
  }
  console.log('both transactions confirmed visible in both accounts\' Horizon history');

  console.log('\n✅ Stellar rail verified end-to-end against the live testnet.');
  console.log(JSON.stringify(
    {
      payerPublicKey: payer.publicKey(),
      recipientPublicKey: recipient.publicKey(),
      nativePaymentHash: xlmResult.hash,
      trustlineHash: trustlineResult.hash,
      assetPaymentHash: assetResult.hash,
      payerBalancesAfter: payerBalanceAfter,
      recipientBalancesAfter: recipientBalanceAfter,
    },
    null,
    2,
  ));
}

main().catch((err) => {
  console.error('\n❌ Stellar testnet walkthrough failed:', err);
  process.exit(1);
});
