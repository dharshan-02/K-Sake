import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(private readonly jwt: JwtService) {}
  async canActivate(context: ExecutionContext) {
    const req = context.switchToHttp().getRequest();
    const token = req.headers.authorization?.match(/^Bearer (.+)$/i)?.[1];
    if (!token) throw new UnauthorizedException();
    try {
      const claims = await this.jwt.verifyAsync(token, { issuer: 'keepsake-api', audience: 'keepsake-client' });
      req.user = { id: claims.sub as string, email: claims.email as string };
      return true;
    } catch { throw new UnauthorizedException(); }
  }
}
