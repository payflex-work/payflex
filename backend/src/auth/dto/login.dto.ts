import { IsHexadecimal, IsNotEmpty, IsString, Length, Matches } from 'class-validator';

export class ChallengeDto {
  // AppUser ids are Postgres uuid() (see prisma/schema.prisma) — rejecting
  // non-uuid ids here avoids a pointless DB round trip and gives the app a
  // clear "wrong format" 400 instead of a "no such user" 404.
  @IsString()
  @Matches(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i, {
    message: 'appUserId must be a PayFlex user id (uuid).',
  })
  appUserId!: string;
}

export class LoginDto {
  @IsString()
  @Matches(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i, {
    message: 'appUserId must be a PayFlex user id (uuid).',
  })
  appUserId!: string;

  /**
   * Ed25519 signature over the challenge, hex-encoded: exactly 64 bytes
   * signed on-device with the account key = 128 hex chars. Anything else
   * can never verify, so it is rejected here with a specific message
   * instead of an ambiguous 401.
   */
  @IsHexadecimal({ message: 'signature must be a hex-encoded Ed25519 signature.' })
  @Length(128, 128, { message: 'signature must be 128 hex characters (64 bytes).' })
  signature!: string;
}

export class RefreshDto {
  @IsString()
  @IsNotEmpty()
  // JWT-shaped (header.payload.signature, base64url). Upper bound catches
  // absurd payloads; the HMAC check in TokenService does the real work.
  @Matches(/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*$/, {
    message: 'refreshToken is malformed.',
  })
  @Length(1, 4096, { message: 'refreshToken is too long.' })
  refreshToken!: string;
}
