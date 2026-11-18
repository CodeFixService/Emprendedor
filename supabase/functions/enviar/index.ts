// Edge Function "enviar" · Libreta de Cobros
//  - Sin "accion": envía las notificaciones push pendientes (la llama la base de datos cada minuto si hay algo).
//  - accion "foto": recibe la foto del comprobante que sube un cliente desde su link (con token de un solo uso).
//  - accion "limpiar": borra archivos viejos (fotos de más de 90 días y cuentas eliminadas).
//  - accion "crear_usuario": el administrador crea una cuenta con su billetera (solo con la sesión del admin).
//  - accion "ping": diagnóstico.
// Se despliega en Supabase → Edge Functions → nombre "enviar" (con "Verify JWT" apagado).
import webpush from 'npm:web-push@3.6.7';
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';

// ---------- G61 a · 📲 Push insistente (núcleo push.sql): cada aviso lleva su "grupo"; el celular confirma al recibirlo
// (service worker → cfx_push_recibido). Sin confirmación se reenvía a 1, 2, 5, 10, 15, 30 min y luego cada 1 h, hasta 48 h.
// deno-lint-ignore no-explicit-any
type Rpc = { rpc: (f: string, a?: Record<string, unknown>) => any };
type SubPush = { endpoint: string; p256dh: string; auth: string };
const ACK_URL = (Deno.env.get('SUPABASE_URL') || '') + '/rest/v1/rpc/cfx_push_recibido';
const ACK_KEY = Deno.env.get('SUPABASE_ANON_KEY') || '';
const grupos = () => { const m = new Map<string, string>(); return (k: string) => { if (!m.has(k)) m.set(k, crypto.randomUUID()); return m.get(k)!; }; };
function conAck(payload: string, grupo: string) {
  try { const o = JSON.parse(payload); o.ack = grupo; o.ackUrl = ACK_URL; o.ackKey = ACK_KEY; return JSON.stringify(o); } catch { return payload; }
}
async function anotarPush(s: Rpc, lista: (SubPush & { grupo: string; payload: string })[]) {
  if (!lista.length) return;
  try { await s.rpc('cfx_push_anotar', { p_lista: lista.map((x) => ({ grupo: x.grupo, endpoint: x.endpoint, p256dh: x.p256dh, auth: x.auth, payload: x.payload })) }); } catch { /* sin push.sql todavía */ }
}
async function reintentarPush(s: Rpc, preparar: () => Promise<boolean>) {
  let data: (SubPush & { payload: string })[] | null = null;
  try { const r = await s.rpc('cfx_push_tomar'); data = r.error ? null : r.data; } catch { return 0; }
  if (!data?.length || !(await preparar())) return 0;
  let n = 0;
  await Promise.allSettled(data.map(async (e) => {
    try { await webpush.sendNotification({ endpoint: e.endpoint, keys: { p256dh: e.p256dh, auth: e.auth } }, e.payload, { TTL: 86400, urgency: 'high' }); n++; }
    catch (err) { const c = (err as { statusCode?: number })?.statusCode; if (c === 404 || c === 410) await s.rpc('cfx_push_muerto', { p_endpoint: e.endpoint }); }
  }));
  return n;
}

const VERSION = '1.4.2';
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (o: unknown, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

function db() {
  return createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

type Envio = { id: number; titulo: string; cuerpo: string; url: string | null; tag: string | null; endpoint: string; p256dh: string; auth: string };

async function enviarCola() {
  const sb = db();
  const { data: sec } = await sb.rpc('srv_secretos');
  if (!sec?.vapid_public || !sec?.vapid_private) {
    await sb.rpc('srv_cola_tomar', { p_max: 1000 }); // sin claves no se puede enviar: se descarta
    return { enviados: 0, error: 'Faltan las claves push (Admin → Ajustes)' };
  }
  webpush.setVapidDetails('mailto:soporte@libretadecobros.cl', sec.vapid_public, sec.vapid_private);
  const reenviados = await reintentarPush(sb, async () => true), gr = grupos();
  let enviados = 0, fallidos = 0;
  for (let vuelta = 0; vuelta < 5; vuelta++) {
    const { data, error } = await sb.rpc('srv_cola_tomar', { p_max: 200 });
    if (error) throw error;
    const lista = (data || []) as Envio[];
    if (!lista.length) break;
    for (let i = 0; i < lista.length; i += 50) {
      const grupo = lista.slice(i, i + 50).map((e) => { const tag = e.tag || ('lc-' + e.id), g = gr(tag);
        return { ...e, grupo: g, payload: conAck(JSON.stringify({ title: e.titulo, body: e.cuerpo, url: e.url || 'app/', tag }), g) }; });
      await anotarPush(sb, grupo);
      const res = await Promise.allSettled(grupo.map((e) => webpush.sendNotification(
        { endpoint: e.endpoint, keys: { p256dh: e.p256dh, auth: e.auth } }, e.payload, { TTL: 86400, urgency: 'high' },
      )));
      for (let j = 0; j < res.length; j++) {
        const r = res[j];
        if (r.status === 'fulfilled') { enviados++; continue; }
        fallidos++;
        const code = (r.reason as { statusCode?: number })?.statusCode;
        if (code === 404 || code === 410) await sb.rpc('srv_quitar_endpoint', { p_endpoint: grupo[j].endpoint });
      }
    }
  }
  return { enviados, fallidos, reenviados };
}

function tipoImagen(b: Uint8Array): string | null {
  if (b.length > 12 && b[0] === 0x52 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x46 && b[8] === 0x57 && b[9] === 0x45 && b[10] === 0x42 && b[11] === 0x50) return 'image/webp';
  if (b.length > 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return 'image/jpeg';
  if (b.length > 8 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return 'image/png';
  return null;
}

async function subirFoto(body: { id?: string; token?: string; data?: string }) {
  const id = String(body.id || '');
  if (!/^[0-9a-f-]{36}$/i.test(id) || typeof body.token !== 'string' || typeof body.data !== 'string') return { ok: false, error: 'Datos inválidos' };
  if (body.data.length > 1_500_000) return { ok: false, error: 'La foto es muy grande (máximo 1 MB)' };
  const sb = db();
  const { data: v, error } = await sb.rpc('srv_foto_validar', { p_id: id, p_token: body.token });
  if (error) throw error;
  if (!v?.ok) return { ok: false, error: 'El permiso para subir la foto venció. Vuelve a enviar el comprobante.' };
  const b64 = body.data.replace(/^data:[^,]*,/, '');
  let bytes: Uint8Array;
  try { bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)); } catch { return { ok: false, error: 'Archivo inválido' }; }
  if (bytes.length > 1_048_576) return { ok: false, error: 'La foto es muy grande (máximo 1 MB)' };
  const tipo = tipoImagen(bytes);
  if (!tipo) return { ok: false, error: 'El archivo no es una imagen' };
  const { error: e2 } = await sb.storage.from('comprobantes').upload(v.ruta, bytes, { contentType: tipo, upsert: true });
  if (e2) return { ok: false, error: 'No se pudo guardar la foto: ' + e2.message };
  await sb.rpc('srv_foto_lista', { p_id: id, p_ruta: v.ruta });
  return { ok: true };
}

async function limpiar() {
  const sb = db();
  let borrados = 0;
  for (let vuelta = 0; vuelta < 10; vuelta++) {
    const { data } = await sb.rpc('srv_archivos_por_borrar', { p_max: 500 });
    const lista = (data || []) as { id: number; bucket: string; ruta: string }[];
    if (!lista.length) break;
    const porBucket = new Map<string, string[]>();
    for (const a of lista) porBucket.set(a.bucket, [...(porBucket.get(a.bucket) || []), a.ruta]);
    for (const [bucket, rutas] of porBucket) await sb.storage.from(bucket).remove(rutas);
    await sb.rpc('srv_archivos_borrados', { p_ids: lista.map((a) => a.id) });
    borrados += lista.length;
  }
  return { borrados };
}

const RUBROS = ['almacen', 'feria', 'catalogo', 'emprendimiento', 'servicios', 'educacion', 'club', 'personal', 'otro'];
async function crearUsuario(req: Request, b: { email?: string; clave?: string; nombre?: string; rubro?: string; dias_pro?: number }) {
  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  const sb = db();
  const { data: who } = await sb.auth.getUser(jwt);
  if (!who?.user) return { ok: false, error: 'Tu sesión terminó. Ingresa de nuevo.' };
  const { data: esAdmin } = await sb.rpc('srv_es_admin', { p_uid: who.user.id });
  if (!esAdmin) return { ok: false, error: 'Solo el administrador puede crear cuentas.' };
  const email = String(b.email || '').trim().toLowerCase();
  const clave = String(b.clave || '');
  const nombre = String(b.nombre || '').trim().replace(/\s+/g, ' ');
  const rubro = RUBROS.includes(String(b.rubro)) ? String(b.rubro) : 'otro';
  const dias = Math.max(0, Math.min(3660, Math.round(Number(b.dias_pro) || 0)));
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return { ok: false, error: 'Correo inválido' };
  if (clave.length < 8 || !/[a-zA-Z]/.test(clave) || !/\d/.test(clave)) return { ok: false, error: 'La contraseña debe tener 8 caracteres o más, con letras y números' };
  if (nombre.length < 2 || nombre.length > 50) return { ok: false, error: 'El nombre del negocio debe tener entre 2 y 50 letras' };
  const { data: nu, error: e1 } = await sb.auth.admin.createUser({ email, password: clave, email_confirm: true, user_metadata: { nombre } });
  if (e1 || !nu?.user) {
    const m = e1?.message || 'No se pudo crear la cuenta';
    return { ok: false, error: /already|registered|exists/i.test(m) ? 'Ese correo ya tiene cuenta' : m };
  }
  const { error: e2 } = await sb.rpc('srv_crear_negocio', { p_uid: nu.user.id, p_nombre: nombre, p_rubro: rubro, p_pro_dias: dias });
  if (e2) { await sb.auth.admin.deleteUser(nu.user.id); return { ok: false, error: e2.message }; }
  return { ok: true };
}

// G37 · Entrar con QR ({accion: 'qr_entrar'}): el computador entra con la sesión que aprobó el celular (núcleo qr.js + qr.sql).
async function qrEntrar(b: { token?: string; secreto?: string }) {
  const s = db();
  const { data: email, error } = await s.rpc('cfx_qr_canjear', { p_token: String(b.token || ''), p_secreto: String(b.secreto || '') });
  if (error) return { ok: false, error: 'Actualiza la base de datos (falta Entrar con QR)' };
  if (!email) return { ok: false, error: 'El código venció o ya se usó' };
  const { data, error: e2 } = await s.auth.admin.generateLink({ type: 'magiclink', email: String(email) });
  if (e2 || !data?.properties?.hashed_token) return { ok: false, error: 'No se pudo abrir la sesión' };
  return { ok: true, token_hash: data.properties.hashed_token };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  // G99 a ⚡ Aviso de Mercado Pago (webhook): no se confía en lo que llega; la base vuelve a preguntarle a MP por esa referencia.
  { const ref = new URL(req.url).searchParams.get('cfx_mp'); if (ref) { try { await db().rpc('cfx_mp_aviso', { p_ref: ref.slice(0, 80) }); } catch { /* el cron revisa igual */ } if (new URL(req.url).searchParams.get('cfx_volver')) { try { const { data: v } = await db().rpc('cfx_pago_volver', { p_ref: ref.slice(0, 80) }); if (typeof v === 'string' && /^https:\/\/[^\s"<>]+$/.test(v)) return new Response(null, { status: 303, headers: { ...CORS, Location: v } }); } catch { /* sin regreso */ } } return new Response('ok', { headers: CORS }); } }
  try {
    const body = req.method === 'POST' ? await req.json().catch(() => ({})) : {};
    if (body?.accion === 'ping') return json({ ok: true, version: VERSION, servicio: !!Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') });
    if (body?.accion === 'qr_entrar') return json(await qrEntrar(body));
    if (body?.accion === 'foto') return json(await subirFoto(body));
    if (body?.accion === 'limpiar') return json(await limpiar());
    if (body?.accion === 'crear_usuario') return json(await crearUsuario(req, body));
    return json(await enviarCola());
  } catch (e) {
    return json({ ok: false, error: String((e as Error)?.message || e) }, 500);
  }
});
