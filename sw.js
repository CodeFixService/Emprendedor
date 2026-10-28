/* Service worker · Libreta de Cobros
   La app NO se actualiza sola: sigue usando la versión guardada en el celular hasta que la persona toca
   "Actualizar" (el botón aparece cuando el administrador libera una versión). Cada versión vive en su propio
   caché "lc-app-<versión>" y "lc-meta" guarda cuál se está usando. También recibe las notificaciones push. */
const ARCHIVOS = [
  './', 'index.html', 'manifest.webmanifest', 'css/app.css',
  'vendor/supabase.js', 'js/config.js', 'js/barra.js', 'css/tema.css', 'js/core.js', 'js/inicio.js', 'js/app.js', 'js/portal.js', 'js/admin.js', 'js/iconos.js', 'js/instalar.js',
  'app/', 'app/index.html', 'c/', 'c/index.html', 'c/manifest.webmanifest', 'admin/', 'admin/index.html', 'legal/', 'legal/index.html',
  'icons/icon-192.png', 'icons/icon-512.png', 'icons/maskable-512.png', 'icons/favicon.svg',
];
const META = 'lc-meta';
let reinstalando = null;
// "?t=" evita copias viejas guardadas por GitHub (su CDN guarda archivos hasta 10 minutos).
const pedirVersion = () => fetch('version.json?t=' + Date.now(), { cache: 'no-store' }).then((r) => r.json()).then((j) => String(j.version));

// Algunos hostings (Cloudflare) redirigen ".../index.html" a ".../". Chrome no acepta una página redirigida
// guardada en caché (ERR_FAILED), así que se guarda y se entrega siempre una copia "limpia", sin la marca de redirección.
async function limpia(res) {
  if (!res || !res.redirected) return res;
  return new Response(await res.blob(), { status: res.status, statusText: res.statusText, headers: res.headers });
}

async function versionActual() {
  const r = await (await caches.open(META)).match('actual');
  return r ? r.text() : null;
}

// Descarga todos los archivos de una versión y la deja como la actual.
async function instalarVersion(v) {
  const c = await caches.open('lc-app-' + v);
  const marca = '?v=' + v + '&t=' + Date.now();
  // Revisa que lo publicado sea de verdad la versión v (si GitHub aún no termina de publicar, no instala nada a medias).
  const core = await (await fetch('js/core.js' + marca, { cache: 'no-store' })).text();
  if (!core.includes("VERSION = '" + v + "'")) throw new Error('La versión ' + v + ' aún se está publicando. Prueba de nuevo en unos minutos.');
  await Promise.all(ARCHIVOS.map(async (f) => {
    const res = await fetch(f + marca, { cache: 'no-store' });
    if (!res.ok) throw new Error('No se pudo descargar ' + f);
    await c.put(new Request(f), await limpia(res));
  }));
  await (await caches.open(META)).put('actual', new Response(v));
  for (const k of await caches.keys()) if (k.startsWith('lc-') && k !== META && k !== 'lc-app-' + v) await caches.delete(k);
  return v;
}

self.addEventListener('install', (e) => {
  // Primera vez en este celular: guarda la versión publicada hoy. Si ya había una, la conserva.
  e.waitUntil(versionActual().then((v) => v || pedirVersion().then(instalarVersion)).catch(() => {}).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

// Botón "Actualizar": baja la versión nueva y avisa cuando está lista.
self.addEventListener('message', (e) => {
  if (!e.data || e.data.tipo !== 'actualizar') return;
  const port = e.ports && e.ports[0];
  e.waitUntil(pedirVersion().then(instalarVersion)
    .then((v) => port && port.postMessage({ ok: true, version: v }))
    .catch((err) => port && port.postMessage({ ok: false, error: (err && err.message) || String(err) })));
});

// Primero la versión guardada; si falta un archivo, se pide a internet.
self.addEventListener('fetch', (e) => {
  const req = e.request;
  const url = new URL(req.url);
  if (req.method !== 'GET' || url.origin !== location.origin) return; // Supabase y otros: siempre a internet
  if (/\/(version\.json|sw\.js)$/.test(url.pathname)) return;          // siempre desde internet
  if (/^\/(rest|auth|storage|functions|realtime)\/v1\//.test(url.pathname)) return; // datos: nunca desde la copia guardada
  e.respondWith((async () => {
    const v = await versionActual();
    if (!v && !reinstalando) { // la copia guardada se borró (por ejemplo, al limpiar el navegador): se vuelve a armar
      reinstalando = pedirVersion().then(instalarVersion).catch(() => {}).then(() => { reinstalando = null; });
    }
    const c = v ? await caches.open('lc-app-' + v) : null;
    const hit = c && await c.match(req, { ignoreSearch: true });
    if (hit) return limpia(hit);
    try {
      const res = await limpia(await fetch(req));
      if (res.ok && c && url.pathname.startsWith(new URL(self.registration.scope).pathname)) c.put(req, res.clone());
      return res;
    } catch (err) {
      if (req.mode === 'navigate' && c) return (await limpia(await c.match('index.html'))) || Response.error();
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
