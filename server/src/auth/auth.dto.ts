import { IsEmail, IsOptional, IsString, IsUUID, MaxLength, MinLength } from 'class-validator';

export class CredentialsDto {
  @IsEmail() @MaxLength(254) email!: string;
  @IsString() @MinLength(12) @MaxLength(128) password!: string;
  @IsOptional() @IsUUID() deviceId?: string;
  @IsOptional() @IsString() @MaxLength(120) deviceName?: string;
}
