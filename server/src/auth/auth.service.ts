import { ConflictException, Injectable, NotFoundException, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as argon2 from 'argon2';
import { randomUUID } from 'node:crypto';
import { PrismaService } from '../prisma/prisma.module';

@Injectable()
export class AuthService {
  constructor(private readonly prisma: PrismaService, private readonly jwt: JwtService) {}

  async register(email: string, password: string, deviceId?: string, deviceName?: string) {
    const normalized = email.trim().toLowerCase();
    const existing = await this.prisma.user.findUnique({ where: { email: normalized } });
    if (existing) throw new ConflictException('Account already exists');
    const passwordHash = await argon2.hash(password, { type: argon2.argon2id, memoryCost: 19_456, timeCost: 2, parallelism: 1 });
    const user = await this.prisma.user.create({ data: { email: normalized, passwordHash } });
    return this.issue(user.id, user.email, deviceId, deviceName);
  }

  async login(email: string, password: string, deviceId?: string, deviceName?: string) {
    const user = await this.prisma.user.findUnique({ where: { email: email.trim().toLowerCase() } });
    if (!user || !(await argon2.verify(user.passwordHash, password))) throw new UnauthorizedException('Invalid email or password');
    return this.issue(user.id, user.email, deviceId, deviceName);
  }

  async verifyAccountPassword(userId: string, password: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user || !(await argon2.verify(user.passwordHash, password))) {
      throw new UnauthorizedException('Password is incorrect');
    }
  }

  async revokeAllDevices(userId: string) {
    await this.prisma.deviceSession.updateMany({
      where: { userId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
  }

  async deleteAccountRecord(userId: string) {
    await this.prisma.user.delete({ where: { id: userId } });
  }

  private async issue(id: string, email: string, deviceId?: string, deviceName?: string) {
    const stableDeviceId = deviceId ?? randomUUID();
    const session = await this.prisma.deviceSession.upsert({
      where: { userId_deviceId: { userId: id, deviceId: stableDeviceId } },
      create: { userId: id, deviceId: stableDeviceId, deviceName: this.cleanDeviceName(deviceName), lastSeenAt: new Date() },
      update: { deviceName: this.cleanDeviceName(deviceName), lastSeenAt: new Date(), revokedAt: null },
    });
    const accessToken = await this.jwt.signAsync({ sub: id, email, sid: session.id });
    return { accessToken, tokenType: 'Bearer', expiresIn: 900 };
  }

  async validateSession(userId: string, sessionId: string) {
    const session = await this.prisma.deviceSession.findFirst({ where: { id: sessionId, userId, revokedAt: null } });
    if (!session) return false;
    if (Date.now() - session.lastSeenAt.getTime() > 5 * 60 * 1000) {
      await this.prisma.deviceSession.update({ where: { id: session.id }, data: { lastSeenAt: new Date() } });
    }
    return true;
  }

  async listDevices(userId: string) {
    return this.prisma.deviceSession.findMany({
      where: { userId, revokedAt: null },
      select: { id: true, deviceName: true, createdAt: true, lastSeenAt: true },
      orderBy: { lastSeenAt: 'desc' },
    });
  }

  async revokeDevice(userId: string, sessionId: string) {
    const result = await this.prisma.deviceSession.updateMany({
      where: { id: sessionId, userId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    if (result.count === 0) throw new NotFoundException('Device session not found');
  }

  private cleanDeviceName(name?: string) {
    const cleaned = name?.replace(/[\u0000-\u001f\u007f]/g, '').trim().slice(0, 120);
    return cleaned || 'Unknown device';
  }
}
