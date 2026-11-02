import { Body, Controller, Post } from '@nestjs/common';
import { AuthService } from './auth.service';
import { CredentialsDto } from './auth.dto';

@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}
  @Post('register') register(@Body() dto: CredentialsDto) { return this.auth.register(dto.email, dto.password); }
  @Post('login') login(@Body() dto: CredentialsDto) { return this.auth.login(dto.email, dto.password); }
}
