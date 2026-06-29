import { Redis } from "@upstash/redis";

// Read-only endpoint to see the download counts.
// Protected by STATS_TOKEN: call /api/stats?token=YOUR_TOKEN
// (If STATS_TOKEN is unset, the endpoint is open — fine if you don't mind the
// number being public, e.g. to show a "N downloads" badge on the site.)
function getRedis() {
  const url = process.env.KV_REST_API_URL || process.env.UPSTASH_REDIS_REST_URL;
  const token =
    process.env.KV_REST_API_TOKEN || process.env.UPSTASH_REDIS_REST_TOKEN;
  if (!url || !token) return null;
  return new Redis({ url, token });
}

export default async function handler(req, res) {
  if (process.env.STATS_TOKEN && req.query.token !== process.env.STATS_TOKEN) {
    res.statusCode = 401;
    res.json({ error: "unauthorized" });
    return;
  }

  const redis = getRedis();
  if (!redis) {
    res.statusCode = 503;
    res.json({ error: "kv not configured" });
    return;
  }

  const today = new Date().toISOString().slice(0, 10);
  const [total, todayCount] = await Promise.all([
    redis.get("downloads:total"),
    redis.get(`downloads:day:${today}`),
  ]);

  res.setHeader("Cache-Control", "no-store");
  res.json({
    total: Number(total ?? 0),
    today: Number(todayCount ?? 0),
  });
}
