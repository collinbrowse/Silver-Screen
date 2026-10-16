// Routing, header, cache, and rate-limit tests for the TMDB proxy.
// Run with `node --test 'worker/test/*.test.js'` (Node 22+, no dependencies).

import assert from "node:assert/strict";
import { test } from "node:test";

import { CACHE_SECONDS, handle, isAllowedPath, upstreamURL } from "../src/index.js";

const TOKEN = "worker-secret-token";

function fakeUpstream(status = 200, body = '{"id":278}') {
  const calls = [];
  const fetch = async (url, init) => {
    calls.push({ url, init });
    return new Response(body, {
      status,
      headers: { "Content-Type": "application/json;charset=utf-8", "Set-Cookie": "tmdb=1" },
    });
  };
  return { fetch, calls };
}

function fakeCache() {
  const store = new Map();
  return {
    store,
    async match(request) {
      return store.get(request.url)?.clone();
    },
    async put(request, response) {
      store.set(request.url, response);
    },
  };
}

function fakeContext() {
  const pending = [];
  return {
    pending,
    waitUntil(promise) {
      pending.push(promise);
    },
  };
}

function fakeLimiter(allow) {
  const keys = [];
  return {
    keys,
    async limit({ key }) {
      keys.push(key);
      return { success: allow };
    },
  };
}

function get(path, headers = {}) {
  return new Request(`https://proxy.example.workers.dev${path}`, { headers });
}

test("upstreamURL keeps the /3 path and query, and rejects anything else", () => {
  assert.equal(
    upstreamURL("https://proxy.example/3/movie/278?language=en-US&append_to_response=credits"),
    "https://api.themoviedb.org/3/movie/278?language=en-US&append_to_response=credits",
  );
  assert.equal(upstreamURL("https://proxy.example/"), null);
  assert.equal(upstreamURL("https://proxy.example/3"), null);
  assert.equal(upstreamURL("https://proxy.example/4/list/1"), null);
  assert.equal(upstreamURL("https://proxy.example/3/../4/list/1"), null);
});

test("allows every TMDB path the app and the health check call", () => {
  const paths = [
    "/3/movie/278",
    "/3/movie/278/reviews",
    "/3/movie/now_playing",
    "/3/movie/upcoming",
    "/3/movie/popular",
    "/3/collection/10",
    "/3/tv/1396",
    "/3/tv/1396/season/1",
    "/3/tv/1396/season/1/episode/1",
    "/3/tv/1396/watch/providers",
    "/3/tv/1396/reviews",
    "/3/tv/on_the_air",
    "/3/tv/popular",
    "/3/person/287",
    "/3/person/popular",
    "/3/search/movie",
    "/3/search/tv",
    "/3/search/person",
    "/3/discover/movie",
    "/3/discover/tv",
  ];
  for (const path of paths) {
    assert.equal(isAllowedPath(path), true, path);
  }
});

test("rejects TMDB paths the app does not use", () => {
  const paths = [
    "/3/",
    "/3/movie",
    "/3/movie/",
    "/3/movie//reviews",
    "/3/account/1",
    "/3/authentication/token/new",
    "/3/list/1",
    "/3/find/tt0111161",
    "/3/configuration",
    "/3/search/multi",
    "/3/search/movie/extra",
    "/3/discover/person",
    "/3/trending/movie/day",
    "/4/list/1",
  ];
  for (const path of paths) {
    assert.equal(isAllowedPath(path), false, path);
  }
});

test("returns 404 JSON for a disallowed path without calling TMDB", async () => {
  const upstream = fakeUpstream();

  const response = await handle(get("/3/account/1"), { TMDB_ACCESS_TOKEN: TOKEN }, fakeContext(), {
    fetch: upstream.fetch,
  });

  assert.equal(response.status, 404);
  assert.equal(response.headers.get("Content-Type"), "application/json");
  assert.deepEqual(await response.json(), { status_message: "Not found." });
  assert.equal(upstream.calls.length, 0);
});

test("returns 400 for encoded separators and dots in any case", async () => {
  const upstream = fakeUpstream();
  const env = { TMDB_ACCESS_TOKEN: TOKEN };
  const paths = [
    "/3/movie/278%2f..%2f..%2faccount",
    "/3/movie/278%2F",
    "/3/movie/278%5creviews",
    "/3/movie/278%5C",
    "/3/movie/278%2e",
    "/3/movie/a%2Eb",
  ];

  for (const path of paths) {
    const response = await handle(get(path), env, fakeContext(), { fetch: upstream.fetch });
    assert.equal(response.status, 400, path);
    assert.equal(response.headers.get("Content-Type"), "application/json");
  }
  assert.equal(upstream.calls.length, 0);
});

test("resolves dot segments before the allow-list check", async () => {
  const upstream = fakeUpstream();

  const response = await handle(get("/3/movie/../account/1"), { TMDB_ACCESS_TOKEN: TOKEN }, fakeContext(), {
    fetch: upstream.fetch,
  });

  assert.equal(response.status, 404);
  assert.equal(upstream.calls.length, 0);
});

test("forwards with the Worker's bearer token and drops client headers", async () => {
  const upstream = fakeUpstream();
  const request = get("/3/movie/278?language=en-US", {
    Authorization: "Bearer client-supplied",
    Cookie: "session=abc",
    "CF-Connecting-IP": "203.0.113.7",
  });

  const response = await handle(request, { TMDB_ACCESS_TOKEN: TOKEN }, fakeContext(), { fetch: upstream.fetch });

  assert.equal(response.status, 200);
  assert.equal(await response.text(), '{"id":278}');
  assert.equal(upstream.calls.length, 1);
  const { url, init } = upstream.calls[0];
  assert.equal(url, "https://api.themoviedb.org/3/movie/278?language=en-US");
  assert.equal(init.method, "GET");
  assert.equal(init.headers.get("Authorization"), `Bearer ${TOKEN}`);
  assert.equal(init.headers.get("Accept"), "application/json");
  assert.equal(init.headers.get("Cookie"), null);
  assert.equal(init.headers.get("CF-Connecting-IP"), null);
});

test("asks Cloudflare's fetch cache to keep only 2xx responses", async () => {
  const upstream = fakeUpstream();

  await handle(get("/3/movie/278"), { TMDB_ACCESS_TOKEN: TOKEN }, fakeContext(), { fetch: upstream.fetch });

  const { cf } = upstream.calls[0].init;
  assert.equal(cf.cacheTtl, undefined);
  assert.deepEqual(cf.cacheTtlByStatus, { "200-299": CACHE_SECONDS, "300-599": 0 });
});

test("returns only the content type and a cache header, never the token", async () => {
  const upstream = fakeUpstream();
  const response = await handle(get("/3/movie/278"), { TMDB_ACCESS_TOKEN: TOKEN }, fakeContext(), {
    fetch: upstream.fetch,
  });

  assert.equal(response.headers.get("Content-Type"), "application/json;charset=utf-8");
  assert.equal(response.headers.get("Cache-Control"), `public, max-age=${CACHE_SECONDS}`);
  assert.equal(response.headers.get("Set-Cookie"), null);
  assert.equal(response.headers.get("Authorization"), null);
});

test("caches a 200 and serves the next request from cache", async () => {
  const upstream = fakeUpstream();
  const cache = fakeCache();
  const env = { TMDB_ACCESS_TOKEN: TOKEN };

  const ctx = fakeContext();
  await handle(get("/3/movie/278"), env, ctx, { fetch: upstream.fetch, cache });
  await Promise.all(ctx.pending);
  const second = await handle(get("/3/movie/278"), env, fakeContext(), { fetch: upstream.fetch, cache });

  assert.equal(upstream.calls.length, 1);
  assert.ok(cache.store.has("https://api.themoviedb.org/3/movie/278"));
  assert.equal(await second.text(), '{"id":278}');
});

test("does not cache an error and passes its status through", async () => {
  const upstream = fakeUpstream(404, '{"status_code":34}');
  const cache = fakeCache();
  const ctx = fakeContext();

  const response = await handle(get("/3/movie/0"), { TMDB_ACCESS_TOKEN: TOKEN }, ctx, { fetch: upstream.fetch, cache });

  assert.equal(response.status, 404);
  assert.equal(response.headers.get("Cache-Control"), "no-store");
  assert.equal(ctx.pending.length, 0);
  assert.equal(cache.store.size, 0);
});

test("rate-limits by client IP before calling TMDB", async () => {
  const upstream = fakeUpstream();
  const limiter = fakeLimiter(false);
  const request = get("/3/movie/278", { "CF-Connecting-IP": "203.0.113.7" });

  const response = await handle(request, { TMDB_ACCESS_TOKEN: TOKEN, RATE_LIMITER: limiter }, fakeContext(), {
    fetch: upstream.fetch,
  });

  assert.equal(response.status, 429);
  assert.equal(response.headers.get("Retry-After"), "60");
  assert.deepEqual(limiter.keys, ["203.0.113.7"]);
  assert.equal(upstream.calls.length, 0);
});

test("lets a request through when the limiter allows it", async () => {
  const upstream = fakeUpstream();
  const limiter = fakeLimiter(true);

  const response = await handle(get("/3/movie/278"), { TMDB_ACCESS_TOKEN: TOKEN, RATE_LIMITER: limiter }, fakeContext(), {
    fetch: upstream.fetch,
  });

  assert.equal(response.status, 200);
  assert.deepEqual(limiter.keys, ["unknown"]);
});

test("rejects non-GET methods and non-/3 paths without calling TMDB", async () => {
  const upstream = fakeUpstream();
  const env = { TMDB_ACCESS_TOKEN: TOKEN };

  const post = new Request("https://proxy.example.workers.dev/3/movie/278/rating", { method: "POST", body: "{}" });
  const posted = await handle(post, env, fakeContext(), { fetch: upstream.fetch });
  const root = await handle(get("/"), env, fakeContext(), { fetch: upstream.fetch });

  assert.equal(posted.status, 405);
  assert.equal(posted.headers.get("Allow"), "GET");
  assert.equal(root.status, 404);
  assert.equal(upstream.calls.length, 0);
});

test("fails clearly when the token secret is missing", async () => {
  const upstream = fakeUpstream();

  const response = await handle(get("/3/movie/278"), {}, fakeContext(), { fetch: upstream.fetch });

  assert.equal(response.status, 500);
  assert.match(await response.text(), /wrangler secret put TMDB_ACCESS_TOKEN/);
  assert.equal(upstream.calls.length, 0);
});

test("returns 502 JSON when TMDB cannot be reached", async () => {
  const fetch = async () => {
    throw new TypeError("network connection lost");
  };
  const ctx = fakeContext();

  const response = await handle(get("/3/movie/278"), { TMDB_ACCESS_TOKEN: TOKEN }, ctx, { fetch, cache: fakeCache() });

  assert.equal(response.status, 502);
  assert.equal(response.headers.get("Cache-Control"), "no-store");
  assert.deepEqual(await response.json(), { status_message: "Could not reach TMDB." });
  assert.equal(ctx.pending.length, 0);
});
