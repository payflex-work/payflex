import { IsEmail, IsNotEmpty, IsString, Matches } from 'class-validator';
import { SanitizedText } from '../../common/validation/validators';

export class CreateUserDto {
  @SanitizedText({ max: 50, min: 1 })
  firstName!: string;

  @SanitizedText({ max: 50, min: 1 })
  lastName!: string;

  // Cap before the DB sees it; IsEmail does the real format work.
  @IsEmail({}, { message: 'email must be a valid email address.' })
  @IsNotEmpty()
  email!: string;

  // E.164, e.g. +2348000000001 — a bare local-format number is rejected.
  @Matches(/^\+[1-9]\d{6,14}$/, {
    message: 'phoneNumber must be E.164, e.g. +2348000000001',
  })
  phoneNumber!: string;
}
