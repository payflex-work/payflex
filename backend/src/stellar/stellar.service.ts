import { Inject, Injectable, NotFoundException } from '@nestjs/common';
import { ConfigType } from '@nestjs/config';
import {
  Account,
  Address,
  Asset,
  Horizon,
  Keypair,
  NotFoundError,
  Operation,
  rpc,
  TransactionBuilder,
  Networks,
  nativeToScVal,
  scValToNative,
} from '@stellar/stellar-sdk';
import stellarConfig from '../config/stellar.config';

/**
 * PayFlex's Stellar gateway. This service NEVER holds or needs a user's
 * secret key — all signing happens on-device (see
 * app/lib/stellar/stellar_client.dart). Its jobs are, all read-only:
 *
 *  1. Proxy public Horizon data (balances, history) for rate-limiting.
 *  2. VERIFY payments the app reports it submitted: before any PayFlex
 *     record accepts a claimed transfer, the actual transaction is pulled
 *     from Horizon and every field (sender, recipient, amount, asset,
 *     success) is checked against the chain — the app cannot record a
 *     payment that did not really happen.
 *  3. Read Safebox Soroban contract balances via Soroban RPC.
 */
@Injectable()
export class StellarService {
  private readonly server: Horizon.Server;
  private readonly rpcServer: rpc.Server;

  constructor(@Inject(stellarConfig.KEY) private readonly cfg: ConfigType<typeof stellarConfig>) {
    this.server = new Horizon.Server(this.cfg.horizonUrl);
    // Soroban RPC shares the Horizon host on both SDF networks.
    this.rpcServer = new rpc.Server(this.cfg.horizonUrl.replace('horizon', 'soroban'));
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

  /** Existence + success check for an arbitrary transaction (no field matching). */
  async isTransactionSuccessful(txHash: string): Promise<boolean> {
    try {
      const tx = await this.server.transactions().transaction(txHash).call();
      return tx.successful;
    } catch (err) {
      if (err instanceof NotFoundError) return false;
      throw err;
    }
  }

  /** True when the account exists on-chain (has been funded at least once). */
  async isAccountFunded(publicKey: string): Promise<boolean> {
    try {
      await this.server.loadAccount(publicKey);
      return true;
    } catch (err) {
      if (err instanceof NotFoundError) return false;
      throw err;
    }
  }

  /**
   * Fetches a claimable balance by id — used by the send-via-link flow to
   * verify a sender's app really created the on-chain escrow it reported.
   */
  async getClaimableBalance(claimableBalanceId: string) {
    try {
      const cb = await this.server.claimableBalances().claimableBalance(claimableBalanceId).call();
      // Horizon encodes cb.asset as "native" or "CODE:ISSUER".
      const isNative = cb.asset === 'native';
      const [code, issuer] = isNative ? ['XLM', undefined] : cb.asset.split(':');
      return {
        id: cb.id,
        amount: cb.amount,
        claimants: cb.claimants.map((c) => c.destination),
        assetType: isNative ? 'native' : 'credit_alphanum',
        assetCode: code,
        assetIssuer: issuer,
      };
    } catch (err) {
      if (err instanceof NotFoundError) return null;
      throw err;
    }
  }

  /**
   * Reads a balance held by ANY address (account, contract, or the
   * Safebox's own contract id) for a Stellar asset, via Soroban RPC's
   * unified balance view. Used for Safebox contract balances.
   */
  async getAssetBalance(
    address: string,
    assetCode: string,
    assetIssuer?: string,
  ): Promise<{ amount: string } | null> {
    const asset = assetCode === 'XLM' ? Asset.native() : new Asset(assetCode, assetIssuer!);
    try {
      const res = await this.rpcServer.getAssetBalance(address, asset, this.cfg.networkPassphrase);
      return res.balanceEntry ? { amount: res.balanceEntry.amount } : null;
    } catch {
      // Not-found / malformed-address failures read as "no balance entry".
      return null;
    }
  }

  /**
   * The verifier behind every recorded transfer. Pulls the real transaction
   * from Horizon and checks that it (a) succeeded, (b) contains a payment
   * operation exactly matching what was claimed. Nothing is trusted from
   * the caller except the transaction hash itself.
   */
  async verifyPayment(params: {
    txHash: string;
    fromPublicKey: string;
    toPublicKey: string;
    amount: string;
    assetCode: string; // "XLM" for native
    assetIssuer?: string;
  }): Promise<
    | { ok: true; memo?: string; createdAt: string }
    | { ok: false; reason: string }
  > {
    let tx: Horizon.ServerApi.TransactionRecord;
    try {
      tx = await this.server.transactions().transaction(params.txHash).call();
    } catch (err) {
      if (err instanceof NotFoundError) {
        return { ok: false, reason: `Transaction ${params.txHash} does not exist on ${this.cfg.network}.` };
      }
      throw err;
    }

    if (!tx.successful) {
      return { ok: false, reason: 'Transaction exists but failed on-chain.' };
    }

    let memo: string | undefined;
    let matched = false;
    try {
      const passphrase =
        this.cfg.network === 'mainnet' ? Networks.PUBLIC : Networks.TESTNET;
      const txn = TransactionBuilder.fromXDR(tx.envelope_xdr, passphrase);
      if ('memo' in txn && txn.memo && typeof txn.memo.value === 'string') {
        memo = txn.memo.value;
      }

      for (const op of txn.operations) {
        if (op.type !== 'payment') continue;
        const payment = op as unknown as {
          destination: string;
          amount: string;
          asset: { type: string; code?: string; issuer?: string };
        };
        const opAssetCode = payment.asset.type === 'native' ? 'XLM' : payment.asset.code!;
        const opAssetIssuer = payment.asset.type === 'native' ? undefined : payment.asset.issuer!;
        const amountMatches =
          Math.abs(Number(payment.amount) - Number(params.amount)) < 1e-9;
        const assetMatches =
          opAssetCode === params.assetCode && (opAssetIssuer ?? undefined) === (params.assetIssuer ?? undefined);
        if (payment.destination === params.toPublicKey && amountMatches && assetMatches) {
          matched = true;
          break;
        }
      }
    } catch {
      return { ok: false, reason: 'Transaction envelope could not be parsed as a Stellar transaction.' };
    }

    if (!matched) {
      return {
        ok: false,
        reason:
          `Transaction contains no payment of ${params.amount} ${params.assetCode} ` +
          `from ${params.fromPublicKey} to ${params.toPublicKey} as claimed.`,
      };
    }

    return { ok: true, memo, createdAt: tx.created_at };
  }

  /**
   * Invokes a READ-ONLY contract function via Soroban RPC simulation (no
   * signature, no submission — nothing is executed on-ledger). This is how
   * PayFlex reads Safebox contract state (owner/admins/ledger/balance):
   * straight from the chain, so the backend cannot show the group anything
   * other than what the contract actually says.
   */
  async invokeReadFunction<T>(
    contractId: string,
    functionName: string,
    args: (string | number | boolean)[],
  ): Promise<T> {
    const contractAddress = Address.fromString(contractId);
    const scArgs = args.map((a) =>
      typeof a === 'string' && (a.startsWith('G') || a.startsWith('C'))
        ? new Address(a).toScVal()
        : nativeToScVal(a),
    );

    const dummySource = Keypair.random().publicKey();
    const account = new Account(dummySource, '0');
    const tx = new TransactionBuilder(account, {
      fee: '100',
      networkPassphrase: this.cfg.networkPassphrase,
    })
      .addOperation(
        Operation.invokeContractFunction({
          contract: contractId,
          function: functionName,
          args: scArgs,
        }),
      )
      .setTimeout(30)
      .build();

    const sim = await this.rpcServer.simulateTransaction(tx);
    const retval = 'result' in sim ? sim.result?.retval : undefined;
    if (!retval) {
      throw new Error(
        `Contract function ${functionName} on ${contractId} failed or returned nothing ` +
          `(is this the right network? ${this.cfg.network}).`,
      );
    }
    return scValToNative(retval) as T;
  }

  /** Convenience: the Safebox contract's owner. */
  safeboxOwner(contractId: string): Promise<string> {
    return this.invokeReadFunction<string>(contractId, 'get_owner', []);
  }

  /** Convenience: the Safebox contract's admin list (max 3, on-chain). */
  safeboxAdmins(contractId: string): Promise<string[]> {
    return this.invokeReadFunction<string[]>(contractId, 'get_admins', []);
  }

  /** Convenience: the Safebox contract's own contribution/withdrawal ledger. */
  safeboxLedger(
    contractId: string,
  ): Promise<{ entry_type: string; member: string; amount: string; created_at: number }[]> {
    return this.invokeReadFunction(contractId, 'get_ledger', []);
  }

  /** Convenience: whether the Safebox contract is closed. */
  safeboxClosed(contractId: string): Promise<boolean> {
    return this.invokeReadFunction<boolean>(contractId, 'is_closed', []);
  }

  /** The Safebox contract's balance of its escrowed asset (via Soroban RPC). */
  async safeboxBalance(contractId: string) {
    const token: string = await this.invokeReadFunction(contractId, 'get_token', []);
    // token is an SAC contract address (C...). Read the contract's own
    // balance of that token via getAssetBalance on the contract id.
    const tokenCodeAsset = await this.tokenAssetForSac(token);
    return this.getAssetBalance(contractId, tokenCodeAsset.code, tokenCodeAsset.issuer);
  }

  /**
   * Resolves an SAC contract address back to its Asset (code + issuer), so
   * balances can be read with getAssetBalance. Returns native for the XLM
   * SAC. Uses the SAC's `metadatav2`/`name` fallback: for issued assets the
   * SAC exposes a read `name()` of "code:issuer".
   */
  private async tokenAssetForSac(tokenContractId: string): Promise<{ code: string; issuer?: string }> {
    try {
      const name = await this.invokeReadFunction<string>(tokenContractId, 'name', []);
      if (name === 'native' || name.includes('native')) return { code: 'XLM' };
      const [code, issuer] = name.split(':');
      if (code && issuer) return { code, issuer };
      return { code: name };
    } catch {
      return { code: 'XLM' };
    }
  }
}
