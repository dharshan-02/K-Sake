import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { FilesService } from './files.service';

describe('FilesService ownership checks', () => {
  const prisma = { vaultFile: { findUnique: jest.fn() } };
  const config = { getOrThrow: jest.fn((key: string) => ({ S3_BUCKET: 'bucket', S3_ACCESS_KEY_ID: 'access', S3_SECRET_ACCESS_KEY: 'secret' }[key])), get: jest.fn((_key: string, fallback: unknown) => fallback) };
  const service = new FilesService(prisma as never, config as never);

  beforeEach(() => jest.clearAllMocks());

  it('does not disclose another account file by issuing a download URL', async () => {
    prisma.vaultFile.findUnique.mockResolvedValue({ id: 'file-1', ownerId: 'owner-a', status: 'ready', objectKey: 'owner-a/file-1' });
    await expect(service.download('owner-b', 'file-1')).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('returns not found for an unknown file', async () => {
    prisma.vaultFile.findUnique.mockResolvedValue(null);
    await expect(service.download('owner-a', 'missing')).rejects.toBeInstanceOf(NotFoundException);
  });
});
