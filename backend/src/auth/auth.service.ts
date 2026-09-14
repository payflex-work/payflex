import { BadRequestException, Injectable, UnauthorizedException } from '@nestjs/common';
import { Keypair } from '@stellar/stellar-sdk';
import { randomBytes } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { TokenService } from '../token/token.service';
import { UsersService } from '../users/users.service';

const CHALLENGE_TTL_SECONDS = 5 * 60;

/**
 * Login proves ownership of the user's on-device Stellar keypair — the same
 * key that signs every payment — so there is no separate password/OTP
 * system to build or store. The challenge is a plain string; the app signs
 * it with the device's Stellar secret seed (StellarKeyService) and the
 * backend verifies the Ed25519 signature against the registered public key.
 *
 * Challenges live in Postgres (LoginChallenge), not Redis — one managed
 * database serves the whole backend. A challenge is short-TTL, single-use
 * state: appUserId is unique so at most one pending challenge exists per
 * user, requesting a new one replaces the old, and consumption is an
 * atomic conditional DELETE whose affected-row count is the single-use
 * gate — exactly one login can ever consume a challenge, even under
 * concurrent attempts.
 */
@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly tokens: TokenService,
    private readonly users: UsersService,
  ) {}

  async createChallenge(appUserId: string): Promise<{ message: string }> {
    const user = await this.users.findById(appUserId);
    if (!user.stellarPublicKey) {
      throw new BadRequestException(
        `User ${appUserId} has no Stellar public key registered yet — set one via ` +
          `PATCH /users/${appUserId}/stellar-public-key (using the bootstrap token from account ` +
          `creation) before logging in.`,
      );
    }
    const nonce = randomBytes(16).toString('hex');
    const message = `Log in to PayFlex\nUser ID: ${appUserId}\nNonce: ${nonce}`;
    const expiresAt = new Date(Date.now() + CHALLENGE_TTL_SECONDS * 1000);
    // Upsert: a fresh request always supersedes any pending challenge.
    await this.prisma.loginChallenge.upsert({
      where: { appUserId },
      create: { appUserId, message, expiresAt },
      update: { message, expiresAt },
    });
    return { message };
  }

  async login(appUserId: string, signatureHex: string) {
    const user = await this.users.findById(appUserId);
    if (!user.stellarPublicKey) {
      throw new BadRequestException(`User ${appUserId} has no Stellar public key registered yet.`);
    }

    const pending = await this.prisma.loginChallenge.findUnique({ where: { appUserId } });
    if (!pending || pending.expiresAt.getTime() < Date.now()) {
      // Same semantics as the former Redis TTL: an expired challenge is an
      // absent challenge.
      if (pending) {
        await this.prisma.loginChallenge.delete({ where: { appUserId } }).catch(() => undefined);
      }
      throw new UnauthorizedException('No pending login challenge — request a new one.');
    }

    let keypair: Keypair;
    try {
      keypair = Keypair.fromPublicKey(user.stellarPublicKey);
    } catch {
      throw new UnauthorizedException("Registered public key is malformed — account is unrecoverable as configured.");
    }

    const signatureOk = (() => {
      try {
        return keypair.verify(Buffer.from(pending.message, 'utf8'), Buffer.from(signatureHex, 'hex'));
      } catch {
        return false;
      }
    })();
    if (!signatureOk) {
      throw new UnauthorizedException("Signature doesn't match this user's registered Stellar public key.");
    }

    // Single-use gate: the conditional delete is atomic — under concurrent
    // logins exactly one caller observes count === 1; everyone else gets
    // rejected as if the challenge never existed.
    const consumed = await this.prisma.loginChallenge.deleteMany({
      where: { appUserId, expiresAt: { gt: new Date() } },
    });
    if (consumed.count === 0) {
      throw new UnauthorizedException('No pending login challenge — request a new one.');
    }

    return this.issueTokens(user.id, user.stellarPublicKey);
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

    return this.issueTokens(user.id, user.stellarPublicKey!);
  }

  private async issueTokens(appUserId: string, stellarPublicKey: string) {
    const accessToken = this.tokens.signAccessToken(appUserId, stellarPublicKey);
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
}
