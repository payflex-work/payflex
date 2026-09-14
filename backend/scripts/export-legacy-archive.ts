/**
 * One-time legacy archive — run BEFORE `prisma migrate deploy` applies the
 * stellar_only migration, which DROPS every table from the previous
 * banking-backed architecture.
 *
 * Writes each table's full contents to JSON files under
 * backend/archive/legacy-<timestamp>/ so no historical record is destroyed:
 * it just leaves the database. See docs/fiat-kyc-gap.md and the migration
 * commit message for the data-retention decision (archive, then drop).
 *
 * Usage: npx ts-node scripts/export-legacy-archive.ts
 */
import { PrismaClient } from '@prisma/client';
import * as fs from 'fs';
import * as path from 'path';

const prisma = new PrismaClient();

// Raw table names — this script runs against the OLD schema (before the
// stellar_only migration drops these tables), where the typed Prisma client
// no longer matches. $queryRawUnsafe keeps it honest and dependency-free.
const LEGACY_TABLES = [
  'AppUser',
  'SmartWallet',
  'WebhookEvent',
  'KycProfile',
  'RailOnboarding',
  'PayTag',
  'TransferProposal',
  'SavingsGoal',
  'SavingsContribution',
  'LoanApplication',
  'LoanRepayment',
  'StandingPlan',
  'StandingPlanPayment',
  'AgentTransaction',
  'SplitBill',
  'SplitBillContributor',
  'ClaimableLink',
  'safeboxes',
  'safebox_members',
  'safebox_transactions',
];

async function main() {
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const dir = path.join(__dirname, '..', 'archive', `legacy-${stamp}`);
  fs.mkdirSync(dir, { recursive: true });

  const summary: Record<string, number> = {};
  for (const table of LEGACY_TABLES) {
    try {
      const rows = (await prisma.$queryRawUnsafe(`SELECT * FROM "${table}"`)) as unknown[];
      fs.writeFileSync(path.join(dir, `${table}.json`), JSON.stringify(rows, (k, v) => (typeof v === 'bigint' ? v.toString() : v), 2));
      summary[table] = rows.length;
    } catch {
      // Table may not exist (fresh database, or already migrated away).
      summary[table] = 0;
    }
  }

  fs.writeFileSync(
    path.join(dir, 'README.md'),
    [
      '# Legacy PayFlex data archive (pre Stellar-only migration)',
      '',
      `Exported: ${new Date().toISOString()}`,
      '',
      'These tables belonged to the previous banking-backed architecture, which has been',
      'removed entirely. The rows were exported here (not deleted) before the',
      '`stellar_only` Prisma migration dropped the tables. Nothing in the live',
      'application reads this archive — it exists purely as a historical record.',
      '',
      JSON.stringify(summary, null, 2),
    ].join('\n'),
  );

  console.log('Legacy archive written to:', dir);
  console.log(JSON.stringify(summary, null, 2));
}

main()
  .catch((e) => {
    console.error(e);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
