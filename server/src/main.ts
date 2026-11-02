import 'reflect-metadata';
import { ValidationPipe } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import helmet from 'helmet';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.use(helmet());
  app.enableShutdownHooks();
  app.setGlobalPrefix('v1');
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }));
  const config = app.get(ConfigService);
  const jwtSecret = config.getOrThrow<string>('JWT_SECRET');
  if (Buffer.byteLength(jwtSecret, 'utf8') < 32) throw new Error('JWT_SECRET must contain at least 32 bytes');
  if (config.get('NODE_ENV') === 'production' && jwtSecret.startsWith('replace-')) throw new Error('Set a unique JWT_SECRET before production startup');
  await app.listen(config.get<number>('PORT', 3000), '0.0.0.0');
}
void bootstrap();
