import "dotenv/config";
import express from "express";
import { S3Client, PutObjectCommand, HeadObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

const app = express();
const port = process.env.PORT || 3000;
const logFullUrls = process.env.DEBUG_LOG_URLS === "1" || process.env.DEBUG_LOG_URLS === "true";

/*
  Scaleway S3-compatible configuration.
  - REGION:       nl-ams (for Amsterdam)
  - ENDPOINT:     https://s3.nl-ams.scw.cloud  (generic regional endpoint)
  - BUCKET:       photosync (your bucket)
  - CREDENTIALS:  use your Scaleway S3 access key/secret

  Notes:
  - The AWS SDK v3 happily signs for custom endpoints (Scaleway).
  - With a generic endpoint + DNS-compliant bucket, the SDK will generate
    a virtual-hosted URL like: https://photosync.s3.nl-ams.scw.cloud/<key>
*/
const region = process.env.S3_REGION || "nl-ams";
const endpoint = process.env.S3_ENDPOINT || "https://s3.nl-ams.scw.cloud";
const bucket = process.env.S3_BUCKET || "photosync";

const s3 = new S3Client({
  region,
  endpoint, // Scaleway S3 endpoint
  // If your bucket or environment requires path-style, set forcePathStyle: true
  // forcePathStyle: false,
  credentials: {
    accessKeyId: process.env.AWS_ACCESS_KEY_ID,       // set to your Scaleway Access Key
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY // set to your Scaleway Secret Key
  }
});

// Basic startup validation/warnings
if (!process.env.AWS_ACCESS_KEY_ID || !process.env.AWS_SECRET_ACCESS_KEY) {
  console.warn("[presign-backend] WARNING: Missing AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY env vars.");
}
if (!bucket) {
  console.warn("[presign-backend] WARNING: S3_BUCKET is empty.");
}

// Simple request logger middleware (safe; avoids logging bodies/secrets)
app.use((req, _res, next) => {
  const ts = new Date().toISOString();
  console.log(`[${ts}] ${req.ip || "[ip?]"} ${req.method} ${req.originalUrl}`);
  next();
});

// Helper to redact query/signature from presigned URLs unless explicitly allowed
const redactUrl = (u) => {
  try {
    const parsed = new URL(u);
    return `${parsed.origin}${parsed.pathname}`;
  } catch {
    return "[invalid url]";
  }
};

app.get("/healthz", (_req, res) => res.json({ ok: true }));

// GET /exists?key=<object-key>
app.get("/exists", async (req, res) => {
  try {
    const { key } = req.query;
    if (!key) return res.status(400).json({ error: "Missing key" });
    console.log(`[exists] request key="${key}" bucket="${bucket}" region="${region}"`);
    await s3.send(new HeadObjectCommand({ Bucket: bucket, Key: key }));
    console.log(`[exists] key exists: ${key}`);
    return res.json({ exists: true });
  } catch (e) {
    // NotFound -> does not exist; other errors -> report 500
    const code = e?.$metadata?.httpStatusCode || e?.name || "";
    if (code === 404 || e?.name === "NotFound" || e?.Code === "NotFound") {
      console.log(`[exists] key not found: ${req.query.key}`);
      return res.json({ exists: false });
    }
    console.error("[exists] error", e?.message || e);
    return res.status(500).json({ error: "Exists check failed" });
  }
});

// GET /presign?key=<object-key>&contentType=<mime>
app.get("/presign", async (req, res) => {
  try {
    const { key, contentType } = req.query;
    if (!key) return res.status(400).json({ error: "Missing key" });
  console.log(`[presign] request key="${key}" contentType="${contentType || "application/octet-stream"}" bucket="${bucket}" region="${region}"`);

    const command = new PutObjectCommand({
      Bucket: bucket,
      Key: key,
      ContentType: contentType || "application/octet-stream"
      // Optional:
      // ACL: "private",
      // ServerSideEncryption: "AES256",
    });

  const url = await getSignedUrl(s3, command, { expiresIn: 3600 }); // 1 hour
  const shown = logFullUrls ? url : redactUrl(url);
  console.log(`[presign] ok url=${shown}`);

    // If you require specific headers on PUT, include them here.
    // Most cases: Content-Type only is fine.
    res.json({ url, headers: {} });
  } catch (e) {
    console.error("[presign] error", e?.message || e);
    res.status(500).json({ error: "Presign failed" });
  }
});

app.listen(port, () => {
  console.log(`Presign API (Scaleway) running on :${port}`);
  console.log(`Region: ${region}  Endpoint: ${endpoint}  Bucket: ${bucket}`);
  if (!logFullUrls) {
    console.log("(URLs in logs are redacted; set DEBUG_LOG_URLS=1 to log full presigned URLs)");
  }
});