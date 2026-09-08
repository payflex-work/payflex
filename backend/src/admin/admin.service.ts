import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

/**
 * Read-only operational visibility into what this build actually has,
 * plus the one piece of real admin authority this app needs today:
 * promoting/demoting another user's admin flag. Deliberately narrow —
 * no user suspension, no KYC override, no data mutation beyond the admin
 * flag itself. Expanding this needs a real product decision, not a
 * guess; see the root README's "Not built" section.
 */
@Injectable()
export class AdminService {
  constructor(private readonly prisma: PrismaService) {}

  async getStats() {
    const [
      totalUsers,
      totalAgents,
      totalAdmins,
      totalSafeboxes,
      loansByStatus,
      totalSavingsGoals,
      totalSplitBills,
      totalClaimableLinks,
      totalAgentTransactions,
    ] = await Promise.all([
      this.prisma.appUser.count(),
      this.prisma.appUser.count({ where: { isAgent: true } }),
      this.prisma.appUser.count({ where: { isAdmin: true } }),
      this.prisma.safebox.count(),
      this.prisma.loanApplication.groupBy({ by: ['status'], _count: true }),
      this.prisma.savingsGoal.count(),
      this.prisma.splitBill.count(),
      this.prisma.claimableLink.count({ where: { status: 'ESCROWED' } }),
      this.prisma.agentTransaction.count(),
    ]);

    return {
      totalUsers,
      totalAgents,
      totalAdmins,
      totalSafeboxes,
      loansByStatus: Object.fromEntries(loansByStatus.map((row) => [row.status, row._count])),
      totalSavingsGoals,
      totalSplitBills,
      pendingEscrowedLinks: totalClaimableLinks,
      totalAgentTransactions,
    };
  }

  async setAdminStatus(targetAppUserId: string, isAdmin: boolean) {
    const target = await this.prisma.appUser.findUnique({ where: { id: targetAppUserId } });
    if (!target) throw new NotFoundException(`No user ${targetAppUserId}.`);
    return this.prisma.appUser.update({ where: { id: targetAppUserId }, data: { isAdmin } });
  }
}
