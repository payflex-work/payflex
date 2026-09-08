import { IsIn, IsNotEmpty, IsOptional, IsString, ValidateIf } from 'class-validator';

export class CreateStandingPlanDto {
  @IsString()
  @IsNotEmpty()
  name!: string;

  @IsString()
  @IsNotEmpty()
  currency!: string;

  @IsString()
  @IsNotEmpty()
  amount!: string;

  @IsIn(['DAILY', 'WEEKLY', 'MONTHLY'])
  frequency!: 'DAILY' | 'WEEKLY' | 'MONTHLY';

  // Exactly one recipient field must be set.
  @ValidateIf((dto: CreateStandingPlanDto) => !dto.toPayTag)
  @IsString()
  @IsNotEmpty()
  toBmoniUserId?: string;

  @ValidateIf((dto: CreateStandingPlanDto) => !dto.toBmoniUserId)
  @IsString()
  @IsNotEmpty()
  toPayTag?: string;

  @IsOptional()
  @IsString()
  description?: string;
}
