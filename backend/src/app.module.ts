import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ScheduleModule } from '@nestjs/schedule';
import { ThrottlerModule, ThrottlerGuard } from '@nestjs/throttler';
import { APP_GUARD } from '@nestjs/core';
import stellarConfig from './config/stellar.config';
import { CommonModule } from './common/common.module';
import { PrismaModule } from './prisma/prisma.module';
import { RedisModule } from './redis/redis.module';
import { TokenModule } from './token/token.module';
import { AuthModule } from './auth/auth.module';
import { AuthGuard } from './auth/auth.guard';
import { UsersModule } from './users/users.module';
import { OnboardingModule } from './onboarding/onboarding.module';
import { ProvidersModule } from './providers/providers.module';
import { GatedModule } from './gated/gated.module';
import { TransferModule } from './transfer/transfer.module';
import { SplitBillModule } from './split-bill/split-bill.module';
import { LinksModule } from './links/links.module';
import { SafeboxModule } from './safebox/safebox.module';
import { AdminModule } from './admin/admin.module';
import { StandingPlansModule } from './standing-plans/standing-plans.module';
import { StellarModule } from './stellar/stellar.module';
import { HealthController } from './health/health.controller';

/**
 * PayFlex backend — Stellar-only architecture. There is no banking-layer
 * module, no KYC module, and no fiat/payments/treasury module: none exists
 * in this build. The fiat/KYC plug-in gap is represented honestly by
 * ProvidersModule (interfaces + hard gate) and GatedModule (paused
 * endpoints that fail closed). See docs/fiat-kyc-gap.md.
 */
@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, load: [stellarConfig] }),
    ScheduleModule.forRoot(),
    // Global default: 60 requests/min per IP, generous enough for normal
    // polling (onboarding status, balances) — stricter per-route limits
    // (see AuthController) override this for brute-forceable endpoints
    // like /auth/challenge and /auth/login.
    ThrottlerModule.forRoot([{ ttl: 60_000, limit: 60 }]),
    CommonModule,
    PrismaModule,
    RedisModule,
    TokenModule,
    AuthModule,
    UsersModule,
    OnboardingModule,
    ProvidersModule,
    GatedModule,
    StellarModule,
    TransferModule,
    SplitBillModule,
    LinksModule,
    SafeboxModule,
    AdminModule,
    StandingPlansModule,
  ],
  controllers: [HealthController],
  providers: [{ provide: APP_GUARD, useClass: AuthGuard }],
})
export class AppModule {}
