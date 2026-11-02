import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.module';

@Injectable()
export class RecoveryService {
  constructor(private readonly prisma: PrismaService) {}

  async save(userId: string, nonce: string, ciphertext: string) {
    if (!/^[A-Za-z0-9_-]{16}$/.test(nonce) || !/^[A-Za-z0-9_-]{64}$/.test(ciphertext)) throw new BadRequestException('Invalid recovery envelope encoding');
    return this.prisma.recoveryEnvelope.upsert({
      where: { userId },
      create: { userId, nonce, ciphertext },
      update: { nonce, ciphertext },
      select: { updatedAt: true },
    });
  }

  async get(userId: string) {
    const envelope = await this.prisma.recoveryEnvelope.findUnique({ where: { userId }, select: { nonce: true, ciphertext: true, updatedAt: true } });
    if (!envelope) throw new NotFoundException('No recovery envelope is set for this account');
    return { version: 1, ...envelope };
  }
}
