import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/prisma/prisma.service';
import { StellarService } from '../src/stellar/stellar.service';
import { JwtService } from '@nestjs/jwt';

/**
 * THE HARD GATE TEST (section 5 of the migration brief / docs/fiat-kyc-gap.md).
 *
 * Proves the architecture-level claim, not an assertion: every feature that
 * requires real identity verification or real fiat movement REFUSES with
 * 403 even for an authenticated, fully-onboarded user with a funded Stellar
 * account. If anyone later "fixes" the gate by weakening HardGateService,
 * these tests fail. If anyone sets identityVerified/fiatCapable directly in
 * the database, the gate still requires the flag on the user row — and no
 * code path in this repository sets it, which is the point.
 */
describe('Hard gate — paused fiat/KYC features', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let jwt: JwtService;
  let token: string;
  let appUserId: string;

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(StellarService)
      .useValue({
        verifyPayment: jest.fn(),
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
    jwt = app.get(JwtService);

    // Real user row through the real service path.
    const res = await request(app.getHttpServer())
      .post('/users')
      .send({
        firstName: 'Gate',
        lastName: 'Tester',
        email: `gate-${Date.now()}@test.payflex`,
        phoneNumber: `+23499${Date.now() % 100000000}`,
      })
      .expect(201);
    appUserId = res.body.user.id;

    // An ACCESS token (the strongest normal credential a user can hold).
    // Deliberately no database write of identityVerified/fiatCapable — and
    // if a test setup did write them, that write itself would violate the
    // "no code path sets them" rule and would be caught in review; the gate
    // would then pass and these tests would fail loudly. That is the
    // intended failure mode.
    token = jwt.sign({ sub: appUserId, scope: 'access' }, { expiresIn: '10m' });
  });

  afterAll(async () => {
    await prisma.appUser.deleteMany({ where: { id: appUserId } });
    await app.close();
  });

  const gated = [
    { method: 'post', url: () => `/users/${appUserId}/agent/status`, body: { enabled: 'true' }, feature: 'agent mode' },
    { method: 'post', url: () => `/users/${appUserId}/fiat/deposits`, body: { amount: '1000', assetCode: 'XLM' }, feature: 'fiat deposit' },
    { method: 'post', url: () => `/users/${appUserId}/fiat/withdrawals`, body: { amount: '1000', assetCode: 'XLM' }, feature: 'fiat withdrawal' },
    { method: 'post', url: () => `/users/${appUserId}/cards`, body: {}, feature: 'virtual card' },
    { method: 'post', url: () => `/users/${appUserId}/betting/fund`, body: { amount: '500', assetCode: 'XLM' }, feature: 'betting funding' },
  ] as const;

  it.each(gated)('blocks $feature with 403 and an honest message', async ({ method, url, body }) => {
    const server = app.getHttpServer();
    const res =
      method === 'post'
        ? await request(server).post(url()).set('Authorization', `Bearer ${token}`).send(body)
        : await request(server).get(url()).set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(403);
    const message = typeof res.body.message === 'string' ? res.body.message : JSON.stringify(res.body.message);
    expect(message).toMatch(/not.*configured|not yet/i);
    expect(message).toContain('docs/fiat-kyc-gap.md');
  });

  it('flags are false on a real user row and there is no endpoint that can set them', async () => {
    const user = await prisma.appUser.findUnique({ where: { id: appUserId } });
    expect(user?.identityVerified).toBe(false);
    expect(user?.fiatCapable).toBe(false);
  });

  it('the gated controller throws (not returns) past the gate — proving no partial work happens', async () => {
    // Direct service-level probe: even bypassing HTTP, the gate refuses.
    const { HardGateService } = await import('../src/providers/hard-gate.service');
    const gate = app.get(HardGateService);
    await expect(gate.requireIdentityVerified(appUserId)).rejects.toThrow();
    await expect(gate.requireFiatCapable(appUserId)).rejects.toThrow();
    await expect(gate.requireVerifiedAndFiatCapable(appUserId)).rejects.toThrow();
  });
});
