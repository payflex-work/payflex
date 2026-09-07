import { BadRequestException, Injectable, UnauthorizedException } from '@nestjs/common';
import { verifyMessage } from 'ethers';
import { randomBytes } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import { TokenService } from '../token/token.service';
import { UsersService } from '../users/users.service';

const CHALLENGE_TTL_SECONDS = 5 * 60;

/**
 * Login proves ownership of the same on-device EVM key BMONI's
 * owner-proof-challenge already relies on — no separate password/OTP
 * system to build or store. The app already has `WalletService.
 * signChallenge` wired up for that exact EIP-191 personal_sign shape
 * (see app/lib/services/wallet_service.dart), so logging in from the app
 * is one more call to a method it already has, not a new capability.
 */
@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly tokens: TokenService,
    private readonly users: UsersService,
  ) {}

  async createChallenge(appUserId: string): Promise<{ message: string }> {
    const user = await this.users.findById(appUserId);
    if (!user.ownerAddress) {
      throw new BadRequestException(
        `User ${appUserId} has no owner address registered yet — set one via ` +
          `PATCH /users/${appUserId}/owner-address (using the bootstrap token from account ` +
          `creation) before logging in.`,
      );
    }
    const nonce = randomBytes(16).toString('hex');
    const message = `Log in to PayFlex\nUser ID: ${appUserId}\nNonce: ${nonce}`;
    await this.redis.setWithTtl(this.challengeKey(appUserId), message, CHALLENGE_TTL_SECONDS);
    return { message };
  }

  async login(appUserId: string, signature: string) {
    const user = await this.users.findById(appUserId);
    if (!user.ownerAddress) {
      throw new BadRequestException(`User ${appUserId} has no owner address registered yet.`);
    }

    const message = await this.redis.getAndDelete(this.challengeKey(appUserId));
    if (!message) {
      throw new UnauthorizedException('No pending login challenge — request a new one.');
    }

    let recovered: string;
    try {
      recovered = verifyMessage(message, signature);
    } catch {
      throw new UnauthorizedException('Malformed signature.');
    }
    if (recovered.toLowerCase() !== user.ownerAddress.toLowerCase()) {
      throw new UnauthorizedException("Signature doesn't match this user's registered owner address.");
    }

    return this.issueTokens(user.id, user.bmoniUserId);
  }

  async refresh(refreshToken: string) {
    const payload = this.tokens.verify(refreshToken);
    if (payload.scope !== 'refresh' || !payload.jti) {
      throw new UnauthorizedException('Not a refresh token.');
    }

    const stored = await this.prisma.refreshToken.findUnique({ where: { jti: payload.jti } });
    if (!stored || stored.revoked || stored.expiresAt.getTime() < Date.now()) {
      throw new UnauthorizedException('Refresh token is invalid, revoked, or expired.');
    }

    const user = await this.users.findById(payload.sub);
    // Rotate: the old refresh token is single-use, so a stolen-and-replayed
    // one stops working the moment the legitimate client refreshes first.
    await this.prisma.refreshToken.update({ where: { jti: payload.jti }, data: { revoked: true } });

    return this.issueTokens(user.id, user.bmoniUserId);
  }

  private async issueTokens(appUserId: string, bmoniUserId: string) {
    const accessToken = this.tokens.signAccessToken(appUserId, bmoniUserId);
    const { token: refreshToken, jti } = this.tokens.signRefreshToken(appUserId);
    await this.prisma.refreshToken.create({
      data: {
        appUserId,
        jti,
        expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
      },
    });
    return { accessToken, refreshToken };
  }

  private challengeKey(appUserId: string): string {
    return `auth:challenge:${appUserId}`;
  }
}
