import { Transform } from 'class-transformer';
import {
  IsString,
  MaxLength,
  MinLength,
  ValidateIf,
  ValidatorConstraint,
  ValidatorConstraintInterface,
  ValidationArguments,
  registerDecorator,
  ValidationOptions,
  isNumberString,
} from 'class-validator';
import { StrKey } from '@stellar/stellar-sdk';

/**
 * Shared request-validation building blocks for every PayFlex DTO.
 *
 * Conventions that hold app-wide (the Flutter side mirrors these in
 * app/lib/utils/validators.dart — keep the two consistent):
 *
 *  - Amounts cross the wire as DECIMAL STRINGS, exactly as they will appear
 *    in a Stellar payment operation (e.g. "5.0000000"). Stellar supports at
 *    most 7 decimal places, and Horizon rejects amounts that don't parse as
 *    a decimal number, so anything else is rejected here first with a clear
 *    message instead of a confusing on-chain or Horizon error later.
 *  - Stellar public keys are validated with the Stellar SDK's own strkey
 *    decoder (base32 checksum verified), not just a shape regex — a typo'd
 *    key that happens to be 56 valid base32 chars must NOT pass.
 *  - Free text is trimmed, stripped of control characters, and length-capped
 *    so nothing oversized or unrenderable reaches the database or the UI.
 */

/** Largest amount accepted anywhere: 1,000,000,000,000 (1e12). */
export const MAX_STELLAR_AMOUNT = '1000000000000';
/** Stellar's native precision: at most 7 decimal places on any amount. */
export const MAX_AMOUNT_DECIMALS = 7;

/**
 * Shape + checksum validation for an Ed25519 account strkey ("G…"). Uses
 * StrKey.isValidEd25519PublicKey so the base32 checksum is actually verified.
 */
export function IsStellarPublicKey(validationOptions?: ValidationOptions) {
  return function (object: object, propertyName: string) {
    registerDecorator({
      name: 'isStellarPublicKey',
      target: object.constructor,
      propertyName,
      options: validationOptions,
      validator: {
        validate(value: unknown) {
          if (typeof value !== 'string') return false;
          if (!/^G[A-Z2-7]{55}$/.test(value)) return false;
          try {
            return StrKey.isValidEd25519PublicKey(value);
          } catch {
            return false;
          }
        },
        defaultMessage(args: ValidationArguments) {
          return `${args.property} must be a valid Stellar Ed25519 account strkey (G…, checksum verified).`;
        },
      },
    });
  };
}

/** Soroban contract id ("C…"), checksum verified via the SDK. */
export function IsStellarContractId(validationOptions?: ValidationOptions) {
  return function (object: object, propertyName: string) {
    registerDecorator({
      name: 'isStellarContractId',
      target: object.constructor,
      propertyName,
      options: validationOptions,
      validator: {
        validate(value: unknown) {
          if (typeof value !== 'string') return false;
          if (!/^C[A-Z2-7]{55}$/.test(value)) return false;
          try {
            return StrKey.isValidContract(value);
          } catch {
            return false;
          }
        },
        defaultMessage(args: ValidationArguments) {
          return `${args.property} must be a valid Soroban contract id (C…, checksum verified).`;
        },
      },
    });
  };
}

/**
 * Horizon claimable-balance id: "00000000" + 64 lowercase hex chars (72
 * total) — see any Horizon /claimable_balances record.
 */
export function IsClaimableBalanceId(validationOptions?: ValidationOptions) {
  return function (object: object, propertyName: string) {
    registerDecorator({
      name: 'isClaimableBalanceId',
      target: object.constructor,
      propertyName,
      options: validationOptions,
      validator: {
        validate(value: unknown) {
          return typeof value === 'string' && /^00000000[0-9a-f]{64}$/.test(value);
        },
        defaultMessage(args: ValidationArguments) {
          return `${args.property} must be a Horizon claimable-balance id (00000000…, 72 hex chars).`;
        },
      },
    });
  };
}

/** A Stellar transaction hash: 64 lowercase hex characters. */
export function IsStellarTxHash(validationOptions?: ValidationOptions) {
  return function (object: object, propertyName: string) {
    registerDecorator({
      name: 'isStellarTxHash',
      target: object.constructor,
      propertyName,
      options: validationOptions,
      validator: {
        validate(value: unknown) {
          return typeof value === 'string' && /^[0-9a-f]{64}$/.test(value);
        },
        defaultMessage(args: ValidationArguments) {
          return `${args.property} must be a 64-character lowercase hex transaction hash.`;
        },
      },
    });
  };
}

/**
 * A decimal amount string exactly as it will appear on-chain: strictly
 * positive, at most [max] (default 1e12), at most 7 decimal places, no
 * exponent/leading-plus/NaN forms. "5.0000000", "0.0000001" pass;
 * "-5", "0", "5e2", "5.12345678", "abc", "NaN", "Infinity" fail.
 */
export function IsStellarAmount(
  options: { max?: string } = {},
  validationOptions?: ValidationOptions,
) {
  const max = options.max ?? MAX_STELLAR_AMOUNT;
  return function (object: object, propertyName: string) {
    registerDecorator({
      name: 'isStellarAmount',
      target: object.constructor,
      propertyName,
      options: validationOptions,
      validator: {
        validate(value: unknown) {
          if (typeof value !== 'string' || value.length === 0 || value.length > 20) return false;
          if (!/^\d+(\.\d{1,7})?$/.test(value)) return false;
          return Number(value) > 0 && Number(value) <= Number(max);
        },
        defaultMessage(args: ValidationArguments) {
          return (
            `${args.property} must be a positive decimal string (e.g. "5.00"), at most ${MAX_AMOUNT_DECIMALS} ` +
            `decimal places, no larger than ${max}.`
          );
        },
      },
    });
  };
}

/**
 * Stellar asset code: the native asset "XLM" or a 1-12 uppercase
 * alphanumeric issued-asset code (Stellar's own limit: alphanum4/alphanum12).
 */
export function IsStellarAssetCode(validationOptions?: ValidationOptions) {
  return function (object: object, propertyName: string) {
    registerDecorator({
      name: 'isStellarAssetCode',
      target: object.constructor,
      propertyName,
      options: validationOptions,
      validator: {
        validate(value: unknown) {
          return typeof value === 'string' && (value === 'XLM' || /^[A-Z0-9]{1,12}$/.test(value));
        },
        defaultMessage(args: ValidationArguments) {
          return `${args.property} must be "XLM" or a 1-12 character uppercase alphanumeric issued-asset code.`;
        },
      },
    });
  };
}

/** PayFlex PayTag: 3-20 lowercase alphanumerics/underscores. */
export function IsPayTag(validationOptions?: ValidationOptions) {
  return function (object: object, propertyName: string) {
    registerDecorator({
      name: 'isPayTag',
      target: object.constructor,
      propertyName,
      options: validationOptions,
      validator: {
        validate(value: unknown) {
          return typeof value === 'string' && /^[a-z0-9_]{3,20}$/.test(value);
        },
        defaultMessage(args: ValidationArguments) {
          return `${args.property} must be 3-20 characters: lowercase letters, digits, underscore.`;
        },
      },
    });
  };
}

/**
 * Issued-asset pairing: when assetCode is not "XLM", assetIssuer must be
 * present and a valid account strkey; when assetCode IS "XLM", an issuer
 * is not allowed. Class-level decorator — attach to DTOs that carry the
 * assetCode/assetIssuer pair.
 *
 * Registered on the assetCode property (always present — it is required
 * with its own validator): class-validator skips decorators whose property
 * key is absent from the incoming object, so anchoring on the OPTIONAL
 * assetIssuer would let an entirely-missing issuer slip past the
 * non-XLM branch.
 */
export function ValidAssetPair() {
  // NOTE: this is a CLASS decorator — `object` here IS the DTO constructor
  // itself, so it is passed to registerDecorator directly (using
  // object.constructor would register onto Function and never fire).
  return function (object: object) {
    registerDecorator({
      name: 'validAssetPair',
      target: object as Parameters<typeof registerDecorator>[0]['target'],
      propertyName: 'assetCode',
      constraints: [],
      validator: {
        validate(_value: unknown, args: ValidationArguments) {
          const dto = args.object as { assetCode?: string; assetIssuer?: unknown };
          const issuer = dto.assetIssuer;
          if (dto.assetCode === 'XLM') return issuer == null;
          // Non-native asset: issuer required + must be a real strkey.
          if (typeof issuer !== 'string') return false;
          if (!/^G[A-Z2-7]{55}$/.test(issuer)) return false;
          try {
            return StrKey.isValidEd25519PublicKey(issuer);
          } catch {
            return false;
          }
        },
        defaultMessage(args: ValidationArguments) {
          const dto = args.object as { assetCode?: string };
          return dto.assetCode === 'XLM'
            ? 'assetIssuer must be empty for the native asset XLM.'
            : 'assetIssuer must be a valid Stellar account strkey (G…) whenever assetCode is not XLM.';
        },
      },
    });
  };
}

/** Strips control characters (except tab/newline for multi-line text) and trims. */
export function sanitizeText(value: unknown): string {
  if (typeof value !== 'string') return value as string;
  // eslint-disable-next-line no-control-regex
  return value.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, '').trim();
}

/**
 * Free-text field: sanitized (control chars stripped, trimmed) then
 * length-checked. Use for names, descriptions, notes, memos — anything a
 * human types that gets stored and displayed back.
 */
export function SanitizedText(options: { max: number; min?: number }) {
  return function (object: object, propertyName: string) {
    // Sanitize first (class-transformer runs transforms before validation).
    Transform(({ value }) => sanitizeText(value))(object, propertyName);
    IsString()(object, propertyName);
    if (options.min) MinLength(options.min)(object, propertyName);
    MaxLength(options.max, {
      message: `${propertyName} must be at most ${options.max} characters.`,
    })(object, propertyName);
  };
}

/**
 * Numeric string field with an inclusive range — for fields like
 * expiresInDays that arrive as strings from the app. Rejects "banana",
 * "NaN", and out-of-range values with a specific message instead of
 * producing NaN-driven Invalid Dates downstream.
 */
export function IsNumericString(options: { min: number; max: number; integer?: boolean }) {
  return function (object: object, propertyName: string) {
    registerDecorator({
      name: 'isNumericString',
      target: object.constructor,
      propertyName,
      options: {},
      validator: {
        validate(value: unknown) {
          if (typeof value !== 'string' || value.length === 0 || value.length > 12) return false;
          if (!isNumberString(value, options.integer ? { no_symbols: true } : {})) return false;
          const n = Number(value);
          return n >= options.min && n <= options.max;
        },
        defaultMessage(args: ValidationArguments) {
          return `${args.property} must be a number between ${options.min} and ${options.max}.`;
        },
      },
    });
  };
}

/**
 * Convenience re-export so DTOs can express "optional but validated when
 * present" with the SDK-backed validators above.
 */
export { IsString, ValidateIf };
