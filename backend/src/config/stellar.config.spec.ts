import stellarConfig from './stellar.config';

describe('stellarConfig', () => {
  const ORIGINAL_ENV = process.env;

  beforeEach(() => {
    process.env = { ...ORIGINAL_ENV };
    delete process.env.STELLAR_NETWORK;
    delete process.env.STELLAR_HORIZON_URL;
    delete process.env.STELLAR_FRIENDBOT_URL;
  });

  afterAll(() => {
    process.env = ORIGINAL_ENV;
  });

  it('defaults to testnet with a valid Horizon URL when nothing is set', () => {
    const cfg = stellarConfig();
    expect(cfg.network).toBe('testnet');
    expect(cfg.horizonUrl).toBe('https://horizon-testnet.stellar.org');
    expect(cfg.friendbotUrl).toBe('https://friendbot.stellar.org');
  });

  it('falls back to the testnet default when STELLAR_HORIZON_URL is present but blank', () => {
    // Regression test: a real bug caught by booting the app — the config
    // used `??` for this fallback, and '' is falsy but not nullish, so
    // `new Horizon.Server('')` crashed the app on boot. This is exactly
    // the "left blank to use the default" .env convention used elsewhere
    // in this project (e.g. PAYFLEX_TREASURY_BMONI_USER_ID=).
    process.env.STELLAR_HORIZON_URL = '';
    const cfg = stellarConfig();
    expect(cfg.horizonUrl).toBe('https://horizon-testnet.stellar.org');
  });

  it('throws if mainnet is selected without an explicit Horizon URL', () => {
    process.env.STELLAR_NETWORK = 'mainnet';
    expect(() => stellarConfig()).toThrow(/STELLAR_HORIZON_URL is not set/);
  });

  it('throws if mainnet is selected with a blank Horizon URL, not silently defaulting', () => {
    process.env.STELLAR_NETWORK = 'mainnet';
    process.env.STELLAR_HORIZON_URL = '';
    expect(() => stellarConfig()).toThrow(/STELLAR_HORIZON_URL is not set/);
  });

  it('uses the real mainnet passphrase and no friendbot when mainnet is explicitly configured', () => {
    process.env.STELLAR_NETWORK = 'mainnet';
    process.env.STELLAR_HORIZON_URL = 'https://horizon.stellar.org';
    const cfg = stellarConfig();
    expect(cfg.networkPassphrase).toBe('Public Global Stellar Network ; September 2015');
    expect(cfg.friendbotUrl).toBeUndefined();
  });
});
