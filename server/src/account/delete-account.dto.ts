import { IsString, MaxLength, MinLength } from 'class-validator';

export class DeleteAccountDto {
  @IsString() @MinLength(1) @MaxLength(128) password!: string;
}
