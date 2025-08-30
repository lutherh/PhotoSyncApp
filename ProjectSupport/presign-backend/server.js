import "dotenv/config";
import express from "express";
import Bonjour from "bonjour-service";
import { S3Client, PutObjectCommand, HeadObjectCommand, ListObjectsV2Command, GetObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

const app = express();
const port = process.env.PORT || 3498;
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

// GET /latest?limit=3&prefix=photos/
app.get("/latest", async (req, res) => {
  try {
    const limit = Math.max(1, Math.min(parseInt(req.query.limit || "3", 10) || 3, 20));
    const prefix = (req.query.prefix || "photos/").toString();
    const resp = await s3.send(new ListObjectsV2Command({ Bucket: bucket, Prefix: prefix, MaxKeys: 1000 }));
    const contents = resp.Contents || [];
    const exts = new Set(["jpg","jpeg","png","gif","heic","tif","tiff"]);
    const images = contents
      .filter(o => !!o.Key && exts.has(o.Key.split(".").pop()?.toLowerCase() || ""))
      .sort((a, b) => (b.LastModified?.getTime?.() || 0) - (a.LastModified?.getTime?.() || 0));

    // Helper to parse YYYY/MM/DD from key like photos/2025/08/29/...
    const parseDateFromKey = (key) => {
      try {
        const m = key.match(/^photos\/(\d{4})\/(\d{2})\/(\d{2})\//);
        if (!m) return null;
        const [_, y, mo, d] = m;
        const dt = new Date(`${y}-${mo}-${d}T12:00:00Z`);
        return isNaN(dt.getTime()) ? null : dt;
      } catch { return null; }
    };

    // Head a larger recent sample to find true capture date via metadata, else key path, else LastModified
    const sample = images.slice(0, 300);
    const withMeta = [];
    for (const obj of sample) {
      try {
        const head = await s3.send(new HeadObjectCommand({ Bucket: bucket, Key: obj.Key }));
        const createdMeta = head.Metadata?.created;
        let sortDate = obj.LastModified;
        if (createdMeta) {
          const n = Number(createdMeta);
          if (!Number.isNaN(n) && n > 1000000000) {
            sortDate = new Date(n);
          } else {
            const d = new Date(createdMeta);
            if (!isNaN(d.getTime())) sortDate = d;
          }
        } else {
          const parsed = parseDateFromKey(obj.Key);
          if (parsed) sortDate = parsed;
        }
        withMeta.push({ obj, sortDate });
      } catch (e) {
        const parsed = parseDateFromKey(obj.Key);
        withMeta.push({ obj, sortDate: parsed || obj.LastModified });
      }
    }
    withMeta.sort((a, b) => (b.sortDate?.getTime?.() || 0) - (a.sortDate?.getTime?.() || 0));
  const chosen = withMeta.slice(0, limit);
  console.log(`[latest] chosen:`, chosen.map(c => ({ key: c.obj.Key, sortDate: c.sortDate?.toISOString?.() || null })).slice(0, 10));

    const out = [];
    for (const { obj } of chosen) {
      const key = obj.Key;
      const url = await getSignedUrl(s3, new GetObjectCommand({ Bucket: bucket, Key: key }), { expiresIn: 600 });
      out.push({ key, url, lastModified: obj.LastModified?.toISOString?.() || null, size: obj.Size || null });
    }
    res.json({ items: out });
  } catch (e) {
    console.error("[latest] error", e?.message || e);
    res.status(500).json({ error: "Latest listing failed" });
  }
});

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
    const { key, contentType, created, filename } = req.query;
    if (!key) return res.status(400).json({ error: "Missing key" });
  console.log(`[presign] request key="${key}" contentType="${contentType || "application/octet-stream"}" created="${created || ""}" filename="${filename || ""}" bucket="${bucket}" region="${region}"`);

    const command = new PutObjectCommand({
      Bucket: bucket,
      Key: key,
      ContentType: contentType || "application/octet-stream",
      // Store capture date and original filename as user-metadata for sorting/browsing later
      Metadata: {
        ...(created ? { created: String(created) } : {}),
        ...(filename ? { filename: String(filename) } : {}),
      }
      // Optional:
      // ACL: "private",
      // ServerSideEncryption: "AES256",
    });

  const url = await getSignedUrl(s3, command, { expiresIn: 3600 }); // 1 hour
  const shown = logFullUrls ? url : redactUrl(url);
  console.log(`[presign] ok url=${shown}`);

    // The client MUST send the same metadata headers that were used to sign the request
    const headers = {
      ...(created ? { "x-amz-meta-created": String(created) } : {}),
      ...(filename ? { "x-amz-meta-filename": String(filename) } : {}),
    };
    res.json({ url, headers });
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
  try {
    const bonjour = new Bonjour();
    bonjour.publish({ name: "PhotoSync Presign", type: "photosync", port });
    console.log("Bonjour service published: _photosync._tcp.local");
  } catch (e) {
    console.warn("Bonjour publish failed or not installed:", e?.message || e);
  }
});