-- Replace the Redis-backed login-challenge store with Postgres (a single
-- Neon database in deployment): a challenge is short-TTL, single-use state
-- and Postgres serves it fine. This removes the last Redis dependency from
-- the system — see src/auth/auth.service.ts for the consume semantics.

CREATE TABLE "LoginChallenge" (
    "id" TEXT NOT NULL,
    "appUserId" TEXT NOT NULL,
    "message" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "LoginChallenge_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "LoginChallenge_appUserId_key" ON "LoginChallenge"("appUserId");

-- AddForeignKey
ALTER TABLE "LoginChallenge" ADD CONSTRAINT "LoginChallenge_appUserId_fkey" FOREIGN KEY ("appUserId") REFERENCES "AppUser"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
