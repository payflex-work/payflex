import { IsBoolean } from 'class-validator';

export class SetAdminStatusDto {
  @IsBoolean()
  isAdmin!: boolean;
}
