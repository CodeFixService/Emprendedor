/* Libreta de Cobros · herramientas comunes (todas las pantallas). Requiere js/config.js y vendor/supabase.js. */
(function (global) {
  'use strict';
  const VERSION = '1.0.0';
  const C = global.LC_CONFIG;
  const RAIZ = new URL('../', document.currentScript.src).href; // carpeta raíz de la app (termina en /)
  const sb = global.supabase.createClient(C.SUPABASE_URL, C.SUPABASE_ANON_KEY, {
    auth: { persistSession: true, autoRefreshToken: true, storageKey: 'lc-auth', detectSessionInUrl: true },
  });

  // ---------- DOM seguro (nunca se usa innerHTML con datos) ----------
  const $ = (s, r) => (r || document).querySelector(s);
  function el(tag, attrs, ...hijos) {
    const e = document.createElement(tag);
    if (attrs) {
      for (const [k, v] of Object.entries(attrs)) {
        if (v == null || v === false) continue;
        if (k === 'class') e.className = v;
        else if (k === 'style') e.style.cssText = v;
        else if (k.startsWith('on') && typeof v === 'function') e.addEventListener(k.slice(2), v);
        else if (k === 'html') throw new Error('html no permitido');
        else if (v === true) e.setAttribute(k, '');
        else e.setAttribute(k, String(v));
      }
    }
    for (const h of hijos.flat(Infinity)) {
      if (h == null || h === false) continue;
      e.append(h instanceof Node ? h : document.createTextNode(String(h)));
    }
    return e;
  }
  const vaciar = (e) => { while (e.firstChild) e.removeChild(e.firstChild); return e; };

  // ---------- Formato ----------
  const pesos = (n) => (n < 0 ? '-' : '') + '$' + Math.abs(Math.round(Number(n) || 0)).toLocaleString('es-CL');
  const ZONA = 'America/Santiago';
  const fechaCorta = (d) => d ? new Date(typeof d === 'string' && d.length === 10 ? d + 'T12:00:00' : d).toLocaleDateString('es-CL', { day: 'numeric', month: 'short', timeZone: ZONA }) : '';
  const fechaLarga = (d) => d ? new Date(typeof d === 'string' && d.length === 10 ? d + 'T12:00:00' : d).toLocaleDateString('es-CL', { weekday: 'long', day: 'numeric', month: 'long', timeZone: ZONA }) : '';
  const hora = (d) => new Date(d).toLocaleTimeString('es-CL', { hour: '2-digit', minute: '2-digit', hourCycle: 'h23', timeZone: ZONA });
  const fechaHora = (d) => fechaCorta(d) + ' ' + hora(d);
  const hoyISO = () => new Date().toLocaleDateString('en-CA', { timeZone: ZONA });
  const sumarDias = (iso, n) => { const d = new Date(iso + 'T12:00:00'); d.setDate(d.getDate() + n); return d.toISOString().slice(0, 10); };
  const diasEntre = (a, b) => Math.round((new Date(b + 'T12:00:00') - new Date(a + 'T12:00:00')) / 86400000);
  function relativo(iso) {
    if (!iso) return '';
    const d = diasEntre(hoyISO(), iso);
    if (d === 0) return 'hoy'; if (d === 1) return 'mañana'; if (d === -1) return 'ayer';
    return d > 0 ? 'en ' + d + ' días' : 'hace ' + (-d) + ' días';
  }
  const iniciales = (n) => (n || '?').trim().split(/\s+/).slice(0, 2).map((p) => p[0]).join('').toUpperCase();
  const COLORES = ['#059669', '#2563eb', '#7c3aed', '#db2777', '#ea580c', '#0d9488', '#4f46e5', '#b45309'];
  const colorDe = (s) => { let h = 0; for (const c of String(s)) h = (h * 31 + c.charCodeAt(0)) >>> 0; return COLORES[h % COLORES.length]; };
  const norm = (t) => String(t || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();

  // ---------- Validaciones (mismas reglas que el servidor) ----------
  const V = {
    telefono(p) {
      const t = String(p || '').trim(); if (!t) return null;
      const d = t.replace(/\D/g, '');
      if (d.length === 11 && d.startsWith('569')) return '+' + d;
      if (d.length === 9 && d.startsWith('9')) return '+56' + d;
      if (d.length === 8 && !t.startsWith('+')) return '+569' + d;
      if (t.startsWith('+') && d.length >= 8 && d.length <= 15 && !d.startsWith('56')) return '+' + d;
      throw new Error('Teléfono inválido. Usa el formato +56 9 1234 5678');
    },
    rut(p) {
      const t = String(p || '').trim(); if (!t) return null;
      const c = t.replace(/[^0-9kK]/g, '').toUpperCase();
      if (c.length < 8 || c.length > 9) throw new Error('RUT inválido');
      const cuerpo = c.slice(0, -1), dv = c.slice(-1);
      if (!/^\d+$/.test(cuerpo)) throw new Error('RUT inválido');
      let s = 0, f = 2;
      for (let i = cuerpo.length - 1; i >= 0; i--) { s += Number(cuerpo[i]) * f; f = f === 7 ? 2 : f + 1; }
      const r = 11 - (s % 11); const esp = r === 11 ? '0' : r === 10 ? 'K' : String(r);
      if (dv !== esp) throw new Error('RUT inválido: el dígito verificador no corresponde');
      return cuerpo + '-' + dv;
    },
    telBonito(t) { const d = String(t || '').replace(/\D/g, ''); return d.length === 11 && d.startsWith('569') ? '+56 9 ' + d.slice(3, 7) + ' ' + d.slice(7) : t || ''; },
    rutBonito(r) { if (!r) return ''; const [c, d] = r.split('-'); return Number(c).toLocaleString('es-CL') + '-' + d; },
    email: (e) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(String(e || '').trim()),
    clave(p, email) {
      if (String(p).length < 8) return 'La contraseña debe tener al menos 8 caracteres';
      if (!/[a-zA-Z]/.test(p) || !/\d/.test(p)) return 'Usa al menos una letra y un número';
      if (email && p.toLowerCase() === String(email).toLowerCase()) return 'La contraseña no puede ser igual al correo';
      return null;
    },
    monto(n) { const v = Math.round(Number(n)); return Number.isFinite(v) && v >= 1 && v <= 9999999 ? v : null; },
    PROHIBIDAS: ['demanda', 'tribunal', 'juzgado', 'embargo', 'dicom', 'abogado', 'policia', 'carabinero', 'carcel', 'denuncia', 'querella', 'boletin comercial', 'cobranza judicial', 'tus familiares', 'tu trabajo', 'tu jefe'],
    prohibida(t) { const n = norm(t); return V.PROHIBIDAS.find((w) => n.includes(w)) || null; },
  };
  const DESECHABLES = ['mailinator.com', 'yopmail.com', 'guerrillamail.com', '10minutemail.com', 'tempmail.com', 'temp-mail.org', 'trashmail.com', 'getnada.com', 'sharklasers.com', 'dispostable.com', 'maildrop.cc', 'throwawaymail.com', 'fakeinbox.com', 'mintemail.com', 'emailondeck.com'];
  V.desechable = (e) => DESECHABLES.includes(String(e || '').split('@')[1]?.toLowerCase());

  // ---------- Llamadas al servidor ----------
  class ErrorApp extends Error { constructor(m, pista) { super(m); this.pista = pista || ''; } }
  function traducir(e) {
    const m = (e && (e.message || e.error_description || e.msg)) || String(e);
    if (/Failed to fetch|NetworkError|Load failed|network/i.test(m)) return new ErrorApp('Sin conexión a internet. Revisa tu señal e intenta de nuevo.', 'RED');
    if (/JWT expired|invalid JWT|not authenticated/i.test(m)) return new ErrorApp('Tu sesión terminó. Ingresa de nuevo.', 'SESION');
    if (/permission denied/i.test(m)) return new ErrorApp('No tienes permiso para esto.');
    if (/Invalid login credentials/i.test(m)) return new ErrorApp('Correo o contraseña incorrectos.');
    if (/User already registered|already been registered/i.test(m)) return new ErrorApp('Ese correo ya tiene cuenta. Ingresa o recupera tu contraseña.');
    if (/rate limit|too many/i.test(m)) return new ErrorApp('Demasiados intentos. Espera un minuto y vuelve a probar.');
    if (/Email not confirmed/i.test(m)) return new ErrorApp('Confirma tu correo con el link que te enviamos.');
    if (/Password should be/i.test(m)) return new ErrorApp('La contraseña es muy débil: usa al menos 8 caracteres con letras y números.');
    return new ErrorApp(m, e && e.hint);
  }
  async function rpc(nombre, params) {
    const { data, error } = await sb.rpc(nombre, params || {});
    if (error) throw traducir(error);
    return data;
  }
  async function funcion(body) {
    const r = await fetch(C.SUPABASE_URL + '/functions/v1/enviar', {
      method: 'POST', headers: { 'Content-Type': 'application/json', apikey: C.SUPABASE_ANON_KEY }, body: JSON.stringify(body),
    }).catch((e) => { throw traducir(e); });
    const j = await r.json().catch(() => ({}));
    if (!r.ok && !j.error) throw new ErrorApp('El servidor de avisos no responde (función "enviar").');
    return j;
  }
  const uuid = () => (crypto.randomUUID ? crypto.randomUUID() : '10000000-1000-4000-8000-100000000000'.replace(/[018]/g, (c) => (c ^ crypto.getRandomValues(new Uint8Array(1))[0] & 15 >> c / 4).toString(16)));

  // ---------- Avisos en pantalla ----------
  function toast(msg, opts) {
    opts = opts || {};
    let cont = $('#toast'); if (!cont) { cont = el('div', { id: 'toast', role: 'status', 'aria-live': 'polite' }); document.body.append(cont); }
    const t = el('div', { class: 'toast' + (opts.error ? ' error' : '') }, msg);
    if (opts.accion) t.append(el('button', { onclick: () => { opts.accion.fn(); t.remove(); } }, opts.accion.texto));
    cont.append(t);
    setTimeout(() => t.remove(), opts.ms || (opts.accion ? 8000 : 3500));
    return t;
  }
  let cargas = 0;
  function cargando(on) {
    cargas = Math.max(0, cargas + (on ? 1 : -1));
    let c = $('#cargando');
    if (cargas && !c) document.body.append(el('div', { id: 'cargando', class: 'cargando' }, el('div', { class: 'spinner' })));
    if (!cargas && c) c.remove();
  }
  async function conCarga(fn) { cargando(true); try { return await fn(); } finally { cargando(false); } }

  function dialogo(titulo, contenido, botones, opts) {
    opts = opts || {};
    return new Promise((resolve) => {
      const velo = el('div', { class: 'velo' });
      const cerrar = (v) => { velo.remove(); document.removeEventListener('keydown', esc); resolve(v); };
      const esc = (e) => { if (e.key === 'Escape' && !opts.fijo) cerrar(null); };
      const caja = el('div', { class: 'dialogo', role: 'dialog', 'aria-modal': 'true', 'aria-label': titulo },
        el('h2', null, titulo), contenido,
        el('div', { class: 'botones' }, (botones || [{ texto: 'Cerrar', valor: null }]).map((b) =>
          el('button', { class: 'btn ' + (b.clase || ''), type: 'button', onclick: async () => {
            if (b.antes) { try { const ok = await b.antes(); if (ok === false) return; } catch (e) { error(e); return; } }
            cerrar(b.valor);
          } }, b.texto))));
      velo.append(caja);
      velo.addEventListener('click', (e) => { if (e.target === velo && !opts.fijo) cerrar(null); });
      document.addEventListener('keydown', esc);
      document.body.append(velo);
      const f = caja.querySelector('input, textarea, select'); if (f && !opts.sinFoco) setTimeout(() => f.focus(), 50);
    });
  }
  const confirmar = (titulo, texto, si, clase) => dialogo(titulo, el('p', null, texto), [
    { texto: 'Cancelar', valor: false }, { texto: si || 'Sí', valor: true, clase: clase || 'primario' }]);
  async function pedirTexto(titulo, etiqueta, opts) {
    opts = opts || {};
    const inp = el(opts.multilinea ? 'textarea' : 'input', { maxlength: opts.max || 100, placeholder: opts.placeholder || '', inputmode: opts.inputmode || null, type: opts.tipo || null });
    if (opts.valor != null) inp.value = opts.valor;
    const err = el('div', { class: 'error' });
    const r = await dialogo(titulo, el('div', { class: 'campo' }, el('label', null, etiqueta), inp, opts.ayuda ? el('div', { class: 'ayuda' }, opts.ayuda) : null, err),
      [{ texto: 'Cancelar', valor: null }, { texto: opts.boton || 'Aceptar', clase: opts.clase || 'primario', valor: true, antes: () => {
        const v = inp.value.trim();
        if ((opts.min || 0) > v.length) { err.textContent = 'Mínimo ' + opts.min + ' caracteres'; return false; }
        if (opts.validar) { const m = opts.validar(v); if (m) { err.textContent = m; return false; } }
        return true;
      } }]);
    return r ? inp.value.trim() : null;
  }

  // Errores: si es del plan, ofrece Premium.
  function error(e) {
    const x = e instanceof ErrorApp ? e : traducir(e);
    console.warn(x);
    if (x.pista === 'PLAN' && global.LC.alPlan) { global.LC.alPlan(x.message); return; }
    if (x.pista === 'SESION' && global.LC.alSesion) { global.LC.alSesion(); return; }
    toast(x.message, { error: true, ms: 5500 });
  }

  // ---------- Copiar, compartir, WhatsApp ----------
  async function copiar(texto, aviso) {
    try { await navigator.clipboard.writeText(texto); }
    catch (e) { const t = el('textarea', { style: 'position:fixed;opacity:0' }); t.value = texto; document.body.append(t); t.select(); document.execCommand('copy'); t.remove(); }
    toast(aviso || 'Copiado ✓');
  }
  const wa = (tel, texto) => 'https://wa.me/' + String(tel || '').replace(/\D/g, '') + '?text=' + encodeURIComponent(texto);
  function abrir(url) { const w = window.open(url, '_blank', 'noopener'); if (!w) location.href = url; }

  // ---------- Imágenes: se achican en el celular antes de subir ----------
  async function achicarImagen(archivo, maxLado, maxBytes) {
    if (!archivo || !/^image\//.test(archivo.type) && !/\.(heic|heif)$/i.test(archivo.name || '')) throw new ErrorApp('Elige una imagen (foto o captura).');
    if (archivo.size > 10 * 1024 * 1024) throw new ErrorApp('La imagen pesa más de 10 MB.');
    const url = URL.createObjectURL(archivo);
    try {
      const img = await new Promise((ok, mal) => { const i = new Image(); i.onload = () => ok(i); i.onerror = () => mal(new ErrorApp('No se pudo leer la imagen. Prueba con una captura de pantalla.')); i.src = url; });
      let w = img.naturalWidth, h = img.naturalHeight; const f = Math.min(1, maxLado / Math.max(w, h)); w = Math.round(w * f); h = Math.round(h * f);
      const cv = el('canvas'); cv.width = w; cv.height = h; cv.getContext('2d').drawImage(img, 0, 0, w, h);
      for (const q of [0.82, 0.7, 0.58, 0.45, 0.35]) {
        const blob = await new Promise((ok) => cv.toBlob(ok, 'image/webp', q));
        const b = blob && blob.type === 'image/webp' ? blob : await new Promise((ok) => cv.toBlob(ok, 'image/jpeg', q));
        if (b && b.size <= maxBytes) return b;
      }
      throw new ErrorApp('La imagen es muy pesada incluso achicada. Prueba con una captura.');
    } finally { URL.revokeObjectURL(url); }
  }
  const blobADataURL = (b) => new Promise((ok) => { const r = new FileReader(); r.onload = () => ok(r.result); r.readAsDataURL(b); });

  // ---------- Notificaciones push ----------
  const pushSoportado = () => 'serviceWorker' in navigator && 'PushManager' in global && 'Notification' in global;
  const esIOS = () => /iPhone|iPad|iPod/.test(navigator.userAgent);
  const instalada = () => matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
  function b64aBytes(b64) { const p = '='.repeat((4 - b64.length % 4) % 4); const r = atob((b64 + p).replace(/-/g, '+').replace(/_/g, '/')); return Uint8Array.from(r, (c) => c.charCodeAt(0)); }
  async function suscribirPush(vapid) {
    if (!pushSoportado()) throw new ErrorApp(esIOS() && !instalada()
      ? 'En iPhone primero agrega la app a tu pantalla de inicio (Compartir → Agregar a inicio) y ábrela desde ahí.'
      : 'Este navegador no permite notificaciones.');
    if (!vapid) throw new ErrorApp('Las notificaciones aún no están activadas por el administrador.');
    if (await Notification.requestPermission() !== 'granted') throw new ErrorApp('No diste permiso para las notificaciones. Actívalo en los ajustes del navegador.');
    const reg = await navigator.serviceWorker.ready;
    const key = b64aBytes(vapid);
    let sub = await reg.pushManager.getSubscription();
    if (sub) {
      const cur = sub.options && sub.options.applicationServerKey ? new Uint8Array(sub.options.applicationServerKey) : null;
      if (!cur || cur.length !== key.length || cur.some((b, i) => b !== key[i])) { await sub.unsubscribe(); sub = null; }
    }
    if (!sub) sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: key });
    return sub.toJSON();
  }
  async function pushActual() {
    if (!pushSoportado() || Notification.permission !== 'granted') return null;
    const reg = await navigator.serviceWorker.getRegistration(); return reg && reg.pushManager ? reg.pushManager.getSubscription() : null;
  }

  // ---------- Service worker, versión e instalación ----------
  let promptInstalar = null;
  global.addEventListener('beforeinstallprompt', (e) => { e.preventDefault(); promptInstalar = e; document.dispatchEvent(new Event('lc-instalable')); });
  async function instalar() {
    if (promptInstalar) { promptInstalar.prompt(); await promptInstalar.userChoice; promptInstalar = null; return true; }
    await dialogo('Instalar la app', el('div', null,
      esIOS() ? el('p', null, 'En iPhone: toca el botón Compartir (cuadrado con flecha) y luego "Agregar a inicio".')
        : el('p', null, 'En el menú del navegador (⋮) elige "Instalar app" o "Agregar a la pantalla principal". En el computador, busca el ícono de instalar en la barra de direcciones.')));
    return false;
  }
  function registrarSW(alActualizar) {
    if (!('serviceWorker' in navigator)) return;
    navigator.serviceWorker.register(RAIZ + 'sw.js', { scope: RAIZ }).then((reg) => {
      const avisar = () => reg.waiting && alActualizar && alActualizar(() => { reg.waiting.postMessage('activar'); });
      if (reg.waiting) avisar();
      reg.addEventListener('updatefound', () => {
        const n = reg.installing; if (!n) return;
        n.addEventListener('statechange', () => { if (n.state === 'installed' && navigator.serviceWorker.controller) avisar(); });
      });
      setInterval(() => reg.update().catch(() => {}), 30 * 60 * 1000);
    }).catch(() => {});
    let recargando = false;
    navigator.serviceWorker.addEventListener('controllerchange', () => { if (!recargando) { recargando = true; location.reload(); } });
  }
  const versionMenor = (a, b) => { const x = String(a).split('.').map(Number), y = String(b).split('.').map(Number); for (let i = 0; i < 3; i++) { if ((x[i] || 0) !== (y[i] || 0)) return (x[i] || 0) < (y[i] || 0); } return false; };

  // ---------- Almacenamiento local seguro ----------
  const local = {
    get(k, d) { try { const v = localStorage.getItem(k); return v == null ? d : JSON.parse(v); } catch (e) { return d; } },
    set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) { /* lleno o bloqueado */ } },
    del(k) { try { localStorage.removeItem(k); } catch (e) { /* nada */ } },
  };
  if (local.get('lc-letra-grande', false)) document.documentElement.classList.add('grande');

  // ---------- Descargas ----------
  function descargar(nombre, contenido, tipo) {
    const b = contenido instanceof Blob ? contenido : new Blob([contenido], { type: tipo || 'text/plain;charset=utf-8' });
    const a = el('a', { href: URL.createObjectURL(b), download: nombre }); document.body.append(a); a.click();
    setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
  }
  function csv(filas, columnas) {
    const esc = (v) => { const s = v == null ? '' : String(v); return /[";\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
    return '﻿' + [columnas.map((c) => esc(c.t)).join(';'), ...filas.map((f) => columnas.map((c) => esc(c.v(f))).join(';'))].join('\r\n');
  }
  function excel(hojas) {
    const esc = (s) => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    const xml = ['<?xml version="1.0"?><Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">',
      '<Styles><Style ss:ID="h"><Font ss:Bold="1"/><Interior ss:Color="#D1FAE5" ss:Pattern="Solid"/></Style></Styles>'];
    for (const h of hojas) {
      xml.push('<Worksheet ss:Name="' + esc(h.nombre).slice(0, 30) + '"><Table>');
      xml.push('<Row>' + h.columnas.map((c) => '<Cell ss:StyleID="h"><Data ss:Type="String">' + esc(c.t) + '</Data></Cell>').join('') + '</Row>');
      for (const f of h.filas) xml.push('<Row>' + h.columnas.map((c) => { const v = c.v(f); const num = typeof v === 'number'; return '<Cell><Data ss:Type="' + (num ? 'Number' : 'String') + '">' + esc(v) + '</Data></Cell>'; }).join('') + '</Row>');
      xml.push('</Table></Worksheet>');
    }
    xml.push('</Workbook>');
    return new Blob([xml.join('')], { type: 'application/vnd.ms-excel' });
  }

  global.LC = {
    VERSION, C, RAIZ, sb, $, el, vaciar, pesos, fechaCorta, fechaLarga, hora, fechaHora, hoyISO, sumarDias, diasEntre, relativo, iniciales, colorDe, norm,
    V, ErrorApp, traducir, rpc, funcion, uuid, toast, cargando, conCarga, dialogo, confirmar, pedirTexto, error, copiar, wa, abrir,
    achicarImagen, blobADataURL, pushSoportado, suscribirPush, pushActual, esIOS, instalada, instalar, registrarSW, versionMenor,
    local, descargar, csv, excel, alPlan: null, alSesion: null,
  };
})(window);
