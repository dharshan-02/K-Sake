import { BadRequestException, NotFoundException } from '@nestjs/common';
import { RecoveryService } from './recovery.service';

describe('RecoveryService', () => {
  const prisma = { recoveryEnvelope: { upsert: jest.fn(), findUnique: jest.fn() } };
  const service = new RecoveryService(prisma as never);

  beforeEach(() => jest.clearAllMocks());

  it('stores only an opaque envelope scoped to the authenticated user', async () => {
    prisma.recoveryEnvelope.upsert.mockResolvedValue({ updatedAt: new Date() });
    const nonce = 'a'.repeat(16);
    const ciphertext = 'b'.repeat(64);
    await service.save('owner-id', nonce, ciphertext);
    expect(prisma.recoveryEnvelope.upsert).toHaveBeenCalledWith(expect.objectContaining({
      where: { userId: 'owner-id' },
      create: { userId: 'owner-id', nonce, ciphertext },
    }));
  });

  it('rejects malformed envelopes', async () => {
    await expect(service.save('owner-id', 'too-short', 'not-encrypted')).rejects.toBeInstanceOf(BadRequestException);
  });

  it('does not return a recovery envelope for another account', async () => {
    prisma.recoveryEnvelope.findUnique.mockResolvedValue(null);
    await expect(service.get('owner-id')).rejects.toBeInstanceOf(NotFoundException);
    expect(prisma.recoveryEnvelope.findUnique).toHaveBeenCalledWith(expect.objectContaining({ where: { userId: 'owner-id' } }));
  });
});
