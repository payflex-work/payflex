import { IsStellarPublicKey } from '../../common/validation/validators';

export class SetStellarPublicKeyDto {
  // Validated with the Stellar SDK's own strkey decoder (base32 checksum
  // verified) — a shape-correct but checksum-broken key is rejected here,
  // matching the service-level check (belt and suspenders: a wrong key
  // registered once is immutable, so it must die at the door).
  @IsStellarPublicKey({
    message: 'stellarPublicKey must be a valid Ed25519 account strkey (G…, checksum verified).',
  })
  stellarPublicKey!: string;
}
