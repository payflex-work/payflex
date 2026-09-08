-- CreateEnum
CREATE TYPE "SafeboxMemberRole" AS ENUM ('OWNER', 'ADMIN', 'MEMBER');

-- CreateEnum
CREATE TYPE "SafeboxStatus" AS ENUM ('ACTIVE', 'CLOSED');

-- CreateEnum
CREATE TYPE "SafeboxTransactionType" AS ENUM ('CONTRIBUTION', 'WITHDRAWAL');

-- CreateEnum
CREATE TYPE "SafeboxTransactionStatus" AS ENUM ('PENDING', 'COMPLETED', 'FAILED');

-- CreateTable
CREATE TABLE "safeboxes" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "ownerId" TEXT NOT NULL,
    "targetAmount" DOUBLE PRECISION,
    "currentBalance" DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    "status" "SafeboxStatus" NOT NULL DEFAULT 'ACTIVE',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "safeboxes_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "safebox_members" (
    "id" TEXT NOT NULL,
    "safeboxId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "role" "SafeboxMemberRole" NOT NULL DEFAULT 'MEMBER',
    "joinedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "safebox_members_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "safebox_transactions" (
    "id" TEXT NOT NULL,
    "safeboxId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "type" "SafeboxTransactionType" NOT NULL,
    "amount" DOUBLE PRECISION NOT NULL,
    "note" TEXT,
    "status" "SafeboxTransactionStatus" NOT NULL DEFAULT 'COMPLETED',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "safebox_transactions_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "safebox_members_safeboxId_userId_key" ON "safebox_members"("safeboxId", "userId");

-- AddForeignKey
ALTER TABLE "safeboxes" ADD CONSTRAINT "safeboxes_ownerId_fkey" FOREIGN KEY ("ownerId") REFERENCES "AppUser"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "safebox_members" ADD CONSTRAINT "safebox_members_userId_fkey" FOREIGN KEY ("userId") REFERENCES "AppUser"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "safebox_members" ADD CONSTRAINT "safebox_members_safeboxId_fkey" FOREIGN KEY ("safeboxId") REFERENCES "safeboxes"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "safebox_transactions" ADD CONSTRAINT "safebox_transactions_userId_fkey" FOREIGN KEY ("userId") REFERENCES "AppUser"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "safebox_transactions" ADD CONSTRAINT "safebox_transactions_safeboxId_fkey" FOREIGN KEY ("safeboxId") REFERENCES "safeboxes"("id") ON DELETE CASCADE ON UPDATE CASCADE;
