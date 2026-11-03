import { ConflictException, UnauthorizedException } from '@nestjs/common';
import * as argon2 from 'argon2';
import { AuthService } from './auth.service';

describe('AuthService', () => {
  const user = { id: 'user-1', email: 'person@example.com', passwordHash: '$argon2id$hash' };
  const prisma = {
    user: { findUnique: jest.fn(), create: jest.fn() },
    deviceSession: {
      upsert: jest.fn().mockResolvedValue({ id: 'session-1' }),
      findFirst: jest.fn(),
      update: jest.fn(),
      findMany: jest.fn(),
      updateMany: jest.fn(),
    },
  };
  const jwt = { signAsync: jest.fn().mockResolvedValue('signed-token') };
  const service = new AuthService(prisma as never, jwt as never);

  beforeEach(() => jest.clearAllMocks());

  it('normalizes email and only persists an Argon2id hash', async () => {
    prisma.user.findUnique.mockResolvedValue(null);
    prisma.user.create.mockImplementation(async ({ data }) => ({ id: user.id, email: data.email }));
    const result = await service.register(' Person@Example.com ', 'a-long-password-1');
    expect(prisma.user.create).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ email: 'person@example.com', passwordHash: expect.stringMatching(/^\$argon2id\$/) }) }));
    expect(prisma.deviceSession.upsert).toHaveBeenCalledWith(expect.objectContaining({
      where: { userId_deviceId: { userId: user.id, deviceId: expect.any(String) } },
      create: expect.objectContaining({ deviceName: 'Unknown device' }),
    }));
    expect(jwt.signAsync).toHaveBeenCalledWith(expect.objectContaining({ sid: 'session-1' }));
    expect(result.accessToken).toBe('signed-token');
  });

  it('rejects duplicate accounts', async () => {
    prisma.user.findUnique.mockResolvedValue(user);
    await expect(service.register(user.email, 'a-long-password-1')).rejects.toBeInstanceOf(ConflictException);
  });

  it('uses a generic error for an invalid password', async () => {
    prisma.user.findUnique.mockResolvedValue({ ...user, passwordHash: await argon2.hash('correct-password') });
    await expect(service.login(user.email, 'wrong-password')).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('rejects a revoked session on protected requests', async () => {
    prisma.deviceSession.findFirst.mockResolvedValue(null);
    await expect(service.validateSession(user.id, 'revoked-session')).resolves.toBe(false);
    expect(prisma.deviceSession.findFirst).toHaveBeenCalledWith({
      where: { id: 'revoked-session', userId: user.id, revokedAt: null },
    });
  });

  it('lists active sessions and scopes revocation to the account', async () => {
    prisma.deviceSession.findMany.mockResolvedValue([]);
    await service.listDevices(user.id);
    expect(prisma.deviceSession.findMany).toHaveBeenCalledWith(expect.objectContaining({
      where: { userId: user.id, revokedAt: null },
    }));
    prisma.deviceSession.updateMany.mockResolvedValue({ count: 1 });
    await service.revokeDevice(user.id, 'session-1');
    expect(prisma.deviceSession.updateMany).toHaveBeenCalledWith(expect.objectContaining({
      where: { id: 'session-1', userId: user.id, revokedAt: null },
    }));
  });
});
