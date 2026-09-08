// @stellar/stellar-sdk's real module graph pulls in several ESM-only
// transitive deps (@noble/hashes, @exodus/bytes, uint8array-extras, ...)
// that Jest's CJS transform can't parse without an ever-growing
// transformIgnorePatterns allowlist. StellarService only needs
// Horizon.Server's shape and NotFoundError's identity — hand-mock exactly
// that instead of loading the real package under Jest at all. This must
// come before every other import (including StellarService's own, which
// transitively imports the real SDK) since ts-jest doesn't hoist
// jest.mock the way babel-jest does.
class FakeNotFoundError extends Error {}
jest.mock('@stellar/stellar-sdk', () => ({
  Horizon: { Server: jest.fn() },
  NotFoundError: FakeNotFoundError,
}));

import { NotFoundException } from '@nestjs/common';
import { NotFoundError, Horizon } from '@stellar/stellar-sdk';
import { StellarService } from './stellar.service';
import stellarConfig from '../config/stellar.config';

describe('StellarService', () => {
  function buildService(overrides?: { loadAccount?: jest.Mock; payments?: jest.Mock }) {
    const loadAccount = overrides?.loadAccount ?? jest.fn();
    const payments = overrides?.payments ?? jest.fn();
    (Horizon.Server as unknown as jest.Mock).mockImplementation(() => ({ loadAccount, payments }));

    const cfg = {
      network: 'testnet' as const,
      horizonUrl: 'https://horizon-testnet.stellar.test',
      friendbotUrl: 'https://friendbot.stellar.test',
      networkPassphrase: 'Test SDF Network ; September 2015',
    };
    return { service: new StellarService(cfg as unknown as ReturnType<typeof stellarConfig>), loadAccount, payments };
  }

  describe('getNetworkInfo', () => {
    it('returns the configured network, defaulting to testnet with friendbot present', () => {
      const { service } = buildService();
      expect(service.getNetworkInfo()).toEqual({
        network: 'testnet',
        horizonUrl: 'https://horizon-testnet.stellar.test',
        friendbotUrl: 'https://friendbot.stellar.test',
        networkPassphrase: 'Test SDF Network ; September 2015',
      });
    });
  });

  describe('getAccount', () => {
    it('maps balances/trustlines from a funded account', async () => {
      const loadAccount = jest.fn().mockResolvedValue({
        accountId: () => 'GABC123',
        sequenceNumber: () => '123',
        balances: [
          { asset_type: 'native', balance: '100.0000000' },
          {
            asset_type: 'credit_alphanum4',
            asset_code: 'USDC',
            asset_issuer: 'GISSUER',
            balance: '50.0000000',
            limit: '1000.0000000',
          },
        ],
      });
      const { service } = buildService({ loadAccount });

      const result = await service.getAccount('GABC123');

      expect(result).toEqual({
        publicKey: 'GABC123',
        sequence: '123',
        balances: [
          { assetType: 'native', assetCode: undefined, assetIssuer: undefined, balance: '100.0000000', limit: undefined },
          { assetType: 'credit_alphanum4', assetCode: 'USDC', assetIssuer: 'GISSUER', balance: '50.0000000', limit: '1000.0000000' },
        ],
      });
    });

    it('translates a 404 (unfunded account) into a clear NotFoundException, not a raw Horizon error', async () => {
      const loadAccount = jest.fn().mockRejectedValue(
        Object.assign(new NotFoundError('Not Found', {} as never), {}),
      );
      const { service } = buildService({ loadAccount });

      await expect(service.getAccount('GUNFUNDED')).rejects.toBeInstanceOf(NotFoundException);
      await expect(service.getAccount('GUNFUNDED')).rejects.toThrow(/not funded\/activated/);
    });

    it('rethrows a non-NotFound error unchanged', async () => {
      const bug = new Error('horizon is down');
      const loadAccount = jest.fn().mockRejectedValue(bug);
      const { service } = buildService({ loadAccount });

      await expect(service.getAccount('GABC123')).rejects.toBe(bug);
    });
  });

  describe('getTransactions', () => {
    it('maps the payments page into a flat history list', async () => {
      const call = jest.fn().mockResolvedValue({
        records: [
          { id: '1', transaction_hash: 'hash1', type: 'payment', created_at: '2026-01-01T00:00:00Z' },
        ],
      });
      const limit = jest.fn().mockReturnValue({ call });
      const order = jest.fn().mockReturnValue({ limit });
      const forAccount = jest.fn().mockReturnValue({ order });
      const payments = jest.fn().mockReturnValue({ forAccount });
      const { service } = buildService({ payments });

      const result = await service.getTransactions('GABC123', 5);

      expect(forAccount).toHaveBeenCalledWith('GABC123');
      expect(order).toHaveBeenCalledWith('desc');
      expect(limit).toHaveBeenCalledWith(5);
      expect(result).toEqual([
        { id: '1', transactionHash: 'hash1', type: 'payment', createdAt: '2026-01-01T00:00:00Z' },
      ]);
    });

    it('translates a 404 into a clear NotFoundException', async () => {
      const call = jest.fn().mockRejectedValue(new NotFoundError('Not Found', {} as never));
      const limit = jest.fn().mockReturnValue({ call });
      const order = jest.fn().mockReturnValue({ limit });
      const forAccount = jest.fn().mockReturnValue({ order });
      const payments = jest.fn().mockReturnValue({ forAccount });
      const { service } = buildService({ payments });

      await expect(service.getTransactions('GUNFUNDED')).rejects.toBeInstanceOf(NotFoundException);
    });
  });
});
