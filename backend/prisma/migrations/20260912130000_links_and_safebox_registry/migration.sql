-- Additive: non-custodial send-via-link records (on-chain claimable
-- balances; the backend only registers/verifies) and the Safebox Soroban
-- contract registry (chain is the source of truth; this is product metadata).

CREATE TABLE "LinkRecord" (
    "id" TEXT NOT NULL,
    "senderAppUserId" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "claimableBalanceId" TEXT,
    "amount" TEXT NOT NULL,
    "assetCode" TEXT NOT NULL,
    "assetIssuer" TEXT,
    "status" TEXT NOT NULL DEFAULT 'PENDING_CB',
    "claimedByAppUserId" TEXT,
    "claimedAt" TIMESTAMP(3),
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "LinkRecord_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "SafeboxRegistry" (
    "id" TEXT NOT NULL,
    "contractId" TEXT NOT NULL,
    "ownerPublicKey" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "kind" TEXT NOT NULL DEFAULT 'SAFEBOX',
    "closed" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SafeboxRegistry_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "LinkRecord_tokenHash_key" ON "LinkRecord"("tokenHash");
CREATE UNIQUE INDEX "LinkRecord_claimableBalanceId_key" ON "LinkRecord"("claimableBalanceId");
CREATE UNIQUE INDEX "SafeboxRegistry_contractId_key" ON "SafeboxRegistry"("contractId");

ALTER TABLE "LinkRecord" ADD CONSTRAINT "LinkRecord_senderAppUserId_fkey" FOREIGN KEY ("senderAppUserId") REFERENCES "AppUser"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "LinkRecord" ADD CONSTRAINT "LinkRecord_claimedByAppUserId_fkey" FOREIGN KEY ("claimedByAppUserId") REFERENCES "AppUser"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
