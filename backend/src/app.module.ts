import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ScheduleModule } from '@nestjs/schedule';
import { ThrottlerModule, ThrottlerGuard } from '@nestjs/throttler';
import { APP_GUARD } from '@nestjs/core';
import bmoniConfig from './config/bmoni.config';
import { CommonModule } from './common/common.module';
import { PrismaModule } from './prisma/prisma.module';
import { RedisModule } from './redis/redis.module';
import { TokenModule } from './token/token.module';
import { AuthModule } from './auth/auth.module';
import { AuthGuard } from './auth/auth.guard';
import { BmoniModule } from './bmoni/bmoni.module';
import { UsersModule } from './users/users.module';
import { OnboardingModule } from './onboarding/onboarding.module';
import { WebhooksModule } from './webhooks/webhooks.module';
import { KycModule } from './kyc/kyc.module';
import { WalletModule } from './wallet/wallet.module';
import { TransferModule } from './transfer/transfer.module';
import { PaymentsModule } from './payments/payments.module';
import { TreasuryModule } from './treasury/treasury.module';
import { SavingsModule } from './savings/savings.module';
import { LoansModule } from './loans/loans.module';
import { AgentModule } from './agent/agent.module';
import { SplitBillModule } from './split-bill/split-bill.module';
import { LinksModule } from './links/links.module';
import { SafeboxModule } from './safebox/safebox.module';
import { AdminModule } from './admin/admin.module';
import { StandingPlansModule } from './standing-plans/standing-plans.module';
import { StellarModule } from './stellar/stellar.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, load: [bmoniConfig] }),
    ScheduleModule.forRoot(),
    // Global default: 60 requests/min per IP, generous enough for normal
    // polling (onboarding status, wallet balances) — stricter per-route
    // limits (see AuthController) override this for brute-forceable
    // endpoints like /auth/challenge and /auth/login.
    ThrottlerModule.forRoot([{ ttl: 60_000, limit: 60 }]),
    CommonModule,
    PrismaModule,
    RedisModule,
    TokenModule,
    AuthModule,
    BmoniModule,
    UsersModule,
    OnboardingModule,
    WebhooksModule,
    KycModule,
    WalletModule,
    TransferModule,
    PaymentsModule,
    TreasuryModule,
    SavingsModule,
    LoansModule,
    AgentModule,
    SplitBillModule,
    LinksModule,
    SafeboxModule,
    AdminModule,
    StandingPlansModule,
    StellarModule,
  ],
  providers: [
    // Order matters: throttling runs before auth so a flood of requests
    // gets rate-limited before reaching AuthGuard's logic at all.
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    { provide: APP_GUARD, useClass: AuthGuard },
  ],
})
export class AppModule {}
