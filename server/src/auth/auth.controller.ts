import { Body, Controller, Delete, Get, Param, ParseUUIDPipe, Post, Req, UseGuards } from '@nestjs/common';
import { AuthService } from './auth.service';
import { CredentialsDto } from './auth.dto';
import { JwtAuthGuard } from './jwt-auth.guard';

@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}
  @Post('register') register(@Body() dto: CredentialsDto) { return this.auth.register(dto.email, dto.password, dto.deviceId, dto.deviceName); }
  @Post('login') login(@Body() dto: CredentialsDto) { return this.auth.login(dto.email, dto.password, dto.deviceId, dto.deviceName); }
  @UseGuards(JwtAuthGuard)
  @Get('devices') devices(@Req() req: { user: { id: string } }) { return this.auth.listDevices(req.user.id); }
  @UseGuards(JwtAuthGuard)
  @Delete('devices/:id') revokeDevice(@Req() req: { user: { id: string } }, @Param('id', new ParseUUIDPipe()) id: string) {
    return this.auth.revokeDevice(req.user.id, id);
  }
}
