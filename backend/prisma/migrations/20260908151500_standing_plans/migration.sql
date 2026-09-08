-- CreateTable
CREATE TABLE "StandingPlan" (
    "id" TEXT NOT NULL,
    "appUserId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "currency" TEXT NOT NULL,
    "amount" TEXT NOT NULL,
    "frequency" TEXT NOT NULL,
    "toBmoniUserId" TEXT,
    "toPayTag" TEXT,
    "description" TEXT,
    "nextPaymentAt" TIMESTAMP(3) NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'ACTIVE',
    "totalPaid" TEXT NOT NULL DEFAULT '0',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "StandingPlan_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "StandingPlanPayment" (
    "id" TEXT NOT NULL,
    "standingPlanId" TEXT NOT NULL,
    "amount" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'DUE',
    "bmoniProposalId" TEXT,
    "dueAt" TIMESTAMP(3) NOT NULL,
    "completedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "StandingPlanPayment_pkey" PRIMARY KEY ("id")
);

-- AddForeignKey
ALTER TABLE "StandingPlan" ADD CONSTRAINT "StandingPlan_appUserId_fkey" FOREIGN KEY ("appUserId") REFERENCES "AppUser"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "StandingPlanPayment" ADD CONSTRAINT "StandingPlanPayment_standingPlanId_fkey" FOREIGN KEY ("standingPlanId") REFERENCES "StandingPlan"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
