CREATE TABLE "DeviceSession" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "deviceId" VARCHAR(80) NOT NULL,
    "deviceName" VARCHAR(120) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastSeenAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "revokedAt" TIMESTAMP(3),
    CONSTRAINT "DeviceSession_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "DeviceSession_userId_deviceId_key" ON "DeviceSession"("userId", "deviceId");
CREATE INDEX "DeviceSession_userId_revokedAt_idx" ON "DeviceSession"("userId", "revokedAt");
ALTER TABLE "DeviceSession" ADD CONSTRAINT "DeviceSession_userId_fkey"
FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
