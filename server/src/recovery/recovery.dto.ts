import { IsString, MaxLength, MinLength } from 'class-validator';

export class RecoveryEnvelopeDto {
  @IsString() @MinLength(16) @MaxLength(32) nonce!: string;
  @IsString() @MinLength(64) @MaxLength(256) ciphertext!: string;
}
