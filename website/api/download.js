import { Redis } from "@upstash/redis";

// The installer is published as a GitHub Release asset — it is far too large
// for Vercel's per-file upload limit now that the speech model ships inside
// the app. We count the download here, then redirect to GitHub so the
// download itself never depends on the counter working.
//
// `releases/latest/download/<asset>` always resolves to the newest release, so
// a release only needs `gh release create` — no website deploy. Override with
// DMG_URL (e.g. to pin a specific tag) if ever needed.
const DMG_URL =
  process.env.DMG_URL ||
  "https://github.com/naghceuz/offlinevoice/releases/latest/download/OfflineVoice-mac.dmg";

// Lazily build the Redis client so a missing/unconfigured KV store degrades
// gracefully (downloads still work) instead of throwing at import time.
// Accepts either the Vercel KV (KV_*) or native Upstash (UPSTASH_*) env names.
function getRedis() {
  const url = process.env.KV_REST_API_URL || process.env.UPSTASH_REDIS_REST_URL;
  const token =
    process.env.KV_REST_API_TOKEN || process.env.UPSTASH_REDIS_REST_TOKEN;
  if (!url || !token) return null;
  return new Redis({ url, token });
}

export default async function handler(req, res) {
  // Count the download — but never let a counter failure block the download.
  try {
    const redis = getRedis();
    if (redis) {
      const day = new Date().toISOString().slice(0, 10); // YYYY-MM-DD (UTC)
      await Promise.all([
        redis.incr("downloads:total"),
        redis.incr(`downloads:day:${day}`),
      ]);
    }
  } catch (err) {
    console.error("download counter failed", err);
  }

  res.setHeader("Location", DMG_URL);
  res.setHeader("Cache-Control", "no-store");
  res.statusCode = 302;
  res.end();
}
