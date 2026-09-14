import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

/**
 * PayFlex's own @handle -> Stellar public key directory. Resolved by
 * TransferService (or the app) before every PayTag payment: a PayTag
 * payment is an ordinary on-device Stellar payment to the resolved key.
 */
@Injectable()
export class PayTagService {
  constructor(private readonly prisma: PrismaService) {}

  async register(appUserId: string, tag: string) {
    try {
      return await this.prisma.payTag.upsert({
        where: { appUserId },
        create: { appUserId, tag },
        update: { tag },
      });
    } catch (err) {
      if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002') {
        throw new ConflictException(`PayTag "${tag}" is already taken.`);
      }
      throw err;
    }
  }

  async getForUser(appUserId: string) {
    return this.prisma.payTag.findUnique({ where: { appUserId } });
  }

  /** Resolves a PayTag to the AppUser it belongs to, for constructing a transfer. */
  async resolve(tag: string) {
    const record = await this.prisma.payTag.findUnique({
      where: { tag },
      include: { appUser: true },
    });
    if (!record) throw new NotFoundException(`No user found for PayTag "${tag}".`);
    return record.appUser;
  }
}
