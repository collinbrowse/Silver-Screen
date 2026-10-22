// TMDB proxy for Silver Screen.
//
// Forwards GET /3/* for the TMDB paths the app uses (ALLOWED_RESOURCES and
// ALLOWED_ENDPOINTS) to api.themoviedb.org and adds the bearer token from the
// TMDB_ACCESS_TOKEN Worker secret, so the token never ships in the app and can be
// rotated without an app update. Successful responses are cached for a few hours,
// and each client IP is rate-limited by the RATE_LIMITER binding (wrangler.toml).
//
// Images do not come through here: the app loads them from image.tmdb.org, which
// needs no token. See worker/README.md for deploy steps.

export const UPSTREAM_ORIGIN = "https://api.themoviedb.org";
export const CACHE_SECONDS = 4 * 60 * 60;
export const RETRY_AFTER_SECONDS = 60;

// TMDB v3 resources the app calls (the repositories under SilverScreen/Data/Repositories)
// and scripts/tmdb_health.py checks. Anything else is 404, so the Worker's token
// cannot be used as a general TMDB key. Add a path here before the app starts using it.
//
// Resources whose ids and sub-paths the app appends (movie/278/reviews,
// tv/1396/season/1/episode/1, tv/1396/watch/providers, ...).
export const ALLOWED_RESOURCES = ["movie", "tv", "person", "collection"];
// Exact list endpoints.
export const ALLOWED_ENDPOINTS = [
  "search/movie",
  "search/tv",
  "search/person",
  "discover/movie",
  "discover/tv",
];

// True when the decoded path could hide a separator or dot segment from the
// allow-list: %2F (/), %5C (\), or %2E (.), in any case.
export function hasEncodedSeparator(requestURL) {
  return /%(2f|5c|2e)/i.test(new URL(requestURL).pathname);
}

// True for a /3/ path the app uses. URL parsing has already resolved `..` segments.
export function isAllowedPath(pathname) {
  if (!pathname.startsWith("/3/")) {
    return false;
  }
  const rest = pathname.slice("/3/".length);
  const segments = rest.split("/");
  if (segments.some((segment) => segment === "")) {
    return false;
  }
  if (ALLOWED_ENDPOINTS.includes(rest)) {
    return true;
  }
  return segments.length >= 2 && ALLOWED_RESOURCES.includes(segments[0]);
}

// Upstream URL for a proxied request, or null when the path is not one the app uses.
// The query string passes through unchanged, so language and paging still reach TMDB.
export function upstreamURL(requestURL) {
  const url = new URL(requestURL);
  if (!isAllowedPath(url.pathname)) {
    return null;
  }
  return `${UPSTREAM_ORIGIN}${url.pathname}${url.search}`;
}

// Headers sent to TMDB. Nothing from the client is forwarded, so a client cannot
// replace the token or add cookies, and the cache key stays the URL alone.
export function upstreamHeaders(token) {
  return new Headers({
    Accept: "application/json",
    Authorization: `Bearer ${token}`,
  });
}

// Cloudflare fetch-cache options for the TMDB request. Only 2xx is kept, so a 404
// or 5xx is not replayed for hours. Everything else gets a TTL of 0 (do not cache).
export function upstreamCacheOptions() {
  return {
    cacheEverything: true,
    cacheTtlByStatus: { "200-299": CACHE_SECONDS, "300-599": 0 },
  };
}

// Headers returned to the app. Only the content type survives from TMDB.
export function responseHeaders(upstream, cacheable) {
  const headers = new Headers();
  const contentType = upstream.headers.get("Content-Type");
  if (contentType) {
    headers.set("Content-Type", contentType);
  }
  headers.set("Cache-Control", cacheable ? `public, max-age=${CACHE_SECONDS}` : "no-store");
  return headers;
}

// The client IP Cloudflare saw. Every request without one shares a single bucket.
export function clientKey(request) {
  return request.headers.get("CF-Connecting-IP") ?? "unknown";
}

function errorResponse(status, message, extraHeaders = {}) {
  return new Response(JSON.stringify({ status_message: message }), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store", ...extraHeaders },
  });
}

// Handles one request. `deps` lets tests swap in a fake upstream and cache.
export async function handle(request, env, ctx, deps) {
  if (request.method !== "GET") {
    return errorResponse(405, "Only GET is supported.", { Allow: "GET" });
  }

  if (hasEncodedSeparator(request.url)) {
    return errorResponse(400, "Encoded path separators are not allowed.");
  }

  const target = upstreamURL(request.url);
  if (!target) {
    return errorResponse(404, "Not found.");
  }

  const token = (env.TMDB_ACCESS_TOKEN ?? "").trim();
  if (!token) {
    // A missing secret is a deploy mistake. Say so without echoing anything.
    return errorResponse(500, "The proxy has no TMDB token. Run wrangler secret put TMDB_ACCESS_TOKEN.");
  }

  if (env.RATE_LIMITER) {
    const { success } = await env.RATE_LIMITER.limit({ key: clientKey(request) });
    if (!success) {
      return errorResponse(429, "Too many requests.", { "Retry-After": String(RETRY_AFTER_SECONDS) });
    }
  }

  const cacheKey = new Request(target, { method: "GET" });
  const cached = await deps.cache?.match(cacheKey);
  if (cached) {
    return cached;
  }

  let upstream;
  try {
    upstream = await deps.fetch(target, {
      method: "GET",
      headers: upstreamHeaders(token),
      cf: upstreamCacheOptions(),
    });
  } catch {
    // TMDB unreachable. Return JSON the app can decode, not a Worker exception page.
    return errorResponse(502, "Could not reach TMDB.");
  }

  const cacheable = upstream.status === 200;
  const response = new Response(upstream.body, {
    status: upstream.status,
    headers: responseHeaders(upstream, cacheable),
  });
  if (cacheable && deps.cache) {
    ctx.waitUntil(deps.cache.put(cacheKey, response.clone()));
  }
  return response;
}

export default {
  async fetch(request, env, ctx) {
    // caches.default is a no-op on workers.dev and works on a custom domain.
    return handle(request, env, ctx, { fetch: (url, init) => fetch(url, init), cache: caches.default });
  },
};
