import { Body, Controller, Post } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { AuthService } from './auth.service';
import { Public } from './public.decorator';
import { ChallengeDto, LoginDto, RefreshDto } from './dto/login.dto';

/**
 * Every route here is public (no access token exists yet at this point in
 * the flow) and reachable pre-auth, so each gets a per-route throttle
 * override tighter than the app-wide default (see app.module.ts) — these
 * are exactly the endpoints someone would hammer to brute-force a
 * challenge/signature or churn through refresh attempts.
 */
@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Public()
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @Post('challenge')
  challenge(@Body() dto: ChallengeDto) {
    return this.auth.createChallenge(dto.appUserId);
  }

  @Public()
  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  @Post('login')
  login(@Body() dto: LoginDto) {
    return this.auth.login(dto.appUserId, dto.signature);
  }

  @Public()
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @Post('refresh')
  refresh(@Body() dto: RefreshDto) {
    return this.auth.refresh(dto.refreshToken);
  }
}
