import { Injectable, NotImplementedException } from '@nestjs/common';

/**
 * ============================================================================
 * PLUG-IN GAP — IDENTITY VERIFICATION (KYC). NOTHING IMPLEMENTS THIS YET.
 * ============================================================================
 *
 * PayFlex currently has NO identity verification of any kind. Any former
 * KYC flow was removed with the previous banking layer and has NOT been
 * replaced — see docs/fiat-kyc-gap.md for what a real integration needs
 * (a regulated provider: a Stellar anchor implementing SEP-12, or an
 * equivalent licensed partner).
 *
 * This interface is the contract a future implementation must satisfy.
 * There is deliberately NO implementation, NO mock, and NO fake in this
 * repository. Any feature that needs verified identity must go through
 * HardGateService.requireIdentityVerified(), which fails closed until a
 * real provider exists.
 *
 * THE HARD GATE: AppUser.identityVerified defaults to false and NO code
 * path in this repository sets it true. Only a future implementation of
 * this interface (wired together with a review process) may do so.
 * ============================================================================
 */

/** What a real KYC submission round-trip would need to carry. The SHAPE is
 * informed by what regulated KYC flows (and SEP-12 generally) require — it
 * exists so a future provider implementer knows the app's expectations —
 * but no behavior is implied by it. */
export interface IdentityVerificationSession {
  /** Provider-side identifier for this verification attempt. */
  sessionId: string;
  /** Human-readable next step the app should show, e.g. "upload proof of address". */
  nextStep: string;
  /** Provider-defined status. Callers must treat unknown values as "not verified". */
  status: 'PENDING' | 'ACTION_REQUIRED' | 'VERIFIED' | 'REJECTED';
}

export interface IdentityVerificationResult {
  verified: boolean;
  /** Why verification failed, when it failed. Must never be fabricated —
   * pass the provider's own reason through verbatim. */
  rejectionReason?: string;
}

export interface IIdentityVerificationProvider {
  /** Start a verification session for a user (real documents, real
   * biometrics, real regulatory checks — provider-defined). */
  startSession(appUserId: string, jurisdiction: string): Promise<IdentityVerificationSession>;

  /** Fetch the current state of a session from the provider. */
  getSession(appUserId: string, sessionId: string): Promise<IdentityVerificationSession>;

  /** The ONLY legitimate place AppUser.identityVerified may be set true:
   * after the provider itself reports VERIFIED. Implementations must
   * persist the provider's session/decision evidence alongside the flag. */
  confirmVerified(appUserId: string, sessionId: string): Promise<IdentityVerificationResult>;
}

/**
 * Stand-in that FAILS CLOSED, loudly. Injected wherever identity-gated
 * features would need a provider. It can never verify anyone.
 */
@Injectable()
export class NoIdentityVerificationProvider implements IIdentityVerificationProvider {
  startSession(): Promise<IdentityVerificationSession> {
    throw new NotImplementedException(
      'Identity verification is not configured in this build — no KYC provider is plugged in. ' +
        'See docs/fiat-kyc-gap.md.',
    );
  }
  getSession(): Promise<IdentityVerificationSession> {
    throw new NotImplementedException(
      'Identity verification is not configured in this build — no KYC provider is plugged in. ' +
        'See docs/fiat-kyc-gap.md.',
    );
  }
  confirmVerified(): Promise<IdentityVerificationResult> {
    throw new NotImplementedException(
      'Identity verification is not configured in this build — no KYC provider is plugged in. ' +
        'See docs/fiat-kyc-gap.md.',
    );
  }
}
