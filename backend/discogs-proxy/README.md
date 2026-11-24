# Discogs proxy (optional)

Discogs requires an authenticated application. Its key and secret must NOT be inside the iOS app, so Lunara talks to this small proxy instead. Without it, the Discogs provider stays off and the rest of the artwork feature works.

**Status: never run against the live Discogs API.** The worker follows the public API docs; test it first.

## Credentials needed
1. A Discogs account → Settings → Developers → create an application → copy the **Consumer Key** and **Consumer Secret**.
2. Deploy `worker.js` (Cloudflare Workers, free tier):
   ```
   wrangler deploy worker.js --name lunara-discogs
   wrangler secret put DISCOGS_KEY
   wrangler secret put DISCOGS_SECRET
   ```
3. In Lunara: Settings → Vinyl artwork → "Discogs proxy URL" → `https://lunara-discogs.<you>.workers.dev` (https only).

## Contract
`GET /lookup?artist=…&album=…` → `{ "releases": [ { id, title, year, format, catno, country, uri, images: [ { type, url } ] } ] }`

## Things to check before turning it on
- Discogs' API terms restrict how images may be stored and shown. The app caches images on the device; read the current terms and attribution rules first.
- Discogs only labels images `primary` / `secondary`. None is guaranteed to be a centre label, so Lunara always shows them as "Not verified as label".
- Discogs enforces rate limits (60 requests/min authenticated); the worker makes up to 5 calls per lookup and the app caches results.
