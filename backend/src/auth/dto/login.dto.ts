import { IsNotEmpty, IsString } from 'class-validator';

export class ChallengeDto {
  @IsString()
  @IsNotEmpty()
  appUserId!: string;
}

export class LoginDto {
  @IsString()
  @IsNotEmpty()
  appUserId!: string;

  @IsString()
  @IsNotEmpty()
  signature!: string;
}

export class RefreshDto {
  @IsString()
  @IsNotEmpty()
  refreshToken!: string;
}
