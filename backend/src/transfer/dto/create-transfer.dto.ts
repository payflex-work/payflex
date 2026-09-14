import { IsNotEmpty, IsOptional, IsString, Matches } from 'class-validator';

/**
 * Exactly one of toPublicKey / toPayTag must be set — the controller
 * validates that and resolves toPayTag to a public key before reaching
 * TransferService. There is no server-side "create transfer" step anymore:
 * the app builds, signs, and submits the payment to Horizon itself, then
 * records it via POST /users/:id/transfers/record where the backend
 * verifies the transaction on-chain before storing it.
 */
export class CreateTransferDto {
  @IsOptional()
  @IsString()
  @Matches(/^G[A-Z2-7]{55}$/, { message: 'toPublicKey must be an Ed25519 account strkey.' })
  toPublicKey?: string;

  @IsOptional()
  @IsString()
  toPayTag?: string;

  /** Decimal string, e.g. "5.00" — NOT minor units. */
  @IsString()
  @IsNotEmpty()
  amount!: string;

  /** "XLM" or an issued asset code (issued assets also need assetIssuer). */
  @IsString()
  @IsNotEmpty()
  assetCode!: string;

  @IsOptional()
  @IsString()
  assetIssuer?: string;

  @IsOptional()
  @IsString()
  description?: string;
}
