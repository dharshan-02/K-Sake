# Security notes

## Current design

- Plaintext files are encrypted locally with a random 256-bit AES-GCM key and a fresh 96-bit nonce per encryption. Ciphertext is saved in the app's private documents directory and uploaded as ciphertext.
- A random vault wrapping secret is generated on device and stored using platform secure storage. The vault database is encrypted with SQLCipher-compatible SQLite3MultipleCiphers. The app asks for device authentication before opening the vault. In this starter, the biometric check gates app launch; the key store itself is not configured with a hardware-backed biometric access-control list. Biometric templates remain inside the operating system; the app only receives an authentication result.
- The API stores encrypted blobs in a private bucket and issues short-lived, object-scoped signed URLs after checking the authenticated owner.
- The API can see account email, file names, encrypted sizes, timestamps, sync state, and active device labels/last-active times. Folder labels stay local. File names should be encrypted in a future protocol version if metadata privacy is required.
- The Hidden Safe is a PIN-gated local view, not a separate cryptographic vault. Its records use the same encrypted database and vault key as regular files. It does not sync hidden records; moving a previously synced file into the Hidden Safe queues deletion of its cloud copy for the next normal-vault sync. A person or malware that can open the regular vault database can also access Hidden Safe records.
- The Activity screen stores local app events in the encrypted database and updates its unread badge as actions complete. It does not use APNs/FCM and does not deliver notifications while the app is closed or across devices.
- Deleted files move to a local Recycle Bin. Permanent deletion queues removal of the cloud copy for the next sync; until then the cloud ciphertext remains stored.

## Key recovery and multi-device

The app can create a random 256-bit recovery code and use it to AES-GCM-wrap the 256-bit vault master key. The server stores only the opaque nonce and ciphertext envelope; it cannot recover the master key without the user's code. On a new device, sign in and enter the code to restore the same vault key before downloading cloud files. The code is shown once and is not recoverable by the service. Replacing a code invalidates the previous one. If a user loses the code and every device that has the vault key, their cloud ciphertext is unrecoverable. This protocol is a starter implementation and still needs independent cryptographic review before production use.

## Threat model and limits

The design protects file contents at rest on the device and in object storage, and from a storage/API operator who has no client key. It does not protect an unlocked, compromised, rooted/jailbroken, or malware-infected device; screenshots or exports made by other apps; traffic metadata; account metadata; or a user who loses their recovery material. Preview creates a temporary plaintext copy in the app cache and deletes it when closed and on next startup; a crash or OS backup may retain it temporarily. Transport must use TLS. Production deployment still needs refresh-token rotation, abuse monitoring, backup policy review, dependency review, and an independent mobile/backend security audit.

## Before production

- Independently review and audit recovery and multi-device enrollment before production use.
- Encrypt filenames, folder names, and search indexes locally or document their exposure.
- Add refresh-token rotation, email verification, password reset with recovery-safe semantics, and account deletion.
- Enforce HTTPS, strict CORS, request size limits, rate limits, bucket lifecycle/retention policy, database backups, and secret rotation.
- Verify Android backup exclusions and iOS file-protection/data-protection settings for ciphertext, database, and caches.
- Review cryptographic format/versioning and test tampering, truncation, nonce uniqueness, and interrupted imports.
