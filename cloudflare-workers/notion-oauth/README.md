# notabene-oauth

Thin OAuth token-exchange proxy for the Nota Bene iOS app's Notion integration.

Notion requires `client_id` + `client_secret` to be sent on every `POST /v1/oauth/token`
call. Embedding the secret in a public iOS binary is unsafe, so this Cloudflare Worker
holds the secret and exposes two endpoints the app talks to instead.

## Endpoints

- `GET /oauth/notion/callback?code=…&state=…`
  Registered as the **redirect URI** in the Notion integration. Forwards the query string
  verbatim to `APP_REDIRECT_SCHEME` via a `302 Location` redirect, which
  `ASWebAuthenticationSession` follows back into the app.

- `POST /oauth/notion/exchange`
  Body: `{ "code": string, "redirect_uri": string }`. Server adds HTTP Basic auth from the
  configured secrets and forwards to `https://api.notion.com/v1/oauth/token`. Notion's
  response body and status are passed through unmodified.

## Local setup

```sh
cd cloudflare-workers/notion-oauth
npm install
```

## Configure secrets (one-time)

After creating the Public integration at <https://www.notion.so/profile/integrations>:

```sh
wrangler secret put NOTION_CLIENT_ID
wrangler secret put NOTION_CLIENT_SECRET
```

`APP_REDIRECT_SCHEME` is a public value defined in `wrangler.jsonc`. Update it there if
the iOS app's URL scheme changes.

## Deploy

```sh
wrangler deploy
```

The first deploy will prompt you to pick a `*.workers.dev` subdomain. The resulting URL
looks like `https://notabene-oauth.<subdomain>.workers.dev`. Register
`https://notabene-oauth.<subdomain>.workers.dev/oauth/notion/callback` as the Notion
integration's redirect URI.

## Type check

```sh
npm run typecheck
```
