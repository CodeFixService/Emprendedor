// Edge Function "enviar" · Libreta de Cobros
//  - Sin "accion": envía las notificaciones push pendientes (la llama la base de datos cada minuto si hay algo).
//  - accion "foto": recibe la foto del comprobante que sube un cliente desde su link (con token de un solo uso).
//  - accion "limpiar": borra archivos viejos (fotos de más de 90 días y cuentas eliminadas).
//  - accion "ping": diagnóstico.
// Se despliega en Supabase → Edge Functions → nombre "enviar" (con "Verify JWT" apagado).
import webpush from 'npm:web-push@3.6.7';
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';

const VERSION = '1.0.0';
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
  let enviados = 0, fallidos = 0;
  for (let vuelta = 0; vuelta < 5; vuelta++) {
    const { data, error } = await sb.rpc('srv_cola_tomar', { p_max: 200 });
    if (error) throw error;
    const lista = (data || []) as Envio[];
    if (!lista.length) break;
    for (let i = 0; i < lista.length; i += 50) {
      const grupo = lista.slice(i, i + 50);
      const res = await Promise.allSettled(grupo.map((e) => webpush.sendNotification(
        { endpoint: e.endpoint, keys: { p256dh: e.p256dh, auth: e.auth } },
        JSON.stringify({ title: e.titulo, body: e.cuerpo, url: e.url || 'app/', tag: e.tag || ('lc-' + e.id) }),
        { TTL: 86400 },
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
  return { enviados, fallidos };
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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = req.method === 'POST' ? await req.json().catch(() => ({})) : {};
    if (body?.accion === 'ping') return json({ ok: true, version: VERSION, servicio: !!Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') });
    if (body?.accion === 'foto') return json(await subirFoto(body));
    if (body?.accion === 'limpiar') return json(await limpiar());
    return json(await enviarCola());
  } catch (e) {
    return json({ ok: false, error: String((e as Error)?.message || e) }, 500);
  }
});
