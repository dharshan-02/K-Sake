import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { FilesModule } from '../files/files.module';
import { AccountController } from './account.controller';

@Module({
  imports: [AuthModule, FilesModule],
  controllers: [AccountController],
})
export class AccountModule {}
