import { ForbiddenException, Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

/**
 * The architecture-level hard gate (see docs/fiat-kyc-gap.md).
 *
 * AppUser.identityVerified and AppUser.fiatCapable default to false and NO
 * code path in this repository sets them true. Every endpoint that would
 * require real identity verification or real fiat movement MUST call the
 * corresponding require* method here BEFORE doing anything else, and MUST
 * fail with an honest, actionable message. Silent degradation ("just skip
 * the check") is the exact failure mode this gate exists to prevent.
 */
@Injectable()
export class HardGateService {
  constructor(private readonly prisma: PrismaService) {}

  /** Throws unless a real IIdentityVerificationProvider has verified the
   * user — which nothing in this build can do. */
  async requireIdentityVerified(appUserId: string): Promise<void> {
    const user = await this.prisma.appUser.findUnique({
      where: { id: appUserId },
      select: { identityVerified: true },
    });
    if (!user?.identityVerified) {
      throw new ForbiddenException(
        'This feature requires verified identity. Identity verification is not yet ' +
          'configured in PayFlex — no KYC provider is plugged in, so nobody can pass ' +
          'this gate yet. See docs/fiat-kyc-gap.md.',
      );
    }
  }

  /** Throws unless a real IFiatRailProvider has made the user fiat-capable —
   * which nothing in this build can do. */
  async requireFiatCapable(appUserId: string): Promise<void> {
    const user = await this.prisma.appUser.findUnique({
      where: { id: appUserId },
      select: { fiatCapable: true },
    });
    if (!user?.fiatCapable) {
      throw new ForbiddenException(
        'This feature moves real fiat money. Fiat rails are not yet configured in ' +
          'PayFlex — no fiat provider is plugged in, so this feature is unavailable ' +
          'to everyone. See docs/fiat-kyc-gap.md.',
      );
    }
  }

  /** Convenience for endpoints gated on both (e.g. agent cash-in/out:
   * physical cash + verified identity). */
  async requireVerifiedAndFiatCapable(appUserId: string): Promise<void> {
    await this.requireIdentityVerified(appUserId);
    await this.requireFiatCapable(appUserId);
  }
}
