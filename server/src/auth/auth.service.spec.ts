import { ConflictException, UnauthorizedException } from '@nestjs/common';
import * as argon2 from 'argon2';
import { AuthService } from './auth.service';

describe('AuthService', () => {
  const user = { id: 'user-1', email: 'person@example.com', passwordHash: '$argon2id$hash' };
  const prisma = { user: { findUnique: jest.fn(), create: jest.fn() } };
  const jwt = { signAsync: jest.fn().mockResolvedValue('signed-token') };
  const service = new AuthService(prisma as never, jwt as never);

  beforeEach(() => jest.clearAllMocks());

  it('normalizes email and only persists an Argon2id hash', async () => {
    prisma.user.findUnique.mockResolvedValue(null);
    prisma.user.create.mockImplementation(async ({ data }) => ({ id: user.id, email: data.email }));
    const result = await service.register(' Person@Example.com ', 'a-long-password-1');
    expect(prisma.user.create).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ email: 'person@example.com', passwordHash: expect.stringMatching(/^\$argon2id\$/) }) }));
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
});
