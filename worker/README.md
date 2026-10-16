# TMDB proxy

A Cloudflare Worker that keeps the TMDB token off the device. The app calls
`https://<worker>/3/...`, and the Worker forwards the request to
`https://api.themoviedb.org/3/...` with the bearer token from a Worker secret.
To rotate the token, change the secret. No app update is needed.

- Forwards `GET` only, and only the TMDB paths the app uses: `/3/movie/…`,
  `/3/tv/…`, `/3/person/…`, `/3/collection/…`, `/3/search/{movie,tv,person}`,
  and `/3/discover/{movie,tv}` (`ALLOWED_RESOURCES` and `ALLOWED_ENDPOINTS` in
  `src/index.js`). Other methods get 405, and other paths get 404. A path with
  an encoded `/`, `\`, or `.` (`%2F`, `%5C`, `%2E`) gets 400. When the app starts
  calling a new TMDB path, add it to the allow-list and deploy the Worker first.
- Sends TMDB only `Accept` and the Worker's own `Authorization`. Nothing from the
  client is forwarded.
- Caches 200 responses for 4 hours (`CACHE_SECONDS` in `src/index.js`), keyed by
  URL. Errors are not cached.
- Limits each client IP to 240 requests a minute (`[[ratelimits]]` in
  `wrangler.toml`). Over the limit, the Worker returns 429 with `Retry-After: 60`.
- Images do not go through the Worker. The app loads them from `image.tmdb.org`,
  which needs no token.

It is plain JavaScript with no runtime dependencies. `wrangler` is only the
deploy tool, and `npx` fetches it when you run it.

## Test

```bash
node --test 'worker/test/*.test.js'
```

CI runs this in the **Validate rules** job.

## Deploy

You need a free Cloudflare account and the TMDB API Read Access Token (the same
value as `TMDB_ACCESS_TOKEN` in `Secrets.xcconfig`). Run these from the `worker/`
folder.

1. Sign in. This opens a browser.

   ```bash
   npx wrangler@4 login
   ```

2. Deploy. The first deploy asks you to pick a `workers.dev` subdomain if the
   account has none, then prints the Worker URL, such as
   `https://silverscreen-tmdb.<subdomain>.workers.dev`.

   ```bash
   npx wrangler@4 deploy
   ```

3. Store the token as a secret. Paste it at the prompt. It never goes in
   `wrangler.toml`.

   ```bash
   npx wrangler@4 secret put TMDB_ACCESS_TOKEN
   ```

4. Check it. Expect `200`. A `500` means step 3 did not take.

   ```bash
   curl -s -o /dev/null -w '%{http_code}\n' https://silverscreen-tmdb.SUBDOMAIN.workers.dev/3/movie/278
   ```

## Switch the app over

The app's base URL is `TMDB_BASE_URL`, and it includes `/3`. When it points
anywhere other than `api.themoviedb.org`, the app sends no token.

- **TestFlight and App Store builds.** Set the repository variable. The release
  job then writes `TMDB_BASE_URL` into `Secrets.xcconfig` and leaves the token
  out of the binary.

  ```bash
  gh variable set TMDB_PROXY_URL --body "https://silverscreen-tmdb.SUBDOMAIN.workers.dev/3"
  ```

  Keep the `TMDB_ACCESS_TOKEN` repository secret. The daily TMDB health check
  and the awards catalog job still call TMDB directly with it.

- **Local builds.** Optional. Add this to `Secrets.xcconfig`, writing `//` as
  `/$()/` because xcconfig treats `//` as a comment:

  ```
  TMDB_BASE_URL = https:/$()/silverscreen-tmdb.SUBDOMAIN.workers.dev/3
  ```

  A Debug build ignores `TMDB_ACCESS_TOKEN` once this is set, so you can keep
  the token for `scripts/marketing.py`. A local `scripts/release.py archive`
  refuses a proxy build that still contains the token, so clear
  `TMDB_ACCESS_TOKEN` before you archive from a Mac.

After the next TestFlight build, check that the app loads movies. Then rotate
the token on TMDB, because older builds contain it. Put the new token in the
Worker with step 3 and in the `TMDB_ACCESS_TOKEN` repository secret.

## Caching on workers.dev

Cloudflare's Cache API stores nothing on a `workers.dev` hostname. It works on a
custom domain. On `workers.dev`, the Worker also asks Cloudflare to cache the
TMDB fetch for 2xx responses only (`cf.cacheTtlByStatus`), but the cached copy
is not guaranteed. To make caching reliable, add a custom domain under **Workers & Pages →
silverscreen-tmdb → Settings → Domains & Routes**, then use that domain in
`TMDB_PROXY_URL`.

## Limits

The free plan allows 100,000 Worker requests a day. Every app call to TMDB is one
request, including cache hits.
