# Delivery dispatch — deployment

## Prerequisites

- HERE account/API key with **Tour Planning v3** access (reuses `HERE_API_KEY`).
- A persistent filesystem volume for proof-photo originals.
- HTTPS — secret driver links are bearer credentials, and browsers require a
  secure context for camera/file uploads.

## Runtime variables

| Variable           | Used by   | Purpose                                                        |
| ------------------ | --------- | ------------------------------------------------------------- |
| `HERE_API_KEY`     | Phoenix   | Geocoding/routing **and** Tour Planning v3.                   |
| `PROOF_PHOTO_ROOT` | Phoenix   | Absolute path Phoenix writes proof-photo originals to.        |
| `IMGPROXY_PREFIX`  | Phoenix   | Base URL of the imgproxy instance.                            |
| `IMGPROXY_KEY`     | Phoenix   | imgproxy URL-signing key (hex).                               |
| `IMGPROXY_SALT`    | Phoenix   | imgproxy URL-signing salt (hex).                              |
| `PHX_HOST`         | Phoenix   | Public host used to build driver email links.                 |

## Volume mounts

Mount the same directory into both containers:

- **Phoenix** — read/write at `PROOF_PHOTO_ROOT`. Originals are written under
  `PROOF_PHOTO_ROOT/proof_photos/<uuid>.<ext>`, unchanged.
- **imgproxy** — read-only, exposed as its local-files source so that
  `local:///proof_photos/<uuid>.<ext>` resolves. Admin photo views use
  short-lived signed imgproxy URLs; raw filesystem paths are never public.

Back the volume up: proof photos are retained indefinitely, so volume loss is
business-data loss.

## Notes

- HEIC display depends on imgproxy's build/codecs even though originals are
  stored unchanged.
- Optimization is synchronous; the HERE call happens before any database
  transaction is opened. Only persistence is transactional.
