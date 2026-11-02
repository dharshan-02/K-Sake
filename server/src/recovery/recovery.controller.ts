import { Body, Controller, Get, Put, Req, UseGuards } from '@nestjs/common';
import { Request } from 'express';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { RecoveryEnvelopeDto } from './recovery.dto';
import { RecoveryService } from './recovery.service';

type AuthRequest = Request & { user: { id: string } };

@UseGuards(JwtAuthGuard)
@Controller('keys/recovery')
export class RecoveryController {
  constructor(private readonly recovery: RecoveryService) {}
  @Put() save(@Req() req: AuthRequest, @Body() dto: RecoveryEnvelopeDto) { return this.recovery.save(req.user.id, dto.nonce, dto.ciphertext); }
  @Get() get(@Req() req: AuthRequest) { return this.recovery.get(req.user.id); }
}
