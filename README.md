# Gifcity Proxy Party

A small Phoenix JSON API for using Internet Archive's GifCities in Datafruits chat.
No database, frontend build, or API key is required. Requires Elixir 1.15+ and
Erlang/OTP 25+. Dependencies are pinned in `mix.lock`.

## Run

```sh
mix deps.get
mix phx.server
```

```sh
curl 'http://localhost:4000/search?q=simpsons'
curl 'http://localhost:4000/health'
mix test
```

The HTTP transport tests bind a localhost port. In a sandbox that prohibits
listening sockets, run `mix test --exclude network`; this excludes two transport
tests while retaining the endpoint and cache tests.

## API

`GET /search?q=simpsons` returns the first 20 upstream rows, skipping malformed
rows. `q` must be a nonblank string of at most 200 bytes after trimming. Additional
parameters are ignored; pagination is not supported.

```json
{
  "data": [{
    "id": "<sha256 of archive capture>",
    "type": "gif",
    "slug": "<same id>",
    "title": "simpsons",
    "url": "http://localhost:4000/images/<signed-token>.gif",
    "preview_url": "http://localhost:4000/images/<signed-token>.gif",
    "images": {
      "original": {"url": "http://localhost:4000/images/<signed-token>.gif"},
      "fixed_width": {"url": "http://localhost:4000/images/<signed-token>.gif"}
    }
  }],
  "pagination": {"count": 1, "offset": 0}
}
```

`GET /images/:token.gif` downloads the GIF on its first request and serves cached
bytes thereafter. Both preview and original URLs serve the same original GIF;
images are not resized. URLs are deterministic and do not expire, so posted chat
messages still work after a restart or cache eviction. Keep `SECRET_KEY_BASE`
stable across deploys and identical on all instances. Rotating it invalidates
previously issued image URLs. The original archive must remain available on a
cache miss; this service is not permanent GIF storage.

`GET /health` returns `{"status":"ok"}` (process health, not upstream readiness).
Errors return `{"error":"..."}` with 400 for invalid queries, 404 for invalid
image tokens, 502 for upstream failures, 503 at capacity, or 504 on fetch deadline.

## Datafruits integration

The response includes the fields read by the existing `gif` serializer:
`data[].id`, `type`, `slug`, `images.original.url`, and `images.fixed_width.url`.
In the chat application's GIF adapter, set the deployed proxy host and change
`urlForQuery` to:

```js
urlForQuery(query) {
  return `${this.urlPrefix()}/search?q=${encodeURIComponent(query.query)}`;
}
```

This repository implements the proxy; the Datafruits frontend is not modified.
The sticker endpoint is not implemented. When testing locally, use
`host = 'http://localhost:4000'` in the chat adapter. Development CORS permits
`http://localhost:4200` plus `https://datafruits.fm` and
`https://www.datafruits.fm`. Production permits those two HTTPS origins by default.

## Cache and upstream behavior

- Search results cache for one hour, keyed by trimmed query, with a fixed seed.
- GIF bytes cache for one day; browser caching is also one day.
- Each instance holds at most 500 entries and approximately 64 MiB of serialized
  cache values. Oldest-expiring entries are evicted first. Caches are in memory
  and are not shared across instances.
- Concurrent misses for the same key share one upstream request. There are at
  most 16 concurrent fetches and 100 waiting callers per key.
- Downloads stop at 5 MiB, with an 8-second receive timeout and a 15-second total
  fetch deadline. Failures are not cached.
- Only server-signed archive capture paths can be fetched. Downloads always go
  to `web.archive.org`; redirects are refused, and GIF signatures are checked
  before serving. Archive captures that redirect or exceed the limit return 502.

The upstream contract follows the [GifCities search client](https://github.com/ArchiveLabs/gifcities/blob/master/src/components/search-results.jsx)
and its [documented result shape](https://github.com/ArchiveLabs/gifcities/blob/master/src/components/results.jsx):
a JSON array with `gif` (timestamp/original URL) and `url_text`. The proxy uses
`https://gifcities.archive.org/api/v1/gifsearch` and raw Wayback replay (`id_`).
Tests use representative fixtures and a local HTTP server. A live upstream smoke
test remains necessary in a network-enabled environment.

## Production

Set these environment variables (terminate TLS at your reverse proxy):

```sh
export SECRET_KEY_BASE="$(mix phx.gen.secret)"
export PHX_HOST="gifs.example.com"
export PORT=4000
export PHX_SERVER=true
# Optional comma-separated exact origins; overrides the defaults:
export CORS_ORIGINS="https://datafruits.fm,https://www.datafruits.fm"
MIX_ENV=prod mix deps.get
MIX_ENV=prod mix release
_build/prod/rel/gifcity_proxy_party/bin/gifcity_proxy_party start
```

`PHX_HOST` controls the public HTTPS URLs returned to chat. Persist the generated
secret in your deployment's secret store. Rate limiting for this public API can
be configured at the reverse proxy; CORS does not restrict non-browser clients.

## Heroku

The included `Procfile` starts a Mix release with the HTTP server enabled.
`elixir_buildpack.config` pins Elixir 1.15.8 / OTP 26.2 and enables release builds.
`app.json` also describes the app for Heroku's dashboard deployment flow.
Use the classic Elixir buildpack on Heroku-22 for this toolchain; no Node buildpack,
database add-on, or migration command is needed.

From a checkout with these files committed, create the app (choose a unique name):

```sh
heroku login
heroku create YOUR_APP_NAME --stack heroku-22 --buildpack https://github.com/HashNuke/heroku-buildpack-elixir.git
heroku apps:info --app YOUR_APP_NAME
```

Copy the hostname from the reported **Web URL**. Use its exact value, including
any generated suffix, without `https://` or a trailing slash. Configure the app:

```sh
heroku config:set --app YOUR_APP_NAME \
  MIX_ENV=prod \
  PHX_HOST=YOUR_EXACT_HEROKU_HOSTNAME \
  SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  CORS_ORIGINS='https://datafruits.fm,https://www.datafruits.fm,http://localhost:4200'

git push heroku HEAD:main
heroku ps:scale web=1 --app YOUR_APP_NAME
heroku logs --tail --app YOUR_APP_NAME
```

For an existing app, use `heroku git:remote --app YOUR_APP_NAME`,
`heroku stack:set heroku-22 --app YOUR_APP_NAME`, and
`heroku buildpacks:set https://github.com/HashNuke/heroku-buildpack-elixir.git --app YOUR_APP_NAME`
instead of `heroku create`. Set the config vars before pushing. Do not reset
`SECRET_KEY_BASE` on subsequent deploys: existing chat image URLs depend on it.
Heroku supplies `PORT`; do not set it yourself. The app listens on `0.0.0.0` and
Heroku terminates HTTPS at its router.

Verify the deployed app:

```sh
curl 'https://YOUR_EXACT_HEROKU_HOSTNAME/health'
curl -i -H 'Origin: https://datafruits.fm' \
  'https://YOUR_EXACT_HEROKU_HOSTNAME/search?q=pizza'
```

Point the Datafruits GIF adapter at `https://YOUR_EXACT_HEROKU_HOSTNAME`.
If using a custom domain, configure it in Heroku and update `PHX_HOST` to that
domain. Cache contents reset whenever a dyno restarts; each dyno has its own cache.

References: [Elixir buildpack release configuration](https://github.com/HashNuke/heroku-buildpack-elixir#elixir-releases)
and [Heroku buildpack management](https://devcenter.heroku.com/articles/managing-buildpacks).
