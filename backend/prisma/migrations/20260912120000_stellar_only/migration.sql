-- Stellar-only migration. Drops every BMONI-era table (after
-- scripts/export-legacy-archive.ts archived their contents to
-- backend/archive/legacy-*/), re-keys identity to Stellar public keys, adds
-- the identityVerified/fiatCapable hard-gate flags, and creates
-- TransferRecord (the app's own record of confirmed on-chain payments).
-- Hand-corrected from `prisma migrate diff` output: the diff missed the
-- mapped safebox_* tables and tried to recreate StandingPlan, which already
-- exists — here it is ALTERed in place with a data-preserving backfill.

-- DropForeignKey
ALTER TABLE "AgentTransaction" DROP CONSTRAINT "AgentTransaction_agentAppUserId_fkey";

-- DropForeignKey
ALTER TABLE "AgentTransaction" DROP CONSTRAINT "AgentTransaction_customerAppUserId_fkey";

-- DropForeignKey
ALTER TABLE "ClaimableLink" DROP CONSTRAINT "ClaimableLink_claimedByAppUserId_fkey";

-- DropForeignKey
ALTER TABLE "ClaimableLink" DROP CONSTRAINT "ClaimableLink_senderAppUserId_fkey";

-- DropForeignKey
ALTER TABLE "KycProfile" DROP CONSTRAINT "KycProfile_appUserId_fkey";

-- DropForeignKey
ALTER TABLE "LoanApplication" DROP CONSTRAINT "LoanApplication_appUserId_fkey";

-- DropForeignKey
ALTER TABLE "LoanRepayment" DROP CONSTRAINT "LoanRepayment_loanApplicationId_fkey";

-- DropForeignKey
ALTER TABLE "RailOnboarding" DROP CONSTRAINT "RailOnboarding_appUserId_fkey";

-- DropForeignKey
ALTER TABLE "SavingsContribution" DROP CONSTRAINT "SavingsContribution_savingsGoalId_fkey";

-- DropForeignKey
ALTER TABLE "SavingsGoal" DROP CONSTRAINT "SavingsGoal_appUserId_fkey";

-- DropForeignKey
ALTER TABLE "SmartWallet" DROP CONSTRAINT "SmartWallet_appUserId_fkey";

-- DropForeignKey
ALTER TABLE "TransferProposal" DROP CONSTRAINT "TransferProposal_appUserId_fkey";

-- DropForeignKey
ALTER TABLE "WebhookEvent" DROP CONSTRAINT "WebhookEvent_appUserId_fkey";

-- DropIndex
DROP INDEX "AppUser_bmoniUserId_key";

-- AlterTable: identity re-keyed to Stellar; hard-gate flags default false
-- and stay false until a real provider is plugged in (docs/fiat-kyc-gap.md)
ALTER TABLE "AppUser" DROP COLUMN "bmoniUserId",
DROP COLUMN "ownerAddress",
ADD COLUMN     "fiatCapable" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "identityVerified" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "stellarAccountActivated" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "stellarPublicKey" TEXT;

-- AlterTable: SplitBill currency -> assetCode (backfill for existing rows)
ALTER TABLE "SplitBill" ADD COLUMN "assetCode" TEXT;
UPDATE "SplitBill" SET "assetCode" = "currency";
ALTER TABLE "SplitBill" ALTER COLUMN "assetCode" SET NOT NULL;
ALTER TABLE "SplitBill" DROP COLUMN "currency";

-- AlterTable: SplitBillContributor records the on-chain payment directly
ALTER TABLE "SplitBillContributor" DROP COLUMN "bmoniProposalId",
ADD COLUMN     "stellarTxHash" TEXT;

-- AlterTable: StandingPlan re-pointed at Stellar recipients
ALTER TABLE "StandingPlan" ADD COLUMN "assetCode" TEXT;
UPDATE "StandingPlan" SET "assetCode" = "currency";
ALTER TABLE "StandingPlan" ALTER COLUMN "assetCode" SET NOT NULL;
ALTER TABLE "StandingPlan" ADD COLUMN "assetIssuer" TEXT;
ALTER TABLE "StandingPlan" DROP COLUMN "toBmoniUserId",
ADD COLUMN     "toPublicKey" TEXT,
DROP COLUMN     "currency";

-- AlterTable: StandingPlanPayment records the on-chain payment directly
ALTER TABLE "StandingPlanPayment" DROP COLUMN "bmoniProposalId",
ADD COLUMN     "stellarTxHash" TEXT;

-- DropTable: Safebox app-level ledger (replaced by the Soroban contract +
-- backend/src/safebox-soroban indexer view); child tables first
DROP TABLE "safebox_transactions";
DROP TABLE "safebox_members";
DROP TABLE "safeboxes";

-- DropTable: BMONI-era tables
DROP TABLE "AgentTransaction";
DROP TABLE "ClaimableLink";
DROP TABLE "KycProfile";
DROP TABLE "LoanApplication";
DROP TABLE "LoanRepayment";
DROP TABLE "RailOnboarding";
DROP TABLE "SavingsContribution";
DROP TABLE "SavingsGoal";
DROP TABLE "SmartWallet";
DROP TABLE "TransferProposal";
DROP TABLE "WebhookEvent";

-- CreateTable: PayFlex's own record of confirmed on-chain payments
-- (Horizon remains the balance/transaction source of truth)
CREATE TABLE "TransferRecord" (
    "id" TEXT NOT NULL,
    "appUserId" TEXT NOT NULL,
    "stellarTxHash" TEXT NOT NULL,
    "fromPublicKey" TEXT NOT NULL,
    "toPublicKey" TEXT NOT NULL,
    "amount" TEXT NOT NULL,
    "assetCode" TEXT NOT NULL,
    "assetIssuer" TEXT,
    "kind" TEXT NOT NULL DEFAULT 'TRANSFER',
    "qrTokenRef" TEXT,
    "splitBillId" TEXT,
    "standingPlanId" TEXT,
    "offlineAuthorizationId" TEXT,
    "memo" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "TransferRecord_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "TransferRecord_stellarTxHash_key" ON "TransferRecord"("stellarTxHash");

-- CreateIndex
CREATE INDEX "TransferRecord_appUserId_createdAt_idx" ON "TransferRecord"("appUserId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "AppUser_stellarPublicKey_key" ON "AppUser"("stellarPublicKey");

-- AddForeignKey (StandingPlan/SplitBill* FKs to AppUser already exist)
ALTER TABLE "TransferRecord" ADD CONSTRAINT "TransferRecord_appUserId_fkey" FOREIGN KEY ("appUserId") REFERENCES "AppUser"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
