import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { StrKey } from '@stellar/stellar-sdk';
import { PrismaService } from '../prisma/prisma.service';
import { CreateUserDto } from './dto/create-user.dto';
import { AppUser } from '@prisma/client';

/**
 * Local account directory for the Stellar-only architecture. Creating a
 * PayFlex account is a purely local act — the user's real account is their
 * non-custodial Stellar keypair generated ON THEIR DEVICE; this backend
 * never sees secret key material and cannot create one for them. The public
 * key is registered (PATCH /users/:id/stellar-public-key) once the app has
 * generated it, and activation (on-chain funding) is verified against
 * Horizon by OnboardingService.
 */
@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  async getOrCreate(dto: CreateUserDto): Promise<AppUser> {
    const existing = await this.prisma.appUser.findUnique({
      where: { phoneNumber: dto.phoneNumber },
    });
    if (existing) return existing;
    return this.prisma.appUser.create({
      data: {
        firstName: dto.firstName,
        lastName: dto.lastName,
        email: dto.email,
        phoneNumber: dto.phoneNumber,
      },
    });
  }

  async findById(id: string): Promise<AppUser> {
    const user = await this.prisma.appUser.findUnique({ where: { id } });
    if (!user) throw new NotFoundException(`No local user with id ${id}`);
    return user;
  }

  /**
   * Registers the public half of the user's on-device Stellar keypair.
   * Strictly validated as an Ed25519 account strkey (G...) — a typo'd or
   * wrong-type key here would brick logins and payments for this account,
   * so it is rejected at the door, not at first use.
   */
  async setStellarPublicKey(id: string, stellarPublicKey: string): Promise<AppUser> {
    this.assertValidEd25519PublicKey(stellarPublicKey);

    const clash = await this.prisma.appUser.findUnique({ where: { stellarPublicKey } });
    if (clash && clash.id !== id) {
      throw new BadRequestException('This Stellar public key is already registered to another account.');
    }

    const user = await this.findById(id);
    if (user.stellarPublicKey && user.stellarPublicKey !== stellarPublicKey) {
      throw new BadRequestException(
        'A Stellar public key is already registered for this account and keys are ' +
          'immutable — rotating keys is not supported because past payments and ' +
          'Safebox/Soroban ownership reference the original key. Create a new account instead.',
      );
    }
    return this.prisma.appUser.update({
      where: { id },
      data: { stellarPublicKey },
    });
  }

  async markStellarAccountActivated(id: string): Promise<AppUser> {
    await this.findById(id);
    return this.prisma.appUser.update({
      where: { id },
      data: { stellarAccountActivated: true },
    });
  }

  private assertValidEd25519PublicKey(publicKey: string): void {
    if (typeof publicKey !== 'string' || !publicKey.startsWith('G')) {
      throw new BadRequestException('stellarPublicKey must be an Ed25519 account strkey starting with "G".');
    }
    try {
      if (!StrKey.isValidEd25519PublicKey(publicKey)) {
        throw new Error('invalid checksum or length');
      }
    } catch {
      throw new BadRequestException('stellarPublicKey is not a valid Ed25519 account strkey.');
    }
  }
}
