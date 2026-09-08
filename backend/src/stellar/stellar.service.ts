import { Inject, Injectable, NotFoundException } from '@nestjs/common';
import { ConfigType } from '@nestjs/config';
import { Horizon, NotFoundError } from '@stellar/stellar-sdk';
import stellarConfig from '../config/stellar.config';

/**
 * Read-only companion to PayFlex's Stellar rail. This service NEVER holds
 * or needs a user's Stellar secret key — all signing happens on-device
 * (see app/lib/stellar/stellar_client.dart), same principle as BMONI's
 * on-device SDK signing. Its only job is proxying public Horizon data
 * (account balances/trustlines, transaction history) through PayFlex's
 * own backend — same "one gateway" shape as BmoniClientService, and
 * rate-limited (see StellarController) since Horizon is a shared public
 * resource this app shouldn't be able to hammer on a user's behalf.
 */
@Injectable()
export class StellarService {
  private readonly server: Horizon.Server;

  constructor(@Inject(stellarConfig.KEY) private readonly cfg: ConfigType<typeof stellarConfig>) {
    this.server = new Horizon.Server(this.cfg.horizonUrl);
  }

  getNetworkInfo() {
    return {
      network: this.cfg.network,
      horizonUrl: this.cfg.horizonUrl,
      friendbotUrl: this.cfg.friendbotUrl,
      networkPassphrase: this.cfg.networkPassphrase,
    };
  }

  /**
   * Balances + trustlines for a public key. Maps Horizon's 404 (account
   * doesn't exist on-chain yet — i.e. never funded) to a clear
   * NotFoundException rather than letting a raw Horizon error surface;
   * an unfunded Stellar account is a completely normal, expected state
   * here (every account starts this way before Friendbot/a real funding
   * payment activates it), not a system error.
   */
  async getAccount(publicKey: string) {
    try {
      const account = await this.server.loadAccount(publicKey);
      return {
        publicKey: account.accountId(),
        sequence: account.sequenceNumber(),
        balances: account.balances.map((b) => ({
          assetType: b.asset_type,
          assetCode: 'asset_code' in b ? b.asset_code : undefined,
          assetIssuer: 'asset_issuer' in b ? b.asset_issuer : undefined,
          balance: b.balance,
          limit: 'limit' in b ? b.limit : undefined,
        })),
      };
    } catch (err) {
      if (err instanceof NotFoundError) {
        throw new NotFoundException(
          `Stellar account ${publicKey} is not funded/activated on-chain yet — ` +
            `fund it via Friendbot (testnet) or a minimum-balance payment (mainnet) first.`,
        );
      }
      throw err;
    }
  }

  async getTransactions(publicKey: string, limit = 20) {
    try {
      const page = await this.server.payments().forAccount(publicKey).order('desc').limit(limit).call();
      return page.records.map((r) => ({
        id: r.id,
        transactionHash: r.transaction_hash,
        type: r.type,
        createdAt: r.created_at,
      }));
    } catch (err) {
      if (err instanceof NotFoundError) {
        throw new NotFoundException(`Stellar account ${publicKey} is not funded/activated on-chain yet.`);
      }
      throw err;
    }
  }
}
