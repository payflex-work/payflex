import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { StellarService } from '../stellar/stellar.service';
import { UsersService } from '../users/users.service';

/**
 * Stellar-native onboarding. Creating a PayFlex account is local (see
 * UsersService); THIS module is about putting that account on-chain:
 *
 *  1. The app generates the user's keypair on-device and registers the
 *     public key (PATCH /users/:id/stellar-public-key).
 *  2. The account must be "activated" — funded past the minimum reserve —
 *     before it can hold assets or make payments. On TESTNET the app can
 *     do this itself via Friendbot; this endpoint double-checks Horizon
 *     and flips the local flag when the account really exists.
 *  3. MAINNET: Friendbot does not exist. Activation requires a real
 *     minimum-reserve payment (currently 1 XLM base reserve) from an
 *     already-funded account. This backend deliberately does NOT automate
 *     holding/paying out that reserve — that's a business decision for a
 *     funded treasury (see docs/fiat-kyc-gap.md), not a code default.
 */
@Injectable()
export class OnboardingService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly stellar: StellarService,
    private readonly users: UsersService,
  ) {}

  /** What the app should show as the next step for this user. */
  async getStatus(appUserId: string) {
    const user = await this.users.findById(appUserId);
    const funded = user.stellarPublicKey
      ? await this.stellar.isAccountFunded(user.stellarPublicKey)
      : false;

    // Keep the local flag honest: it reflects what Horizon says right now.
    if (funded && !user.stellarAccountActivated) {
      await this.prisma.appUser.update({
        where: { id: appUserId },
        data: { stellarAccountActivated: true },
      });
    }

    return {
      hasStellarKey: Boolean(user.stellarPublicKey),
      accountFunded: funded,
      activated: funded,
      nextStep: !user.stellarPublicKey
        ? 'Generate a Stellar keypair on this device, then register its public key.'
        : !funded
          ? 'Fund the account to activate it: testnet = Friendbot, mainnet = a real minimum-reserve payment (see docs/fiat-kyc-gap.md).'
          : 'Account is live — payments, Safeboxes, and links are available.',
    };
  }

  /**
   * Confirms activation for the CALLING user's account. On testnet the app
   * has usually already hit Friendbot directly; this is the server-side
   * verification that the account genuinely exists on-ledger. On mainnet
   * this endpoint does not fund anything — it only verifies.
   */
  async confirmActivation(appUserId: string) {
    const user = await this.users.findById(appUserId);
    if (!user.stellarPublicKey) {
      throw new NotFoundException('No Stellar public key registered for this account yet.');
    }
    const funded = await this.stellar.isAccountFunded(user.stellarPublicKey);
    if (!funded) {
      return { activated: false, reason: 'Account is not funded on-ledger yet.' };
    }
    await this.users.markStellarAccountActivated(user.id);
    return { activated: true };
  }
}
