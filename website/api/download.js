import { Redis } from "@upstash/redis";

// The real installer lives as a static file under public/. We redirect to it
// after counting so the download itself never depends on the counter working.
const DMG_PATH = "/downloads/OfflineVoice-mac.dmg";

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

  res.setHeader("Location", DMG_PATH);
  res.statusCode = 302;
  res.end();
}
