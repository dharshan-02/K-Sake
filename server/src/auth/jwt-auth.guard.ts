import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { AuthService } from './auth.service';

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(private readonly jwt: JwtService, private readonly auth: AuthService) {}
  async canActivate(context: ExecutionContext) {
    const req = context.switchToHttp().getRequest();
    const token = req.headers.authorization?.match(/^Bearer (.+)$/i)?.[1];
    if (!token) throw new UnauthorizedException();
    try {
      const claims = await this.jwt.verifyAsync(token, { issuer: 'keepsake-api', audience: 'keepsake-client' });
      if (typeof claims.sid !== 'string' || !(await this.auth.validateSession(claims.sub as string, claims.sid))) throw new UnauthorizedException();
      req.user = { id: claims.sub as string, email: claims.email as string, sessionId: claims.sid };
      return true;
    } catch { throw new UnauthorizedException(); }
  }
}
