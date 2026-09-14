import { BadRequestException, Injectable } from '@nestjs/common';
import { IsOptional, IsString } from 'class-validator';
import { HmacTokenService } from '../common/hmac-token.service';
import { UsersService } from '../users/users.service';

export interface QrPayload {
  recipientAppUserId: string;
  recipientStellarPublicKey: string;
  amount: string;
  assetCode: string;
  assetIssuer?: string;
  expiresAt: string;
}

export class GenerateQrDto {
  @IsString()
  amount!: string;

  @IsString()
  assetCode!: string;

  @IsOptional()
  @IsString()
  assetIssuer?: string;

  @IsOptional()
  @IsString()
  expiresInSeconds?: number;
}

/**
 * App-layer QR Pay — a short-lived, HMAC-signed payload naming a
 * recipient/amount/asset (see HmacTokenService). Stellar-native now: the
 * QR carries the recipient's Stellar public key, so the payer's app can
 * build the payment entirely on-device. Scanning resolves via `decode`;
 * after the payer signs and submits, they record the payment through
 * TransferService with kind=QR_PAY and this token as qrTokenRef.
 */
@Injectable()
export class QrPayService {
  constructor(
    private readonly tokens: HmacTokenService,
    private readonly users: UsersService,
  ) {}

  async generate(
    appUserId: string,
    params: { amount: string; assetCode: string; assetIssuer?: string; expiresInSeconds?: number },
  ): Promise<{ token: string; payload: QrPayload }> {
    const user = await this.users.findById(appUserId);
    if (!user.stellarPublicKey) {
      throw new BadRequestException('You must register a Stellar public key before generating a payment QR.');
    }
    const expiresAt = new Date(
      Date.now() + (Number(params.expiresInSeconds ?? 300)) * 1000,
    ).toISOString();
    const payload: QrPayload = {
      recipientAppUserId: user.id,
      recipientStellarPublicKey: user.stellarPublicKey,
      amount: params.amount,
      assetCode: params.assetCode,
      assetIssuer: params.assetIssuer,
      expiresAt,
    };
    return { token: this.tokens.sign(payload), payload };
  }

  /** Scanning a QR resolves to this — a pre-filled confirm screen shows this before paying. */
  decode(token: string): QrPayload {
    return this.tokens.verify<QrPayload>(token);
  }
}
