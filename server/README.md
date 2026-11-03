# API

All routes are prefixed with `/v1`. Register and login return a 15 minute bearer access token tied to a persisted device session. Authenticated routes validate that session on each request. Send a stable UUID `deviceId` and a user-safe `deviceName` in the authentication body; older clients may omit these values but will be listed as separate unknown devices.

| Method | Route | Purpose |
| --- | --- | --- |
| POST | `/auth/register` | Create an account (email plus 12–128 character password) |
| POST | `/auth/login` | Sign in |
| POST | `/auth/logout` | Revoke the current device session |
| DELETE | `/auth/account` | Re-authenticate with the account password, remove stored cloud objects, and permanently delete the account and sessions |
| GET | `/auth/devices` | List active device sessions for the signed-in account |
| DELETE | `/auth/devices/:id` | Revoke a device session; future requests using its token are rejected |
| GET | `/files` | List this account's metadata |
| POST | `/files/upload` | Start an encrypted blob upload and receive a short-lived PUT URL |
| POST | `/files/:id/complete` | Confirm the ciphertext object and exact byte count arrived |
| GET | `/files/:id/download` | Receive a short-lived GET URL for a ready object |
| PATCH | `/files/:id` | Rename an owned file using `expectedUpdatedAt` for stale-write detection |
| DELETE | `/files/:id` | Delete an owned object and metadata |
| PUT | `/keys/recovery` | Save an opaque, client-encrypted vault-key recovery envelope |
| GET | `/keys/recovery` | Retrieve the caller's encrypted recovery envelope |

The mobile client encrypts a file before calling `/files/upload`; the API accepts only an object key derived from the authenticated owner and client file UUID. The S3 bucket must stay private, and the signer endpoint must be reachable from the device using the returned URL.

Run `npm run db:migrate` during deployment to apply the `DeviceSession` migration. Device revocation blocks cloud API access but does not remotely wipe ciphertext or local files already downloaded onto a device. Account deletion requires S3-compatible storage to be reachable; if any object cannot be removed, deletion stops and can be retried. Ensure bucket versioning/retention policies do not retain deleted object versions when permanent physical erasure is required. This API currently has no refresh-token endpoint; after a 15 minute token expires, the user must authenticate again.
