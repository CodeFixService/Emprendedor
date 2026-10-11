-- =====================================================================
--  LIBRETA DE COBROS · instalación completa de la base de datos
--  Proyecto Supabase propio (independiente de CodeFix Apps).
--  Se puede ejecutar de nuevo para actualizar: no borra datos.
--  © CodeFix · Josué Castillo
-- =====================================================================

-- ---------- Extensiones ----------
create extension if not exists pgcrypto with schema extensions;
do $$ begin create extension if not exists pg_cron; exception when others then raise notice 'pg_cron: %', sqlerrm; end $$;
do $$ begin create extension if not exists pg_net with schema extensions; exception when others then raise notice 'pg_net: %', sqlerrm; end $$;

create schema if not exists privado;
revoke all on schema privado from public, anon, authenticated;
grant usage on schema privado to authenticated;

-- ---------- Configuración interna ----------
create table if not exists privado.config (clave text primary key, valor text not null);
insert into privado.config values
  ('version_bd', '1'),
  ('admin_email', 'juanjosuecastilloloyola@gmail.com'),
  ('url_proyecto', 'https://zbgfvxsqajtixjzxoxeu.supabase.co'),
  ('zona', 'America/Santiago')
on conflict (clave) do update set valor = excluded.valor;
insert into privado.config values ('admin_id', '') on conflict (clave) do nothing;

create table if not exists privado.secretos (nombre text primary key, valor text not null);
create table if not exists privado.pruebas_usadas (email_hash text primary key, at timestamptz default now());
create table if not exists privado.limites (clave text, ventana bigint, n int default 0, primary key (clave, ventana));
create table if not exists privado.tareas_hechas (tarea text, fecha date, primary key (tarea, fecha));
create table if not exists privado.archivos_por_borrar (id bigserial primary key, bucket text not null, ruta text not null, creado timestamptz default now());
create table if not exists privado.fotos_pendientes (comprobante uuid primary key, token_hash text not null, vence timestamptz not null);

-- =====================================================================
--  TABLAS
-- =====================================================================
create table if not exists public.ajustes (
  id int primary key default 1 check (id = 1),
  precio_mensual int not null default 4990 check (precio_mensual between 0 and 1000000),
  precio_anual int not null default 49900 check (precio_anual between 0 and 10000000),
  link_pago text not null default '',
  transferencia jsonb not null default '{}'::jsonb,
  contacto_whatsapp text not null default '',
  dias_prueba int not null default 14 check (dias_prueba between 0 and 60),
  dias_gracia int not null default 3 check (dias_gracia between 0 and 15),
  lim_normal jsonb not null default '{"clientes":20,"movimientos":250,"cuotas":2,"productos":6,"comprobantes":15,"historial_meses":6}'::jsonb,
  lim_premium jsonb not null default '{"productos":30,"comprobantes":300,"ayudantes":3}'::jsonb,
  version_legal int not null default 1,
  version_min text not null default '1.0.0',
  actualizado timestamptz default now()
);
insert into public.ajustes (id) values (1) on conflict do nothing;

create table if not exists public.perfiles (
  id uuid primary key references auth.users (id) on delete cascade,
  nombre text not null default '',
  terminos_version int not null default 0,
  terminos_at timestamptz,
  creado timestamptz not null default now()
);

create table if not exists public.negocios (
  id uuid primary key default gen_random_uuid(),
  dueno uuid not null unique references auth.users (id) on delete cascade,
  nombre text not null check (char_length(nombre) between 2 and 50),
  rubro text not null default 'otro' check (rubro in ('almacen','feria','catalogo','emprendimiento','servicios','educacion','club','personal','otro')),
  whatsapp text,
  banco jsonb not null default '{}'::jsonb,
  venc_defecto text not null default '7' check (venc_defecto in ('0','7','15','30','fin')),
  limite_general int not null default 0 check (limite_general between 0 and 5000000),
  pin_activo boolean not null default true,
  saldo_a_favor boolean not null default false,
  logo_url text,
  color text check (color is null or color in ('#059669','#2563eb','#7c3aed','#db2777','#ea580c','#0d9488','#4f46e5','#334155')),
  plantilla_propia text check (plantilla_propia is null or char_length(plantilla_propia) <= 500),
  premium_hasta timestamptz,
  en_prueba boolean not null default false,
  plan_aplicado text not null default 'normal' check (plan_aplicado in ('normal','premium')),
  estado text not null default 'activo' check (estado in ('activo','suspendido','eliminado')),
  motivo_suspension text,
  eliminar_desde timestamptz,
  nota_admin text,
  ultimo_uso timestamptz default now(),
  creado timestamptz not null default now()
);

create table if not exists public.miembros (
  negocio uuid not null references public.negocios (id) on delete cascade,
  usuario uuid not null unique references auth.users (id) on delete cascade,
  rol text not null check (rol in ('dueno','ayudante')),
  nombre text not null default '',
  activo boolean not null default true,
  creado timestamptz not null default now(),
  primary key (negocio, usuario)
);

create table if not exists public.invitaciones (
  codigo text primary key,
  negocio uuid not null references public.negocios (id) on delete cascade,
  vence timestamptz not null,
  usada_por uuid,
  creado timestamptz not null default now()
);

create table if not exists public.clientes (
  id uuid primary key default gen_random_uuid(),
  negocio uuid not null references public.negocios (id) on delete cascade,
  nombre text not null check (char_length(nombre) between 2 and 60),
  nombre_norm text not null,
  apodo text check (apodo is null or char_length(apodo) <= 30),
  telefono text,
  rut text,
  nota text check (nota is null or char_length(nota) <= 200),
  limite int check (limite is null or limite between 0 and 5000000),
  estado text not null default 'activo' check (estado in ('activo','archivado','borrado')),
  bloqueado boolean not null default false,
  fuera_de_plan boolean not null default false,
  saldo bigint not null default 0,
  prox_venc date,
  atrasado boolean not null default false,
  puntaje text not null default 'nuevo' check (puntaje in ('nuevo','bueno','regular','riesgoso')),
  ultimo_mov timestamptz,
  link_codigo text not null unique,
  pin_hash text,
  pin_intentos int not null default 0,
  pin_bloqueo_hasta timestamptz,
  pin_fallos_dia int not null default 0,
  pin_dia date,
  link_bloqueado boolean not null default false,
  creado_por uuid,
  creado timestamptz not null default now()
);
create index if not exists clientes_negocio on public.clientes (negocio, estado);

create table if not exists public.ventas_cuotas (
  id uuid primary key,
  negocio uuid not null references public.negocios (id) on delete cascade,
  cliente uuid not null references public.clientes (id) on delete cascade,
  descripcion text not null check (char_length(descripcion) between 2 and 80),
  total int not null check (total between 1000 and 9999999),
  pie int not null default 0 check (pie >= 0),
  n int not null check (n between 2 and 24),
  frecuencia text not null check (frecuencia in ('semanal','quincenal','mensual')),
  primera date not null,
  estado text not null default 'activa' check (estado in ('activa','pagada','anulada')),
  creado_por uuid,
  creado timestamptz not null default now()
);
create index if not exists ventas_cliente on public.ventas_cuotas (cliente);

create table if not exists public.cuotas (
  venta uuid not null references public.ventas_cuotas (id) on delete cascade,
  numero int not null,
  monto int not null check (monto > 0),
  vence date not null,
  pagado int not null default 0,
  primary key (venta, numero)
);

create table if not exists public.movimientos (
  id uuid primary key,
  negocio uuid not null references public.negocios (id) on delete cascade,
  cliente uuid not null references public.clientes (id) on delete cascade,
  tipo text not null check (tipo in ('cargo','abono','ajuste')),
  signo smallint not null check (signo in (1, -1)),
  monto int not null check (monto between 1 and 9999999),
  descripcion text check (descripcion is null or char_length(descripcion) <= 120),
  medio text check (medio is null or medio in ('efectivo','transferencia','otro')),
  fecha timestamptz not null default now(),
  vence date,
  venta uuid references public.ventas_cuotas (id) on delete cascade,
  comprobante uuid,
  cuenta_plan boolean not null default true,
  confirmacion text check (confirmacion is null or confirmacion in ('pendiente','reconocido','reclamado')),
  reclamo_motivo text,
  respuesta text,
  creado_por uuid,
  creado_at timestamptz not null default now(),
  anulado_at timestamptz,
  anulado_por uuid,
  motivo_anulacion text,
  check ((tipo = 'cargo' and signo = 1) or (tipo = 'abono' and signo = -1) or tipo = 'ajuste')
);
create index if not exists mov_cliente on public.movimientos (cliente, fecha desc);
create index if not exists mov_negocio on public.movimientos (negocio, fecha desc);

create table if not exists public.comprobantes (
  id uuid primary key default gen_random_uuid(),
  negocio uuid not null references public.negocios (id) on delete cascade,
  cliente uuid not null references public.clientes (id) on delete cascade,
  monto int not null check (monto between 1 and 9999999),
  fecha date not null,
  comentario text check (comentario is null or char_length(comentario) <= 100),
  foto_path text,
  estado text not null default 'pendiente' check (estado in ('pendiente','aprobado','rechazado')),
  motivo text,
  abono uuid,
  revisado_por uuid,
  revisado_at timestamptz,
  creado timestamptz not null default now()
);
create index if not exists comp_negocio on public.comprobantes (negocio, estado);

create table if not exists public.recordatorios (
  id bigserial primary key,
  negocio uuid not null references public.negocios (id) on delete cascade,
  cliente uuid not null references public.clientes (id) on delete cascade,
  canal text not null check (canal in ('whatsapp','push')),
  tono text not null,
  enviado_por uuid,
  at timestamptz not null default now()
);
create index if not exists rec_cliente on public.recordatorios (cliente, at desc);

create table if not exists public.productos (
  id uuid primary key default gen_random_uuid(),
  negocio uuid not null references public.negocios (id) on delete cascade,
  nombre text not null check (char_length(nombre) between 2 and 30),
  precio int not null check (precio between 1 and 9999999),
  orden int not null default 0
);

create table if not exists public.uso_mensual (
  negocio uuid not null references public.negocios (id) on delete cascade,
  mes date not null,
  movimientos int not null default 0,
  comprobantes int not null default 0,
  primary key (negocio, mes)
);

create table if not exists public.notificaciones (
  id bigserial primary key,
  usuario uuid references auth.users (id) on delete cascade,
  negocio uuid references public.negocios (id) on delete cascade,
  titulo text not null,
  cuerpo text not null default '',
  url text,
  leido boolean not null default false,
  creado timestamptz not null default now()
);
create index if not exists notif_neg on public.notificaciones (negocio, creado desc);
create index if not exists notif_usr on public.notificaciones (usuario, creado desc);

create table if not exists public.sesiones_cliente (
  id uuid primary key default gen_random_uuid(),
  token_hash text not null unique,
  cliente uuid not null references public.clientes (id) on delete cascade,
  vence timestamptz not null,
  visto timestamptz default now(),
  creado timestamptz not null default now()
);

create table if not exists public.push_subs (
  endpoint text primary key,
  p256dh text not null,
  auth text not null,
  usuario uuid references auth.users (id) on delete cascade,
  sesion uuid references public.sesiones_cliente (id) on delete cascade,
  cliente uuid references public.clientes (id) on delete cascade,
  creado timestamptz not null default now()
);

create table if not exists public.cola_push (
  id bigserial primary key,
  usuario uuid,
  negocio uuid,
  cliente uuid,
  titulo text not null,
  cuerpo text not null default '',
  url text,
  tag text,
  creado timestamptz not null default now(),
  tomado_at timestamptz
);

create table if not exists public.solicitudes_pago (
  id uuid primary key default gen_random_uuid(),
  negocio uuid not null references public.negocios (id) on delete cascade,
  meses int not null default 1 check (meses in (1, 12)),
  monto int not null default 0,
  comprobante_path text,
  nota text check (nota is null or char_length(nota) <= 200),
  estado text not null default 'pendiente' check (estado in ('pendiente','aprobada','rechazada')),
  motivo text,
  creado timestamptz not null default now(),
  revisado_at timestamptz
);

create table if not exists public.keys (
  codigo text primary key,
  meses int not null check (meses in (1, 3, 6, 12)),
  precio int not null default 0,
  creado timestamptz not null default now(),
  usada_por uuid references public.negocios (id) on delete set null,
  usada_at timestamptz,
  revocada boolean not null default false
);

create table if not exists public.feriados (fecha date primary key, nombre text not null);
insert into public.feriados values
  ('2026-01-01','Año Nuevo'),('2026-04-03','Viernes Santo'),('2026-04-04','Sábado Santo'),('2026-05-01','Día del Trabajo'),
  ('2026-05-21','Glorias Navales'),('2026-06-21','Pueblos Indígenas'),('2026-06-29','San Pedro y San Pablo'),
  ('2026-07-16','Virgen del Carmen'),('2026-08-15','Asunción de la Virgen'),('2026-09-18','Independencia'),
  ('2026-09-19','Glorias del Ejército'),('2026-10-12','Encuentro de Dos Mundos'),('2026-10-31','Iglesias Evangélicas'),
  ('2026-11-01','Todos los Santos'),('2026-12-08','Inmaculada Concepción'),('2026-12-25','Navidad'),
  ('2027-01-01','Año Nuevo'),('2027-03-26','Viernes Santo'),('2027-03-27','Sábado Santo'),('2027-05-01','Día del Trabajo'),
  ('2027-05-21','Glorias Navales'),('2027-06-21','Pueblos Indígenas'),('2027-06-28','San Pedro y San Pablo'),
  ('2027-07-16','Virgen del Carmen'),('2027-08-15','Asunción de la Virgen'),('2027-09-18','Independencia'),
  ('2027-09-19','Glorias del Ejército'),('2027-10-11','Encuentro de Dos Mundos'),('2027-10-31','Iglesias Evangélicas'),
  ('2027-11-01','Todos los Santos'),('2027-12-08','Inmaculada Concepción'),('2027-12-25','Navidad')
on conflict do nothing;

create table if not exists public.auditoria (
  id bigserial primary key,
  negocio uuid references public.negocios (id) on delete cascade,
  usuario uuid,
  accion text not null,
  detalle jsonb,
  at timestamptz not null default now()
);
create index if not exists audit_neg on public.auditoria (negocio, at desc);

-- =====================================================================
--  AYUDANTES INTERNOS (esquema privado: no se pueden llamar desde la app)
-- =====================================================================
create or replace function privado.hoy() returns date language sql stable as
  $$ select (now() at time zone 'America/Santiago')::date $$;

create or replace function privado.norm(t text) returns text language sql immutable as $$
  select lower(translate(btrim(regexp_replace(coalesce(t, ''), '\s+', ' ', 'g')), 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun'))
$$;

create or replace function privado.limpio(t text, maximo int) returns text language sql immutable as $$
  select nullif(left(btrim(regexp_replace(coalesce(t, ''), '\s+', ' ', 'g')), maximo), '')
$$;

create or replace function privado.fallo(msg text, pista text default null) returns void language plpgsql as $$
begin
  raise exception using message = msg, hint = coalesce(pista, '');
end $$;

create or replace function privado.pesos(n bigint) returns text language sql immutable as $$
  select '$' || replace(to_char(abs(n), 'FM999G999G999G999'), ',', '.')
$$;

create or replace function privado.telefono(p text) returns text language plpgsql immutable as $$
declare d text := regexp_replace(coalesce(p, ''), '\D', '', 'g');
begin
  if btrim(coalesce(p, '')) = '' then return null; end if;
  if length(d) = 11 and d like '569%' then return '+' || d; end if;
  if length(d) = 9 and d like '9%' then return '+56' || d; end if;
  if length(d) = 8 and left(btrim(p), 1) <> '+' then return '+569' || d; end if;
  if left(btrim(p), 1) = '+' and length(d) between 8 and 15 and d not like '56%' then return '+' || d; end if;
  perform privado.fallo('Teléfono inválido. Usa el formato +56 9 1234 5678');
end $$;

create or replace function privado.rut(p text) returns text language plpgsql immutable as $$
declare c text := upper(regexp_replace(coalesce(p, ''), '[^0-9kK]', '', 'g'));
  cuerpo text; dv text; s int := 0; f int := 2; i int; r int; esperado text;
begin
  if btrim(coalesce(p, '')) = '' then return null; end if;
  if length(c) < 8 or length(c) > 9 then perform privado.fallo('RUT inválido'); end if;
  cuerpo := left(c, -1); dv := right(c, 1);
  if cuerpo !~ '^\d+$' then perform privado.fallo('RUT inválido'); end if;
  for i in reverse length(cuerpo)..1 loop
    s := s + substr(cuerpo, i, 1)::int * f;
    f := case when f = 7 then 2 else f + 1 end;
  end loop;
  r := 11 - (s % 11);
  esperado := case r when 11 then '0' when 10 then 'K' else r::text end;
  if dv <> esperado then perform privado.fallo('RUT inválido: el dígito verificador no corresponde'); end if;
  return cuerpo || '-' || dv;
end $$;

create or replace function privado.codigo(n int) returns text language plpgsql volatile as $$
declare abc text := 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'; b bytea := extensions.gen_random_bytes(n); s text := ''; i int;
begin
  for i in 0..n - 1 loop s := s || substr(abc, (get_byte(b, i) % length(abc)) + 1, 1); end loop;
  return s;
end $$;

create or replace function privado.sha(t text) returns text language sql immutable as
  $$ select encode(extensions.digest(t, 'sha256'), 'hex') $$;

-- El administrador queda fijado por su id con privado.fijar_admin() (solo desde el SQL Editor de Supabase).
-- Así nadie puede volverse admin registrándose con el mismo correo.
create or replace function privado.es_admin() returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select auth.uid() is not null and auth.uid()::text = (select valor from privado.config where clave = 'admin_id')
$$;

create or replace function privado.fijar_admin() returns text language plpgsql security definer set search_path = public, pg_temp as $$
declare v uuid;
begin
  select id into v from auth.users where lower(email) = (select valor from privado.config where clave = 'admin_email') and email_confirmed_at is not null
   order by created_at limit 1;
  if v is null then return 'ERROR: primero crea el usuario ' || (select valor from privado.config where clave = 'admin_email') || ' en Authentication → Users (con Auto Confirm User).'; end if;
  insert into privado.config values ('admin_id', v::text) on conflict (clave) do update set valor = excluded.valor;
  return 'Administrador fijado ✓ (' || v || ')';
end $$;

create or replace function privado.es_premium(p_neg uuid) returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select n.premium_hasta + make_interval(days => case when n.en_prueba then 0 else a.dias_gracia end) > now()
    from public.negocios n, public.ajustes a where n.id = p_neg and a.id = 1), false)
$$;

-- Negocio de la sesión (para las reglas de lectura). El ayudante solo entra si el negocio es Premium.
create or replace function privado.mi_negocio() returns uuid language sql stable security definer set search_path = public, pg_temp as $$
  select m.negocio from public.miembros m join public.negocios n on n.id = m.negocio
  where m.usuario = auth.uid() and m.activo and n.estado <> 'eliminado'
    and (m.rol = 'dueno' or privado.es_premium(n.id))
  limit 1
$$;

create or replace function privado.mi_rol() returns text language sql stable security definer set search_path = public, pg_temp as $$
  select m.rol from public.miembros m where m.usuario = auth.uid() and m.negocio = privado.mi_negocio()
$$;

create or replace function privado.mi_premium() returns boolean language sql stable security definer set search_path = public, pg_temp as
  $$ select privado.es_premium(privado.mi_negocio()) $$;

-- Exige sesión y libreta activa. Devuelve el id del negocio.
create or replace function privado.exigir(p_dueno boolean default false) returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare v uuid; n record;
begin
  if auth.uid() is null then perform privado.fallo('Tu sesión terminó. Ingresa de nuevo.', 'SESION'); end if;
  v := privado.mi_negocio();
  if v is null then perform privado.fallo('No tienes una libreta activa.', 'SIN_NEGOCIO'); end if;
  select * into n from public.negocios where id = v;
  if n.estado = 'suspendido' then
    perform privado.fallo('Tu cuenta está suspendida' || coalesce(': ' || n.motivo_suspension, '') || '. Puedes exportar tus datos desde Más → Ajustes.', 'SUSPENDIDO');
  end if;
  if p_dueno and privado.mi_rol() <> 'dueno' then perform privado.fallo('Solo el dueño puede hacer esto.'); end if;
  if n.ultimo_uso is null or n.ultimo_uso < now() - interval '1 hour' then
    update public.negocios set ultimo_uso = now() where id = v;
  end if;
  return v;
end $$;

create or replace function privado.limite(p_neg uuid, p_clave text) returns int language sql stable security definer set search_path = public, pg_temp as $$
  select case when privado.es_premium(p_neg) then (a.lim_premium ->> p_clave)::int else (a.lim_normal ->> p_clave)::int end
  from public.ajustes a where a.id = 1
$$;

create or replace function privado.uso(p_neg uuid) returns public.uso_mensual language plpgsql security definer set search_path = public, pg_temp as $$
declare u public.uso_mensual; m date := date_trunc('month', privado.hoy())::date;
begin
  insert into public.uso_mensual (negocio, mes) values (p_neg, m) on conflict do nothing;
  select * into u from public.uso_mensual where negocio = p_neg and mes = m;
  return u;
end $$;

create or replace function privado.limitar(p_clave text, p_max int, p_segundos int) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare w bigint := floor(extract(epoch from now()) / p_segundos); c int;
begin
  insert into privado.limites (clave, ventana, n) values (p_clave, w, 1)
  on conflict (clave, ventana) do update set n = privado.limites.n + 1 returning n into c;
  if c > p_max then perform privado.fallo('Vas muy rápido. Espera un momento y vuelve a intentar.', 'RAPIDO'); end if;
end $$;

create or replace function privado.auditar(p_neg uuid, p_accion text, p_detalle jsonb) returns void language sql security definer set search_path = public, pg_temp as $$
  insert into public.auditoria (negocio, usuario, accion, detalle) values (p_neg, auth.uid(), p_accion, p_detalle)
$$;

create or replace function privado.push(p_usuario uuid, p_negocio uuid, p_cliente uuid, p_titulo text, p_cuerpo text, p_url text, p_tag text default null)
returns void language sql security definer set search_path = public, pg_temp as $$
  insert into public.cola_push (usuario, negocio, cliente, titulo, cuerpo, url, tag)
  values (p_usuario, p_negocio, p_cliente, left(p_titulo, 80), left(coalesce(p_cuerpo, ''), 200), p_url, p_tag)
$$;

-- Aviso al negocio: bandeja para todos y push (si p_push).
create or replace function privado.avisar_negocio(p_neg uuid, p_titulo text, p_cuerpo text, p_url text, p_push boolean default true)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into public.notificaciones (negocio, titulo, cuerpo, url) values (p_neg, p_titulo, coalesce(p_cuerpo, ''), p_url);
  if p_push then perform privado.push(null, p_neg, null, p_titulo, p_cuerpo, coalesce(p_url, 'app/')); end if;
end $$;

create or replace function privado.avisar_usuario(p_usr uuid, p_titulo text, p_cuerpo text, p_url text, p_push boolean default true)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if p_usr is null then return; end if;
  insert into public.notificaciones (usuario, titulo, cuerpo, url) values (p_usr, p_titulo, coalesce(p_cuerpo, ''), p_url);
  if p_push then perform privado.push(p_usr, null, null, p_titulo, p_cuerpo, coalesce(p_url, 'app/')); end if;
end $$;

-- ---------- Recalcular saldo, cuotas y vencimientos de un cliente ----------
-- Los abonos se aplican a la deuda más antigua (por fecha de vencimiento).
create or replace function privado.recalcular(p_cliente uuid) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare credito bigint; total_credito bigint; deuda bigint := 0; r record; pag bigint; prox date := null; v_hoy date := privado.hoy();
  v_atr boolean; v_rec int; v_recl int; v_movs int; v_punt text; v_dias int;
begin
  select coalesce(sum(monto), 0) into total_credito from public.movimientos
   where cliente = p_cliente and anulado_at is null and signo = -1;
  credito := total_credito;
  for r in
    select 'm'::text k, m.id, 0 num, m.monto::bigint monto, coalesce(m.vence, (m.fecha at time zone 'America/Santiago')::date) due, m.fecha ord
      from public.movimientos m
     where m.cliente = p_cliente and m.anulado_at is null and m.signo = 1 and m.venta is null
    union all
    select 'c', c.venta, c.numero, c.monto, c.vence, v.creado
      from public.cuotas c join public.ventas_cuotas v on v.id = c.venta
     where v.cliente = p_cliente and v.estado <> 'anulada'
    order by due, ord, num
  loop
    deuda := deuda + r.monto;
    pag := least(r.monto, credito);
    credito := credito - pag;
    if r.k = 'c' then
      update public.cuotas set pagado = pag where venta = r.id and numero = r.num and pagado <> pag;
    end if;
    if pag < r.monto and prox is null then prox := r.due; end if;
  end loop;
  update public.ventas_cuotas v set estado = case
      when not exists (select 1 from public.cuotas c where c.venta = v.id and c.pagado < c.monto) then 'pagada' else 'activa' end
   where v.cliente = p_cliente and v.estado <> 'anulada';
  v_atr := prox is not null and prox < v_hoy;
  v_dias := case when v_atr then v_hoy - prox else 0 end;
  select count(*) into v_rec from public.recordatorios where cliente = p_cliente and at > now() - interval '90 days';
  select count(*) filter (where confirmacion = 'reclamado'), count(*) into v_recl, v_movs
    from public.movimientos where cliente = p_cliente and anulado_at is null;
  v_punt := case
    when v_movs < 4 then 'nuevo'
    when v_dias > 30 or v_recl >= 2 or (v_atr and v_rec >= 4) then 'riesgoso'
    when v_atr or v_rec >= 3 then 'regular'
    else 'bueno' end;
  update public.clientes set saldo = deuda - total_credito, prox_venc = prox, atrasado = v_atr, puntaje = v_punt,
    ultimo_mov = (select max(creado_at) from public.movimientos where cliente = p_cliente)
   where id = p_cliente;
end $$;

-- ---------- Planes: aplica la subida o bajada de plan ----------
create or replace function privado.aplicar_plan(p_neg uuid) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare n record; prem boolean := privado.es_premium(p_neg); lim int;
begin
  select * into n from public.negocios where id = p_neg for update;
  if not found then return; end if;
  if prem and n.plan_aplicado = 'normal' then
    update public.clientes set fuera_de_plan = false where negocio = p_neg and fuera_de_plan;
    update public.negocios set plan_aplicado = 'premium' where id = p_neg;
  elsif not prem and n.plan_aplicado = 'premium' then
    lim := (select (lim_normal ->> 'clientes')::int from public.ajustes where id = 1);
    update public.clientes c set fuera_de_plan = true
     where c.id in (select id from public.clientes where negocio = p_neg and estado = 'activo' and not fuera_de_plan
                     order by ultimo_mov desc nulls last, creado desc offset lim);
    update public.negocios set plan_aplicado = 'normal', en_prueba = false where id = p_neg;
    perform privado.avisar_negocio(p_neg, 'Tu Premium terminó',
      'Tu libreta pasó al plan Normal. No se borró nada y puedes seguir cobrando. Hazte Premium para volver a tener todo.', 'app/#plan');
  end if;
end $$;

-- ---------- ¿Se puede cobrar a este cliente ahora? (Ley 19.496, art. 37) ----------
create or replace function privado.cobro_permitido(p_cliente uuid, out ok boolean, out motivo text, out proxima timestamptz)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare ahora timestamp := now() at time zone 'America/Santiago'; cand timestamp := ahora; cnt int; primero timestamp; ultimo timestamp; i int;
begin
  select count(*), min(at at time zone 'America/Santiago'), max(at at time zone 'America/Santiago') into cnt, primero, ultimo
    from public.recordatorios where cliente = p_cliente and at > now() - interval '7 days';
  motivo := null;
  if cnt >= 2 then cand := greatest(cand, primero + interval '7 days'); motivo := 'Ya enviaste 2 recordatorios esta semana (máximo legal).'; end if;
  if ultimo is not null and ahora::date - ultimo::date < 2 then
    cand := greatest(cand, (ultimo::date + 2)::timestamp + interval '8 hours');
    motivo := coalesce(motivo, 'Debe haber al menos 2 días entre recordatorios.');
  end if;
  for i in 1..30 loop
    if cand::time < time '08:00' then cand := cand::date + interval '8 hours'; end if;
    if cand::time >= time '20:00' then cand := (cand::date + 1) + interval '8 hours'; continue; end if;
    if extract(isodow from cand) = 7 or exists (select 1 from public.feriados where fecha = cand::date) then
      cand := (cand::date + 1) + interval '8 hours'; continue;
    end if;
    exit;
  end loop;
  ok := cand <= ahora;
  if not ok and motivo is null then motivo := 'Solo se puede cobrar de lunes a sábado, de 08:00 a 20:00, sin feriados.'; end if;
  proxima := cand at time zone 'America/Santiago';
end $$;

-- ---------- Inserción de movimientos (núcleo, valida todo) ----------
create or replace function privado.mov_insertar(
  p_neg uuid, p_id uuid, p_cliente uuid, p_tipo text, p_monto int, p_signo int, p_desc text, p_medio text,
  p_fecha timestamptz, p_vence date, p_venta uuid, p_forzar_limite boolean, p_confirmar_dup boolean, p_comprobante uuid default null
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare c record; n record; v_rol text := coalesce(privado.mi_rol(), 'dueno'); prem boolean := privado.es_premium(p_neg);
  v_fecha timestamptz := coalesce(p_fecha, now()); v_vence date; v_lim int; u public.uso_mensual; v_cuenta boolean := true;
  v_signo int; v_desc text := privado.limpio(p_desc, 120); ex record;
begin
  if p_id is null then perform privado.fallo('Falta el identificador del movimiento'); end if;
  select * into ex from public.movimientos where id = p_id;
  if found then
    if ex.negocio <> p_neg then perform privado.fallo('Movimiento inválido'); end if;
    return jsonb_build_object('ok', true, 'repetido', true, 'saldo', (select saldo from public.clientes where id = ex.cliente));
  end if;
  if p_tipo not in ('cargo','abono','ajuste') then perform privado.fallo('Tipo de movimiento inválido'); end if;
  if p_monto is null or p_monto < 1 or p_monto > 9999999 then perform privado.fallo('El monto debe ser entre $1 y $9.999.999'); end if;
  v_signo := case p_tipo when 'cargo' then 1 when 'abono' then -1 else p_signo end;
  if v_signo is null or v_signo not in (1, -1) then perform privado.fallo('Indica si el ajuste suma o resta'); end if;
  if p_tipo = 'ajuste' then
    if v_rol <> 'dueno' then perform privado.fallo('Solo el dueño puede hacer ajustes'); end if;
    if v_desc is null or char_length(v_desc) < 5 then perform privado.fallo('Escribe el motivo del ajuste (mínimo 5 letras)'); end if;
  end if;
  if p_medio is not null and p_medio not in ('efectivo','transferencia','otro') then perform privado.fallo('Medio de pago inválido'); end if;

  select * into c from public.clientes where id = p_cliente and negocio = p_neg for update;
  if not found or c.estado = 'borrado' then perform privado.fallo('Cliente no encontrado'); end if;
  select * into n from public.negocios where id = p_neg;

  if v_fecha > now() + interval '5 minutes' then perform privado.fallo('La fecha no puede ser futura'); end if;
  if v_rol = 'dueno' and v_fecha < now() - interval '1 year' then perform privado.fallo('La fecha puede ser hasta 1 año atrás'); end if;
  if v_rol = 'ayudante' and v_fecha < now() - interval '3 days' then perform privado.fallo('Como ayudante puedes anotar hasta 3 días atrás'); end if;

  if v_signo = 1 then
    if c.estado <> 'activo' then perform privado.fallo('Este cliente está archivado. Reactívalo para anotarle deuda.'); end if;
    if c.bloqueado then perform privado.fallo('Este cliente está en "solo cobro": no se le puede anotar más deuda.'); end if;
    if c.fuera_de_plan then perform privado.fallo('Este cliente quedó fuera del plan Normal (solo cobro). Hazte Premium o archiva clientes saldados.', 'PLAN'); end if;
    v_vence := coalesce(p_vence, case n.venc_defecto
      when 'fin' then (date_trunc('month', (v_fecha at time zone 'America/Santiago')::date) + interval '1 month - 1 day')::date
      else (v_fecha at time zone 'America/Santiago')::date + n.venc_defecto::int end);
    if v_vence < (v_fecha at time zone 'America/Santiago')::date then perform privado.fallo('El vencimiento no puede ser antes de la fecha'); end if;
    if v_vence > (v_fecha at time zone 'America/Santiago')::date + 730 then perform privado.fallo('El vencimiento es demasiado lejano'); end if;
    v_lim := coalesce(case when prem then c.limite end, nullif(n.limite_general, 0));
    if v_lim is not null and v_lim > 0 and c.saldo + p_monto > v_lim then
      if v_rol = 'ayudante' then perform privado.fallo('Supera el límite de fiado de este cliente (' || privado.pesos(v_lim) || '). Solo el dueño puede autorizarlo.'); end if;
      if not coalesce(p_forzar_limite, false) then
        return jsonb_build_object('ok', false, 'limite', v_lim, 'saldo', c.saldo);
      end if;
    end if;
  else
    if not n.saldo_a_favor and p_monto > c.saldo then
      perform privado.fallo(case when c.saldo <= 0 then 'Este cliente no tiene deuda.' else 'El cliente debe ' || privado.pesos(c.saldo) || '. El abono no puede ser mayor.' end);
    end if;
  end if;

  if not coalesce(p_confirmar_dup, false) and exists (select 1 from public.movimientos
      where cliente = p_cliente and tipo = p_tipo and monto = p_monto and anulado_at is null and creado_at > now() - interval '60 seconds') then
    return jsonb_build_object('ok', false, 'duplicado', true);
  end if;

  if p_tipo = 'ajuste' then
    v_cuenta := false;
  elsif not prem then
    u := privado.uso(p_neg);
    if u.movimientos >= privado.limite(p_neg, 'movimientos') then
      if v_signo = 1 then
        perform privado.fallo('Llegaste a los ' || privado.limite(p_neg, 'movimientos') || ' movimientos de este mes del plan Normal. Los abonos siguen funcionando. Hazte Premium para anotar sin límite.', 'PLAN');
      end if;
      v_cuenta := false;
    end if;
  end if;
  perform privado.limitar('mov:' || p_neg, 300, 3600);

  insert into public.movimientos (id, negocio, cliente, tipo, signo, monto, descripcion, medio, fecha, vence, venta, comprobante,
    cuenta_plan, confirmacion, creado_por)
  values (p_id, p_neg, p_cliente, p_tipo, v_signo, p_monto, v_desc, case when v_signo = -1 then coalesce(p_medio, 'efectivo') end,
    v_fecha, case when v_signo = 1 then v_vence end, p_venta, p_comprobante, v_cuenta,
    case when p_tipo = 'cargo' then 'pendiente' end, auth.uid());
  if v_cuenta then
    perform privado.uso(p_neg);
    update public.uso_mensual set movimientos = movimientos + 1 where negocio = p_neg and mes = date_trunc('month', privado.hoy())::date;
  end if;
  perform privado.recalcular(p_cliente);
  if p_tipo = 'ajuste' then perform privado.auditar(p_neg, 'ajuste', jsonb_build_object('mov', p_id, 'cliente', p_cliente, 'monto', p_monto * v_signo, 'motivo', v_desc)); end if;
  if p_tipo = 'cargo' and p_venta is null then
    perform privado.push(null, null, p_cliente, n.nombre || ': nuevo cargo', 'Se anotó ' || privado.pesos(p_monto) || coalesce(' · ' || v_desc, '') || '. Toca para revisarlo.', 'c/');
  elsif v_signo = -1 and p_comprobante is null then
    perform privado.push(null, null, p_cliente, n.nombre || ': pago recibido', 'Se registró tu pago de ' || privado.pesos(p_monto) || '. ¡Gracias!', 'c/');
  end if;
  return jsonb_build_object('ok', true, 'saldo', (select saldo from public.clientes where id = p_cliente));
end $$;

-- =====================================================================
--  FUNCIONES DE LA APP (negocio)
-- =====================================================================
create or replace function public.ping() returns text language sql stable as $$ select 'ok' $$;

create or replace function public.config_publica() returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object('precio_mensual', a.precio_mensual, 'precio_anual', a.precio_anual, 'link_pago', a.link_pago,
    'transferencia', a.transferencia, 'contacto_whatsapp', a.contacto_whatsapp, 'dias_prueba', a.dias_prueba,
    'lim_normal', a.lim_normal, 'lim_premium', a.lim_premium, 'version_legal', a.version_legal, 'version_min', a.version_min,
    'vapid_public', (select valor from privado.secretos where nombre = 'vapid_public'))
  from public.ajustes a where a.id = 1
$$;

create or replace function public.mi_estado() returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid; n record; m record; u public.uso_mensual; prem boolean; a record; per record; v_elim record;
begin
  if auth.uid() is null then perform privado.fallo('Tu sesión terminó. Ingresa de nuevo.', 'SESION'); end if;
  select * into a from public.ajustes where id = 1;
  select * into per from public.perfiles where id = auth.uid();
  if not found then
    insert into public.perfiles (id) values (auth.uid()) on conflict do nothing;
    select * into per from public.perfiles where id = auth.uid();
  end if;
  v_neg := privado.mi_negocio();
  if v_neg is null then
    select n2.id, n2.eliminar_desde into v_elim from public.negocios n2 where n2.dueno = auth.uid() and n2.estado = 'eliminado';
    return jsonb_build_object('usuario', auth.uid(), 'es_admin', privado.es_admin(), 'negocio', null,
      'ayudante_pausado', exists (select 1 from public.miembros where usuario = auth.uid() and rol = 'ayudante'),
      'eliminado', v_elim.id is not null, 'eliminar_desde', v_elim.eliminar_desde,
      'terminos_ok', per.terminos_version >= a.version_legal, 'config', public.config_publica());
  end if;
  perform privado.aplicar_plan(v_neg);
  select * into n from public.negocios where id = v_neg;
  select * into m from public.miembros where negocio = v_neg and usuario = auth.uid();
  prem := privado.es_premium(v_neg);
  u := privado.uso(v_neg);
  return jsonb_build_object(
    'usuario', auth.uid(), 'es_admin', privado.es_admin(), 'rol', m.rol, 'mi_nombre', m.nombre,
    'terminos_ok', per.terminos_version >= a.version_legal,
    'negocio', jsonb_build_object('id', n.id, 'nombre', n.nombre, 'rubro', n.rubro, 'whatsapp', n.whatsapp, 'banco', n.banco,
      'venc_defecto', n.venc_defecto, 'limite_general', n.limite_general, 'pin_activo', n.pin_activo, 'saldo_a_favor', n.saldo_a_favor,
      'logo_url', n.logo_url, 'color', n.color, 'plantilla_propia', n.plantilla_propia, 'estado', n.estado,
      'motivo_suspension', n.motivo_suspension, 'creado', n.creado),
    'plan', jsonb_build_object('premium', prem, 'hasta', n.premium_hasta, 'en_prueba', n.en_prueba and prem,
      'en_gracia', prem and not n.en_prueba and n.premium_hasta < now(), 'dias_gracia', a.dias_gracia,
      'pago_pendiente', exists (select 1 from public.solicitudes_pago where negocio = v_neg and estado = 'pendiente')),
    'limites', case when prem then a.lim_premium else a.lim_normal end,
    'uso', jsonb_build_object('movimientos', u.movimientos, 'comprobantes', u.comprobantes,
      'clientes', (select count(*) from public.clientes where negocio = v_neg and estado = 'activo' and not fuera_de_plan),
      'fuera_de_plan', (select count(*) from public.clientes where negocio = v_neg and estado = 'activo' and fuera_de_plan),
      'cuotas', (select count(*) from public.ventas_cuotas where negocio = v_neg and estado = 'activa'),
      'productos', (select count(*) from public.productos where negocio = v_neg),
      'ayudantes', (select count(*) from public.miembros where negocio = v_neg and rol = 'ayudante')),
    'pendientes', jsonb_build_object(
      'comprobantes', (select count(*) from public.comprobantes where negocio = v_neg and estado = 'pendiente'),
      'reclamos', (select count(*) from public.movimientos where negocio = v_neg and confirmacion = 'reclamado' and respuesta is null and anulado_at is null),
      'avisos', (select count(*) from public.notificaciones where (negocio = v_neg or usuario = auth.uid()) and not leido)),
    'config', public.config_publica());
end $$;

create or replace function public.aceptar_terminos() returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then perform privado.fallo('Ingresa de nuevo.'); end if;
  insert into public.perfiles (id, terminos_version, terminos_at) values (auth.uid(), (select version_legal from public.ajustes where id = 1), now())
  on conflict (id) do update set terminos_version = excluded.terminos_version, terminos_at = now();
end $$;

create or replace function public.crear_negocio(p_nombre text, p_rubro text, p_acepta boolean) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_id uuid; v_email text; v_hash text; v_dias int; v_nombre text := privado.limpio(p_nombre, 50); v_prueba boolean := false;
begin
  if auth.uid() is null then perform privado.fallo('Ingresa de nuevo.'); end if;
  if not coalesce(p_acepta, false) then perform privado.fallo('Debes aceptar los Términos y la Privacidad'); end if;
  if exists (select 1 from public.miembros where usuario = auth.uid()) or exists (select 1 from public.negocios where dueno = auth.uid()) then
    perform privado.fallo('Tu cuenta ya tiene una libreta');
  end if;
  if v_nombre is null or char_length(v_nombre) < 2 then perform privado.fallo('El nombre del negocio debe tener entre 2 y 50 letras'); end if;
  if coalesce(p_rubro, 'otro') not in ('almacen','feria','catalogo','emprendimiento','servicios','educacion','club','personal','otro') then
    perform privado.fallo('Rubro inválido');
  end if;
  perform privado.limitar('crear_neg', 200, 3600);
  select lower(email) into v_email from auth.users where id = auth.uid();
  v_hash := privado.sha(coalesce(v_email, auth.uid()::text));
  select dias_prueba into v_dias from public.ajustes where id = 1;
  if v_dias > 0 and not exists (select 1 from privado.pruebas_usadas where email_hash = v_hash) then
    insert into privado.pruebas_usadas (email_hash) values (v_hash);
    v_prueba := true;
  end if;
  insert into public.negocios (dueno, nombre, rubro, premium_hasta, en_prueba, plan_aplicado)
  values (auth.uid(), v_nombre, coalesce(p_rubro, 'otro'), case when v_prueba then now() + make_interval(days => v_dias) end, v_prueba,
    case when v_prueba then 'premium' else 'normal' end)
  returning id into v_id;
  insert into public.miembros (negocio, usuario, rol, nombre) values (v_id, auth.uid(), 'dueno', v_nombre);
  perform public.aceptar_terminos();
  perform privado.avisar_usuario((select nullif(valor, '')::uuid from privado.config where clave = 'admin_id'),
    'Nueva libreta: ' || v_nombre, 'Rubro: ' || coalesce(p_rubro, 'otro') || coalesce(' · ' || v_email, ''), 'admin/', true);
  return jsonb_build_object('ok', true, 'id', v_id, 'prueba', v_prueba, 'dias', case when v_prueba then v_dias else 0 end);
end $$;

create or replace function public.guardar_negocio(p jsonb) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true); prem boolean := privado.es_premium(v_neg); b jsonb := coalesce(p -> 'banco', '{}'::jsonb);
  v_nombre text := privado.limpio(p ->> 'nombre', 50); v_banco jsonb; v_lim int; v_logo text := nullif(p ->> 'logo_url', '');
  v_plant text := privado.limpio(p ->> 'plantilla_propia', 500); v_bad text;
begin
  if v_nombre is null or char_length(v_nombre) < 2 then perform privado.fallo('El nombre del negocio debe tener entre 2 y 50 letras'); end if;
  if coalesce(p ->> 'rubro', 'otro') not in ('almacen','feria','catalogo','emprendimiento','servicios','educacion','club','personal','otro') then perform privado.fallo('Rubro inválido'); end if;
  if coalesce(p ->> 'venc_defecto', '7') not in ('0','7','15','30','fin') then perform privado.fallo('Vencimiento inválido'); end if;
  v_lim := coalesce(nullif(p ->> 'limite_general', '')::int, 0);
  if v_lim < 0 or v_lim > 5000000 then perform privado.fallo('El límite general debe ser entre $0 y $5.000.000'); end if;
  v_banco := jsonb_strip_nulls(jsonb_build_object(
    'banco', privado.limpio(b ->> 'banco', 40), 'tipo', privado.limpio(b ->> 'tipo', 30),
    'numero', nullif(regexp_replace(coalesce(b ->> 'numero', ''), '\D', '', 'g'), ''),
    'rut', privado.rut(b ->> 'rut'), 'titular', privado.limpio(b ->> 'titular', 60), 'email', privado.limpio(lower(b ->> 'email'), 80)));
  if v_banco ? 'numero' and length(v_banco ->> 'numero') not between 4 and 20 then perform privado.fallo('El número de cuenta debe tener entre 4 y 20 dígitos'); end if;
  if v_banco ? 'email' and (v_banco ->> 'email') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then perform privado.fallo('Correo de transferencia inválido'); end if;
  if v_banco ? 'titular' and char_length(v_banco ->> 'titular') < 2 then perform privado.fallo('Nombre del titular muy corto'); end if;
  if not prem then
    v_logo := null; v_plant := null;
  else
    if v_logo is not null and v_logo not like (select valor from privado.config where clave = 'url_proyecto') || '/storage/v1/object/public/logos/' || v_neg || '/%' then
      perform privado.fallo('Logo inválido');
    end if;
    if p ->> 'color' is not null and p ->> 'color' not in ('#059669','#2563eb','#7c3aed','#db2777','#ea580c','#0d9488','#4f46e5','#334155') then
      perform privado.fallo('Color inválido');
    end if;
    if v_plant is not null then
      select w into v_bad from unnest(array['demanda','tribunal','juzgado','embargo','dicom','abogado','policia','carabinero','carcel','denuncia','querella','boletin comercial','cobranza judicial','tus familiares','tu trabajo','tu jefe']) w
       where privado.norm(v_plant) like '%' || w || '%' limit 1;
      if v_bad is not null then perform privado.fallo('El mensaje no puede contener "' || v_bad || '": la ley prohíbe amenazas en la cobranza.'); end if;
    end if;
  end if;
  update public.negocios set nombre = v_nombre, rubro = coalesce(p ->> 'rubro', 'otro'), whatsapp = privado.telefono(p ->> 'whatsapp'),
    banco = v_banco, venc_defecto = coalesce(p ->> 'venc_defecto', '7'), limite_general = v_lim,
    pin_activo = coalesce((p ->> 'pin_activo')::boolean, true), saldo_a_favor = coalesce((p ->> 'saldo_a_favor')::boolean, false),
    logo_url = case when prem then v_logo else logo_url end,
    color = case when prem then nullif(p ->> 'color', '') else color end,
    plantilla_propia = case when prem then v_plant else plantilla_propia end
   where id = v_neg;
  update public.miembros set nombre = v_nombre where negocio = v_neg and rol = 'dueno';
end $$;

-- ---------- Clientes ----------
create or replace function public.crear_cliente(p_nombre text, p_apodo text, p_telefono text, p_rut text, p_nota text,
  p_limite int, p_pin text, p_saldo_inicial int, p_forzar boolean, p_autorizado boolean)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(); v_nombre text := privado.limpio(p_nombre, 60); v_tel text := privado.telefono(p_telefono);
  v_rut text := privado.rut(p_rut); v_id uuid; v_pin text; dup record; v_lim int;
begin
  if not coalesce(p_autorizado, false) then perform privado.fallo('Confirma que el cliente te autorizó a registrar sus datos'); end if;
  if v_nombre is null or char_length(v_nombre) < 2 then perform privado.fallo('El nombre debe tener entre 2 y 60 letras'); end if;
  if p_limite is not null and (p_limite < 0 or p_limite > 5000000) then perform privado.fallo('El límite debe ser entre $0 y $5.000.000'); end if;
  if p_saldo_inicial is not null and (p_saldo_inicial < 0 or p_saldo_inicial > 9999999) then perform privado.fallo('El saldo inicial debe ser entre $0 y $9.999.999'); end if;
  v_pin := coalesce(nullif(btrim(p_pin), ''), right(regexp_replace(coalesce(v_tel, ''), '\D', '', 'g'), 4));
  if v_pin = '' then v_pin := null; end if;
  if v_pin is not null and v_pin !~ '^\d{4}$' then perform privado.fallo('El PIN debe tener 4 números'); end if;
  if not coalesce(p_forzar, false) then
    select id, nombre, telefono into dup from public.clientes
     where negocio = v_neg and estado <> 'borrado' and (nombre_norm = privado.norm(v_nombre) or (v_tel is not null and telefono = v_tel)) limit 1;
    if found then return jsonb_build_object('ok', false, 'duplicado', jsonb_build_object('id', dup.id, 'nombre', dup.nombre, 'telefono', dup.telefono)); end if;
  end if;
  v_lim := privado.limite(v_neg, 'clientes');
  if v_lim is not null and (select count(*) from public.clientes where negocio = v_neg and estado = 'activo' and not fuera_de_plan) >= v_lim then
    perform privado.fallo('Llegaste a los ' || v_lim || ' clientes activos del plan Normal. Archiva clientes saldados o hazte Premium para tener clientes ilimitados.', 'PLAN');
  end if;
  perform privado.limitar('cli:' || v_neg, 60, 3600);
  insert into public.clientes (negocio, nombre, nombre_norm, apodo, telefono, rut, nota, limite, link_codigo, pin_hash, creado_por)
  values (v_neg, v_nombre, privado.norm(v_nombre), privado.limpio(p_apodo, 30), v_tel, v_rut, privado.limpio(p_nota, 200),
    case when privado.es_premium(v_neg) then nullif(p_limite, 0) end, privado.codigo(24),
    case when v_pin is not null then extensions.crypt(v_pin, extensions.gen_salt('bf', 8)) end, auth.uid())
  returning id into v_id;
  if coalesce(p_saldo_inicial, 0) > 0 then
    insert into public.movimientos (id, negocio, cliente, tipo, signo, monto, descripcion, vence, cuenta_plan, confirmacion, creado_por)
    values (gen_random_uuid(), v_neg, v_id, 'cargo', 1, p_saldo_inicial, 'Saldo anterior (cuaderno)', privado.hoy(), false, 'pendiente', auth.uid());
    perform privado.recalcular(v_id);
  end if;
  return jsonb_build_object('ok', true, 'id', v_id, 'sin_pin', v_pin is null);
end $$;

create or replace function public.editar_cliente(p_id uuid, p_nombre text, p_apodo text, p_telefono text, p_rut text, p_nota text, p_limite int)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(); c record; v_nombre text := privado.limpio(p_nombre, 60); v_lim int := nullif(p_limite, 0);
begin
  select * into c from public.clientes where id = p_id and negocio = v_neg and estado <> 'borrado';
  if not found then perform privado.fallo('Cliente no encontrado'); end if;
  if v_nombre is null or char_length(v_nombre) < 2 then perform privado.fallo('El nombre debe tener entre 2 y 60 letras'); end if;
  if v_lim is not null and (v_lim < 0 or v_lim > 5000000) then perform privado.fallo('El límite debe ser entre $0 y $5.000.000'); end if;
  if privado.mi_rol() <> 'dueno' and v_lim is distinct from c.limite then perform privado.fallo('Solo el dueño puede cambiar el límite'); end if;
  update public.clientes set nombre = v_nombre, nombre_norm = privado.norm(v_nombre), apodo = privado.limpio(p_apodo, 30),
    telefono = privado.telefono(p_telefono), rut = privado.rut(p_rut), nota = privado.limpio(p_nota, 200),
    limite = case when privado.es_premium(v_neg) then v_lim else limite end
   where id = p_id;
  if v_lim is distinct from c.limite then perform privado.auditar(v_neg, 'limite_cliente', jsonb_build_object('cliente', p_id, 'antes', c.limite, 'despues', v_lim)); end if;
end $$;

create or replace function public.estado_cliente(p_id uuid, p_accion text) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(); c record; v_lim int;
begin
  select * into c from public.clientes where id = p_id and negocio = v_neg and estado <> 'borrado' for update;
  if not found then perform privado.fallo('Cliente no encontrado'); end if;
  if p_accion = 'archivar' then
    if c.saldo <> 0 then perform privado.fallo('Solo se puede archivar un cliente con saldo $0'); end if;
    update public.clientes set estado = 'archivado', fuera_de_plan = false where id = p_id;
  elsif p_accion in ('reactivar', 'incluir') then
    v_lim := privado.limite(v_neg, 'clientes');
    if v_lim is not null and (select count(*) from public.clientes where negocio = v_neg and estado = 'activo' and not fuera_de_plan and id <> p_id) >= v_lim then
      perform privado.fallo('No hay cupo: el plan Normal permite ' || v_lim || ' clientes activos. Archiva otro o hazte Premium.', 'PLAN');
    end if;
    update public.clientes set estado = 'activo', fuera_de_plan = false where id = p_id;
  elsif p_accion = 'bloquear' then
    update public.clientes set bloqueado = true where id = p_id;
  elsif p_accion = 'desbloquear' then
    update public.clientes set bloqueado = false where id = p_id;
  else
    perform privado.fallo('Acción inválida');
  end if;
end $$;

create or replace function public.borrar_cliente(p_id uuid, p_confirmacion text) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true); c record;
begin
  select * into c from public.clientes where id = p_id and negocio = v_neg and estado <> 'borrado';
  if not found then perform privado.fallo('Cliente no encontrado'); end if;
  if c.saldo <> 0 then perform privado.fallo('Solo se puede borrar un cliente con saldo $0'); end if;
  if privado.norm(p_confirmacion) <> c.nombre_norm then perform privado.fallo('Escribe el nombre del cliente para confirmar'); end if;
  delete from public.sesiones_cliente where cliente = p_id;
  delete from public.push_subs where cliente = p_id;
  insert into privado.archivos_por_borrar (bucket, ruta) select 'comprobantes', foto_path from public.comprobantes where cliente = p_id and foto_path is not null;
  update public.comprobantes set foto_path = null, comentario = null where cliente = p_id;
  update public.clientes set estado = 'borrado', nombre = 'Cliente borrado', nombre_norm = 'cliente borrado', apodo = null, telefono = null,
    rut = null, nota = null, pin_hash = null, link_codigo = privado.codigo(32), link_bloqueado = true where id = p_id;
  perform privado.auditar(v_neg, 'borrar_cliente', jsonb_build_object('cliente', p_id));
end $$;

create or replace function public.link_cliente(p_id uuid, p_regenerar boolean, p_pin text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(); c record; v_cod text;
begin
  select * into c from public.clientes where id = p_id and negocio = v_neg and estado <> 'borrado';
  if not found then perform privado.fallo('Cliente no encontrado'); end if;
  if nullif(btrim(p_pin), '') is not null then
    if btrim(p_pin) !~ '^\d{4}$' then perform privado.fallo('El PIN debe tener 4 números'); end if;
    update public.clientes set pin_hash = extensions.crypt(btrim(p_pin), extensions.gen_salt('bf', 8)), pin_intentos = 0,
      pin_bloqueo_hasta = null, link_bloqueado = false, pin_fallos_dia = 0 where id = p_id;
    delete from public.sesiones_cliente where cliente = p_id;
  end if;
  if coalesce(p_regenerar, false) then
    v_cod := privado.codigo(24);
    update public.clientes set link_codigo = v_cod, link_bloqueado = false, pin_intentos = 0, pin_bloqueo_hasta = null, pin_fallos_dia = 0 where id = p_id;
    delete from public.sesiones_cliente where cliente = p_id;
    perform privado.auditar(v_neg, 'nuevo_link', jsonb_build_object('cliente', p_id));
  end if;
  select link_codigo, pin_hash is not null as tiene_pin, link_bloqueado into c from public.clientes where id = p_id;
  return jsonb_build_object('codigo', c.link_codigo, 'tiene_pin', c.tiene_pin, 'bloqueado', c.link_bloqueado);
end $$;

-- ---------- Movimientos ----------
create or replace function public.registrar_movimiento(p_id uuid, p_cliente uuid, p_tipo text, p_monto int, p_descripcion text,
  p_medio text, p_fecha timestamptz, p_vence date, p_signo int, p_forzar_limite boolean, p_confirmar_dup boolean)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  return privado.mov_insertar(privado.exigir(), p_id, p_cliente, p_tipo, p_monto, p_signo, p_descripcion, p_medio, p_fecha, p_vence,
    null, p_forzar_limite, p_confirmar_dup);
end $$;

create or replace function public.anular_movimiento(p_id uuid, p_motivo text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(); m record; v_mot text := privado.limpio(p_motivo, 100);
begin
  select * into m from public.movimientos where id = p_id and negocio = v_neg for update;
  if not found then perform privado.fallo('Movimiento no encontrado'); end if;
  if m.anulado_at is not null then return jsonb_build_object('ok', true); end if;
  if m.venta is not null then perform privado.fallo('Es una venta en cuotas: anúlala desde la pestaña Cuotas'); end if;
  if v_mot is null or char_length(v_mot) < 5 then perform privado.fallo('Escribe el motivo (mínimo 5 letras)'); end if;
  if privado.mi_rol() <> 'dueno' and (m.creado_por is distinct from auth.uid() or m.creado_at < now() - interval '10 minutes') then
    perform privado.fallo('Como ayudante solo puedes anular lo tuyo, en los primeros 10 minutos');
  end if;
  update public.movimientos set anulado_at = now(), anulado_por = auth.uid(), motivo_anulacion = v_mot where id = p_id;
  perform privado.recalcular(m.cliente);
  perform privado.auditar(v_neg, 'anular', jsonb_build_object('mov', p_id, 'cliente', m.cliente, 'tipo', m.tipo, 'monto', m.monto, 'motivo', v_mot));
  return jsonb_build_object('ok', true, 'saldo', (select saldo from public.clientes where id = m.cliente));
end $$;

create or replace function public.crear_venta_cuotas(p_id uuid, p_cliente uuid, p_descripcion text, p_total int, p_pie int, p_n int,
  p_frecuencia text, p_primera date, p_forzar_limite boolean) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(); v_desc text := privado.limpio(p_descripcion, 80); v_fin int; base int; i int; v_lim int;
  v_venc date; r jsonb; v_pie int := coalesce(p_pie, 0); hoy date := privado.hoy();
begin
  if v_desc is null or char_length(v_desc) < 2 then perform privado.fallo('Escribe qué se vendió (2 a 80 letras)'); end if;
  if p_total is null or p_total < 1000 or p_total > 9999999 then perform privado.fallo('El total debe ser entre $1.000 y $9.999.999'); end if;
  if v_pie < 0 or v_pie >= p_total then perform privado.fallo('El pie debe ser menor que el total'); end if;
  if p_n is null or p_n < 2 or p_n > 24 then perform privado.fallo('Las cuotas deben ser entre 2 y 24'); end if;
  if p_frecuencia not in ('semanal','quincenal','mensual') then perform privado.fallo('Frecuencia inválida'); end if;
  if p_primera is null or p_primera < hoy or p_primera > hoy + 60 then perform privado.fallo('La primera cuota debe ser entre hoy y 60 días más'); end if;
  v_fin := p_total - v_pie;
  if v_fin / p_n < 1 then perform privado.fallo('Monto muy chico para tantas cuotas'); end if;
  v_lim := privado.limite(v_neg, 'cuotas');
  if v_lim is not null and (select count(*) from public.ventas_cuotas where negocio = v_neg and estado = 'activa') >= v_lim then
    perform privado.fallo('El plan Normal permite ' || v_lim || ' ventas en cuotas activas. Hazte Premium para tener ilimitadas.', 'PLAN');
  end if;
  if exists (select 1 from public.ventas_cuotas where id = p_id) then return jsonb_build_object('ok', true, 'repetido', true); end if;
  v_venc := case p_frecuencia when 'semanal' then p_primera + 7 * (p_n - 1) when 'quincenal' then p_primera + 14 * (p_n - 1)
    else (p_primera + make_interval(months => p_n - 1))::date end;
  insert into public.ventas_cuotas (id, negocio, cliente, descripcion, total, pie, n, frecuencia, primera, creado_por)
  select p_id, v_neg, p_cliente, v_desc, p_total, v_pie, p_n, p_frecuencia, p_primera, auth.uid()
   where exists (select 1 from public.clientes where id = p_cliente and negocio = v_neg);
  if not found then perform privado.fallo('Cliente no encontrado'); end if;
  base := v_fin / p_n;
  for i in 1..p_n loop
    insert into public.cuotas (venta, numero, monto, vence) values (p_id, i,
      case when i = p_n then v_fin - base * (p_n - 1) else base end,
      case p_frecuencia when 'semanal' then p_primera + 7 * (i - 1) when 'quincenal' then p_primera + 14 * (i - 1)
        else (p_primera + make_interval(months => i - 1))::date end);
  end loop;
  r := privado.mov_insertar(v_neg, p_id, p_cliente, 'cargo', v_fin, 1,
    v_desc || ' · ' || p_n || ' cuotas' || case when v_pie > 0 then ' (total ' || privado.pesos(p_total) || ', pie ' || privado.pesos(v_pie) || ')' else '' end,
    null, now(), v_venc, p_id, p_forzar_limite, true);
  if not (r ->> 'ok')::boolean then
    delete from public.ventas_cuotas where id = p_id;
    return r;
  end if;
  perform privado.push(null, null, p_cliente, (select nombre from public.negocios where id = v_neg) || ': venta en cuotas',
    v_desc || ': ' || p_n || ' cuotas. Toca para ver el calendario.', 'c/');
  return r;
end $$;

create or replace function public.anular_venta_cuotas(p_venta uuid, p_motivo text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(); v record; m record; v_mot text := privado.limpio(p_motivo, 100);
begin
  select * into v from public.ventas_cuotas where id = p_venta and negocio = v_neg for update;
  if not found then perform privado.fallo('Venta no encontrada'); end if;
  if v.estado = 'anulada' then return jsonb_build_object('ok', true); end if;
  if v_mot is null or char_length(v_mot) < 5 then perform privado.fallo('Escribe el motivo (mínimo 5 letras)'); end if;
  select * into m from public.movimientos where id = p_venta;
  if privado.mi_rol() <> 'dueno' and (m.creado_por is distinct from auth.uid() or m.creado_at < now() - interval '10 minutes') then
    perform privado.fallo('Como ayudante solo puedes anular lo tuyo, en los primeros 10 minutos');
  end if;
  update public.ventas_cuotas set estado = 'anulada' where id = p_venta;
  update public.movimientos set anulado_at = now(), anulado_por = auth.uid(), motivo_anulacion = v_mot where id = p_venta;
  perform privado.recalcular(v.cliente);
  perform privado.auditar(v_neg, 'anular_cuotas', jsonb_build_object('venta', p_venta, 'cliente', v.cliente, 'motivo', v_mot));
  return jsonb_build_object('ok', true, 'saldo', (select saldo from public.clientes where id = v.cliente));
end $$;

create or replace function public.responder_reclamo(p_mov uuid, p_mantener boolean, p_comentario text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true); m record; v_com text := privado.limpio(p_comentario, 150);
begin
  select * into m from public.movimientos where id = p_mov and negocio = v_neg and confirmacion = 'reclamado';
  if not found then perform privado.fallo('Reclamo no encontrado'); end if;
  if v_com is null or char_length(v_com) < 3 then perform privado.fallo('Escribe una respuesta para el cliente'); end if;
  if p_mantener then
    update public.movimientos set respuesta = v_com where id = p_mov;
  else
    if m.venta is not null then
      perform public.anular_venta_cuotas(m.venta, 'Reclamo: ' || v_com);
      update public.movimientos set respuesta = v_com where id = p_mov;
    else
      update public.movimientos set respuesta = v_com, anulado_at = now(), anulado_por = auth.uid(), motivo_anulacion = 'Reclamo aceptado: ' || v_com where id = p_mov;
      perform privado.recalcular(m.cliente);
    end if;
  end if;
  perform privado.push(null, null, m.cliente, 'Respuesta a tu reclamo', v_com, 'c/');
end $$;

-- ---------- Cobrar ----------
create or replace function public.puede_cobrar(p_cliente uuid) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(); r record;
begin
  if not exists (select 1 from public.clientes where id = p_cliente and negocio = v_neg) then perform privado.fallo('Cliente no encontrado'); end if;
  select * into r from privado.cobro_permitido(p_cliente);
  return jsonb_build_object('ok', r.ok, 'motivo', r.motivo, 'proxima', r.proxima,
    'push', exists (select 1 from public.push_subs where cliente = p_cliente));
end $$;

create or replace function public.registrar_recordatorio(p_cliente uuid, p_canal text, p_tono text, p_texto text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(); c record; r record; prem boolean := privado.es_premium(v_neg); v_bad text; n record;
begin
  select * into c from public.clientes where id = p_cliente and negocio = v_neg and estado <> 'borrado';
  if not found then perform privado.fallo('Cliente no encontrado'); end if;
  if p_canal not in ('whatsapp','push') then perform privado.fallo('Canal inválido'); end if;
  if p_tono not in ('amable','neutral','firme','propio') then perform privado.fallo('Tono inválido'); end if;
  if p_tono <> 'amable' and not prem then perform privado.fallo('Los tonos neutral, firme y propio son Premium', 'PLAN'); end if;
  if c.saldo <= 0 then perform privado.fallo('Este cliente no tiene deuda'); end if;
  if p_canal = 'whatsapp' and c.telefono is null then perform privado.fallo('Agrega el teléfono del cliente para cobrarle por WhatsApp'); end if;
  if p_canal = 'push' and not exists (select 1 from public.push_subs where cliente = p_cliente) then
    perform privado.fallo('Este cliente no activó los avisos en su link');
  end if;
  select w into v_bad from unnest(array['demanda','tribunal','juzgado','embargo','dicom','abogado','policia','carabinero','carcel','denuncia','querella','boletin comercial','cobranza judicial','tus familiares','tu trabajo','tu jefe']) w
   where privado.norm(p_texto) like '%' || w || '%' limit 1;
  if v_bad is not null then perform privado.fallo('El mensaje no puede contener "' || v_bad || '": la ley prohíbe amenazas en la cobranza.'); end if;
  select * into r from privado.cobro_permitido(p_cliente);
  if not r.ok then
    return jsonb_build_object('ok', false, 'motivo', r.motivo, 'proxima', r.proxima);
  end if;
  insert into public.recordatorios (negocio, cliente, canal, tono, enviado_por) values (v_neg, p_cliente, p_canal, p_tono, auth.uid());
  if p_canal = 'push' then
    select nombre into n from public.negocios where id = v_neg;
    perform privado.push(null, null, p_cliente, n.nombre || ': recordatorio', coalesce(privado.limpio(p_texto, 180), 'Tienes un saldo pendiente de ' || privado.pesos(c.saldo) || '.'), 'c/');
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- ---------- Comprobantes ----------
create or replace function public.revisar_comprobante(p_id uuid, p_aprobar boolean, p_monto int, p_motivo text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(); k record; r jsonb; v_mot text := privado.limpio(p_motivo, 100); n record; v_abono uuid := gen_random_uuid();
begin
  select * into k from public.comprobantes where id = p_id and negocio = v_neg for update;
  if not found then perform privado.fallo('Comprobante no encontrado'); end if;
  if k.estado <> 'pendiente' then perform privado.fallo('Este comprobante ya fue revisado'); end if;
  select nombre into n from public.negocios where id = v_neg;
  if p_aprobar then
    r := privado.mov_insertar(v_neg, v_abono, k.cliente, 'abono', coalesce(p_monto, k.monto), -1, 'Transferencia (comprobante)',
      'transferencia', now(), null, null, false, true, p_id);
    update public.comprobantes set estado = 'aprobado', abono = v_abono, revisado_por = auth.uid(), revisado_at = now() where id = p_id;
    perform privado.push(null, null, k.cliente, n.nombre || ': pago confirmado', 'Confirmamos tu transferencia de ' || privado.pesos(coalesce(p_monto, k.monto)) || '. ¡Gracias!', 'c/');
    return r;
  else
    if v_mot is null or char_length(v_mot) < 3 then perform privado.fallo('Escribe el motivo del rechazo'); end if;
    update public.comprobantes set estado = 'rechazado', motivo = v_mot, revisado_por = auth.uid(), revisado_at = now() where id = p_id;
    perform privado.push(null, null, k.cliente, n.nombre || ': comprobante no aprobado', v_mot, 'c/');
    return jsonb_build_object('ok', true);
  end if;
end $$;

-- ---------- Productos frecuentes ----------
create or replace function public.guardar_producto(p_id uuid, p_nombre text, p_precio int) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true); v_nom text := privado.limpio(p_nombre, 30); v_lim int;
begin
  if v_nom is null or char_length(v_nom) < 2 then perform privado.fallo('El nombre debe tener entre 2 y 30 letras'); end if;
  if p_precio is null or p_precio < 1 or p_precio > 9999999 then perform privado.fallo('El precio debe ser entre $1 y $9.999.999'); end if;
  if p_id is not null and exists (select 1 from public.productos where id = p_id and negocio = v_neg) then
    update public.productos set nombre = v_nom, precio = p_precio where id = p_id;
  else
    v_lim := privado.limite(v_neg, 'productos');
    if (select count(*) from public.productos where negocio = v_neg) >= v_lim then
      perform privado.fallo('Tu plan permite ' || v_lim || ' productos frecuentes.', case when privado.es_premium(v_neg) then null else 'PLAN' end);
    end if;
    insert into public.productos (negocio, nombre, precio, orden)
    values (v_neg, v_nom, p_precio, coalesce((select max(orden) + 1 from public.productos where negocio = v_neg), 0));
  end if;
end $$;

create or replace function public.borrar_producto(p_id uuid) returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin delete from public.productos where id = p_id and negocio = privado.exigir(true); end $$;

create or replace function public.ordenar_productos(p_ids uuid[]) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true); i int;
begin
  for i in 1..coalesce(array_length(p_ids, 1), 0) loop
    update public.productos set orden = i where id = p_ids[i] and negocio = v_neg;
  end loop;
end $$;

-- ---------- Ayudantes ----------
create or replace function public.invitar_ayudante() returns text language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true); v_cod text := privado.codigo(20); v_lim int;
begin
  if not privado.es_premium(v_neg) then perform privado.fallo('Los ayudantes son Premium', 'PLAN'); end if;
  v_lim := privado.limite(v_neg, 'ayudantes');
  if (select count(*) from public.miembros where negocio = v_neg and rol = 'ayudante') >= v_lim then
    perform privado.fallo('Puedes tener hasta ' || v_lim || ' ayudantes');
  end if;
  delete from public.invitaciones where negocio = v_neg and (vence < now() or usada_por is not null);
  insert into public.invitaciones (codigo, negocio, vence) values (v_cod, v_neg, now() + interval '48 hours');
  return v_cod;
end $$;

create or replace function public.aceptar_invitacion(p_codigo text, p_nombre text) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare i record; v_nom text := privado.limpio(p_nombre, 40);
begin
  if auth.uid() is null then perform privado.fallo('Ingresa de nuevo.'); end if;
  if exists (select 1 from public.miembros where usuario = auth.uid()) or exists (select 1 from public.negocios where dueno = auth.uid()) then
    perform privado.fallo('Esta cuenta ya pertenece a una libreta. Usa otro correo para ser ayudante.');
  end if;
  if v_nom is null or char_length(v_nom) < 2 then perform privado.fallo('Escribe tu nombre'); end if;
  perform privado.limitar('inv:' || auth.uid(), 10, 3600);
  select * into i from public.invitaciones where codigo = p_codigo for update;
  if not found or i.usada_por is not null or i.vence < now() then perform privado.fallo('La invitación no es válida o ya venció. Pide una nueva.'); end if;
  if not privado.es_premium(i.negocio) then perform privado.fallo('La libreta que te invitó ya no es Premium'); end if;
  if (select count(*) from public.miembros where negocio = i.negocio and rol = 'ayudante') >= privado.limite(i.negocio, 'ayudantes') then
    perform privado.fallo('La libreta ya tiene el máximo de ayudantes');
  end if;
  insert into public.miembros (negocio, usuario, rol, nombre) values (i.negocio, auth.uid(), 'ayudante', v_nom);
  update public.invitaciones set usada_por = auth.uid() where codigo = p_codigo;
  perform public.aceptar_terminos();
  perform privado.avisar_negocio(i.negocio, 'Nuevo ayudante', v_nom || ' se unió a tu libreta.', 'app/#ayudantes', true);
end $$;

create or replace function public.quitar_ayudante(p_usuario uuid) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true);
begin
  delete from public.miembros where negocio = v_neg and usuario = p_usuario and rol = 'ayudante';
  if not found then perform privado.fallo('Ayudante no encontrado'); end if;
  delete from public.push_subs where usuario = p_usuario;
  perform privado.auditar(v_neg, 'quitar_ayudante', jsonb_build_object('usuario', p_usuario));
end $$;

create or replace function public.ayudantes() returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true);
begin
  return coalesce((select jsonb_agg(jsonb_build_object('usuario', m.usuario, 'nombre', m.nombre, 'email', u.email, 'creado', m.creado) order by m.creado)
    from public.miembros m join auth.users u on u.id = m.usuario where m.negocio = v_neg and m.rol = 'ayudante'), '[]'::jsonb);
end $$;

-- ---------- Plan Premium ----------
create or replace function public.usar_key(p_codigo text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true); k record; v_hasta timestamptz;
begin
  perform privado.limitar('key:' || v_neg, 10, 3600);
  select * into k from public.keys where codigo = upper(btrim(p_codigo)) for update;
  if not found or k.revocada or k.usada_por is not null then perform privado.fallo('Key inválida o ya usada'); end if;
  update public.negocios set premium_hasta = greatest(coalesce(premium_hasta, now()), now()) + make_interval(months => k.meses), en_prueba = false
   where id = v_neg returning premium_hasta into v_hasta;
  update public.keys set usada_por = v_neg, usada_at = now() where codigo = k.codigo;
  perform privado.aplicar_plan(v_neg);
  perform privado.auditar(v_neg, 'key', jsonb_build_object('meses', k.meses));
  return jsonb_build_object('ok', true, 'hasta', v_hasta);
end $$;

create or replace function public.solicitar_pago(p_meses int, p_path text, p_nota text) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true); a record; n record;
begin
  if p_meses not in (1, 12) then perform privado.fallo('Elige mensual o anual'); end if;
  if exists (select 1 from public.solicitudes_pago where negocio = v_neg and estado = 'pendiente') then
    perform privado.fallo('Ya tienes un pago en revisión. Te avisaremos apenas se apruebe.');
  end if;
  if p_path is not null and p_path not like v_neg || '/%' then perform privado.fallo('Archivo inválido'); end if;
  select * into a from public.ajustes where id = 1;
  select nombre into n from public.negocios where id = v_neg;
  insert into public.solicitudes_pago (negocio, meses, monto, comprobante_path, nota)
  values (v_neg, p_meses, case when p_meses = 12 then a.precio_anual else a.precio_mensual end, p_path, privado.limpio(p_nota, 200));
  perform privado.avisar_usuario((select nullif(valor, '')::uuid from privado.config where clave = 'admin_id'),
    'Pago por revisar', n.nombre || ' dice que pagó Premium ' || case when p_meses = 12 then 'anual' else 'mensual' end || '.', 'admin/#pagos', true);
end $$;

-- ---------- Notificaciones y push ----------
create or replace function public.marcar_leidas() returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.notificaciones set leido = true where not leido and (usuario = auth.uid() or negocio = privado.mi_negocio());
end $$;

create or replace function public.guardar_push(p_endpoint text, p_p256dh text, p_auth text) returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then perform privado.fallo('Ingresa de nuevo.'); end if;
  if p_endpoint !~ '^https://' or length(p_endpoint) > 1000 or length(p_p256dh) > 200 or length(p_auth) > 100 then perform privado.fallo('Suscripción inválida'); end if;
  insert into public.push_subs (endpoint, p256dh, auth, usuario) values (p_endpoint, p_p256dh, p_auth, auth.uid())
  on conflict (endpoint) do update set p256dh = excluded.p256dh, auth = excluded.auth, usuario = auth.uid(), sesion = null, cliente = null;
end $$;

create or replace function public.borrar_push(p_endpoint text) returns void language sql security definer set search_path = public, pg_temp as $$
  delete from public.push_subs where endpoint = p_endpoint and usuario = auth.uid()
$$;

-- ---------- Tablero y reportes ----------
create or replace function public.tablero() returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(); hoy date := privado.hoy(); m0 timestamptz; m1 timestamptz;
begin
  m0 := (date_trunc('month', hoy)::timestamp) at time zone 'America/Santiago';
  m1 := ((date_trunc('month', hoy) - interval '1 month')::timestamp) at time zone 'America/Santiago';
  return jsonb_build_object(
    'por_cobrar', (select coalesce(sum(saldo), 0) from public.clientes where negocio = v_neg and saldo > 0 and estado <> 'borrado'),
    'deudores', (select count(*) from public.clientes where negocio = v_neg and saldo > 0 and estado <> 'borrado'),
    'vence_hoy', (select jsonb_build_object('n', count(*), 'monto', coalesce(sum(saldo), 0)) from public.clientes where negocio = v_neg and saldo > 0 and prox_venc = hoy),
    'atrasados', (select jsonb_build_object('n', count(*), 'monto', coalesce(sum(saldo), 0)) from public.clientes where negocio = v_neg and saldo > 0 and atrasado),
    'recuperado_mes', (select coalesce(sum(monto), 0) from public.movimientos where negocio = v_neg and signo = -1 and tipo = 'abono' and anulado_at is null and fecha >= m0),
    'recuperado_mes_pasado', (select coalesce(sum(monto), 0) from public.movimientos where negocio = v_neg and signo = -1 and tipo = 'abono' and anulado_at is null and fecha >= m1 and fecha < m0),
    'fiado_mes', (select coalesce(sum(monto), 0) from public.movimientos where negocio = v_neg and tipo = 'cargo' and anulado_at is null and fecha >= m0),
    'cobrar_hoy', coalesce((select jsonb_agg(x) from (select id, nombre, apodo, saldo, prox_venc, atrasado, telefono from public.clientes
        where negocio = v_neg and saldo > 0 and prox_venc <= hoy and estado <> 'borrado' order by prox_venc, saldo desc limit 30) x), '[]'::jsonb));
end $$;

create or replace function public.reporte(p_desde date, p_hasta date) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true); prem boolean := privado.es_premium(v_neg); d date := p_desde; h date := p_hasta;
  t0 timestamptz; t1 timestamptz; limitado boolean := false;
begin
  if d is null or h is null or h < d then perform privado.fallo('Rango de fechas inválido'); end if;
  if h - d > 731 then perform privado.fallo('El rango máximo es 2 años'); end if;
  if not prem and d < date_trunc('month', privado.hoy())::date then d := date_trunc('month', privado.hoy())::date; limitado := true; end if;
  if h < d then h := d; end if;
  t0 := d::timestamp at time zone 'America/Santiago'; t1 := (h + 1)::timestamp at time zone 'America/Santiago';
  return jsonb_build_object('desde', d, 'hasta', h, 'limitado', limitado,
    'fiado', (select coalesce(sum(monto), 0) from public.movimientos where negocio = v_neg and tipo = 'cargo' and anulado_at is null and fecha >= t0 and fecha < t1),
    'cobrado', (select coalesce(sum(monto), 0) from public.movimientos where negocio = v_neg and tipo = 'abono' and anulado_at is null and fecha >= t0 and fecha < t1),
    'por_medio', coalesce((select jsonb_object_agg(medio, s) from (select medio, sum(monto) s from public.movimientos
        where negocio = v_neg and tipo = 'abono' and anulado_at is null and fecha >= t0 and fecha < t1 group by medio) x), '{}'::jsonb),
    'por_dia', case when prem then coalesce((select jsonb_agg(x order by dia) from (select (fecha at time zone 'America/Santiago')::date dia,
        sum(monto) filter (where tipo = 'cargo') fiado, sum(monto) filter (where tipo = 'abono') cobrado
        from public.movimientos where negocio = v_neg and anulado_at is null and fecha >= t0 and fecha < t1 group by 1) x), '[]'::jsonb) else null end,
    'mayores_deudores', coalesce((select jsonb_agg(x) from (select nombre, saldo, atrasado, puntaje from public.clientes
        where negocio = v_neg and saldo > 0 and estado <> 'borrado' order by saldo desc limit 5) x), '[]'::jsonb),
    'mejores_pagadores', case when prem then coalesce((select jsonb_agg(x) from (select c.nombre, sum(m.monto) pagado from public.movimientos m
        join public.clientes c on c.id = m.cliente where m.negocio = v_neg and m.tipo = 'abono' and m.anulado_at is null and m.fecha >= t0 and m.fecha < t1
        group by c.nombre order by 2 desc limit 5) x), '[]'::jsonb) else null end,
    'atrasados', (select jsonb_build_object('n', count(*), 'monto', coalesce(sum(saldo), 0)) from public.clientes where negocio = v_neg and saldo > 0 and atrasado));
end $$;

create or replace function public.exportar_datos() returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid;
begin
  if auth.uid() is null then perform privado.fallo('Ingresa de nuevo.'); end if;
  select id into v_neg from public.negocios where dueno = auth.uid();
  if v_neg is null then perform privado.fallo('Solo el dueño puede exportar'); end if;
  perform privado.limitar('exp:' || v_neg, 20, 3600);
  return jsonb_build_object(
    'negocio', (select to_jsonb(n) - 'nota_admin' from public.negocios n where id = v_neg),
    'clientes', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'nombre', nombre, 'apodo', apodo, 'telefono', telefono, 'rut', rut,
        'nota', nota, 'limite', limite, 'estado', estado, 'saldo', saldo, 'prox_venc', prox_venc, 'creado', creado) order by nombre)
        from public.clientes where negocio = v_neg and estado <> 'borrado'), '[]'::jsonb),
    'movimientos', coalesce((select jsonb_agg(jsonb_build_object('fecha', m.fecha, 'cliente', c.nombre, 'tipo', m.tipo, 'signo', m.signo, 'monto', m.monto,
        'descripcion', m.descripcion, 'medio', m.medio, 'vence', m.vence, 'confirmacion', m.confirmacion, 'anulado', m.anulado_at is not null,
        'motivo_anulacion', m.motivo_anulacion) order by m.fecha)
        from public.movimientos m join public.clientes c on c.id = m.cliente where m.negocio = v_neg), '[]'::jsonb),
    'cuotas', coalesce((select jsonb_agg(jsonb_build_object('venta', v.descripcion, 'cliente', c.nombre, 'numero', q.numero, 'monto', q.monto,
        'vence', q.vence, 'pagado', q.pagado, 'estado_venta', v.estado) order by v.creado, q.numero)
        from public.cuotas q join public.ventas_cuotas v on v.id = q.venta join public.clientes c on c.id = v.cliente where v.negocio = v_neg), '[]'::jsonb));
end $$;

-- ---------- Cuenta ----------
create or replace function public.borrar_mi_cuenta(p_confirmacion text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare n record;
begin
  if auth.uid() is null then perform privado.fallo('Ingresa de nuevo.'); end if;
  select * into n from public.negocios where dueno = auth.uid();
  if not found then
    delete from public.push_subs where usuario = auth.uid();
    delete from public.miembros where usuario = auth.uid();
    delete from auth.users where id = auth.uid();
    return jsonb_build_object('ok', true, 'inmediato', true);
  end if;
  if privado.norm(p_confirmacion) <> privado.norm(n.nombre) then perform privado.fallo('Escribe el nombre de tu negocio para confirmar'); end if;
  update public.negocios set estado = 'eliminado', eliminar_desde = now() + interval '30 days' where id = n.id;
  delete from public.miembros where negocio = n.id and rol = 'ayudante';
  delete from public.sesiones_cliente s using public.clientes c where c.id = s.cliente and c.negocio = n.id;
  delete from public.push_subs where usuario = auth.uid();
  perform privado.auditar(n.id, 'borrar_cuenta', null);
  return jsonb_build_object('ok', true, 'eliminar_desde', now() + interval '30 days');
end $$;

create or replace function public.recuperar_mi_cuenta() returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.negocios set estado = 'activo', eliminar_desde = null where dueno = auth.uid() and estado = 'eliminado';
  if not found then perform privado.fallo('No hay una cuenta por recuperar'); end if;
end $$;

-- =====================================================================
--  LINK DEL CLIENTE (sin cuenta: solo código + PIN)
-- =====================================================================
create or replace function privado.sesion(p_token text) returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare s record;
begin
  select s2.* into s from public.sesiones_cliente s2 join public.clientes c on c.id = s2.cliente
   where s2.token_hash = privado.sha(coalesce(p_token, '')) and s2.vence > now() and c.estado <> 'borrado' and not c.link_bloqueado;
  if not found then perform privado.fallo('Tu sesión terminó. Vuelve a abrir el link que te mandó el negocio.', 'SESION'); end if;
  if s.visto < now() - interval '10 minutes' then update public.sesiones_cliente set visto = now() where id = s.id; end if;
  return s.cliente;
end $$;

create or replace function public.portal_info(p_codigo text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare c record; n record; v_ip text;
begin
  begin v_ip := split_part(coalesce(current_setting('request.headers', true)::json ->> 'x-forwarded-for', ''), ',', 1); exception when others then v_ip := ''; end;
  if v_ip <> '' then perform privado.limitar('ipinfo:' || v_ip, 120, 3600); end if;
  select * into c from public.clientes where link_codigo = coalesce(p_codigo, '') and estado <> 'borrado';
  if not found then return jsonb_build_object('ok', false); end if;
  select * into n from public.negocios where id = c.negocio;
  return jsonb_build_object('ok', n.estado = 'activo', 'negocio', n.nombre, 'pin', n.pin_activo, 'bloqueado', c.link_bloqueado,
    'logo_url', case when privado.es_premium(n.id) then n.logo_url end, 'color', case when privado.es_premium(n.id) then n.color end);
end $$;

create or replace function public.portal_entrar(p_codigo text, p_pin text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare c record; n record; v_tok text; v_ip text; hoy date := privado.hoy();
begin
  begin v_ip := split_part(coalesce(current_setting('request.headers', true)::json ->> 'x-forwarded-for', ''), ',', 1); exception when others then v_ip := ''; end;
  if v_ip <> '' then perform privado.limitar('ip:' || v_ip, 60, 3600); end if;
  select * into c from public.clientes where link_codigo = coalesce(p_codigo, '') and estado <> 'borrado' for update;
  if not found then perform privado.fallo('Este link no es válido. Pídele al negocio que te lo envíe de nuevo.'); end if;
  select * into n from public.negocios where id = c.negocio;
  if n.estado <> 'activo' then perform privado.fallo('Este link no está disponible por ahora.'); end if;
  if c.link_bloqueado then perform privado.fallo('Este link está bloqueado por seguridad. Pídele a ' || n.nombre || ' uno nuevo.'); end if;
  if c.pin_bloqueo_hasta > now() then
    perform privado.fallo('Demasiados intentos. Prueba de nuevo en ' || ceil(extract(epoch from c.pin_bloqueo_hasta - now()) / 60) || ' minutos.');
  end if;
  if n.pin_activo then
    if c.pin_hash is null then perform privado.fallo(n.nombre || ' aún no define tu PIN. Pídeselo.'); end if;
    if coalesce(p_pin, '') !~ '^\d{4}$' or extensions.crypt(p_pin, c.pin_hash) <> c.pin_hash then
      update public.clientes set
        pin_fallos_dia = case when pin_dia = hoy then pin_fallos_dia + 1 else 1 end, pin_dia = hoy,
        pin_intentos = case when pin_intentos + 1 >= 5 then 0 else pin_intentos + 1 end,
        pin_bloqueo_hasta = case when pin_intentos + 1 >= 5 then now() + interval '15 minutes' else pin_bloqueo_hasta end
       where id = c.id returning * into c;
      if c.pin_fallos_dia >= 20 then
        update public.clientes set link_bloqueado = true where id = c.id;
        perform privado.avisar_negocio(c.negocio, 'Link bloqueado', 'El link de ' || c.nombre || ' se bloqueó por muchos PIN incorrectos. Genera uno nuevo desde su ficha.', 'app/#cliente/' || c.id, true);
        return jsonb_build_object('ok', false, 'error', 'Este link se bloqueó por seguridad. Pídele a ' || n.nombre || ' uno nuevo.');
      end if;
      return jsonb_build_object('ok', false, 'error', case when c.pin_intentos = 0 then 'PIN incorrecto. Espera 15 minutos para intentar de nuevo.'
        else 'PIN incorrecto. Te quedan ' || (5 - c.pin_intentos) || ' intentos.' end);
    end if;
  end if;
  update public.clientes set pin_intentos = 0, pin_bloqueo_hasta = null where id = c.id;
  v_tok := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.sesiones_cliente (token_hash, cliente, vence) values (privado.sha(v_tok), c.id, now() + interval '30 days');
  delete from public.sesiones_cliente where cliente = c.id and id not in (select id from public.sesiones_cliente where cliente = c.id order by creado desc limit 5);
  return jsonb_build_object('ok', true, 'sesion', v_tok);
end $$;

create or replace function public.portal_ver(p_sesion text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_cli uuid := privado.sesion(p_sesion); c record; n record; prem boolean;
begin
  select * into c from public.clientes where id = v_cli;
  select * into n from public.negocios where id = c.negocio;
  prem := privado.es_premium(n.id);
  return jsonb_build_object(
    'negocio', jsonb_build_object('nombre', n.nombre, 'whatsapp', n.whatsapp, 'banco', n.banco,
      'logo_url', case when prem then n.logo_url end, 'color', case when prem then n.color end, 'marca', not prem,
      'estado', n.estado),
    'cliente', jsonb_build_object('nombre', c.nombre, 'saldo', c.saldo, 'prox_venc', c.prox_venc, 'atrasado', c.atrasado),
    'movimientos', coalesce((select jsonb_agg(x order by x.fecha desc) from (
        select id, tipo, signo, monto, descripcion, medio, fecha, vence, venta is not null as cuotas, confirmacion, reclamo_motivo, respuesta,
          anulado_at is not null as anulado, motivo_anulacion
        from public.movimientos where cliente = v_cli and (prem or fecha > now() - make_interval(months => 6))
        order by fecha desc limit 300) x), '[]'::jsonb),
    'cuotas', coalesce((select jsonb_agg(jsonb_build_object('descripcion', v.descripcion, 'total', v.total, 'pie', v.pie, 'estado', v.estado,
        'cuotas', (select jsonb_agg(jsonb_build_object('numero', q.numero, 'monto', q.monto, 'vence', q.vence, 'pagado', q.pagado) order by q.numero)
                   from public.cuotas q where q.venta = v.id)) order by v.creado desc)
        from public.ventas_cuotas v where v.cliente = v_cli and v.estado <> 'anulada'), '[]'::jsonb),
    'comprobantes', coalesce((select jsonb_agg(x order by x.creado desc) from (select monto, fecha, estado, motivo, creado
        from public.comprobantes where cliente = v_cli order by creado desc limit 10) x), '[]'::jsonb),
    'vapid_public', (select valor from privado.secretos where nombre = 'vapid_public'));
end $$;

create or replace function public.portal_confirmar(p_sesion text, p_mov uuid, p_reconoce boolean, p_motivo text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_cli uuid := privado.sesion(p_sesion); m record; v_mot text := privado.limpio(p_motivo, 150); c record;
begin
  select * into m from public.movimientos where id = p_mov and cliente = v_cli and tipo = 'cargo' and anulado_at is null for update;
  if not found then perform privado.fallo('Cargo no encontrado'); end if;
  if m.confirmacion <> 'pendiente' then perform privado.fallo('Ya respondiste este cargo'); end if;
  select * into c from public.clientes where id = v_cli;
  if p_reconoce then
    update public.movimientos set confirmacion = 'reconocido' where id = p_mov;
  else
    if v_mot is null or char_length(v_mot) < 5 then perform privado.fallo('Cuéntale al negocio por qué no lo reconoces (mínimo 5 letras)'); end if;
    update public.movimientos set confirmacion = 'reclamado', reclamo_motivo = v_mot where id = p_mov;
    perform privado.avisar_negocio(m.negocio, 'Reclamo de ' || c.nombre, privado.pesos(m.monto) || ': ' || v_mot, 'app/#cliente/' || v_cli, true);
  end if;
  perform privado.recalcular(v_cli);
end $$;

create or replace function public.portal_comprobante(p_sesion text, p_monto int, p_fecha date, p_comentario text, p_con_foto boolean) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_cli uuid := privado.sesion(p_sesion); c record; u public.uso_mensual; v_lim int; v_id uuid; v_tok text; hoy date := privado.hoy();
begin
  select * into c from public.clientes where id = v_cli;
  if c.saldo <= 0 then perform privado.fallo('No tienes saldo pendiente.'); end if;
  if p_monto is null or p_monto < 1 or p_monto > c.saldo + 100000 then perform privado.fallo('Revisa el monto: debe ser entre $1 y ' || privado.pesos(c.saldo + 100000)); end if;
  if p_fecha is null or p_fecha > hoy or p_fecha < hoy - 30 then perform privado.fallo('La fecha de la transferencia debe ser de los últimos 30 días'); end if;
  if (select count(*) from public.comprobantes where cliente = v_cli and estado = 'pendiente') >= 3 then
    perform privado.fallo('Tienes 3 comprobantes esperando revisión. Espera que el negocio los revise.');
  end if;
  if (select count(*) from public.comprobantes where cliente = v_cli and creado > now() - interval '1 day') >= 5 then
    perform privado.fallo('Máximo 5 comprobantes por día.');
  end if;
  u := privado.uso(c.negocio);
  v_lim := privado.limite(c.negocio, 'comprobantes');
  if u.comprobantes >= v_lim then
    perform privado.fallo('El negocio alcanzó su límite de comprobantes este mes. Envíale el comprobante por WhatsApp.');
  end if;
  insert into public.comprobantes (negocio, cliente, monto, fecha, comentario) values (c.negocio, v_cli, p_monto, p_fecha, privado.limpio(p_comentario, 100))
  returning id into v_id;
  update public.uso_mensual set comprobantes = comprobantes + 1 where negocio = c.negocio and mes = date_trunc('month', hoy)::date;
  perform privado.avisar_negocio(c.negocio, 'Comprobante de ' || c.nombre, 'Dice que transfirió ' || privado.pesos(p_monto) || '. Revísalo y apruébalo.', 'app/#comprobantes', true);
  if coalesce(p_con_foto, false) then
    v_tok := encode(extensions.gen_random_bytes(24), 'hex');
    insert into privado.fotos_pendientes (comprobante, token_hash, vence) values (v_id, privado.sha(v_tok), now() + interval '15 minutes');
  end if;
  return jsonb_build_object('ok', true, 'id', v_id, 'foto_token', v_tok);
end $$;

create or replace function public.portal_push(p_sesion text, p_endpoint text, p_p256dh text, p_auth text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_cli uuid := privado.sesion(p_sesion); v_ses uuid;
begin
  if p_endpoint !~ '^https://' or length(p_endpoint) > 1000 or length(p_p256dh) > 200 or length(p_auth) > 100 then perform privado.fallo('Suscripción inválida'); end if;
  select id into v_ses from public.sesiones_cliente where token_hash = privado.sha(p_sesion);
  insert into public.push_subs (endpoint, p256dh, auth, sesion, cliente) values (p_endpoint, p_p256dh, p_auth, v_ses, v_cli)
  on conflict (endpoint) do update set p256dh = excluded.p256dh, auth = excluded.auth, sesion = v_ses, cliente = v_cli, usuario = null;
end $$;

create or replace function public.portal_salir(p_sesion text) returns void language sql security definer set search_path = public, pg_temp as $$
  delete from public.sesiones_cliente where token_hash = privado.sha(coalesce(p_sesion, ''))
$$;

-- =====================================================================
--  ADMINISTRADOR (solo Josué)
-- =====================================================================
create or replace function privado.solo_admin() returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin if not privado.es_admin() then perform privado.fallo('Solo el administrador.'); end if; end $$;

create or replace function public.admin_resumen() returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m0 date := date_trunc('month', privado.hoy())::date;
begin
  perform privado.solo_admin();
  return jsonb_build_object(
    'negocios', (select count(*) from public.negocios where estado <> 'eliminado'),
    'activos_7d', (select count(*) from public.negocios where estado = 'activo' and ultimo_uso > now() - interval '7 days'),
    'premium', (select count(*) from public.negocios n where estado <> 'eliminado' and privado.es_premium(n.id) and not en_prueba),
    'en_prueba', (select count(*) from public.negocios n where estado <> 'eliminado' and en_prueba and privado.es_premium(n.id)),
    'suspendidos', (select count(*) from public.negocios where estado = 'suspendido'),
    'ingresos_mes', (select coalesce(sum(monto), 0) from public.solicitudes_pago where estado = 'aprobada' and revisado_at >= m0)
      + (select coalesce(sum(precio), 0) from public.keys where usada_at >= m0),
    'pagos_pendientes', (select count(*) from public.solicitudes_pago where estado = 'pendiente'),
    'clientes_total', (select count(*) from public.clientes where estado <> 'borrado'),
    'movimientos_mes', (select coalesce(sum(movimientos), 0) from public.uso_mensual where mes = m0),
    'bd_mb', round(pg_database_size(current_database()) / 1048576.0, 1),
    'archivos_mb', (select round(coalesce(sum((metadata ->> 'size')::bigint), 0) / 1048576.0, 1) from storage.objects),
    'cola_push', (select count(*) from public.cola_push where tomado_at is null),
    'cron_ok', (select count(*) from cron.job where jobname like 'lc-%') >= 2,
    'push_ok', exists (select 1 from privado.secretos where nombre = 'vapid_private'));
end $$;

create or replace function public.admin_negocios(p_buscar text, p_filtro text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform privado.solo_admin();
  return coalesce((select jsonb_agg(x) from (
    select n.id, n.nombre, n.rubro, n.estado, n.motivo_suspension, n.premium_hasta, n.en_prueba, privado.es_premium(n.id) premium,
      n.ultimo_uso, n.creado, n.nota_admin, n.whatsapp, u.email,
      (select count(*) from public.clientes c where c.negocio = n.id and c.estado = 'activo') clientes,
      (select movimientos from public.uso_mensual um where um.negocio = n.id and um.mes = date_trunc('month', privado.hoy())::date) movimientos_mes
    from public.negocios n join auth.users u on u.id = n.dueno
    where (coalesce(p_buscar, '') = '' or privado.norm(n.nombre) like '%' || privado.norm(p_buscar) || '%' or lower(u.email) like '%' || lower(p_buscar) || '%')
      and (coalesce(p_filtro, 'todos') = 'todos'
        or (p_filtro = 'premium' and privado.es_premium(n.id) and not n.en_prueba)
        or (p_filtro = 'prueba' and n.en_prueba and privado.es_premium(n.id))
        or (p_filtro = 'normal' and not privado.es_premium(n.id) and n.estado = 'activo')
        or (p_filtro = 'suspendido' and n.estado = 'suspendido')
        or (p_filtro = 'eliminado' and n.estado = 'eliminado'))
    order by n.creado desc limit 300) x), '[]'::jsonb);
end $$;

create or replace function public.admin_plan(p_negocio uuid, p_accion text, p_dias int) returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform privado.solo_admin();
  if p_accion = 'sumar' then
    if p_dias is null or p_dias < 1 or p_dias > 3660 then perform privado.fallo('Días inválidos'); end if;
    update public.negocios set premium_hasta = greatest(coalesce(premium_hasta, now()), now()) + make_interval(days => p_dias), en_prueba = false where id = p_negocio;
    perform privado.avisar_negocio(p_negocio, '¡Premium activado!', 'Se sumaron ' || p_dias || ' días de Premium a tu libreta.', 'app/#plan', true);
  elsif p_accion = 'quitar' then
    update public.negocios set premium_hasta = now() - interval '30 days', en_prueba = false where id = p_negocio;
  else
    perform privado.fallo('Acción inválida');
  end if;
  perform privado.aplicar_plan(p_negocio);
  perform privado.auditar(p_negocio, 'admin_plan', jsonb_build_object('accion', p_accion, 'dias', p_dias));
end $$;

create or replace function public.admin_estado(p_negocio uuid, p_suspender boolean, p_motivo text, p_nota text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform privado.solo_admin();
  if p_suspender is not null then
    if p_suspender and coalesce(privado.limpio(p_motivo, 150), '') = '' then perform privado.fallo('Escribe el motivo'); end if;
    update public.negocios set estado = case when p_suspender then 'suspendido' else 'activo' end,
      motivo_suspension = case when p_suspender then privado.limpio(p_motivo, 150) end
     where id = p_negocio and estado <> 'eliminado';
  end if;
  if p_nota is not null then update public.negocios set nota_admin = privado.limpio(p_nota, 500) where id = p_negocio; end if;
end $$;

create or replace function public.admin_pagos() returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform privado.solo_admin();
  return coalesce((select jsonb_agg(x) from (select s.*, n.nombre negocio_nombre from public.solicitudes_pago s join public.negocios n on n.id = s.negocio
    order by (s.estado = 'pendiente') desc, s.creado desc limit 100) x), '[]'::jsonb);
end $$;

create or replace function public.admin_resolver_pago(p_id uuid, p_aprobar boolean, p_motivo text) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare s record;
begin
  perform privado.solo_admin();
  select * into s from public.solicitudes_pago where id = p_id and estado = 'pendiente' for update;
  if not found then perform privado.fallo('Solicitud no encontrada'); end if;
  if p_aprobar then
    update public.negocios set premium_hasta = greatest(coalesce(premium_hasta, now()), now()) + make_interval(months => s.meses), en_prueba = false where id = s.negocio;
    update public.solicitudes_pago set estado = 'aprobada', revisado_at = now() where id = p_id;
    perform privado.aplicar_plan(s.negocio);
    perform privado.avisar_negocio(s.negocio, '¡Pago aprobado!', 'Tu Premium quedó activo por ' || case when s.meses = 12 then '1 año' else '1 mes' end || '. ¡Gracias!', 'app/#plan', true);
  else
    if coalesce(privado.limpio(p_motivo, 150), '') = '' then perform privado.fallo('Escribe el motivo'); end if;
    update public.solicitudes_pago set estado = 'rechazada', motivo = privado.limpio(p_motivo, 150), revisado_at = now() where id = p_id;
    perform privado.avisar_negocio(s.negocio, 'Pago no aprobado', privado.limpio(p_motivo, 150), 'app/#plan', true);
  end if;
end $$;

create or replace function public.admin_crear_keys(p_meses int, p_cantidad int, p_precio int) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare i int; v text; out jsonb := '[]'::jsonb;
begin
  perform privado.solo_admin();
  if p_meses not in (1, 3, 6, 12) then perform privado.fallo('Duración inválida'); end if;
  if p_cantidad is null or p_cantidad < 1 or p_cantidad > 50 then perform privado.fallo('Cantidad entre 1 y 50'); end if;
  for i in 1..p_cantidad loop
    v := 'LC-' || upper(privado.codigo(4)) || '-' || upper(privado.codigo(4)) || '-' || upper(privado.codigo(4));
    insert into public.keys (codigo, meses, precio) values (v, p_meses, greatest(coalesce(p_precio, 0), 0));
    out := out || to_jsonb(v);
  end loop;
  return out;
end $$;

create or replace function public.admin_keys() returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform privado.solo_admin();
  return coalesce((select jsonb_agg(x) from (select k.*, n.nombre negocio_nombre from public.keys k left join public.negocios n on n.id = k.usada_por
    order by k.creado desc limit 200) x), '[]'::jsonb);
end $$;

create or replace function public.admin_revocar_key(p_codigo text) returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform privado.solo_admin();
  update public.keys set revocada = true where codigo = p_codigo and usada_por is null;
end $$;

create or replace function public.admin_aviso(p_destino text, p_negocio uuid, p_titulo text, p_cuerpo text) returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare r record; v_n int := 0; v_t text := privado.limpio(p_titulo, 80); v_c text := privado.limpio(p_cuerpo, 300);
begin
  perform privado.solo_admin();
  if v_t is null then perform privado.fallo('Escribe el título'); end if;
  for r in select n.id from public.negocios n where n.estado = 'activo' and (
      p_destino = 'todos' or (p_destino = 'premium' and privado.es_premium(n.id)) or (p_destino = 'normal' and not privado.es_premium(n.id))
      or (p_destino = 'negocio' and n.id = p_negocio))
  loop
    perform privado.avisar_negocio(r.id, v_t, v_c, 'app/#avisos', true);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

create or replace function public.admin_guardar_ajustes(p jsonb) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare ln jsonb := p -> 'lim_normal'; k text;
begin
  perform privado.solo_admin();
  if ln is not null then
    foreach k in array array['clientes','movimientos','cuotas','productos','comprobantes','historial_meses'] loop
      if not (ln ? k) or (ln ->> k)::int < 1 or (ln ->> k)::int > 100000 then perform privado.fallo('Límite inválido: ' || k); end if;
    end loop;
  end if;
  if coalesce(p ->> 'link_pago', '') <> '' and p ->> 'link_pago' !~ '^https://' then perform privado.fallo('El link de pago debe empezar con https://'); end if;
  update public.ajustes set
    precio_mensual = coalesce((p ->> 'precio_mensual')::int, precio_mensual),
    precio_anual = coalesce((p ->> 'precio_anual')::int, precio_anual),
    link_pago = coalesce(p ->> 'link_pago', link_pago),
    transferencia = coalesce(p -> 'transferencia', transferencia),
    contacto_whatsapp = coalesce(privado.telefono(nullif(p ->> 'contacto_whatsapp', '')), case when p ? 'contacto_whatsapp' then '' else contacto_whatsapp end),
    dias_prueba = coalesce((p ->> 'dias_prueba')::int, dias_prueba),
    dias_gracia = coalesce((p ->> 'dias_gracia')::int, dias_gracia),
    lim_normal = coalesce(ln, lim_normal),
    version_legal = coalesce((p ->> 'version_legal')::int, version_legal),
    version_min = coalesce(nullif(p ->> 'version_min', ''), version_min),
    actualizado = now()
   where id = 1;
end $$;

create or replace function public.admin_set_secret(p_nombre text, p_valor text) returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform privado.solo_admin();
  if p_nombre not in ('vapid_public','vapid_private') then perform privado.fallo('Secreto inválido'); end if;
  insert into privado.secretos (nombre, valor) values (p_nombre, p_valor) on conflict (nombre) do update set valor = excluded.valor;
  if p_nombre = 'vapid_public' then delete from public.push_subs where endpoint is not null; end if;
end $$;

create or replace function public.admin_feriado(p_fecha date, p_nombre text, p_borrar boolean) returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform privado.solo_admin();
  if p_borrar then delete from public.feriados where fecha = p_fecha;
  else insert into public.feriados values (p_fecha, coalesce(privado.limpio(p_nombre, 60), 'Feriado')) on conflict (fecha) do update set nombre = excluded.nombre;
  end if;
end $$;

-- =====================================================================
--  SOLO PARA EL SERVIDOR (Edge Function "enviar", con la clave de servicio)
-- =====================================================================
create or replace function public.srv_secretos() returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_object_agg(nombre, valor), '{}'::jsonb) from privado.secretos
$$;

create or replace function public.srv_cola_tomar(p_max int) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare ids bigint[];
begin
  select array_agg(id) into ids from (select id from public.cola_push where tomado_at is null order by id limit p_max for update skip locked) x;
  if ids is null then return '[]'::jsonb; end if;
  update public.cola_push set tomado_at = now() where id = any (ids);
  return coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'titulo', q.titulo, 'cuerpo', q.cuerpo, 'url', q.url, 'tag', q.tag,
      'endpoint', s.endpoint, 'p256dh', s.p256dh, 'auth', s.auth))
    from public.cola_push q
    join public.push_subs s on (q.usuario is not null and s.usuario = q.usuario)
      or (q.cliente is not null and s.cliente = q.cliente)
      or (q.negocio is not null and s.usuario in (select m.usuario from public.miembros m where m.negocio = q.negocio and m.activo))
    where q.id = any (ids)), '[]'::jsonb);
end $$;

create or replace function public.srv_quitar_endpoint(p_endpoint text) returns void language sql security definer set search_path = public, pg_temp as $$
  delete from public.push_subs where endpoint = p_endpoint
$$;

create or replace function public.srv_foto_validar(p_id uuid, p_token text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare f record; k record;
begin
  select * into f from privado.fotos_pendientes where comprobante = p_id and token_hash = privado.sha(coalesce(p_token, '')) and vence > now();
  if not found then return jsonb_build_object('ok', false); end if;
  select negocio into k from public.comprobantes where id = p_id;
  return jsonb_build_object('ok', true, 'ruta', k.negocio || '/' || p_id || '.webp');
end $$;

create or replace function public.srv_foto_lista(p_id uuid, p_ruta text) returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.comprobantes set foto_path = p_ruta where id = p_id;
  delete from privado.fotos_pendientes where comprobante = p_id;
end $$;

create or replace function public.srv_archivos_por_borrar(p_max int) returns jsonb language sql security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'bucket', bucket, 'ruta', ruta)), '[]'::jsonb)
  from (select * from privado.archivos_por_borrar order by id limit p_max) x
$$;

create or replace function public.srv_archivos_borrados(p_ids bigint[]) returns void language sql security definer set search_path = public, pg_temp as $$
  delete from privado.archivos_por_borrar where id = any (p_ids)
$$;

-- =====================================================================
--  TAREAS AUTOMÁTICAS
-- =====================================================================
create or replace function privado.llamar_funcion(p_body jsonb) returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  perform net.http_post(url := (select valor from privado.config where clave = 'url_proyecto') || '/functions/v1/enviar',
    body := p_body, headers := '{"Content-Type": "application/json"}'::jsonb);
exception when others then raise notice 'llamar_funcion: %', sqlerrm;
end $$;

create or replace function privado.tarea_cola() returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if exists (select 1 from public.cola_push where tomado_at is null) then perform privado.llamar_funcion('{}'::jsonb); end if;
  delete from public.cola_push where tomado_at < now() - interval '2 days';
end $$;

create or replace function privado.tarea_horaria() returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare ahora timestamp := now() at time zone 'America/Santiago'; hoy date := ahora::date; h int := extract(hour from ahora); r record; c record;
  v_txt text; n_hoy int; n_atr int; m_atr bigint; dias int; ok boolean;
begin
  -- 1) Diaria (desde las 00:00): vencimientos, planes, limpieza
  if not exists (select 1 from privado.tareas_hechas where tarea = 'diaria' and fecha = hoy) then
    insert into privado.tareas_hechas values ('diaria', hoy);
    for c in select id from public.clientes where estado <> 'borrado' and saldo > 0 and prox_venc < hoy and not atrasado loop
      perform privado.recalcular(c.id);
    end loop;
    for r in select id from public.negocios where estado <> 'eliminado' loop perform privado.aplicar_plan(r.id); end loop;
    for r in select id, dueno from public.negocios where estado = 'eliminado' and eliminar_desde < now() loop
      insert into privado.archivos_por_borrar (bucket, ruta) select 'comprobantes', foto_path from public.comprobantes where negocio = r.id and foto_path is not null;
      insert into privado.archivos_por_borrar (bucket, ruta) select 'pagos', comprobante_path from public.solicitudes_pago where negocio = r.id and comprobante_path is not null;
      delete from public.negocios where id = r.id;
      delete from auth.users where id = r.dueno;
    end loop;
    delete from public.sesiones_cliente where vence < now();
    delete from privado.limites where ventana < floor(extract(epoch from now()) / 86400) - 2 and ventana < floor(extract(epoch from now()) / 3600) - 48;
    delete from public.invitaciones where vence < now() - interval '7 days';
    delete from privado.fotos_pendientes where vence < now();
    delete from public.notificaciones where creado < now() - interval '90 days';
    delete from privado.tareas_hechas where fecha < hoy - 30;
  end if;

  -- 2) Resumen de las 09:00 y avisos de plan
  if h >= 9 and not exists (select 1 from privado.tareas_hechas where tarea = 'resumen' and fecha = hoy) then
    insert into privado.tareas_hechas values ('resumen', hoy);
    for r in select n.id, n.premium_hasta, n.en_prueba, privado.es_premium(n.id) prem from public.negocios n where n.estado = 'activo' loop
      select count(*) filter (where prox_venc = hoy), count(*) filter (where atrasado), coalesce(sum(saldo) filter (where atrasado), 0)
        into n_hoy, n_atr, m_atr from public.clientes where negocio = r.id and saldo > 0 and estado <> 'borrado';
      if n_hoy + n_atr > 0 then
        v_txt := concat_ws(' · ', case when n_hoy > 0 then n_hoy || ' vencen hoy' end,
                                  case when n_atr > 0 then n_atr || ' atrasados por ' || privado.pesos(m_atr) end);
        perform privado.avisar_negocio(r.id, 'Para cobrar hoy', v_txt, 'app/', r.prem);
      end if;
      if r.premium_hasta is not null then
        dias := (r.premium_hasta at time zone 'America/Santiago')::date - hoy;
        if r.en_prueba and dias in (4, 1) then
          perform privado.avisar_negocio(r.id, 'Te quedan ' || dias || ' días de Premium', 'Después tu libreta pasa a Normal (no se borra nada). Hazte Premium para seguir con todo.', 'app/#plan', true);
        elsif not r.en_prueba and dias in (7, 3, 1, 0) then
          perform privado.avisar_negocio(r.id, case when dias = 0 then 'Tu Premium vence hoy' else 'Tu Premium vence en ' || dias || ' días' end,
            'Renueva desde Más → Mi plan para no perder nada.', 'app/#plan', true);
        elsif not r.en_prueba and dias < 0 and r.prem then
          perform privado.avisar_negocio(r.id, 'Premium vencido: estás en días de gracia', 'Renueva para no pasar al plan Normal.', 'app/#plan', true);
        end if;
      end if;
    end loop;
  end if;

  -- 3) Avisos automáticos de cuotas (Premium), lunes a sábado desde las 10:00, sin feriados
  if h >= 10 and h < 20 and extract(isodow from ahora) < 7 and not exists (select 1 from public.feriados where fecha = hoy)
     and not exists (select 1 from privado.tareas_hechas where tarea = 'cuotas' and fecha = hoy) then
    insert into privado.tareas_hechas values ('cuotas', hoy);
    for c in select cl.id, cl.negocio, cl.saldo, cl.prox_venc, cl.atrasado, n.nombre from public.clientes cl join public.negocios n on n.id = cl.negocio
       where n.estado = 'activo' and cl.saldo > 0 and cl.estado <> 'borrado' and (cl.prox_venc = hoy + 1 or cl.atrasado)
         and exists (select 1 from public.ventas_cuotas v where v.cliente = cl.id and v.estado = 'activa')
         and exists (select 1 from public.push_subs s where s.cliente = cl.id) and privado.es_premium(n.id) loop
      select (privado.cobro_permitido(c.id)).ok into ok;
      if ok then
        insert into public.recordatorios (negocio, cliente, canal, tono) values (c.negocio, c.id, 'push', 'auto');
        perform privado.push(null, null, c.id, c.nombre || ': ' || case when c.atrasado then 'cuota atrasada' else 'tu cuota vence mañana' end,
          'Saldo pendiente: ' || privado.pesos(c.saldo) || '. Toca para ver los datos de transferencia.', 'c/');
      end if;
    end loop;
  end if;

  -- 4) Semanal (domingo desde las 03:00): fotos viejas, verificar saldos
  if extract(isodow from ahora) = 7 and h >= 3 and not exists (select 1 from privado.tareas_hechas where tarea = 'semanal' and fecha = hoy) then
    insert into privado.tareas_hechas values ('semanal', hoy);
    insert into privado.archivos_por_borrar (bucket, ruta)
      select 'comprobantes', foto_path from public.comprobantes where foto_path is not null and estado <> 'pendiente' and revisado_at < now() - interval '90 days';
    update public.comprobantes set foto_path = null where foto_path is not null and estado <> 'pendiente' and revisado_at < now() - interval '90 days';
    for c in select id from public.clientes where estado <> 'borrado' loop perform privado.recalcular(c.id); end loop;
    perform privado.llamar_funcion('{"accion": "limpiar"}'::jsonb);
  end if;
end $$;

-- =====================================================================
--  CUENTAS NUEVAS (disparador en auth.users)
-- =====================================================================
create or replace function privado.nuevo_usuario() returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into public.perfiles (id, nombre) values (new.id, left(coalesce(new.raw_user_meta_data ->> 'nombre', ''), 60)) on conflict do nothing;
  return new;
exception when others then return new;
end $$;
drop trigger if exists lc_nuevo_usuario on auth.users;
create trigger lc_nuevo_usuario after insert on auth.users for each row execute function privado.nuevo_usuario();

-- =====================================================================
--  PERMISOS (RLS): cada negocio ve solo lo suyo; nadie escribe directo
-- =====================================================================
do $$ declare t text; begin
  foreach t in array array['ajustes','perfiles','negocios','miembros','invitaciones','clientes','ventas_cuotas','cuotas','movimientos',
    'comprobantes','recordatorios','productos','uso_mensual','notificaciones','sesiones_cliente','push_subs','cola_push','solicitudes_pago',
    'keys','feriados','auditoria'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;
alter table privado.config enable row level security;
alter table privado.secretos enable row level security;

do $$ declare p record; begin
  for p in select policyname, tablename from pg_policies where schemaname = 'public' loop
    execute format('drop policy if exists %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

create policy lectura on public.ajustes for select to authenticated using (true);
create policy lectura on public.feriados for select to authenticated using (true);
create policy lectura on public.perfiles for select to authenticated using (id = auth.uid());
create policy lectura on public.negocios for select to authenticated using (id = (select privado.mi_negocio()) or (select privado.es_admin()));
create policy lectura on public.miembros for select to authenticated using (negocio = (select privado.mi_negocio()));
create policy lectura on public.clientes for select to authenticated using (negocio = (select privado.mi_negocio()));
create policy lectura on public.ventas_cuotas for select to authenticated using (negocio = (select privado.mi_negocio()));
create policy lectura on public.cuotas for select to authenticated using (exists (select 1 from public.ventas_cuotas v where v.id = venta and v.negocio = (select privado.mi_negocio())));
create policy lectura on public.movimientos for select to authenticated using (negocio = (select privado.mi_negocio())
  and ((select privado.mi_premium()) or fecha > now() - interval '6 months'));
create policy lectura on public.comprobantes for select to authenticated using (negocio = (select privado.mi_negocio()));
create policy lectura on public.recordatorios for select to authenticated using (negocio = (select privado.mi_negocio()));
create policy lectura on public.productos for select to authenticated using (negocio = (select privado.mi_negocio()));
create policy lectura on public.uso_mensual for select to authenticated using (negocio = (select privado.mi_negocio()) or (select privado.es_admin()));
create policy lectura on public.notificaciones for select to authenticated using (usuario = auth.uid() or negocio = (select privado.mi_negocio()));
create policy lectura on public.solicitudes_pago for select to authenticated using ((negocio = (select privado.mi_negocio()) and (select privado.mi_rol()) = 'dueno') or (select privado.es_admin()));
create policy lectura on public.auditoria for select to authenticated using (negocio = (select privado.mi_negocio()) and (select privado.mi_rol()) = 'dueno');

grant usage on schema public to anon, authenticated, service_role;
grant select (id, dueno, nombre, rubro, whatsapp, banco, venc_defecto, limite_general, pin_activo, saldo_a_favor, logo_url, color,
  plantilla_propia, premium_hasta, en_prueba, plan_aplicado, estado, motivo_suspension, eliminar_desde, ultimo_uso, creado) on public.negocios to authenticated;
grant select on public.ajustes, public.feriados, public.perfiles, public.miembros, public.ventas_cuotas, public.cuotas,
  public.movimientos, public.recordatorios, public.productos, public.uso_mensual, public.notificaciones, public.solicitudes_pago,
  public.auditoria to authenticated;
grant select (id, negocio, nombre, apodo, telefono, rut, nota, limite, estado, bloqueado, fuera_de_plan, saldo, prox_venc, atrasado, puntaje,
  ultimo_mov, link_codigo, link_bloqueado, creado) on public.clientes to authenticated;
grant select (id, negocio, cliente, monto, fecha, comentario, foto_path, estado, motivo, abono, revisado_at, creado) on public.comprobantes to authenticated;
grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;

-- Funciones: nadie las puede llamar salvo las que se autorizan abajo
revoke all on all functions in schema public from public, anon, authenticated;
revoke all on all functions in schema privado from public, anon, authenticated;
grant execute on function privado.mi_negocio(), privado.mi_rol(), privado.mi_premium(), privado.es_admin(), privado.es_premium(uuid) to authenticated;
grant execute on function public.ping(), public.config_publica(), public.portal_info(text), public.portal_entrar(text, text), public.portal_ver(text),
  public.portal_confirmar(text, uuid, boolean, text), public.portal_comprobante(text, int, date, text, boolean),
  public.portal_push(text, text, text, text), public.portal_salir(text) to anon, authenticated;
grant execute on function public.mi_estado(), public.aceptar_terminos(), public.crear_negocio(text, text, boolean), public.guardar_negocio(jsonb),
  public.crear_cliente(text, text, text, text, text, int, text, int, boolean, boolean), public.editar_cliente(uuid, text, text, text, text, text, int),
  public.estado_cliente(uuid, text), public.borrar_cliente(uuid, text), public.link_cliente(uuid, boolean, text),
  public.registrar_movimiento(uuid, uuid, text, int, text, text, timestamptz, date, int, boolean, boolean), public.anular_movimiento(uuid, text),
  public.crear_venta_cuotas(uuid, uuid, text, int, int, int, text, date, boolean), public.anular_venta_cuotas(uuid, text),
  public.responder_reclamo(uuid, boolean, text), public.puede_cobrar(uuid), public.registrar_recordatorio(uuid, text, text, text),
  public.revisar_comprobante(uuid, boolean, int, text), public.guardar_producto(uuid, text, int), public.borrar_producto(uuid),
  public.ordenar_productos(uuid[]), public.invitar_ayudante(), public.aceptar_invitacion(text, text), public.quitar_ayudante(uuid),
  public.ayudantes(), public.usar_key(text), public.solicitar_pago(int, text, text), public.marcar_leidas(),
  public.guardar_push(text, text, text), public.borrar_push(text), public.tablero(), public.reporte(date, date), public.exportar_datos(),
  public.borrar_mi_cuenta(text), public.recuperar_mi_cuenta(),
  public.admin_resumen(), public.admin_negocios(text, text), public.admin_plan(uuid, text, int), public.admin_estado(uuid, boolean, text, text),
  public.admin_pagos(), public.admin_resolver_pago(uuid, boolean, text), public.admin_crear_keys(int, int, int), public.admin_keys(),
  public.admin_revocar_key(text), public.admin_aviso(text, uuid, text, text), public.admin_guardar_ajustes(jsonb),
  public.admin_set_secret(text, text), public.admin_feriado(date, text, boolean) to authenticated;
grant execute on function public.srv_secretos(), public.srv_cola_tomar(int), public.srv_quitar_endpoint(text), public.srv_foto_validar(uuid, text),
  public.srv_foto_lista(uuid, text), public.srv_archivos_por_borrar(int), public.srv_archivos_borrados(bigint[]) to service_role;

-- =====================================================================
--  ARCHIVOS (Storage)
-- =====================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('comprobantes', 'comprobantes', false, 1048576, array['image/webp','image/jpeg','image/png']),
  ('logos', 'logos', true, 102400, array['image/webp','image/png','image/jpeg']),
  ('pagos', 'pagos', false, 1048576, array['image/webp','image/jpeg','image/png'])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists lc_comprobantes_ver on storage.objects;
drop policy if exists lc_logos_subir on storage.objects;
drop policy if exists lc_logos_cambiar on storage.objects;
drop policy if exists lc_logos_borrar on storage.objects;
drop policy if exists lc_logos_ver on storage.objects;
drop policy if exists lc_pagos_subir on storage.objects;
drop policy if exists lc_pagos_ver on storage.objects;
create policy lc_comprobantes_ver on storage.objects for select to authenticated
  using (bucket_id = 'comprobantes' and (storage.foldername(name))[1] = (select privado.mi_negocio())::text);
create policy lc_logos_ver on storage.objects for select to authenticated
  using (bucket_id = 'logos' and (storage.foldername(name))[1] = (select privado.mi_negocio())::text);
create policy lc_logos_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'logos' and (storage.foldername(name))[1] = (select privado.mi_negocio())::text
    and (select privado.mi_rol()) = 'dueno' and (select privado.mi_premium()));
create policy lc_logos_cambiar on storage.objects for update to authenticated
  using (bucket_id = 'logos' and (storage.foldername(name))[1] = (select privado.mi_negocio())::text and (select privado.mi_rol()) = 'dueno');
create policy lc_logos_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'logos' and (storage.foldername(name))[1] = (select privado.mi_negocio())::text and (select privado.mi_rol()) = 'dueno');
create policy lc_pagos_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'pagos' and (storage.foldername(name))[1] = (select privado.mi_negocio())::text and (select privado.mi_rol()) = 'dueno');
create policy lc_pagos_ver on storage.objects for select to authenticated
  using (bucket_id = 'pagos' and ((storage.foldername(name))[1] = (select privado.mi_negocio())::text or (select privado.es_admin())));

-- =====================================================================
--  TIEMPO REAL Y TAREAS PROGRAMADAS
-- =====================================================================
do $$ declare t text; begin
  foreach t in array array['movimientos','notificaciones'] loop
    begin execute format('alter publication supabase_realtime add table public.%I', t);
    exception when others then null; end;
  end loop;
end $$;

do $$ begin
  perform cron.unschedule(jobid) from cron.job where jobname in ('lc-cola', 'lc-hora');
  perform cron.schedule('lc-cola', '* * * * *', 'select privado.tarea_cola()');
  perform cron.schedule('lc-hora', '7 * * * *', 'select privado.tarea_horaria()');
exception when others then raise notice 'cron: %', sqlerrm;
end $$;

select 'Libreta instalada v' || (select valor from privado.config where clave = 'version_bd') as resultado;
