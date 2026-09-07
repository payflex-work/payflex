import { BadRequestException, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Wallet } from 'ethers';
import { AuthService } from './auth.service';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import { TokenService } from '../token/token.service';
import { UsersService } from '../users/users.service';

/**
 * Real ethers wallets/signatures throughout (never a mocked verifyMessage)
 * — this is security-critical crypto, and the whole point of testing it
 * is to catch a real signature-verification bug, not a mocked one.
 */
describe('AuthService', () => {
  const ownerWallet = Wallet.createRandom();
  const user = {
    id: 'user-1',
    bmoniUserId: 'bmoni-1',
    ownerAddress: ownerWallet.address,
  };

  function buildService(overrides?: {
    findById?: jest.Mock;
    setWithTtl?: jest.Mock;
    getAndDelete?: jest.Mock;
    refreshTokenFindUnique?: jest.Mock;
    refreshTokenUpdate?: jest.Mock;
    refreshTokenCreate?: jest.Mock;
  }) {
    const prisma = {
      refreshToken: {
        findUnique: overrides?.refreshTokenFindUnique ?? jest.fn(),
        update: overrides?.refreshTokenUpdate ?? jest.fn(),
        create: overrides?.refreshTokenCreate ?? jest.fn(),
      },
    } as unknown as PrismaService;
    const redis = {
      setWithTtl: overrides?.setWithTtl ?? jest.fn(),
      getAndDelete: overrides?.getAndDelete ?? jest.fn(),
    } as unknown as RedisService;
    const tokens = new TokenService(new JwtService({ secret: 'test-secret' }));
    const users = {
      findById: overrides?.findById ?? jest.fn().mockResolvedValue(user),
    } as unknown as UsersService;
    return { service: new AuthService(prisma, redis, tokens, users), prisma, redis, tokens, users };
  }

  describe('createChallenge', () => {
    it('stores a fresh message keyed by appUserId and returns it', async () => {
      const setWithTtl = jest.fn();
      const { service } = buildService({ setWithTtl });

      const result = await service.createChallenge(user.id);

      expect(result.message).toContain(`User ID: ${user.id}`);
      expect(setWithTtl).toHaveBeenCalledWith(
        `auth:challenge:${user.id}`,
        result.message,
        5 * 60,
      );
    });

    it('rejects a user with no owner address registered yet', async () => {
      const findById = jest.fn().mockResolvedValue({ ...user, ownerAddress: null });
      const { service } = buildService({ findById });

      await expect(service.createChallenge(user.id)).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  describe('login', () => {
    it('issues tokens when the signature matches the registered owner address', async () => {
      const message = 'Log in to PayFlex\nUser ID: user-1\nNonce: abc123';
      const getAndDelete = jest.fn().mockResolvedValue(message);
      const refreshTokenCreate = jest.fn();
      const { service } = buildService({ getAndDelete, refreshTokenCreate });
      const signature = await ownerWallet.signMessage(message);

      const result = await service.login(user.id, signature);

      expect(result.accessToken).toEqual(expect.any(String));
      expect(result.refreshToken).toEqual(expect.any(String));
      expect(refreshTokenCreate).toHaveBeenCalledWith(
        expect.objectContaining({ data: expect.objectContaining({ appUserId: user.id }) }),
      );
    });

    it('rejects when there is no pending challenge (none requested, or already consumed)', async () => {
      const getAndDelete = jest.fn().mockResolvedValue(null);
      const { service } = buildService({ getAndDelete });

      await expect(service.login(user.id, '0xdead')).rejects.toBeInstanceOf(UnauthorizedException);
    });

    it('rejects a signature from a different wallet than the registered owner address', async () => {
      const message = 'Log in to PayFlex\nUser ID: user-1\nNonce: abc123';
      const getAndDelete = jest.fn().mockResolvedValue(message);
      const { service } = buildService({ getAndDelete });
      const impostorWallet = Wallet.createRandom();
      const signature = await impostorWallet.signMessage(message);

      await expect(service.login(user.id, signature)).rejects.toBeInstanceOf(UnauthorizedException);
    });

    it('rejects a malformed signature', async () => {
      const message = 'Log in to PayFlex\nUser ID: user-1\nNonce: abc123';
      const getAndDelete = jest.fn().mockResolvedValue(message);
      const { service } = buildService({ getAndDelete });

      await expect(service.login(user.id, 'not-a-signature')).rejects.toBeInstanceOf(
        UnauthorizedException,
      );
    });

    it('rejects a user with no owner address registered yet', async () => {
      const findById = jest.fn().mockResolvedValue({ ...user, ownerAddress: null });
      const { service } = buildService({ findById });

      await expect(service.login(user.id, '0xdead')).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  describe('refresh', () => {
    function signRefresh(tokens: TokenService, appUserId: string) {
      return tokens.signRefreshToken(appUserId);
    }

    it('rotates a valid, non-revoked, non-expired refresh token', async () => {
      // Sign with a throwaway TokenService first purely to get a real
      // (token, jti) pair — JwtService is stateless given a fixed secret,
      // so a token signed here verifies fine against the service under
      // test below, which is built separately with the DB mocks wired in.
      const { token, jti } = signRefresh(new TokenService(new JwtService({ secret: 'test-secret' })), user.id);
      const refreshTokenUpdate = jest.fn();
      const { service } = buildService({
        refreshTokenFindUnique: jest.fn().mockResolvedValue({
          jti,
          appUserId: user.id,
          revoked: false,
          expiresAt: new Date(Date.now() + 60_000),
        }),
        refreshTokenUpdate,
      });

      const result = await service.refresh(token);

      expect(refreshTokenUpdate).toHaveBeenCalledWith({
        where: { jti },
        data: { revoked: true },
      });
      expect(result.accessToken).toEqual(expect.any(String));
      expect(result.refreshToken).toEqual(expect.any(String));
    });

    it('rejects an access-scope token passed as a refresh token', async () => {
      const { service, tokens } = buildService();
      const accessToken = tokens.signAccessToken(user.id, user.bmoniUserId);

      await expect(service.refresh(accessToken)).rejects.toBeInstanceOf(UnauthorizedException);
    });

    it('rejects a refresh token with no matching row on file', async () => {
      const { service, tokens } = buildService({
        refreshTokenFindUnique: jest.fn().mockResolvedValue(null),
      });
      const { token } = signRefresh(tokens, user.id);

      await expect(service.refresh(token)).rejects.toBeInstanceOf(UnauthorizedException);
    });

    it('rejects a revoked refresh token (already rotated once, replay attempt)', async () => {
      const { service, tokens } = buildService({
        refreshTokenFindUnique: jest.fn().mockResolvedValue({
          revoked: true,
          expiresAt: new Date(Date.now() + 60_000),
        }),
      });
      const { token } = signRefresh(tokens, user.id);

      await expect(service.refresh(token)).rejects.toBeInstanceOf(UnauthorizedException);
    });

    it('rejects an expired refresh token row', async () => {
      const { service, tokens } = buildService({
        refreshTokenFindUnique: jest.fn().mockResolvedValue({
          revoked: false,
          expiresAt: new Date(Date.now() - 1000),
        }),
      });
      const { token } = signRefresh(tokens, user.id);

      await expect(service.refresh(token)).rejects.toBeInstanceOf(UnauthorizedException);
    });
  });
});
