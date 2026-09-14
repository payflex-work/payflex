import { BadRequestException } from '@nestjs/common';
import { Keypair } from '@stellar/stellar-sdk';
import { UsersService } from './users.service';
import { PrismaService } from '../prisma/prisma.service';

describe('UsersService (Stellar-only)', () => {
  const dto = {
    firstName: 'Samson',
    lastName: 'Jabo',
    email: 'samson@payflex.test',
    phoneNumber: '+2348000000001',
  };

  function keypair() {
    return Keypair.random();
  }

  function buildService(overrides?: { findUnique?: jest.Mock; create?: jest.Mock; update?: jest.Mock }) {
    const prisma = {
      appUser: {
        findUnique: overrides?.findUnique ?? jest.fn().mockResolvedValue(null),
        create: overrides?.create ?? jest.fn().mockImplementation(({ data }) => ({ id: 'local-1', ...data })),
        update: overrides?.update ?? jest.fn().mockImplementation(({ where, data }) => ({ id: where.id, ...data })),
      },
    } as unknown as PrismaService;
    return { service: new UsersService(prisma), prisma };
  }

  describe('getOrCreate', () => {
    it('is local-only: no external provider, no chain, just a row', async () => {
      const create = jest.fn().mockImplementation(({ data }) => ({ id: 'local-2', ...data }));
      const { service } = buildService({ create });

      const result = await service.getOrCreate(dto);

      expect(create).toHaveBeenCalledWith({ data: dto });
      expect(result).toMatchObject({ phoneNumber: dto.phoneNumber });
      // A fresh user has NO key and NO verification — the hard gate's
      // defaults. (The service inserts only the DTO fields; identityVerified
      // / fiatCapable default to false at the DATABASE level, so they come
      // back undefined in this mock and the gate e2e suite asserts the
      // false-defaults against the real DB.)
      expect(result.stellarPublicKey).toBeUndefined();
      expect(result).not.toHaveProperty('identityVerified', true);
      expect(result).not.toHaveProperty('fiatCapable', true);
    });

    it('returns the existing local row when the phone number is already registered', async () => {
      const existing = { id: 'local-1', ...dto };
      const findUnique = jest.fn().mockResolvedValue(existing);
      const { service } = buildService({ findUnique });

      const result = await service.getOrCreate(dto);
      expect(result).toBe(existing);
    });
  });

  describe('setStellarPublicKey', () => {
    it('accepts a valid Ed25519 strkey', async () => {
      const pk = keypair().publicKey();
      const update = jest.fn().mockImplementation(({ data }) => ({ id: 'local-1', ...data }));
      const findUnique = jest.fn().mockResolvedValue({ id: 'local-1', stellarPublicKey: null });
      const { service } = buildService({ findUnique, update });

      const result = await service.setStellarPublicKey('local-1', pk);
      expect(result.stellarPublicKey).toBe(pk);
    });

    it('rejects a non-G string', async () => {
      const { service } = buildService();
      await expect(service.setStellarPublicKey('local-1', 'SABC...')).rejects.toBeInstanceOf(BadRequestException);
    });

    it('rejects a well-formed-looking key with a broken checksum', async () => {
      const { service } = buildService();
      const bad = 'G' + 'A'.repeat(55);
      await expect(service.setStellarPublicKey('local-1', bad)).rejects.toBeInstanceOf(BadRequestException);
    });

    it('rejects a key already registered to a different account', async () => {
      const pk = keypair().publicKey();
      const findUnique = jest.fn().mockImplementation(({ where }) =>
        where.stellarPublicKey ? { id: 'someone-else', stellarPublicKey: pk } : null,
      );
      const { service } = buildService({ findUnique });

      await expect(service.setStellarPublicKey('local-1', pk)).rejects.toThrow(/already registered/);
    });

    it('refuses key rotation once a key is set', async () => {
      const original = keypair().publicKey();
      const replacement = keypair().publicKey();
      const findUnique = jest.fn()
        .mockResolvedValueOnce(null) // uniqueness clash check
        .mockResolvedValueOnce({ id: 'local-1', stellarPublicKey: original }); // the user
      const { service } = buildService({ findUnique });

      await expect(service.setStellarPublicKey('local-1', replacement)).rejects.toThrow(/immutable/);
    });
  });
});
