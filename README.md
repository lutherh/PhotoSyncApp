# PhotoSync (iOS) — Scaleway S3 Setup

This app uploads iOS photos to an S3-compatible store using presigned URLs. It works out of the box with Scaleway Object Storage.

## Your Storage

- Provider: Scaleway
- Region: NL-AMS
- Bucket: `photosync`
- Bucket domain: `https://photosync.s3.nl-ams.scw.cloud`
- Generic regional endpoint: `https://s3.nl-ams.scw.cloud`

## What changes from AWS?

Nothing in the iOS app. Only the presign backend needs to sign URLs against the Scaleway endpoint/region with your Scaleway access key and secret. The iOS app simply performs HTTP PUT to whatever presigned URL is returned.

## Steps

1) Backend: run the presign server

```bash
cd ProjectSupport/presign-backend
cp .env.example .env
# edit .env and set AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY to your Scaleway S3 keys
npm i
PORT=3498 npm start
# server on http://localhost:3498
```

2) iOS app: Presign API base (manual or discovery)

- Optional manual override: set `PRESIGN_BASE_URL` in `Configuration.plist`, e.g.:

```
PRESIGN_BASE_URL = http://<your-mac-ip>:3498
```

- If unset, the app will try Bonjour discovery for `_photosync._tcp` on your LAN and use the discovered host:port.

The app will call:

```
GET https://your-api.example.com/presign?key=<computed-key>&contentType=<mime>
```

The server returns:
```json
{ "url": "https://photosync.s3.nl-ams.scw.cloud/ios/...", "headers": {} }
```

3) Permissions and Background Modes

- Same as before: enable Photo Library access, Background fetch, Background processing.
- No app code changes needed for Scaleway.

## Troubleshooting

- 403 on PUT:
  - Ensure your presign server uses the correct endpoint (`https://s3.nl-ams.scw.cloud`) and region (`nl-ams`).
  - Verify credentials are Scaleway Object Storage keys (not IAM for other services).
  - Check that the bucket exists in the same region and name is correct.

- URL shape:
  - The presign server will produce virtual-hosted URLs like:
    `https://photosync.s3.nl-ams.scw.cloud/<key>`
  - If your environment prefers path-style URLs, set `forcePathStyle: true` in `S3Client` (server.js).

- ACL / Encryption:
  - If you need ACL or SSE, add them to the `PutObjectCommand` and they will be included in the signature.

## Notes

- The iOS client uses a background URLSession and presigned PUT. No AWS/Scaleway SDK is embedded in the app.
- CORS is not applicable to native iOS uploads.
