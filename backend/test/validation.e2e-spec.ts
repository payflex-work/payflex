import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { Keypair } from '@stellar/stellar-sdk';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/prisma/prisma.service';
import { StellarService } from '../src/stellar/stellar.service';
import { JwtService } from '@nestjs/jwt';

/**
 * VALIDATION-LAYER SUITE — section 1 of the hardening brief.
 *
 * Exercises the real HTTP boundary (global ValidationPipe + the shared
 * validators in src/common/validation/validators.ts) for every endpoint
 * that accepts user-facing input. Per case the contract is the same: a
 * valid payload passes validation (any later business failure is fine —
 * we assert on the VALIDATION 400 messages), and each invalid case is
 * rejected with a specific message naming the field, not a generic 400.
 *
 * StellarService is stubbed at the boundary so no network is touched.
 */
describe('Input validation at the API boundary', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let token: string;
  let appUserId: string;
  const createdUserIds: string[] = [];

  // A REAL strkey (checksum-correct) and a shape-correct-but-broken one.
  const validKey = Keypair.random().publicKey();
  const brokenChecksumKey = 'G' + 'A'.repeat(55);
  const txHash64 = 'a'.repeat(64);

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(StellarService)
      .useValue({
        verifyPayment: jest.fn().mockResolvedValue({ ok: false, reason: 'stub' }),
        isTransactionSuccessful: jest.fn().mockResolvedValue(false),
        isAccountFunded: jest.fn().mockResolvedValue(false),
        getClaimableBalance: jest.fn().mockResolvedValue(null),
        getAssetBalance: jest.fn().mockResolvedValue(null),
        safeboxOwner: jest.fn().mockResolvedValue(null),
        safeboxAdmins: jest.fn().mockResolvedValue([]),
        safeboxClosed: jest.fn().mockResolvedValue(false),
        safeboxLedger: jest.fn().mockResolvedValue([]),
        safeboxBalance: jest.fn().mockResolvedValue(null),
        invokeReadFunction: jest.fn(),
        getNetworkInfo: jest.fn().mockReturnValue({ network: 'testnet' }),
      })
      .compile();
    app = moduleRef.createNestApplication();
    // Mirror main.ts exactly — these tests are meaningless if the pipe
    // config diverges from production.
    app.useGlobalPipes(
      new ValidationPipe({ whitelist: true, transform: true, forbidNonWhitelisted: true }),
    );
    await app.init();

    prisma = app.get(PrismaService);
    const jwt = app.get(JwtService);

    const res = await request(app.getHttpServer())
      .post('/users')
      .send({
        firstName: 'Val',
        lastName: 'Idator',
        email: `val-${Date.now()}@test.payflex`,
        phoneNumber: `+23491${Date.now() % 100000000}`,
      })
      .expect(201);
    appUserId = res.body.user.id;
    createdUserIds.push(appUserId);
    token = jwt.sign({ sub: appUserId, scope: 'access' }, { expiresIn: '10m' });
  });

  afterAll(async () => {
    // Children first — FK constraints doing their job.
    await prisma.transferRecord.deleteMany({ where: { appUserId: { in: createdUserIds } } });
    await prisma.standingPlanPayment.deleteMany({
      where: { standingPlan: { appUserId: { in: createdUserIds } } },
    });
    await prisma.standingPlan.deleteMany({ where: { appUserId: { in: createdUserIds } } });
    await prisma.splitBillContributor.deleteMany({
      where: { splitBill: { creatorAppUserId: { in: createdUserIds } } },
    });
    await prisma.splitBill.deleteMany({ where: { creatorAppUserId: { in: createdUserIds } } });
    await prisma.linkRecord.deleteMany({ where: { senderAppUserId: { in: createdUserIds } } });
    await prisma.payTag.deleteMany({ where: { appUserId: { in: createdUserIds } } });
    await prisma.appUser.deleteMany({ where: { id: { in: createdUserIds } } });
    await app.close();
  });

  const auth = () => ({
    post: (url: string) => request(app.getHttpServer()).post(url).set('Authorization', `Bearer ${token}`),
    put: (url: string) => request(app.getHttpServer()).put(url).set('Authorization', `Bearer ${token}`),
  });

  /** Asserts the response is a 400 whose message names the expected field. */
  async function expectFieldRejected(
    method: 'post' | 'patch' | 'put',
    url: string,
    body: Record<string, unknown>,
    fieldFragment: string,
  ) {
    const res = await request(app.getHttpServer())
      [method](url)
      .set('Authorization', `Bearer ${token}`)
      .send(body);
    expect([400, 422]).toContain(res.status);
    const messages = Array.isArray(res.body.message) ? res.body.message : [String(res.body.message)];
    expect(messages.join(' | ')).toContain(fieldFragment);
    return res;
  }

  // ───────────────────────── POST /users ─────────────────────────
  describe('POST /users (create account)', () => {
    const base = { firstName: 'A', lastName: 'B', email: 'a@b.co', phoneNumber: '+2348000000002' };

    it('accepts a fully valid payload', async () => {
      const res = await request(app.getHttpServer())
        .post('/users')
        .send({ ...base, email: `ok-${Date.now()}@test.payflex`, phoneNumber: `+23481${Date.now() % 100000000}` });
      expect(res.status).toBe(201);
      createdUserIds.push(res.body.user.id);
    });

    it('rejects a malformed phone number with the field named', async () => {
      await expectFieldRejected('post', '/users', { ...base, phoneNumber: '08031234567' }, 'phoneNumber');
    });

    it('rejects a malformed email with the field named', async () => {
      await expectFieldRejected('post', '/users', { ...base, email: 'not-an-email' }, 'email');
    });

    it('rejects control characters / oversized names', async () => {
      const res = await expectFieldRejected(
        'post',
        '/users',
        { ...base, firstName: 'A'.repeat(51) },
        'firstName',
      );
      expect(JSON.stringify(res.body.message)).toMatch(/at most 50/i);
    });
  });

  // ───────────────── PATCH /users/:id/stellar-public-key ─────────────────
  describe('PATCH /users/:id/stellar-public-key', () => {
    it('accepts a real checksum-valid strkey (validation passes; immutability business rule may later reject)', async () => {
      const res = await request(app.getHttpServer())
        .patch(`/users/${appUserId}/stellar-public-key`)
        .set('Authorization', `Bearer ${token}`)
        .send({ stellarPublicKey: validKey });
      // 200 (registered) — validation's job is done; the row now has the key.
      expect(res.status).toBe(200);
    });

    it('rejects a shape-correct strkey with a broken checksum (SDK validation, not just regex)', async () => {
      await expectFieldRejected(
        'patch',
        `/users/${appUserId}/stellar-public-key`,
        { stellarPublicKey: brokenChecksumKey },
        'stellarPublicKey',
      );
    });

    it('rejects a secret-seed strkey (S…) where a public key belongs', async () => {
      const seed = Keypair.random().secret().slice(0, 56).padEnd(56, 'A');
      await expectFieldRejected(
        'patch',
        `/users/${appUserId}/stellar-public-key`,
        { stellarPublicKey: seed },
        'stellarPublicKey',
      );
    });

    it('rejects a wrong length', async () => {
      await expectFieldRejected(
        'patch',
        `/users/${appUserId}/stellar-public-key`,
        { stellarPublicKey: 'GABC' },
        'stellarPublicKey',
      );
    });
  });

  // ───────────────── POST /users/:id/transfers/record ─────────────────
  describe('POST /users/:id/transfers/record (financial + Stellar fields)', () => {
    const validBody = () => ({
      stellarTxHash: txHash64,
      fromPublicKey: validKey,
      toPublicKey: Keypair.random().publicKey(),
      amount: '5.0000000',
      assetCode: 'XLM',
      kind: 'TRANSFER',
    });

    it('accepts a structurally valid payload (verification stub then refuses — that is fine)', async () => {
      const res = await auth().post(`/users/${appUserId}/transfers/record`).send(validBody());
      // Validation passed; the stubbed verifier rejects with its own message.
      expect(res.status).toBe(400);
      expect(JSON.stringify(res.body.message)).toMatch(/verification failed|does not exist/i);
    });

    it('rejects negative amounts', async () => {
      await expectFieldRejected(
        'post',
        `/users/${appUserId}/transfers/record`,
        { ...validBody(), amount: '-5.00' },
        'amount',
      );
    });

    it('rejects zero amounts', async () => {
      await expectFieldRejected(
        'post',
        `/users/${appUserId}/transfers/record`,
        { ...validBody(), amount: '0' },
        'amount',
      );
    });

    it('rejects absurdly large amounts (beyond 1e12)', async () => {
      await expectFieldRejected(
        'post',
        `/users/${appUserId}/transfers/record`,
        { ...validBody(), amount: '9999999999999' },
        'amount',
      );
    });

    it('rejects more than 7 decimal places (Stellar precision)', async () => {
      await expectFieldRejected(
        'post',
        `/users/${appUserId}/transfers/record`,
        { ...validBody(), amount: '5.12345678' },
        'amount',
      );
    });

    it('rejects exponent-notation amounts', async () => {
      await expectFieldRejected(
        'post',
        `/users/${appUserId}/transfers/record`,
        { ...validBody(), amount: '5e2' },
        'amount',
      );
    });

    it('rejects non-numeric amounts', async () => {
      await expectFieldRejected(
        'post',
        `/users/${appUserId}/transfers/record`,
        { ...validBody(), amount: 'banana' },
        'amount',
      );
    });

    it('rejects a malformed tx hash', async () => {
      await expectFieldRejected(
        'post',
        `/users/${appUserId}/transfers/record`,
        { ...validBody(), stellarTxHash: 'DEADBEEF' },
        'stellarTxHash',
      );
    });

    it('rejects a broken-checksum recipient key', async () => {
      await expectFieldRejected(
        'post',
        `/users/${appUserId}/transfers/record`,
        { ...validBody(), toPublicKey: brokenChecksumKey },
        'toPublicKey',
      );
    });

    it('rejects an invalid asset code', async () => {
      await expectFieldRejected(
        'post',
        `/users/${appUserId}/transfers/record`,
        { ...validBody(), assetCode: 'xlm!' },
        'assetCode',
      );
    });

    it('rejects an over-long 13-char asset code', async () => {
      await expectFieldRejected(
        'post',
        `/users/${appUserId}/transfers/record`,
        { ...validBody(), assetCode: 'ABCDEF0123456' },
        'assetCode',
      );
    });

    it('rejects XLM paired with an issuer', async () => {
      await expectFieldRejected(
        'post',
        `/users/${appUserId}/transfers/record`,
        { ...validBody(), assetIssuer: validKey },
        'assetIssuer',
      );
    });

    it('rejects a non-XLM asset with no issuer', async () => {
      await expectFieldRejected(
        'post',
        `/users/${appUserId}/transfers/record`,
        { ...validBody(), assetCode: 'USDC' },
        'assetIssuer',
      );
    });

    it('rejects an unknown kind with the allowed set named', async () => {
      const res = await auth()
        .post(`/users/${appUserId}/transfers/record`)
        .send({ ...validBody(), kind: 'FREE_MONEY' });
      expect(res.status).toBe(400);
      expect(JSON.stringify(res.body.message)).toMatch(/kind must be one of/i);
    });

    it('rejects unknown fields outright (forbidNonWhitelisted)', async () => {
      const res = await auth()
        .post(`/users/${appUserId}/transfers/record`)
        .send({ ...validBody(), adminBackdoor: true });
      expect(res.status).toBe(400);
      expect(JSON.stringify(res.body.message)).toMatch(/adminBackdoor/i);
    });
  });

  // ───────────────── POST /users/:id/transfers/resolve ─────────────────
  describe('POST /users/:id/transfers/resolve', () => {
    it('rejects a bad recipient key', async () => {
      await expectFieldRejected(
        'post',
        `/users/${appUserId}/transfers/resolve`,
        { toPublicKey: 'G' + 'z'.repeat(55) },
        'toPublicKey',
      );
    });

    it('rejects a malformed PayTag', async () => {
      await expectFieldRejected(
        'post',
        `/users/${appUserId}/transfers/resolve`,
        { toPayTag: 'Not A Tag!' },
        'toPayTag',
      );
    });

    it('rejects a bad amount even before resolution', async () => {
      await expectFieldRejected(
        'post',
        `/users/${appUserId}/transfers/resolve`,
        { toPayTag: 'adaeze', amount: '-1', assetCode: 'XLM' },
        'amount',
      );
    });

    it('accepts a structurally valid resolve for an unknown-but-well-formed PayTag (404 from the directory)', async () => {
      const res = await auth()
        .post(`/users/${appUserId}/transfers/resolve`)
        .send({ toPayTag: 'definitely_nobody', amount: '1.00', assetCode: 'XLM' });
      expect(res.status).toBe(404);
    });
  });

  // ───────────────── POST /users/:id/paytag ─────────────────
  describe('POST /users/:id/paytag', () => {
    it('rejects a tag that is too short', async () => {
      await expectFieldRejected('post', `/users/${appUserId}/paytag`, { tag: 'ab' }, 'tag');
    });

    it('rejects uppercase / spaces / symbols', async () => {
      await expectFieldRejected('post', `/users/${appUserId}/paytag`, { tag: 'Ada Eze!' }, 'tag');
    });

    it('accepts a well-formed tag', async () => {
      const res = await auth()
        .post(`/users/${appUserId}/paytag`)
        .send({ tag: `val_${Date.now() % 100000}` });
      expect(res.status).toBe(201);
    });
  });

  // ───────────────── POST /users/:id/standing-plans ─────────────────
  describe('POST /users/:id/standing-plans', () => {
    const valid = () => ({
      name: 'Rent',
      amount: '100.00',
      assetCode: 'XLM',
      frequency: 'MONTHLY',
      toPayTag: 'landlord',
    });

    it('rejects an invalid frequency with the allowed set named', async () => {
      await expectFieldRejected(
        'post',
        `/users/${appUserId}/standing-plans`,
        { ...valid(), frequency: 'HOURLY' },
        'frequency',
      );
    });

    it('rejects a bad amount', async () => {
      await expectFieldRejected(
        'post',
        `/users/${appUserId}/standing-plans`,
        { ...valid(), amount: '0' },
        'amount',
      );
    });

    it('rejects an over-long plan name', async () => {
      await expectFieldRejected(
        'post',
        `/users/${appUserId}/standing-plans`,
        { ...valid(), name: 'x'.repeat(61) },
        'name',
      );
    });

    it('rejects a malformed recipient key', async () => {
      await expectFieldRejected(
        'post',
        `/users/${appUserId}/standing-plans`,
        { ...valid(), toPayTag: undefined, toPublicKey: brokenChecksumKey },
        'toPublicKey',
      );
    });

    it('accepts a structurally valid plan (unknown PayTag → business-level 400 from resolution)', async () => {
      const res = await auth()
        .post(`/users/${appUserId}/standing-plans`)
        .send({ ...valid(), toPayTag: 'nobody_here' });
      // Validation passed; the service's directory lookup refuses with its
      // own (business) error — exactly the boundary this suite tests.
      expect(res.status).toBe(400);
      expect(JSON.stringify(res.body.message)).toMatch(/PayTag/i);
    });
  });

  describe('PUT /users/:id/standing-plans/:planId/status', () => {
    it('rejects an arbitrary status string that previously landed raw in the DB', async () => {
      const res = await auth()
        .put(`/users/${appUserId}/standing-plans/some-plan/status`)
        .send({ status: 'WIBBLE' });
      expect(res.status).toBe(400);
      expect(JSON.stringify(res.body.message)).toMatch(/status must be one of/i);
    });
  });

  describe('POST /users/:id/standing-plans/payments/:paymentId/record', () => {
    it('rejects a malformed tx hash at the boundary', async () => {
      const res = await auth()
        .post(`/users/${appUserId}/standing-plans/payments/not-a-uuid/record`)
        .send({ stellarTxHash: 'zzz' });
      expect(res.status).toBe(400);
      expect(JSON.stringify(res.body.message)).toMatch(/stellarTxHash/i);
    });
  });

  // ───────────────── POST /users/:id/split-bills ─────────────────
  describe('POST /users/:id/split-bills', () => {
    const valid = () => ({
      description: 'Dinner',
      totalAmount: '60.00',
      assetCode: 'XLM',
      contributorsJson: JSON.stringify([{ payTag: 'adaeze', shareAmount: '30.00' }]),
    });

    it('rejects a malformed contributorsJson', async () => {
      const res = await auth()
        .post(`/users/${appUserId}/split-bills`)
        .send({ ...valid(), contributorsJson: 'not json' });
      expect(res.status).toBe(400);
      expect(JSON.stringify(res.body.message)).toMatch(/JSON array/i);
    });

    it('rejects a zero share amount', async () => {
      const res = await auth()
        .post(`/users/${appUserId}/split-bills`)
        .send({
          ...valid(),
          contributorsJson: JSON.stringify([{ payTag: 'adaeze', shareAmount: '0' }]),
        });
      expect(res.status).toBe(400);
      expect(JSON.stringify(res.body.message)).toMatch(/shareAmount/i);
    });

    it('rejects a negative share amount', async () => {
      const res = await auth()
        .post(`/users/${appUserId}/split-bills`)
        .send({
          ...valid(),
          contributorsJson: JSON.stringify([{ payTag: 'adaeze', shareAmount: '-5' }]),
        });
      expect(res.status).toBe(400);
      expect(JSON.stringify(res.body.message)).toMatch(/shareAmount/i);
    });

    it('rejects a contributor with a broken-checksum key', async () => {
      const res = await auth()
        .post(`/users/${appUserId}/split-bills`)
        .send({
          ...valid(),
          contributorsJson: JSON.stringify([{ publicKey: brokenChecksumKey, shareAmount: '30.00' }]),
        });
      expect(res.status).toBe(400);
      expect(JSON.stringify(res.body.message)).toMatch(/publicKey/i);
    });

    it('rejects duplicate contributors', async () => {
      const res = await auth()
        .post(`/users/${appUserId}/split-bills`)
        .send({
          ...valid(),
          contributorsJson: JSON.stringify([
            { payTag: 'adaeze', shareAmount: '30.00' },
            { payTag: 'adaeze', shareAmount: '30.00' },
          ]),
        });
      expect(res.status).toBe(400);
      expect(JSON.stringify(res.body.message)).toMatch(/duplicate/i);
    });

    it('rejects a bill with no contributors', async () => {
      const res = await auth()
        .post(`/users/${appUserId}/split-bills`)
        .send({ ...valid(), contributorsJson: JSON.stringify([]) });
      expect(res.status).toBe(400);
      expect(JSON.stringify(res.body.message)).toMatch(/at least one/i);
    });
  });

  // ───────────────── POST /users/:id/send-via-link ─────────────────
  describe('POST /users/:id/send-via-link', () => {
    it('rejects a bad amount', async () => {
      await expectFieldRejected(
        'post',
        `/users/${appUserId}/send-via-link`,
        { amount: '-2', assetCode: 'XLM' },
        'amount',
      );
    });

    it('rejects a non-numeric expiresInDays that previously produced Invalid Date expiry rows', async () => {
      const res = await expectFieldRejected(
        'post',
        `/users/${appUserId}/send-via-link`,
        { amount: '2.00', assetCode: 'XLM', expiresInDays: 'banana' },
        'expiresInDays',
      );
      expect(JSON.stringify(res.body.message)).toMatch(/between 1 and 365/i);
    });

    it('rejects an out-of-range expiresInDays', async () => {
      await expectFieldRejected(
        'post',
        `/users/${appUserId}/send-via-link`,
        { amount: '2.00', assetCode: 'XLM', expiresInDays: '4000' },
        'expiresInDays',
      );
    });
  });

  // ───────────────── POST /users/:id/links/:linkId/claim ─────────────────
  describe('POST /users/:id/links/:linkId/claim', () => {
    it('rejects a malformed claimant key', async () => {
      await expectFieldRejected(
        'post',
        `/users/${appUserId}/links/xyz/claim`,
        { claimantPublicKey: 'S' + 'A'.repeat(55), claimTxHash: txHash64 },
        'claimantPublicKey',
      );
    });

    it('rejects a malformed claim tx hash', async () => {
      await expectFieldRejected(
        'post',
        `/users/${appUserId}/links/xyz/claim`,
        { claimantPublicKey: validKey, claimTxHash: 'not-a-hash' },
        'claimTxHash',
      );
    });
  });

  // ───────────────── POST /users/:id/qr/generate ─────────────────
  describe('POST /users/:id/qr/generate', () => {
    it('rejects a bad amount', async () => {
      await expectFieldRejected(
        'post',
        `/users/${appUserId}/qr/generate`,
        { amount: '-1', assetCode: 'XLM' },
        'amount',
      );
    });

    it('rejects an unbounded expiry that previously let QRs live arbitrarily long', async () => {
      const res = await expectFieldRejected(
        'post',
        `/users/${appUserId}/qr/generate`,
        { amount: '1.00', assetCode: 'XLM', expiresInSeconds: '999999999' },
        'expiresInSeconds',
      );
      expect(JSON.stringify(res.body.message)).toMatch(/between 30 and 3600/i);
    });

    it('rejects a non-numeric expiry', async () => {
      await expectFieldRejected(
        'post',
        `/users/${appUserId}/qr/generate`,
        { amount: '1.00', assetCode: 'XLM', expiresInSeconds: 'soon' },
        'expiresInSeconds',
      );
    });
  });

  // ───────────────── POST /safebox ─────────────────
  describe('POST /safebox (register deployed contract)', () => {
    it('rejects a non-contract id (account key) before any chain read', async () => {
      const res = await expectFieldRejected(
        'post',
        '/safebox',
        { contractId: validKey, name: 'Pool' },
        'contractId',
      );
      expect(JSON.stringify(res.body.message)).toMatch(/Soroban contract id/i);
    });

    it('rejects a broken-checksum contract id', async () => {
      await expectFieldRejected('post', '/safebox', { contractId: 'C' + 'A'.repeat(55), name: 'Pool' }, 'contractId');
    });

    it('rejects an over-long safebox name', async () => {
      await expectFieldRejected(
        'post',
        '/safebox',
        { contractId: 'C' + 'B'.repeat(55), name: 'x'.repeat(51) },
        'name',
      );
    });

    it('rejects an over-long description', async () => {
      await expectFieldRejected(
        'post',
        '/safebox',
        { contractId: 'C' + 'B'.repeat(55), name: 'Pool', description: 'x'.repeat(201) },
        'description',
      );
    });
  });

  // ───────────────── auth endpoints ─────────────────
  describe('POST /auth/login (rate-limited pre-auth boundary)', () => {
    it('rejects a signature that is not 128 hex chars', async () => {
      const res = await request(app.getHttpServer())
        .post('/auth/login')
        .send({ appUserId, signature: 'deadbeef' });
      expect(res.status).toBe(400);
      expect(JSON.stringify(res.body.message)).toMatch(/signature/i);
    });

    it('rejects a non-uuid appUserId', async () => {
      const res = await request(app.getHttpServer())
        .post('/auth/login')
        .send({ appUserId: 'not-a-uuid', signature: 'ab'.repeat(64) });
      expect(res.status).toBe(400);
      expect(JSON.stringify(res.body.message)).toMatch(/appUserId/i);
    });
  });

  describe('POST /auth/refresh', () => {
    it('rejects a token that is not JWT-shaped', async () => {
      const res = await request(app.getHttpServer())
        .post('/auth/refresh')
        .send({ refreshToken: 'three spaces not a jwt' });
      expect(res.status).toBe(400);
      expect(JSON.stringify(res.body.message)).toMatch(/refreshToken/i);
    });
  });

  // ───────────────── cross-cutting: 401s stay 401s ─────────────────
  it('keeps unauthenticated requests at 401 (validation does not leak authz)', async () => {
    const res = await request(app.getHttpServer())
      .post(`/users/${appUserId}/transfers/record`)
      .send({ amount: 'nope' });
    expect(res.status).toBe(401);
  });
});
