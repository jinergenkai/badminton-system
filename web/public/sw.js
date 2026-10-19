// Service worker Sổ Cầu Lông — app shell chạy offline.
// - Trang (navigate): mạng trước, rớt mạng thì trả index.html đã cache.
// - /assets/* (file build có hash), icon, font Google: cache trước.
// - /api/* và mọi request khác origin/không phải GET: không đụng (sổ tiền đã có cache localStorage riêng).
const VERSION = "v1";
const SHELL = `shell-${VERSION}`, STATIC = `static-${VERSION}`;
const PRECACHE = ["/", "/index.html", "/manifest.webmanifest", "/icons/icon-192.png", "/icons/icon.svg"];

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(SHELL).then((c) => c.addAll(PRECACHE)));
});

self.addEventListener("activate", (e) => {
  e.waitUntil((async () => {
    const keep = new Set([SHELL, STATIC]);
    for (const k of await caches.keys()) if (!keep.has(k)) await caches.delete(k);
    await self.clients.claim();
  })());
});

self.addEventListener("message", (e) => { if (e.data === "skipWaiting") self.skipWaiting(); });

const isFont = (u) => u.hostname === "fonts.googleapis.com" || u.hostname === "fonts.gstatic.com";

self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  const same = url.origin === self.location.origin;
  if (same && url.pathname.startsWith("/api/")) return;

  if (req.mode === "navigate") {
    e.respondWith((async () => {
      try {
        const res = await fetch(req);
        const c = await caches.open(SHELL); c.put("/index.html", res.clone());
        return res;
      } catch {
        return (await caches.match("/index.html")) || (await caches.match("/")) || Response.error();
      }
    })());
    return;
  }

  if ((same && (url.pathname.startsWith("/assets/") || url.pathname.startsWith("/icons/"))) || isFont(url)) {
    e.respondWith((async () => {
      const hit = await caches.match(req);
      if (hit) return hit;
      const res = await fetch(req);
      if (res.ok || res.type === "opaque") { const c = await caches.open(STATIC); c.put(req, res.clone()); }
      return res;
    })());
  }
});
