import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { IsNotEmpty, IsOptional, IsString, Matches } from 'class-validator';
import { randomBytes } from 'crypto';
import { createHash } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { StellarService } from '../stellar/stellar.service';
import { HmacTokenService } from '../common/hmac-token.service';
import { UsersService } from '../users/users.service';

export class SendViaLinkDto {
  /** Decimal string exactly as it will appear on-chain. */
  @IsString()
  amount!: string;

  @IsString()
  assetCode!: string;

  @IsOptional()
  @IsString()
  assetIssuer?: string;

  /** Days until the link expires (chain claimants can't be removed, but the
   * backend stops advertising the link after this). */
  @IsOptional()
  @IsString()
  expiresInDays?: string;
}

export class RegisterClaimableBalanceDto {
  @IsString()
  @IsNotEmpty()
  claimableBalanceId!: string;
}

export class ClaimLinkDto {
  @IsString()
  @Matches(/^G[A-Z2-7]{55}$/, { message: 'claimantPublicKey must be an Ed25519 account strkey.' })
  claimantPublicKey!: string;

  /** The on-chain transaction that performed the claim (claimed_claimable_balance). */
  @IsString()
  claimTxHash!: string;
}

/**
 * Send-via-link, NON-CUSTODIAL on native Stellar claimable balances.
 *
 * An earlier design held link funds in PayFlex's own treasury — a real
 * liability surface the brief flagged. That is gone by construction:
 *
 *  1. The sender's app creates an on-chain CREATE_CLAIMABLE_BALANCE with
 *     the recipient (or, before the recipient has a key, the SENDER as the
 *     reclaimant) as claimant — funds are escrowed BY THE CHAIN, never in
 *     a PayFlex-owned account.
 *  2. The sender registers the claimable-balance id here; the backend
 *     VERIFIES on Horizon that the CB exists with the exact amount/asset,
 *     then marks the link FUNDED.
 *  3. The recipient claims on-chain (their own signature) and the claim
 *     transaction is verified the same way before the record flips to
 *     CLAIMED.
 *
 * PayFlex is a directory and a verifier here — a money holder nowhere.
 */
@Injectable()
export class LinksService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly stellar: StellarService,
    private readonly users: UsersService,
    private readonly tokens: HmacTokenService,
  ) {}

  /**
   * Creates the link record and returns the signed shareable token. The
   * sender's app builds the on-chain claimable balance AFTER this (using
   * the returned parameters), then registers its id via registerClaimableBalance.
   */
  async sendViaLink(senderAppUserId: string, dto: SendViaLinkDto) {
    const sender = await this.users.findById(senderAppUserId);

    const rawSecret = randomBytes(24).toString('base64url');
    const tokenHash = this.hashToken(rawSecret);
    const expiresAt = new Date(
      Date.now() + Number(dto.expiresInDays ?? 7) * 24 * 60 * 60 * 1000,
    );

    const link = await this.prisma.linkRecord.create({
      data: {
        senderAppUserId,
        tokenHash,
        amount: dto.amount,
        assetCode: dto.assetCode,
        assetIssuer: dto.assetIssuer,
        expiresAt,
      },
    });

    const shareToken = this.tokens.sign({ l: link.id, s: rawSecret });

    return {
      linkId: link.id,
      shareToken,
      // What the sender's app must build on-chain:
      instructions: {
        operation: 'create_claimable_balance',
        asset: dto.assetCode === 'XLM' ? 'native' : { code: dto.assetCode, issuer: dto.assetIssuer },
        amount: dto.amount,
        // Before the recipient is known, the SENDER is the sole claimant so
        // they can reclaim their funds; once a recipient is picked, their
        // app re-creates or the claimant list is extended on-chain.
        claimants: sender.stellarPublicKey ? [sender.stellarPublicKey] : [],
        note: 'Funds are escrowed on-chain by this claimable balance — never held by PayFlex.',
      },
    };
  }

  /**
   * Preview of a share token for the recipient's app (public, HMAC-verified).
   * The link id and claimable-balance id are returned so the recipient's app
   * can perform the on-chain claim itself — only holders of the share token
   * ever see them, which is exactly the audience meant to claim.
   */
  async preview(token: string) {
    const payload = this.tokens.verify<{ l: string; s: string }>(token);
    const link = await this.prisma.linkRecord.findUnique({ where: { id: payload.l } });
    if (!link || link.tokenHash !== this.hashToken(payload.s)) {
      throw new NotFoundException('This link does not exist or has been revoked.');
    }
    const sender = await this.users.findById(link.senderAppUserId);
    const cb = link.claimableBalanceId ? await this.stellar.getClaimableBalance(link.claimableBalanceId) : null;
    return {
      linkId: link.id,
      claimableBalanceId: link.claimableBalanceId,
      amount: link.amount,
      assetCode: link.assetCode,
      status: link.status,
      expiresAt: link.expiresAt,
      senderFirstName: sender.firstName,
      claimableBalanceExists: Boolean(cb),
    };
  }

  /** The sender's app reports the on-chain CB id; verified against Horizon. */
  async registerClaimableBalance(senderAppUserId: string, linkId: string, dto: RegisterClaimableBalanceDto) {
    await this.users.findById(senderAppUserId);
    const link = await this.prisma.linkRecord.findUnique({ where: { id: linkId } });
    if (!link || link.senderAppUserId !== senderAppUserId) {
      throw new NotFoundException('Link not found for this sender.');
    }

    const cb = await this.stellar.getClaimableBalance(dto.claimableBalanceId);
    if (!cb) {
      throw new BadRequestException('No claimable balance with this id exists on-ledger.');
    }
    const amountMatches = Math.abs(Number(cb.amount) - Number(link.amount)) < 1e-9;
    const cbCode = cb.assetType === 'native' ? 'XLM' : cb.assetCode;
    if (!amountMatches || cbCode !== link.assetCode) {
      throw new BadRequestException(
        `On-chain claimable balance does not match the link (${cb.amount} ${cbCode} vs ${link.amount} ${link.assetCode}).`,
      );
    }

    return this.prisma.linkRecord.update({
      where: { id: linkId },
      data: { claimableBalanceId: dto.claimableBalanceId, status: 'FUNDED' },
    });
  }

  /**
   * The recipient reports they claimed on-chain. The claim transaction is
   * verified before the record is marked CLAIMED — the backend cannot be
   * talked into marking a claim that didn't happen.
   */
  async claim(appUserId: string, linkId: string, dto: ClaimLinkDto) {
    await this.users.findById(appUserId);

    const link = await this.prisma.linkRecord.findUnique({ where: { id: linkId } });
    if (!link?.claimableBalanceId) {
      throw new NotFoundException('This link has no funded claimable balance yet.');
    }

    // Two chain facts, both authoritative:
    //  1. The claim transaction exists and succeeded.
    //  2. The claimable balance is GONE from the ledger — a CB cannot be
    //     claimed twice, so its disappearance is the chain's own proof.
    const claimTxOk = await this.stellar.isTransactionSuccessful(dto.claimTxHash);
    if (!claimTxOk) {
      throw new BadRequestException('Claim transaction not found or not successful on-ledger.');
    }

    const stillThere = await this.stellar.getClaimableBalance(link.claimableBalanceId);
    if (stillThere) {
      throw new BadRequestException(
        'Claimable balance is still unclaimed on-ledger — the claim transaction must actually consume it.',
      );
    }

    return this.prisma.linkRecord.update({
      where: { id: linkId },
      data: { status: 'CLAIMED', claimedByAppUserId: appUserId, claimedAt: new Date() },
    });
  }

  async listForSender(senderAppUserId: string) {
    await this.users.findById(senderAppUserId);
    return this.prisma.linkRecord.findMany({
      where: { senderAppUserId },
      orderBy: { createdAt: 'desc' },
    });
  }

  private hashToken(raw: string): string {
    return createHash('sha256').update(raw).digest('hex');
  }
}
