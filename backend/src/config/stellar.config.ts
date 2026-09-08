import { registerAs } from '@nestjs/config';

export interface StellarConfig {
  network: 'testnet' | 'mainnet';
  horizonUrl: string;
  friendbotUrl: string | undefined;
  networkPassphrase: string;
}

/**
 * Config for PayFlex's Stellar rail — a second, optional payment network
 * that sits ALONGSIDE BMONI (see docs/stellar-rail.md), never routed
 * through it. Defaults to testnet; mainnet requires an explicit env flag
 * since it involves real, irreversible funds — this mirrors BMONI_ENV's
 * sandbox-vs-production split in bmoni.config.ts, but the stakes of
 * flipping this one by accident are higher (BMONI's sandbox/production
 * split still goes through a regulated custodian; Stellar mainnet is
 * unmediated on-chain value with no recovery path for a mistake).
 */
export default registerAs('stellar', (): StellarConfig => {
  const network = (process.env.STELLAR_NETWORK ?? 'testnet') as 'testnet' | 'mainnet';

  if (network === 'mainnet') {
    const horizonUrl = process.env.STELLAR_HORIZON_URL;
    if (!horizonUrl) {
      throw new Error(
        'STELLAR_NETWORK=mainnet but STELLAR_HORIZON_URL is not set. This is a deliberate ' +
          'business/compliance decision (see docs/stellar-rail.md) — set it explicitly, ' +
          'e.g. STELLAR_HORIZON_URL=https://horizon.stellar.org, never as a silent default.',
      );
    }
    return {
      network,
      horizonUrl: horizonUrl.replace(/\/+$/, ''),
      friendbotUrl: undefined, // Friendbot only exists on testnet — there is no mainnet equivalent.
      networkPassphrase: 'Public Global Stellar Network ; September 2015',
    };
  }

  return {
    network: 'testnet',
    // `||`, not `??`: a present-but-blank STELLAR_HORIZON_URL= line in
    // .env (the same "left blank to use the default" convention used
    // elsewhere in this file) must still fall through to the default —
    // '' is falsy but not nullish, so `??` would pass it straight to
    // `new URL('')` and crash the app on boot.
    horizonUrl: (process.env.STELLAR_HORIZON_URL || 'https://horizon-testnet.stellar.org').replace(/\/+$/, ''),
    friendbotUrl: process.env.STELLAR_FRIENDBOT_URL || 'https://friendbot.stellar.org',
    networkPassphrase: 'Test SDF Network ; September 2015',
  };
});
