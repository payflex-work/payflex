import { Injectable, NotImplementedException } from '@nestjs/common';

/**
 * ============================================================================
 * PLUG-IN GAP — FIAT RAIL (deposits/withdrawals, NGN/USD <-> Stellar asset).
 * NOTHING IMPLEMENTS THIS YET.
 * ============================================================================
 *
 * PayFlex currently cannot move fiat money at all. Deposits, withdrawals,
 * virtual cards, agent cash-in/cash-out, and betting funding all require a
 * fiat rail that does not exist in this build — see docs/fiat-kyc-gap.md
 * for the real options when this gets picked up (a Stellar anchor
 * implementing SEP-6/SEP-24 for NGN or USD, or another regulated partner).
 *
 * This interface is the contract a future implementation must satisfy.
 * There is deliberately NO implementation, NO mock, and NO fake in this
 * repository. Any feature that moves fiat must go through
 * HardGateService.requireFiatCapable(), which fails closed until a real
 * provider exists.
 *
 * THE HARD GATE: AppUser.fiatCapable defaults to false and NO code path in
 * this repository sets it true. Only a future implementation of this
 * interface may do so.
 * ============================================================================
 */

/** An asset a future fiat rail could support. Declared up front so the app's
 * gated surfaces can render honest "unavailable" states per asset. */
export interface FiatAsset {
  /** ISO 4217 code, e.g. "NGN", "USD". */
  fiatCode: string;
  /** The Stellar asset a real anchor would issue against the fiat balance. */
  stellarAssetCode: string;
  stellarAssetIssuer: string;
}

export interface FiatQuote {
  fiatAmount: string;
  stellarAmount: string;
  asset: FiatAsset;
  /** Provider-defined reference. Never fabricated by PayFlex. */
  quoteId: string;
  expiresAt: string;
}

export interface FiatDepositInstruction {
  /** How the user actually pays the fiat (bank transfer details, anchor
   * interactive flow URL, etc.) — provider-defined. */
  instruction: string;
  quoteId: string;
}

export interface FiatWithdrawalResult {
  /** Provider-side id for the payout. */
  payoutId: string;
  status: 'PENDING' | 'COMPLETED' | 'REJECTED';
  /** Provider's own failure reason verbatim; never synthesized. */
  rejectionReason?: string;
}

export interface IFiatRailProvider {
  /** Assets this provider can actually move. An empty list means the
   * provider is wired but supports nothing — still not a fake. */
  supportedAssets(): Promise<FiatAsset[]>;

  /** Quote a deposit (fiat in -> Stellar asset out). */
  quoteDeposit(asset: FiatAsset, fiatAmount: string): Promise<FiatQuote>;

  /** Instructions for the user to complete a fiat deposit. */
  startDeposit(quoteId: string): Promise<FiatDepositInstruction>;

  /** Withdraw: burn/return the Stellar asset, pay out fiat externally. */
  withdraw(appUserId: string, asset: FiatAsset, stellarAmount: string, destination: unknown): Promise<FiatWithdrawalResult>;
}

/**
 * Stand-in that FAILS CLOSED, loudly. Injected wherever fiat movement would
 * be needed. It can never move a single unit of fiat.
 */
@Injectable()
export class NoFiatRailProvider implements IFiatRailProvider {
  supportedAssets(): Promise<FiatAsset[]> {
    throw new NotImplementedException(
      'Fiat rails are not configured in this build — no fiat provider is plugged in. ' +
        'See docs/fiat-kyc-gap.md.',
    );
  }
  quoteDeposit(): Promise<FiatQuote> {
    throw new NotImplementedException(
      'Fiat rails are not configured in this build — no fiat provider is plugged in. ' +
        'See docs/fiat-kyc-gap.md.',
    );
  }
  startDeposit(): Promise<FiatDepositInstruction> {
    throw new NotImplementedException(
      'Fiat rails are not configured in this build — no fiat provider is plugged in. ' +
        'See docs/fiat-kyc-gap.md.',
    );
  }
  withdraw(): Promise<FiatWithdrawalResult> {
    throw new NotImplementedException(
      'Fiat rails are not configured in this build — no fiat provider is plugged in. ' +
        'See docs/fiat-kyc-gap.md.',
    );
  }
}
