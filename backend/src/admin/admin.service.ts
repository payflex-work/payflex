import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

/**
 * Read-only operational visibility into what this build actually has,
 * plus the one piece of real admin authority this app needs today:
 * promoting/demoting another user's admin flag. Deliberately narrow —
 * no user suspension, no KYC override, no data mutation beyond the admin
 * flag itself. Expanding this needs a real product decision, not a guess;
 * see the root README's "Not built" section.
 */
@Injectable()
export class AdminService {
  constructor(private readonly prisma: PrismaService) {}

  async getStats() {
    const [totalUsers, verifiedUsers, fiatCapableUsers, totalAdmins, totalSplitBills, totalLinks, activeStandingPlans] =
      await Promise.all([
        this.prisma.appUser.count(),
        this.prisma.appUser.count({ where: { identityVerified: true } }),
        this.prisma.appUser.count({ where: { fiatCapable: true } }),
        this.prisma.appUser.count({ where: { isAdmin: true } }),
        this.prisma.splitBill.count(),
        this.prisma.linkRecord.count(),
        this.prisma.standingPlan.count({ where: { status: 'ACTIVE' } }),
      ]);

    return {
      totalUsers,
      identityVerifiedUsers: verifiedUsers,
      fiatCapableUsers,
      totalAdmins,
      totalSplitBills,
      totalSendViaLinks: totalLinks,
      activeStandingPlans,
      // Honest architectural note surfaced in the dashboard itself:
      gateStatus: {
        identityVerification: 'NOT CONFIGURED — no KYC provider plugged in (docs/fiat-kyc-gap.md)',
        fiatRails: 'NOT CONFIGURED — no fiat provider plugged in (docs/fiat-kyc-gap.md)',
        identityVerifiedUsers: verifiedUsers,
        fiatCapableUsers,
      },
    };
  }

  async setAdminStatus(targetAppUserId: string, isAdmin: boolean) {
    const target = await this.prisma.appUser.findUnique({ where: { id: targetAppUserId } });
    if (!target) throw new NotFoundException(`No user ${targetAppUserId}.`);
    return this.prisma.appUser.update({ where: { id: targetAppUserId }, data: { isAdmin } });
  }
}
