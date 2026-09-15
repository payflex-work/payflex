import { IsPayTag } from '../../common/validation/validators';

export class RegisterPayTagDto {
  // Lowercase alnum/underscore, 3-20 chars — deliberately conservative
  // for a first pass; loosen later if product wants unicode handles etc.
  // (Shared with the Flutter side's PayTag validator — keep in sync.)
  @IsPayTag({ message: 'tag must be 3-20 characters: lowercase letters, digits, underscore' })
  tag!: string;
}
