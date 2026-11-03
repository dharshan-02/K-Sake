import { ConflictException, ForbiddenException, Injectable, NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DeleteObjectCommand, DeleteObjectsCommand, GetObjectCommand, HeadObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { PrismaService } from '../prisma/prisma.module';

@Injectable()
export class FilesService {
  private readonly s3: S3Client;
  private readonly signer: S3Client;
  private readonly bucket: string;
  private readonly ttl: number;

  constructor(private readonly prisma: PrismaService, config: ConfigService) {
    this.bucket = config.getOrThrow('S3_BUCKET');
    this.ttl = Math.min(900, Math.max(60, Number(config.get('PRESIGNED_URL_TTL_SECONDS', 300))));
    this.s3 = new S3Client({
      region: config.get('S3_REGION', 'us-east-1'),
      endpoint: config.get('S3_ENDPOINT') || undefined,
      forcePathStyle: config.get('S3_FORCE_PATH_STYLE') === 'true',
      credentials: { accessKeyId: config.getOrThrow('S3_ACCESS_KEY_ID'), secretAccessKey: config.getOrThrow('S3_SECRET_ACCESS_KEY') },
    });
    this.signer = new S3Client({
      region: config.get('S3_REGION', 'us-east-1'),
      endpoint: config.get('S3_PUBLIC_ENDPOINT') || config.get('S3_ENDPOINT') || undefined,
      forcePathStyle: config.get('S3_FORCE_PATH_STYLE') === 'true',
      credentials: { accessKeyId: config.getOrThrow('S3_ACCESS_KEY_ID'), secretAccessKey: config.getOrThrow('S3_SECRET_ACCESS_KEY') },
    });
  }

  async list(ownerId: string) {
    const files = await this.prisma.vaultFile.findMany({ where: { ownerId, status: 'ready' }, orderBy: { createdAt: 'desc' } });
    return files.map(({ objectKey: _secret, size, ...f }) => ({ ...f, size: Number(size) }));
  }

  async beginUpload(ownerId: string, dto: { id: string; name: string; mimeType: string; size: number }) {
    const existing = await this.prisma.vaultFile.findUnique({ where: { id: dto.id } });
    if (existing && existing.ownerId !== ownerId) throw new ForbiddenException();
    if (existing?.status === 'ready') return { fileId: existing.id, alreadyUploaded: true, updatedAt: existing.updatedAt };
    if (existing && existing.size !== BigInt(dto.size)) throw new ConflictException('File ID already exists with a different encrypted size');
    const id = dto.id;
    const objectKey = `${ownerId}/${id}`;
    const file = existing ?? await this.prisma.vaultFile.create({ data: { id, ownerId, objectKey, name: dto.name, mimeType: 'application/octet-stream', size: BigInt(dto.size), status: 'pending' } });
    try {
      const uploadUrl = await getSignedUrl(this.signer, new PutObjectCommand({ Bucket: this.bucket, Key: objectKey, ContentType: 'application/octet-stream' }), { expiresIn: this.ttl });
      return { fileId: file.id, uploadUrl, expiresIn: this.ttl, requiredHeaders: { 'content-type': 'application/octet-stream' } };
    } catch (e) {
      await this.prisma.vaultFile.delete({ where: { id: file.id } });
      throw new ServiceUnavailableException('File storage is unavailable');
    }
  }

  async finishUpload(ownerId: string, id: string) {
    const file = await this.owned(ownerId, id);
    if (file.status === 'ready') return { id, status: 'ready', updatedAt: file.updatedAt };
    try {
      const stored = await this.s3.send(new HeadObjectCommand({ Bucket: this.bucket, Key: file.objectKey }));
      if (stored.ContentLength !== Number(file.size)) throw new ForbiddenException('Uploaded object size did not match the request');
    } catch (e) {
      if (e instanceof ForbiddenException) throw e;
      throw new NotFoundException('Encrypted upload has not arrived');
    }
    const ready = await this.prisma.vaultFile.update({ where: { id }, data: { status: 'ready' }, select: { updatedAt: true } });
    return { id, status: 'ready', updatedAt: ready.updatedAt };
  }

  async download(ownerId: string, id: string) {
    const file = await this.owned(ownerId, id);
    if (file.status !== 'ready') throw new NotFoundException();
    const url = await getSignedUrl(this.signer, new GetObjectCommand({ Bucket: this.bucket, Key: file.objectKey }), { expiresIn: this.ttl });
    return { downloadUrl: url, expiresIn: this.ttl };
  }

  async rename(ownerId: string, id: string, name: string, expectedUpdatedAt: string) {
    const current = await this.owned(ownerId, id);
    if (current.updatedAt.getTime() !== new Date(expectedUpdatedAt).getTime()) throw new ConflictException('File metadata changed on another device. Review the cloud copy before replacing its name.');
    const file = await this.prisma.vaultFile.update({ where: { id }, data: { name } });
    return { id: file.id, name: file.name, updatedAt: file.updatedAt };
  }

  async remove(ownerId: string, id: string) {
    const file = await this.owned(ownerId, id);
    try { await this.s3.send(new DeleteObjectCommand({ Bucket: this.bucket, Key: file.objectKey })); }
    catch { throw new ServiceUnavailableException('File storage is unavailable'); }
    await this.prisma.vaultFile.delete({ where: { id } });
    return { id, deleted: true };
  }

  async deleteAllForOwner(ownerId: string) {
    const files = await this.prisma.vaultFile.findMany({
      where: { ownerId },
      select: { objectKey: true },
    });
    for (let index = 0; index < files.length; index += 1000) {
      const batch = files.slice(index, index + 1000);
      try {
        const result = await this.s3.send(
          new DeleteObjectsCommand({
            Bucket: this.bucket,
            Delete: {
              Objects: batch.map(({ objectKey }) => ({ Key: objectKey })),
              Quiet: true,
            },
          }),
        );
        if (result.Errors?.length) {
          throw new Error('One or more stored objects could not be removed');
        }
      } catch {
        throw new ServiceUnavailableException(
          'Cloud files could not be fully removed. The account has not been deleted; retry when storage is available.',
        );
      }
    }
  }

  private async owned(ownerId: string, id: string) {
    const file = await this.prisma.vaultFile.findUnique({ where: { id } });
    if (!file) throw new NotFoundException();
    if (file.ownerId !== ownerId) throw new ForbiddenException();
    return file;
  }
}
