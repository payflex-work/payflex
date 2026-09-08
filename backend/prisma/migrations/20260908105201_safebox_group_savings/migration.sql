-- CreateTable
CREATE TABLE "Safebox" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "currency" TEXT NOT NULL,
    "targetAmount" TEXT,
    "currentBalance" TEXT NOT NULL DEFAULT '0',
    "status" TEXT NOT NULL DEFAULT 'ACTIVE',
    "ownerAppUserId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Safebox_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SafeboxMember" (
    "id" TEXT NOT NULL,
    "safeboxId" TEXT NOT NULL,
    "appUserId" TEXT NOT NULL,
    "role" TEXT NOT NULL DEFAULT 'MEMBER',
    "joinedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SafeboxMember_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SafeboxTransaction" (
    "id" TEXT NOT NULL,
    "safeboxId" TEXT NOT NULL,
    "appUserId" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "amount" TEXT NOT NULL,
    "note" TEXT,
    "status" TEXT NOT NULL DEFAULT 'PROPOSED',
    "bmoniProposalId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SafeboxTransaction_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "SafeboxMember_safeboxId_appUserId_key" ON "SafeboxMember"("safeboxId", "appUserId");

-- AddForeignKey
ALTER TABLE "Safebox" ADD CONSTRAINT "Safebox_ownerAppUserId_fkey" FOREIGN KEY ("ownerAppUserId") REFERENCES "AppUser"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SafeboxMember" ADD CONSTRAINT "SafeboxMember_safeboxId_fkey" FOREIGN KEY ("safeboxId") REFERENCES "Safebox"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SafeboxMember" ADD CONSTRAINT "SafeboxMember_appUserId_fkey" FOREIGN KEY ("appUserId") REFERENCES "AppUser"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SafeboxTransaction" ADD CONSTRAINT "SafeboxTransaction_safeboxId_fkey" FOREIGN KEY ("safeboxId") REFERENCES "Safebox"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SafeboxTransaction" ADD CONSTRAINT "SafeboxTransaction_appUserId_fkey" FOREIGN KEY ("appUserId") REFERENCES "AppUser"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
