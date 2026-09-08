import axios from 'axios';
import { ConfigService } from '@nestjs/config';
import { BmoniClientService } from './bmoni-client.service';
import { BmoniApiError, BmoniNetworkError } from './bmoni.errors';

jest.mock('axios');
const mockedAxios = axios as jest.Mocked<typeof axios>;

/**
 * BmoniClientService is the single gateway every feature module depends
 * on for real money movement — these tests pin down its two riskiest
 * behaviors: translating axios errors into the typed BmoniApiError/
 * BmoniNetworkError callers branch on, and createProposal/getProposal's
 * documented (non-obvious, spec-diverging) request/response wrapping.
 */
describe('BmoniClientService', () => {
  function buildService() {
    const request = jest.fn();
    mockedAxios.create.mockReturnValue({ request } as unknown as ReturnType<typeof axios.create>);
    const configService = {
      getOrThrow: jest.fn().mockReturnValue({
        env: 'sandbox',
        baseUrl: 'https://embedded-sandbox.bmoni.test',
        apiKey: 'test-api-key',
      }),
    } as unknown as ConfigService;
    return { service: new BmoniClientService(configService), request };
  }

  describe('request() error translation', () => {
    it('returns response data on success', async () => {
      const { service, request } = buildService();
      request.mockResolvedValue({ data: { ok: true } });

      const result = await service.getSupportedCurrencies();

      expect(result).toEqual({ ok: true });
    });

    it('wraps a BMONI HTTP error response into BmoniApiError with status/error/message/path preserved', async () => {
      const { service, request } = buildService();
      const axiosError = {
        isAxiosError: true,
        response: {
          status: 400,
          data: { error: 'Bad Request', message: 'proposal.currency must be one of the following values' },
        },
      };
      request.mockRejectedValue(axiosError);
      mockedAxios.isAxiosError.mockReturnValue(true);

      await expect(service.getSupportedCurrencies()).rejects.toMatchObject({
        status: 400,
        bmoniError: 'Bad Request',
        bmoniMessage: 'proposal.currency must be one of the following values',
      });
      await expect(service.getSupportedCurrencies()).rejects.toBeInstanceOf(BmoniApiError);
    });

    it('preserves a class-validator-style message array unjoined on the error object', async () => {
      const { service, request } = buildService();
      const axiosError = {
        isAxiosError: true,
        response: { status: 400, data: { message: ['name must be a string', 'amount must be a number'] } },
      };
      request.mockRejectedValue(axiosError);
      mockedAxios.isAxiosError.mockReturnValue(true);

      let caught: BmoniApiError | undefined;
      try {
        await service.getSupportedCurrencies();
      } catch (err) {
        caught = err as BmoniApiError;
      }
      expect(caught?.bmoniMessage).toEqual(['name must be a string', 'amount must be a number']);
      expect(caught?.message).toContain('name must be a string; amount must be a number');
    });

    it('wraps a connection failure (no response) into BmoniNetworkError, not BmoniApiError', async () => {
      const { service, request } = buildService();
      const axiosError = { isAxiosError: true, response: undefined };
      request.mockRejectedValue(axiosError);
      mockedAxios.isAxiosError.mockReturnValue(true);

      await expect(service.getSupportedCurrencies()).rejects.toBeInstanceOf(BmoniNetworkError);
    });

    it('rethrows a non-axios error unchanged', async () => {
      const { service, request } = buildService();
      const bug = new TypeError('unexpected');
      request.mockRejectedValue(bug);
      mockedAxios.isAxiosError.mockReturnValue(false);

      await expect(service.getSupportedCurrencies()).rejects.toBe(bug);
    });
  });

  describe('BmoniApiError status convenience getters', () => {
    it.each([
      [400, 'isBadRequest'],
      [401, 'isUnauthorized'],
      [403, 'isForbidden'],
      [404, 'isNotFound'],
      [409, 'isConflict'],
    ] as const)('status %d sets only %s', (status, flag) => {
      const err = new BmoniApiError(status, undefined, undefined, '/some/path');
      expect(err[flag]).toBe(true);
      expect(err.isServerError).toBe(false);
    });

    it('treats any 5xx as a server error', () => {
      expect(new BmoniApiError(500, undefined, undefined, '/p').isServerError).toBe(true);
      expect(new BmoniApiError(503, undefined, undefined, '/p').isServerError).toBe(true);
      expect(new BmoniApiError(499, undefined, undefined, '/p').isServerError).toBe(false);
    });
  });

  describe('createProposal', () => {
    it('wraps the request body as { proposal } and unwraps { proposal } from the response', async () => {
      const { service, request } = buildService();
      request.mockResolvedValue({ data: { proposal: { id: 'proposal-1', status: 'PENDING_APPROVALS' } } });

      const result = await service.createProposal('user-1', 'wallet-1', {
        type: 'TRANSFER',
        toUserId: 'user-2',
        amount: '10.00',
        currency: 'CNGN',
      } as never);

      expect(request).toHaveBeenCalledWith(
        expect.objectContaining({
          method: 'POST',
          data: { proposal: expect.objectContaining({ toUserId: 'user-2', amount: '10.00' }) },
        }),
      );
      expect(result).toEqual({ id: 'proposal-1', status: 'PENDING_APPROVALS' });
    });
  });

  describe('getProposal', () => {
    it('unwraps { proposal } from the response', async () => {
      const { service, request } = buildService();
      request.mockResolvedValue({ data: { proposal: { id: 'proposal-1', status: 'CONFIRMED' } } });

      const result = await service.getProposal('user-1', 'proposal-1');

      expect(result).toEqual({ id: 'proposal-1', status: 'CONFIRMED' });
    });
  });
});
