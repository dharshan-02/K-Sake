# API

All routes are prefixed with `/v1`. Register and login return a 15 minute bearer access token. Authenticated file routes are scoped to the user ID in the verified JWT.

| Method | Route | Purpose |
| --- | --- | --- |
| POST | `/auth/register` | Create an account (email plus 12–128 character password) |
| POST | `/auth/login` | Sign in |
| GET | `/files` | List this account's metadata |
| POST | `/files/upload` | Start an encrypted blob upload and receive a short-lived PUT URL |
| POST | `/files/:id/complete` | Confirm the ciphertext object and exact byte count arrived |
| GET | `/files/:id/download` | Receive a short-lived GET URL for a ready object |
| PATCH | `/files/:id` | Rename an owned file using `expectedUpdatedAt` for stale-write detection |
| DELETE | `/files/:id` | Delete an owned object and metadata |
| PUT | `/keys/recovery` | Save an opaque, client-encrypted vault-key recovery envelope |
| GET | `/keys/recovery` | Retrieve the caller's encrypted recovery envelope |

The mobile client encrypts a file before calling `/files/upload`; the API accepts only an object key derived from the authenticated owner and client file UUID. The S3 bucket must stay private, and the signer endpoint must be reachable from the device using the returned URL.
