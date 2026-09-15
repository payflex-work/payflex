import { IsOptional } from 'class-validator';
import {
  IsStellarPublicKey,
  IsStellarAmount,
  IsStellarAssetCode,
  IsPayTag,
  ValidAssetPair,
  SanitizedText,
} from '../../common/validation/validators';

/**
 * Exactly one of toPublicKey / toPayTag must be set — the controller
 * validates that and resolves toPayTag to a public key before reaching
 * TransferService. There is no server-side "create transfer" step anymore:
 * the app builds, signs, and submits the payment to Horizon itself, then
 * records it via POST /users/:id/transfers/record where the backend
 * verifies the transaction on-chain before storing it.
 */
@ValidAssetPair()
export class CreateTransferDto {
  @IsOptional()
  @IsStellarPublicKey({ message: 'toPublicKey must be a valid Stellar Ed25519 account strkey (G…).' })
  toPublicKey?: string;

  @IsOptional()
  @IsPayTag({ message: 'toPayTag must be 3-20 characters: lowercase letters, digits, underscore.' })
  toPayTag?: string;

  /**
   * Decimal string, e.g. "5.00" — NOT minor units. Validated as strictly
   * positive, ≤7 decimals, ≤1e12 — matching Stellar's own amount rules so
   * a bad value dies here with a clear message, not on Horizon.
   */
  @IsStellarAmount()
  amount!: string;

  /** "XLM" or an issued asset code (issued assets also need assetIssuer). */
  @IsStellarAssetCode()
  assetCode!: string;

  @IsOptional()
  assetIssuer?: string;

  @IsOptional()
  @SanitizedText({ max: 200 })
  description?: string;
}
