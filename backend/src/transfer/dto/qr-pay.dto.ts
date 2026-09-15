import { IsOptional } from 'class-validator';
import {
  IsStellarAmount,
  IsStellarAssetCode,
  ValidAssetPair,
  IsNumericString,
} from '../../common/validation/validators';

/** Generate a payment-request QR: amount + asset, short-lived. */
@ValidAssetPair()
export class GenerateQrDto {
  @IsStellarAmount()
  amount!: string;

  @IsStellarAssetCode()
  assetCode!: string;

  @IsOptional()
  assetIssuer?: string;

  /** QR lifetime in seconds — bounded so tokens can't be made effectively permanent. */
  @IsOptional()
  @IsNumericString({ min: 30, max: 3600, integer: true })
  expiresInSeconds?: string;
}
