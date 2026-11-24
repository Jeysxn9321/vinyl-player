// Cloudflare Worker: holds the Discogs key/secret so they never ship in the app.
// NOT RUN LIVE. Written against the public Discogs API docs; test it before relying on it.
// Secrets: `wrangler secret put DISCOGS_KEY` and `wrangler secret put DISCOGS_SECRET`.
const UA = "LunaraProxy/1.0";

export default {
  async fetch(req, env) {
    const u = new URL(req.url);
    if (u.pathname !== "/lookup") return new Response("not found", { status: 404 });
    const artist = u.searchParams.get("artist"), album = u.searchParams.get("album");
    if (!artist || !album) return new Response("artist and album required", { status: 400 });
    const auth = `Discogs key=${env.DISCOGS_KEY}, secret=${env.DISCOGS_SECRET}`;
    const h = { "User-Agent": UA, Authorization: auth };

    const s = new URL("https://api.discogs.com/database/search");
    s.search = new URLSearchParams({ artist, release_title: album, type: "release", format: "Vinyl", per_page: "5" });
    const sr = await fetch(s, { headers: h });
    if (!sr.ok) return new Response("discogs " + sr.status, { status: 502 });
    const found = (await sr.json()).results || [];

    const releases = [];
    for (const r of found.slice(0, 4)) {            // Discogs allows 60 authenticated requests/min; stay small
      const rr = await fetch(`https://api.discogs.com/releases/${r.id}`, { headers: h });
      if (!rr.ok) continue;
      const d = await rr.json();
      releases.push({
        id: d.id, title: d.title, year: d.year ? String(d.year) : null,
        format: (d.formats || []).map(f => [f.name, ...(f.descriptions || [])].join(", ")).join(" + ") || null,
        catno: (d.labels || [])[0]?.catno || null, country: d.country || null, uri: d.uri || null,
        images: (d.images || []).map(i => ({ type: i.type, url: i.uri })),
      });
    }
    return new Response(JSON.stringify({ releases }), {
      headers: { "content-type": "application/json", "cache-control": "public, max-age=86400" },
    });
  },
};
