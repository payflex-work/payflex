import { IsString, IsNumber, IsOptional, Min, MaxLength } from 'class-validator';

export class CreateSafeboxDto {
  @IsString()
  @MaxLength(50)
  name: string;

  @IsString()
  @MaxLength(200)
  description: string;

  @IsOptional()
  @IsNumber()
  @Min(1)
  targetAmount?: number;
}

export class ContributeSafeboxDto {
  @IsNumber()
  @Min(1)
  amount: number;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  note?: string;
}

export class WithdrawSafeboxDto {
  @IsNumber()
  @Min(1)
  amount: number;

  @IsString()
  @MaxLength(100)
  note: string;

  @IsString()
  recipientAccountId: string;
}

export class UpdateMemberRoleDto {
  @IsString()
  targetUserId: string;

  @IsString()
  role: 'ADMIN' | 'MEMBER';
}

export class InitiateOwnershipTransferDto {
  @IsString()
  newOwnerUserId: string;
}

export class ConfirmOwnershipTransferDto {
  @IsString()
  transferToken: string;
}
