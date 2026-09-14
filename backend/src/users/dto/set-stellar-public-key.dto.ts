import { IsString, Matches } from 'class-validator';

export class SetStellarPublicKeyDto {
  @IsString()
  @Matches(/^G[A-Z2-7]{55}$/, { message: 'stellarPublicKey must be an Ed25519 account strkey (G...).' })
  stellarPublicKey!: string;
}
