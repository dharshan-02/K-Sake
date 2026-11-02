import { Module } from '@nestjs/common';
import { RecoveryController } from './recovery.controller';
import { RecoveryService } from './recovery.service';
import { AuthModule } from '../auth/auth.module';

@Module({ imports: [AuthModule], controllers: [RecoveryController], providers: [RecoveryService] })
export class RecoveryModule {}
