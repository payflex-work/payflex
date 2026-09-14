import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { randomUUID } from 'crypto';

export type TokenScope = 'bootstrap' | 'access' | 'refresh';

export interface TokenPayload {
  sub: string; // appUserId
  scope: TokenScope;
  stellarPublicKey?: string; // present on access tokens only
  jti?: string; // present on refresh tokens only, for revocation lookups
}

/**
 * Pure JWT signing/verification — deliberately has no dependency on
 * UsersService or the database, so both AuthModule (which does need
 * UsersService, to look up the Stellar public key during login) and
 * UsersModule (which needs to mint a bootstrap token right after creating a
 * user) can depend on this without a circular module import between them.
 */
@Injectable()
export class TokenService {
  constructor(private readonly jwt: JwtService) {}

  /**
   * Issued once, immediately after account creation, before the app has
   * registered a Stellar public key (so the real challenge/signature login
   * isn't possible yet) or logged in at all. Scoped to exactly one use —
   * AuthGuard only accepts a bootstrap token on
   * PATCH /users/:id/stellar-public-key, nothing else — and expires in 10
   * minutes. See AuthGuard's doc comment for the residual-risk tradeoff
   * this accepts.
   */
  signBootstrapToken(appUserId: string): string {
    return this.jwt.sign({ sub: appUserId, scope: 'bootstrap' }, { expiresIn: '10m' });
  }

  signAccessToken(appUserId: string, stellarPublicKey: string): string {
    return this.jwt.sign(
      { sub: appUserId, stellarPublicKey, scope: 'access' },
      { expiresIn: '2h' },
    );
  }

  signRefreshToken(appUserId: string): { token: string; jti: string } {
    const jti = randomUUID();
    const token = this.jwt.sign({ sub: appUserId, scope: 'refresh', jti }, { expiresIn: '30d' });
    return { token, jti };
  }

  /** Verifies signature + expiry; throws UnauthorizedException on any failure. */
  verify(token: string): TokenPayload {
    try {
      return this.jwt.verify(token);
    } catch {
      throw new UnauthorizedException('Token is invalid or expired.');
    }
  }
}
