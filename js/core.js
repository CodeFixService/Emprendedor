/* Libreta de Cobros · herramientas comunes (todas las pantallas). Requiere js/config.js y vendor/supabase.js. */
(function (global) {
  'use strict';
  const VERSION = '1.21.9';
  const BD = 21; // versión de la base de datos que necesita esta versión de la app
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
  const fechaISO = (d) => new Date(d).toLocaleDateString('en-CA', { timeZone: ZONA });
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
  // Colores del tema (los mismos que acepta el servidor) e íconos de perfil: emojis, sin subir imágenes.
  const TEMAS = [['#059669', 'Esmeralda'], ['#2563eb', 'Azul'], ['#4f46e5', 'Índigo'], ['#7c3aed', 'Morado'], ['#db2777', 'Rosado'], ['#e11d48', 'Frambuesa'],
    ['#ea580c', 'Naranjo'], ['#d97706', 'Ámbar'], ['#0d9488', 'Turquesa'], ['#0284c7', 'Celeste'], ['#92400e', 'Café'], ['#334155', 'Grafito']];
  const ICONOS = ['🏪', '🛒', '🥖', '🥑', '🍎', '🍓', '🧁', '🍰', '🍩', '☕', '🍔', '🌭', '🌮', '🍕', '🍣', '🥤', '🍦', '🧃', '🍺', '🍷',
    '👕', '👗', '👟', '👜', '💄', '💅', '💇', '✂️', '🧵', '🧶', '🎨', '📚', '✏️', '🎓', '🛠️', '🔧', '🚗', '🛵', '🚚', '🐶',
    '🌸', '🌱', '📱', '💻', '🎁', '🧸', '💊', '🏠', '⚽', '🎵', '📸', '💎', '⭐', '🔥', '💰', '🙂'];
  // Textos y planes por defecto; el administrador los cambia en Ajustes (se guardan en la base de datos).
  const TEXTOS_DEF = {
    landing_titulo: 'Tu negocio en el bolsillo. Cobra sin vergüenza.',
    landing_bajada: 'Ventas, gastos y fiado en 3 segundos. Tu cliente ve lo que debe con un link y te paga por transferencia.',
    pro_titulo: 'Esto es Pro ⭐',
    pago_instrucciones: 'Paga con el botón y después sube la foto del comprobante. {negocio} lo revisa y te avisa apenas lo apruebe.',
  };
  const PLANES_DEF = {
    free: { nombre: 'Free', descripcion: 'Gratis para siempre, con límites.', beneficios: [] },
    pro: { nombre: 'Pro', descripcion: 'Todo sin límites.', beneficios: ['♾️ Todo sin límites: clientes, fiados, ventas, gastos y cuotas', '📣 Cobrar a todos de una, con tonos y tu propio mensaje',
      '🧾 Recibos con imagen para mandar por WhatsApp', '📈 Reportes avanzados: mejores clientes, mejores días y comparación con el mes anterior',
      '🎯 Meta de ventas y presupuesto de gastos con alertas', '🗂️ Historial completo, Excel y estado de cuenta en PDF',
      '🔔 Resumen semanal al celular y avisos automáticos de cuotas', '🎨 Tu color en el link de tus clientes', '🤝 Billeteras conectadas: cuentas claras con familia y amigos'] },
  };
  const texto = (cfg, k) => ((cfg && cfg.textos && cfg.textos[k]) || TEXTOS_DEF[k] || '');
  const plan = (cfg, k) => { const p = (cfg && cfg.planes && cfg.planes[k]) || {}; const d = PLANES_DEF[k] || {};
    return { nombre: p.nombre || d.nombre, descripcion: p.descripcion || d.descripcion, beneficios: Array.isArray(p.beneficios) && p.beneficios.length ? p.beneficios : d.beneficios }; };
  // Íconos de línea (SVG fijos, sin datos del usuario), iguales en el menú de abajo y en "Más".
  const IC = {
    inicio: '<path d="M4 11l8-7 8 7v9a1 1 0 0 1-1 1h-4v-6H9v6H5a1 1 0 0 1-1-1z"/>',
    caja: '<rect x="3" y="6" width="18" height="14" rx="2"/><path d="M3 10h18M16 15h2M7 6V4.5A1.5 1.5 0 0 1 8.5 3H17"/>',
    mas: '<path d="M12 5v14M5 12h14"/>',
    clientes: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c0-3.5 3-5.5 6.5-5.5s6.5 2 6.5 5.5M16 4.6a3.5 3.5 0 0 1 0 6.8M18 14.7c2 .6 3.5 2.3 3.5 5.3"/>',
    menu: '<circle cx="5" cy="12" r="1.6"/><circle cx="12" cy="12" r="1.6"/><circle cx="19" cy="12" r="1.6"/>',
    chat: '<path d="M21 12a8 8 0 0 1-11.6 7.1L4 20l1-4.7A8 8 0 1 1 21 12z"/>',
    recibo: '<path d="M6 3h12v18l-3-2-3 2-3-2-3 2zM9 8h6M9 12h6M9 16h3"/>',
    megafono: '<path d="M3 10v4a1 1 0 0 0 1 1h2l5 4V5L6 9H4a1 1 0 0 0-1 1zM15 9a4 4 0 0 1 0 6M18 6a8 8 0 0 1 0 12"/>',
    grafico: '<path d="M4 20V10M10 20V4M16 20v-8M22 20H2"/>',
    enlace: '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>',
    etiqueta: '<path d="M3 12V4h8l10 10-8 8z"/><circle cx="7.5" cy="8.5" r="1.5"/>',
    estrella: '<path d="M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1L3.2 9.5l6.1-.9z"/>',
    regalo: '<rect x="3" y="8" width="18" height="5" rx="1"/><path d="M5 13v8h14v-8M12 8v13M12 8C10 4 6.5 4 6.5 6.5S10 8 12 8zM12 8c2-4 5.5-4 5.5-1.5S14 8 12 8z"/>',
    campana: '<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9M10 21a2 2 0 0 0 4 0"/>',
    reloj: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    ajustes: '<path d="M4 6h9M17 6h3M4 12h3M11 12h9M4 18h11M19 18h1"/><circle cx="15" cy="6" r="2"/><circle cx="9" cy="12" r="2"/><circle cx="17" cy="18" r="2"/>',
    paleta: '<path d="M12 3a9 9 0 1 0 0 18c1.1 0 1.5-.8 1.5-1.5 0-1.3-1-1.5-1-2.7 0-1 .8-1.8 1.8-1.8H17a4 4 0 0 0 4-4C21 6.6 17 3 12 3z"/><circle cx="7.5" cy="11" r="1"/><circle cx="10" cy="7" r="1"/><circle cx="15" cy="7" r="1"/>',
    usuario: '<circle cx="12" cy="8" r="4"/><path d="M4 21c0-4 4-6 8-6s8 2 8 6"/>',
    ayuda: '<circle cx="12" cy="12" r="9"/><path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.6.3-1 .9-1 1.6V14M12 17.5v.5"/>',
    escudo: '<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/>',
    salir: '<path d="M15 4h4a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1h-4M10 16l4-4-4-4M14 12H4"/>',
    tienda: '<path d="M3 9l1.5-5h15L21 9M3 9v11h18V9M3 9h18M9 20v-6h6v6"/>',
    tarjeta: '<rect x="2.5" y="5" width="19" height="14" rx="2"/><path d="M2.5 10h19M6 15h4"/>',
  };
  const parser = new DOMParser();
  function ico(nombre, tam) {
    const s = tam || 22;
    const doc = parser.parseFromString('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="' + s + '" height="' + s + '" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + (IC[nombre] || '') + '</svg>', 'image/svg+xml');
    const svg = document.importNode(doc.documentElement, true); svg.setAttribute('class', 'ic'); return svg;
  }
  // Las barras de opciones que se deslizan de lado quedan mostrando la opción elegida (no vuelven al inicio).
  // (El núcleo recuerda dónde quedó cada tira; aquí solo se asegura que la opción elegida se vea, sin mover la tira si ya se ve.)
  function centrarActivos(raiz) { requestAnimationFrame(() => { if (window.CodeFixTiras) window.CodeFixTiras.ajustar(raiz); }); }
  function aplicarColor(hex, guardar) {
    const r = document.documentElement.style;
    if (!/^#[0-9a-f]{6}$/i.test(hex || '')) hex = null;
    if (hex) {
      const n = parseInt(hex.slice(1), 16), k = 0.82;
      const os = '#' + [n >> 16, (n >> 8) & 255, n & 255].map((x) => Math.round(x * k).toString(16).padStart(2, '0')).join('');
      r.setProperty('--marca', hex); r.setProperty('--marca-2', os);
    } else { r.removeProperty('--marca'); r.removeProperty('--marca-2'); }
    const m = document.querySelector('meta[name="theme-color"]'); if (m) m.content = hex || '#059669';
    if (guardar !== false) local.set('lc-color', hex);
  }
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
  async function funcion(body, token) {
    const r = await fetch(C.SUPABASE_URL + '/functions/v1/enviar', {
      method: 'POST', headers: { 'Content-Type': 'application/json', apikey: C.SUPABASE_ANON_KEY, Authorization: 'Bearer ' + (token || C.SUPABASE_ANON_KEY) },
      body: JSON.stringify(body),
    }).catch(() => { throw new ErrorApp('No se pudo conectar con la función "enviar". Revisa tu internet o que la función esté desplegada.', 'RED'); });
    const j = await r.json().catch(() => ({}));
    if (!r.ok && !j.error) {
      const m = { 401: 'Supabase rechazó la llamada (401). En la función "enviar" apaga "Verify JWT" y guarda.',
        404: 'No existe una función llamada "enviar" (404). Revisa el nombre en Edge Functions.',
        500: 'La función "enviar" tuvo un error interno (500). Revisa que el código pegado esté completo.',
        503: 'La función "enviar" está arrancando o caída (503). Espera un minuto y prueba de nuevo.' }[r.status];
      throw new ErrorApp(m || 'La función "enviar" respondió con error ' + r.status + '.');
    }
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
    if (x.pista === 'BLOQUEADO' && global.LC.alBloqueo) { global.LC.alBloqueo(x.message); return; }
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
  // Abre en otra pestaña (WhatsApp, link de pago…). Con 'noopener' el navegador devuelve null aunque sí abra,
  // por eso se corta el vínculo a mano; solo si de verdad se bloqueó se abre en la misma pestaña.
  function abrir(url) {
    const w = window.open(url, '_blank');
    if (w) { try { w.opener = null; } catch (e) { /* nada */ } } else location.href = url;
  }

  // Calidad de fotos según su uso: viene del núcleo (fotos.js); estos valores son el respaldo.
  const FOTO = (k) => (window.CFX_FOTO && window.CFX_FOTO[k]) || { comprobante: { lado: 1000, calidad: 0.6, kb: 110 }, documento: { lado: 1400, calidad: 0.72, kb: 300 }, vitrina: { lado: 1080, calidad: 0.8, kb: 220 }, portada: { lado: 1280, calidad: 0.8, kb: 300 }, perfil: { lado: 400, calidad: 0.8, kb: 45 }, logo: { lado: 256, calidad: 0.85, kb: 30 } }[k];
  // ---------- Imágenes: se achican en el celular antes de subir ----------
  async function achicarImagen(archivo, maxLado, maxBytes) {
    if (!archivo || !/^image\//.test(archivo.type) && !/\.(heic|heif)$/i.test(archivo.name || '')) throw new ErrorApp('Elige una imagen (foto o captura).');
    if (archivo.size > 10 * 1024 * 1024) throw new ErrorApp('La imagen pesa más de 10 MB.');
    const url = URL.createObjectURL(archivo);
    try {
      const img = await new Promise((ok, mal) => { const i = new Image(); i.onload = () => ok(i); i.onerror = () => mal(new ErrorApp('No se pudo leer la imagen. Prueba con una captura de pantalla.')); i.src = url; });
      let w = img.naturalWidth, h = img.naturalHeight; const f = Math.min(1, maxLado / Math.max(w, h)); w = Math.round(w * f); h = Math.round(h * f);
      const cv = el('canvas'); cv.width = w; cv.height = h; cv.getContext('2d').drawImage(img, 0, 0, w, h);
      for (const q of [0.72, 0.6, 0.5, 0.4, 0.32]) {
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
  // La app NO se actualiza sola: usa la versión guardada en el celular hasta que la persona toca "Actualizar",
  // y ese botón aparece solo cuando el administrador libera una versión nueva (igual que en CodeFix).
  function registrarSW() {
    if (!('serviceWorker' in navigator)) return;
    navigator.serviceWorker.register(RAIZ + 'sw.js', { scope: RAIZ }).catch(() => {});
  }
  // Borra solo la copia guardada de esta app (no toca CodeFix ni tus datos) y la vuelve a descargar.
  async function repararApp() {
    cargando(true);
    try {
      for (const k of await caches.keys()) if (k.startsWith('lc-')) await caches.delete(k);
      const regs = navigator.serviceWorker ? await navigator.serviceWorker.getRegistrations() : [];
      for (const r of regs) if (r.scope === RAIZ) await r.unregister();
    } catch (e) { /* nada */ }
    location.reload();
  }
  function actualizarAhora() {
    cargando(true);
    const listo = () => location.reload();
    navigator.serviceWorker && navigator.serviceWorker.ready.then((reg) => {
      const sw = reg.active; if (!sw) return listo();
      const ch = new MessageChannel();
      ch.port1.onmessage = (e) => { cargando(false); if (e.data && e.data.ok) listo(); else toast((e.data && e.data.error) || 'No se pudo actualizar: revisa tu internet.', { error: true, ms: 8000 }); };
      sw.postMessage({ tipo: 'actualizar' }, [ch.port2]);
      setTimeout(() => { cargando(false); }, 30000);
    }).catch(listo);
    if (!navigator.serviceWorker) listo();
  }
  // Llama a mostrar(texto, accion, forzada) si hay una versión liberada más nueva que la de este celular.
  function revisarVersion(cfg, mostrar) {
    if (!cfg) return;
    const lib = cfg.version_liberada, min = cfg.version_min;
    if (min && versionMenor(VERSION, min)) return mostrar('Esta versión de la app ya no funciona bien. Actualízala para seguir.', actualizarAhora, true);
    if (lib && versionMenor(VERSION, lib)) return mostrar('✨ Hay una versión nueva (v' + lib + ').', actualizarAhora, false);
    mostrar(null);
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
  // Cambia los emojis del menú por los íconos de línea (si algo falla, queda el emoji).
  document.querySelectorAll('[data-ico]').forEach((n) => { try { vaciar(n).append(ico(n.dataset.ico, n.closest('.nav') ? 24 : 20)); } catch (e) { /* queda el emoji */ } });

  global.LC = {
    VERSION, BD, ico, centrarActivos, TEXTOS_DEF, PLANES_DEF, texto, plan, C, RAIZ, sb, $, el, vaciar, TEMAS, ICONOS, aplicarColor, pesos, fechaCorta, fechaLarga, hora, fechaHora, hoyISO, fechaISO, sumarDias, diasEntre, relativo, iniciales, colorDe, norm,
    V, ErrorApp, traducir, rpc, funcion, uuid, toast, cargando, conCarga, dialogo, confirmar, pedirTexto, error, copiar, wa, abrir,
    achicarImagen, FOTO, blobADataURL, pushSoportado, suscribirPush, pushActual, esIOS, instalada, instalar, registrarSW, versionMenor, revisarVersion, actualizarAhora, repararApp,
    local, descargar, csv, alPlan: null, alSesion: null, alBloqueo: null,
  };
})(window);
