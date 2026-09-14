import { IsNotEmpty, IsOptional, IsString, Matches } from 'class-validator';

/**
 * The app's report of a payment it has already built, signed on-device, and
 * submitted to Horizon. NOTHING here is trusted: StellarService.verifyPayment
 * re-reads the real transaction and every field must match the chain before
 * a TransferRecord is written. kind is one of TRANSFER | QR_PAY |
 * OFFLINE_REDEMPTION | SPLIT_BILL | STANDING_PLAN | LINK_CLAIM.
 */
export class RecordTransferDto {
  @IsString()
  @IsNotEmpty()
  stellarTxHash!: string;

  @IsString()
  @Matches(/^G[A-Z2-7]{55}$/, { message: 'fromPublicKey must be an Ed25519 account strkey.' })
  fromPublicKey!: string;

  @IsString()
  @Matches(/^G[A-Z2-7]{55}$/, { message: 'toPublicKey must be an Ed25519 account strkey.' })
  toPublicKey!: string;

  /** Decimal string exactly as submitted on-chain, e.g. "5.0000000". */
  @IsString()
  @IsNotEmpty()
  amount!: string;

  @IsString()
  @IsNotEmpty()
  assetCode!: string;

  @IsOptional()
  @IsString()
  assetIssuer?: string;

  @IsOptional()
  @IsString()
  kind?: string;

  @IsOptional()
  @IsString()
  qrTokenRef?: string;

  @IsOptional()
  @IsString()
  splitBillId?: string;

  @IsOptional()
  @IsString()
  standingPlanId?: string;

  @IsOptional()
  @IsString()
  offlineAuthorizationId?: string;

  @IsOptional()
  @IsString()
  memo?: string;
}
