CREATE TABLE "User" (
    "id" UUID NOT NULL,
    "email" VARCHAR(254) NOT NULL,
    "passwordHash" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "VaultFile" (
    "id" UUID NOT NULL,
    "ownerId" UUID NOT NULL,
    "objectKey" TEXT NOT NULL,
    "name" VARCHAR(255) NOT NULL,
    "mimeType" VARCHAR(160) NOT NULL,
    "size" BIGINT NOT NULL,
    "status" VARCHAR(16) NOT NULL DEFAULT 'pending',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "VaultFile_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "RecoveryEnvelope" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "nonce" VARCHAR(32) NOT NULL,
    "ciphertext" VARCHAR(256) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "RecoveryEnvelope_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "User_email_key" ON "User"("email");
CREATE UNIQUE INDEX "VaultFile_objectKey_key" ON "VaultFile"("objectKey");
CREATE UNIQUE INDEX "RecoveryEnvelope_userId_key" ON "RecoveryEnvelope"("userId");
CREATE INDEX "VaultFile_ownerId_createdAt_idx" ON "VaultFile"("ownerId", "createdAt");

ALTER TABLE "VaultFile" ADD CONSTRAINT "VaultFile_ownerId_fkey"
FOREIGN KEY ("ownerId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "RecoveryEnvelope" ADD CONSTRAINT "RecoveryEnvelope_userId_fkey"
FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
