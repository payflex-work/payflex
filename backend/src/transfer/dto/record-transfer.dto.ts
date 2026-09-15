import { IsOptional } from 'class-validator';
import {
  IsStellarPublicKey,
  IsStellarTxHash,
  IsStellarAmount,
  IsStellarAssetCode,
  ValidAssetPair,
  SanitizedText,
} from '../../common/validation/validators';

/**
 * The app's report of a payment it has already built, signed on-device, and
 * submitted to Horizon. NOTHING here is trusted: StellarService.verifyPayment
 * re-reads the real transaction and every field must match the chain before
 * a TransferRecord is written. kind is one of TRANSFER | QR_PAY |
 * OFFLINE_REDEMPTION | SPLIT_BILL | STANDING_PLAN | LINK_CLAIM.
 */
@ValidAssetPair()
export class RecordTransferDto {
  @IsStellarTxHash({ message: 'stellarTxHash must be a 64-character lowercase hex transaction hash.' })
  stellarTxHash!: string;

  @IsStellarPublicKey({ message: 'fromPublicKey must be a valid Stellar Ed25519 account strkey (G…).' })
  fromPublicKey!: string;

  @IsStellarPublicKey({ message: 'toPublicKey must be a valid Stellar Ed25519 account strkey (G…).' })
  toPublicKey!: string;

  /** Decimal string exactly as submitted on-chain, e.g. "5.0000000". */
  @IsStellarAmount()
  amount!: string;

  @IsStellarAssetCode()
  assetCode!: string;

  @IsOptional()
  assetIssuer?: string;

  @IsOptional()
  kind?: string; // membership of VALID_KINDS enforced in TransferService (clear message naming the allowed set)

  @IsOptional()
  @SanitizedText({ max: 100 })
  qrTokenRef?: string;

  @IsOptional()
  @SanitizedText({ max: 64 })
  splitBillId?: string;

  @IsOptional()
  @SanitizedText({ max: 64 })
  standingPlanId?: string;

  @IsOptional()
  @SanitizedText({ max: 100 })
  offlineAuthorizationId?: string;

  @IsOptional()
  @SanitizedText({ max: 140 })
  memo?: string;
}
