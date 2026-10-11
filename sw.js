/* Service worker · Libreta de Cobros
   Guarda la app para abrirla sin internet. Una versión nueva se instala en segundo plano y se activa
   cuando la persona toca "Actualizar" (o sola, si es la primera vez). Recibe las notificaciones push. */
const VERSION = '1.0.0';
const CACHE = 'lc-' + VERSION;
const ARCHIVOS = [
  './', 'index.html', 'manifest.webmanifest', 'css/app.css',
  'vendor/supabase.js', 'js/config.js', 'js/core.js', 'js/inicio.js', 'js/app.js', 'js/portal.js', 'js/admin.js',
  'app/', 'app/index.html', 'c/', 'c/index.html', 'c/manifest.webmanifest', 'admin/', 'admin/index.html', 'legal/', 'legal/index.html',
  'icons/icon-192.png', 'icons/icon-512.png', 'icons/maskable-512.png', 'icons/favicon.svg',
];

self.addEventListener('install', (e) => {
  e.waitUntil((async () => {
    const previas = (await caches.keys()).filter((k) => k.startsWith('lc-'));
    const c = await caches.open(CACHE);
    await c.addAll(ARCHIVOS.map((f) => new Request(f, { cache: 'reload' })));
    if (!previas.length) await self.skipWaiting(); // primera instalación: se activa al tiro
  })());
});

self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    for (const k of await caches.keys()) if (k.startsWith('lc-') && k !== CACHE) await caches.delete(k);
    await self.clients.claim();
  })());
});

self.addEventListener('message', (e) => { if (e.data === 'activar') self.skipWaiting(); });

self.addEventListener('fetch', (e) => {
  const req = e.request;
  const url = new URL(req.url);
  if (req.method !== 'GET' || url.origin !== location.origin) return; // Supabase y otros: siempre a internet
  e.respondWith((async () => {
    const c = await caches.open(CACHE);
    const hit = await c.match(req, { ignoreSearch: true });
    if (hit) return hit;
    try {
      const res = await fetch(req);
      if (res.ok && url.pathname.startsWith(new URL(self.registration.scope).pathname)) c.put(req, res.clone());
      return res;
    } catch (err) {
      if (req.mode === 'navigate') return (await c.match('index.html')) || Response.error();
      return Response.error();
    }
  })());
});

self.addEventListener('push', (e) => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (err) { d = { title: e.data && e.data.text() }; }
  e.waitUntil(self.registration.showNotification(d.title || 'Libreta de Cobros', {
    body: d.body || '', icon: 'icons/icon-192.png', badge: 'icons/icon-192.png', tag: d.tag, renotify: !!d.tag,
    data: { url: new URL(d.url || 'app/', self.registration.scope).href },
  }));
});

self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  const url = (e.notification.data && e.notification.data.url) || self.registration.scope;
  e.waitUntil((async () => {
    const lista = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    const destino = new URL(url);
    for (const c of lista) {
      const u = new URL(c.url);
      if (u.pathname === destino.pathname && 'focus' in c) { if (destino.hash) c.navigate(destino.href).catch(() => {}); return c.focus(); }
    }
    return self.clients.openWindow(url);
  })());
});
