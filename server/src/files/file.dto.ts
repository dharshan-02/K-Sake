import { IsDateString, IsInt, IsString, IsUUID, Max, MaxLength, Min, MinLength } from 'class-validator';

export class CreateFileDto {
  @IsUUID() id!: string;
  @IsString() @MinLength(1) @MaxLength(255) name!: string;
  @IsString() @MinLength(1) @MaxLength(160) mimeType!: string;
  @IsInt() @Min(1) @Max(5 * 1024 * 1024 * 1024) size!: number;
}

export class RenameFileDto {
  @IsString() @MinLength(1) @MaxLength(255) name!: string;
  @IsDateString() expectedUpdatedAt!: string;
}
