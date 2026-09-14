import { Body, Controller, Param, Post } from '@nestjs/common';
import { IsOptional, IsString } from 'class-validator';
import { HardGateService } from '../providers/hard-gate.service';

class AgentStatusDto {
  @IsString()
  enabled!: string; // "true"/"false" — kept a string to keep the DTO trivial

  @IsOptional()
  @IsString()
  location?: string;
}

class FiatAmountDto {
  @IsString()
  amount!: string;

  @IsString()
  assetCode!: string;

  @IsOptional()
  @IsString()
  assetIssuer?: string;

  @IsOptional()
  @IsString()
  destination?: string;
}

/**
 * GATED FEATURE ENDPOINTS — reachable on purpose, blocked by the hard gate
 * (see docs/fiat-kyc-gap.md). These exist so that:
 *
 *  1. The gate is REAL and testable (a test can call these endpoints and
 *     prove they refuse), not just a missing screen in the app.
 *  2. When a real IIdentityVerificationProvider / IFiatRailProvider is
 *     plugged in later, the wiring already has its home — the endpoints
 *     flip from "always refused" to "calls the real provider" without a
 *     new API surface.
 *
 * None of these may do ANY work before HardGateService approves — and the
 * gate cannot approve, because no code path in this repository can set
 * identityVerified/fiatCapable true. That is the architecture-level
 * guarantee; it is not a TODO left to future discipline.
 */
@Controller()
export class GatedController {
  constructor(private readonly gate: HardGateService) {}

  /** Agent cash-in/cash-out: physical cash handling → needs verified identity AND a fiat rail. */
  @Post('users/:id/agent/status')
  async setAgentStatus(@Param('id') id: string, @Body() _dto: AgentStatusDto) {
    await this.gate.requireVerifiedAndFiatCapable(id);
    throw new Error('unreachable while the gate is closed');
  }

  /** Fiat deposit (off-ramp in) → needs a real IFiatRailProvider. */
  @Post('users/:id/fiat/deposits')
  async deposit(@Param('id') id: string, @Body() _dto: FiatAmountDto) {
    await this.gate.requireFiatCapable(id);
    throw new Error('unreachable while the gate is closed');
  }

  /** Fiat withdrawal (off-ramp out) → needs a real IFiatRailProvider. */
  @Post('users/:id/fiat/withdrawals')
  async withdraw(@Param('id') id: string, @Body() _dto: FiatAmountDto) {
    await this.gate.requireFiatCapable(id);
    throw new Error('unreachable while the gate is closed');
  }

  /** Virtual card issuance → needs a card-issuing partner (Stellar cannot issue cards). */
  @Post('users/:id/cards')
  async issueCard(@Param('id') id: string) {
    await this.gate.requireVerifiedAndFiatCapable(id);
    throw new Error('unreachable while the gate is closed');
  }

  /** Licensed betting provider funding → fiat movement to licensed operators. */
  @Post('users/:id/betting/fund')
  async fundBetting(@Param('id') id: string, @Body() _dto: FiatAmountDto) {
    await this.gate.requireVerifiedAndFiatCapable(id);
    throw new Error('unreachable while the gate is closed');
  }
}
