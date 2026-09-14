import { INestApplication, ValidationPipe } from '@nestjs/common';
import { randomBytes } from 'crypto';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { Keypair } from '@stellar/stellar-sdk';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/prisma/prisma.service';
import { StellarService } from '../src/stellar/stellar.service';
import { JwtService } from '@nestjs/jwt';

/**
 * Transfer recording: the backend verifies every claimed payment before
 * storing it. StellarService is mocked at the boundary (a stub Horizon),
 * so these tests exercise the real controller/service/DB path with zero
 * network — the verification logic itself is the thing under test.
 */
describe('Transfer record verification', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let token: string;
  let bootstrapToken: string;
  let appUserId: string;

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(StellarService)
      .useValue({
        verifyPayment: jest.fn().mockResolvedValue({ ok: false, reason: 'Transaction 0x… does not exist on testnet.' }),
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
    app.useGlobalPipes(new ValidationPipe({ whitelist: true }));
    await app.init();

    prisma = app.get(PrismaService);
    const jwt = app.get(JwtService);

    const uniquePhone = `+23499${Date.now() % 100000000}`;
    const res = await request(app.getHttpServer())
      .post('/users')
      .send({
        firstName: 'Pay',
        lastName: 'Recorder',
        email: `payrec-${Date.now()}@test.payflex`,
        phoneNumber: uniquePhone,
      })
      .expect(201);
    appUserId = res.body.user.id;
    bootstrapToken = res.body.bootstrapToken;
    token = jwt.sign({ sub: appUserId, scope: 'access' }, { expiresIn: '10m' });
    // Isolate from any previous run's rows.
    await prisma.transferRecord.deleteMany({ where: { appUserId } });
  });

  afterAll(async () => {
    // Children first — the FK constraint is doing its job.
    await prisma.transferRecord.deleteMany({ where: { appUserId } });
    await prisma.appUser.deleteMany({ where: { id: appUserId } });
    await app.close();
  });

  it('rejects a claimed payment the verifier says does not exist (nothing is recorded)', async () => {
    const res = await request(app.getHttpServer())
      .post(`/users/${appUserId}/transfers/record`)
      .set('Authorization', `Bearer ${token}`)
      .send({
        stellarTxHash: 'a'.repeat(64),
        fromPublicKey: Keypair.random().publicKey(),
        toPublicKey: Keypair.random().publicKey(),
        amount: '10.0000000',
        assetCode: 'XLM',
        kind: 'TRANSFER',
      });
    expect(res.status).toBe(400);
    expect(JSON.stringify(res.body.message)).toMatch(/does not exist/i);

    const records = await prisma.transferRecord.findMany({ where: { appUserId } });
    expect(records).toHaveLength(0);
  });

  it('records a payment once verification PASSES, and it is idempotent by tx hash', async () => {
    const stellar = app.get(StellarService);
    // Both submissions hit the same verified payment — keep verification
    // green for every call so the idempotency of the *record insert* is
    // what's actually under test.
    (stellar.verifyPayment as jest.Mock).mockResolvedValue({ ok: true, memo: 'e2e', createdAt: new Date().toISOString() });

    const body = {
      stellarTxHash: randomBytes(32).toString('hex'),
      fromPublicKey: Keypair.random().publicKey(),
      toPublicKey: Keypair.random().publicKey(),
      amount: '10.0000000',
      assetCode: 'XLM',
      kind: 'TRANSFER',
    };
    // fromPublicKey must equal the user's registered key — register one via
    // the real bootstrap-token flow from account creation.
    const pkRes = await request(app.getHttpServer())
      .patch(`/users/${appUserId}/stellar-public-key`)
      .set('Authorization', `Bearer ${bootstrapToken}`)
      .send({ stellarPublicKey: body.fromPublicKey });
    expect(pkRes.status).toBe(200);

    const first = await request(app.getHttpServer())
      .post(`/users/${appUserId}/transfers/record`)
      .set('Authorization', `Bearer ${token}`)
      .send(body);
    expect(first.status).toBe(201);

    const second = await request(app.getHttpServer())
      .post(`/users/${appUserId}/transfers/record`)
      .set('Authorization', `Bearer ${token}`)
      .send(body);
    expect([200, 201]).toContain(second.status);
    expect(second.body.id).toBe(first.body.id);

    const records = await prisma.transferRecord.findMany({ where: { appUserId } });
    expect(records).toHaveLength(1);
  });
});
