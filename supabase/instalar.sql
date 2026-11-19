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
  ('version_bd', '74'),
  ('admin_email', 'juanjosuecastilloloyola@gmail.com'),
  ('url_proyecto', 'https://zbgfvxsqajtixjzxoxeu.supabase.co'),
  ('zona', 'America/Santiago'),
  ('anon_key', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpiZ2Z2eHNxYWp0aXhqenhveGV1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE3NDQ0NzUsImV4cCI6MjEwNzMyMDQ3NX0._JyVta9bPzX56iHb-e9lcdy6-NTm16WGaqEZAGbszGE')
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
alter table public.ajustes add column if not exists version_liberada text not null default '1.0.0';

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

-- ---------- v3: prueba de 7 días + bloqueo, activación, caja (ingresos y gastos), soporte, billetera personal ----------
alter table public.negocios add column if not exists prueba_hasta timestamptz;
alter table public.negocios add column if not exists activado boolean not null default false;
alter table public.ajustes add column if not exists precio_activacion int not null default 10000;
alter table public.uso_mensual add column if not exists caja int not null default 0;
alter table public.negocios drop constraint if exists negocios_plan_aplicado_check;
alter table public.negocios add constraint negocios_plan_aplicado_check check (plan_aplicado in ('normal','premium','bloqueado'));
do $$ begin
  if not exists (select 1 from privado.config where clave = 'migracion_v3') then
    update public.negocios set prueba_hasta = premium_hasta, premium_hasta = null, en_prueba = false, plan_aplicado = 'normal' where en_prueba;
    update public.negocios set prueba_hasta = creado + interval '7 days' where prueba_hasta is null;
    update public.ajustes set dias_prueba = 7,
      lim_normal = lim_normal || '{"caja":300,"categorias":5}'::jsonb,
      lim_premium = lim_premium || '{"ayudantes":0,"categorias":50}'::jsonb where id = 1;
    delete from public.miembros where rol = 'ayudante';
    insert into privado.config values ('migracion_v3', '1');
  end if;
end $$;

create table if not exists public.caja (
  id uuid primary key,
  negocio uuid not null references public.negocios (id) on delete cascade,
  tipo text not null check (tipo in ('ingreso','gasto')),
  monto int not null check (monto between 1 and 99999999),
  categoria text not null check (char_length(categoria) between 2 and 24),
  descripcion text check (descripcion is null or char_length(descripcion) <= 120),
  medio text not null default 'efectivo' check (medio in ('efectivo','transferencia','tarjeta','otro')),
  fecha timestamptz not null default now(),
  creado_por uuid,
  creado_at timestamptz not null default now(),
  anulado_at timestamptz,
  anulado_por uuid,
  motivo_anulacion text
);
create index if not exists caja_neg on public.caja (negocio, fecha desc);

create table if not exists public.categorias (
  id uuid primary key default gen_random_uuid(),
  negocio uuid not null references public.negocios (id) on delete cascade,
  tipo text not null check (tipo in ('ingreso','gasto')),
  nombre text not null check (char_length(nombre) between 2 and 24),
  creado timestamptz not null default now()
);
create unique index if not exists categorias_unica on public.categorias (negocio, tipo, lower(nombre));

alter table public.negocios add column if not exists quiere_pro_at timestamptz;
alter table public.negocios add column if not exists meta_ventas int check (meta_ventas is null or meta_ventas between 0 and 999999999);
alter table public.negocios add column if not exists presupuesto_gastos int check (presupuesto_gastos is null or presupuesto_gastos between 0 and 999999999);

create table if not exists public.soporte (
  id bigserial primary key,
  negocio uuid not null references public.negocios (id) on delete cascade,
  de text not null check (de in ('negocio','admin')),
  texto text not null check (char_length(texto) between 1 and 1000),
  leido boolean not null default false,
  creado timestamptz not null default now()
);
create index if not exists soporte_neg on public.soporte (negocio, creado);

-- ---------- v5: Pro de prueba que pasa a Free (sin bloqueo), cupones, ícono y color de perfil ----------
alter table public.negocios add column if not exists icono text check (icono is null or char_length(icono) between 1 and 16);
alter table public.negocios add column if not exists cupon text;
alter table public.solicitudes_pago add column if not exists cupon text;
create table if not exists public.cupones (
  codigo text primary key check (codigo ~ '^[A-Z0-9-]{3,20}$'),
  descuento int not null check (descuento between 1 and 100),
  usos_max int check (usos_max is null or usos_max between 1 and 100000),
  usos int not null default 0,
  vence date,
  activo boolean not null default true,
  creado timestamptz not null default now()
);
do $$ begin
  if not exists (select 1 from privado.config where clave = 'migracion_v5') then
    -- Las billeteras bloqueadas pasan a Free: se marcan como 'premium' para que aplicar_plan les baje el plan con aviso.
    update public.negocios set plan_aplicado = 'premium' where plan_aplicado = 'bloqueado';
    update public.negocios set plan_aplicado = 'premium' where plan_aplicado = 'normal' and prueba_hasta > now();
    update public.negocios set color = null where color is not null and color !~ '^#[0-9a-f]{6}$';
    insert into privado.config values ('migracion_v5', '1');
  end if;
end $$;

-- ---------- v6: link de pago (general del negocio y uno propio por cliente) ----------
alter table public.negocios add column if not exists link_pago text check (link_pago is null or (char_length(link_pago) <= 300 and link_pago ~ '^https://'));
alter table public.clientes add column if not exists link_pago text check (link_pago is null or (char_length(link_pago) <= 300 and link_pago ~ '^https://'));

-- ---------- v7: pago de fiados con comprobante y billeteras conectadas (Pro) ----------
alter table public.movimientos add column if not exists foto_path text check (foto_path is null or char_length(foto_path) <= 200);
alter table public.negocios add column if not exists codigo_conexion text;
create unique index if not exists negocios_codigo_conexion on public.negocios (codigo_conexion);
alter table public.negocios add column if not exists conexiones_extra int not null default 0 check (conexiones_extra between 0 and 200);
alter table public.ajustes add column if not exists conexiones_incluidas int not null default 10 check (conexiones_incluidas between 0 and 1000);
alter table public.ajustes add column if not exists conexiones_paquete int not null default 5 check (conexiones_paquete between 1 and 100);
alter table public.ajustes add column if not exists precio_paquete int not null default 2000 check (precio_paquete between 0 and 1000000);
alter table public.solicitudes_pago add column if not exists tipo text not null default 'pro' check (tipo in ('pro','conexiones'));
alter table public.solicitudes_pago add column if not exists paquetes int not null default 0 check (paquetes between 0 and 50);

-- ---------- v8: todo administrable (textos, planes, reglas, 2 espacios de links de pago) ----------
alter table public.ajustes add column if not exists textos jsonb not null default '{}'::jsonb;
alter table public.ajustes add column if not exists planes jsonb not null default '{}'::jsonb;
alter table public.ajustes add column if not exists links_pro jsonb not null default '[]'::jsonb;
alter table public.ajustes add column if not exists dias_comprobantes int not null default 30 check (dias_comprobantes between 7 and 365);
alter table public.ajustes add column if not exists dias_aviso int not null default 7 check (dias_aviso between 1 and 30);
alter table public.negocios add column if not exists links_pago jsonb not null default '[]'::jsonb;
do $$ begin
  if not exists (select 1 from privado.config where clave = 'migracion_v8') then
    update public.ajustes set links_pro = jsonb_build_array(jsonb_build_object('texto', 'Mercado Pago', 'url', link_pago, 'activo', true),
      jsonb_build_object('texto', '', 'url', '', 'activo', false)) where id = 1 and links_pro = '[]'::jsonb;
    update public.negocios set links_pago = jsonb_build_array(jsonb_build_object('texto', 'Mercado Pago', 'url', link_pago, 'activo', true),
      jsonb_build_object('texto', '', 'url', '', 'activo', false)) where link_pago is not null and links_pago = '[]'::jsonb;
    insert into privado.config values ('migracion_v8', '1');
  end if;
end $$;

-- ---------- v10: link de pago propio para el plan anual (el mensual sigue en los 2 espacios) ----------
alter table public.ajustes add column if not exists link_pago_anual text not null default ''
  check (link_pago_anual = '' or (char_length(link_pago_anual) <= 300 and link_pago_anual ~ '^https://'));

-- ---------- v9: plan anual e "Invita y gana" (referidos) ----------
alter table public.negocios add column if not exists codigo_ref text;
create unique index if not exists negocios_codigo_ref on public.negocios (codigo_ref);
alter table public.negocios add column if not exists referido_por uuid references public.negocios (id) on delete set null;
alter table public.negocios add column if not exists ref_revisado_at timestamptz;
alter table public.negocios add column if not exists ref_dias int not null default 0 check (ref_dias between 0 and 90);
create index if not exists negocios_referido_por on public.negocios (referido_por) where referido_por is not null;
alter table public.ajustes add column if not exists dias_referido int not null default 15 check (dias_referido between 0 and 90);
alter table public.ajustes add column if not exists ref_min_registros int not null default 10 check (ref_min_registros between 1 and 1000);
alter table public.ajustes add column if not exists ref_max_premios int not null default 12 check (ref_max_premios between 0 and 1000);
do $$ begin
  if not exists (select 1 from privado.config where clave = 'migracion_v9') then
    -- Términos nuevos (conexiones, links de pago, comprobantes, plan anual y referidos): todos los aceptan de nuevo.
    update public.ajustes set version_legal = version_legal + 1 where id = 1;
    insert into privado.config values ('migracion_v9', '1');
  end if;
end $$;

-- Conexión entre dos billeteras (siempre a < b). Cada una solo ve el nombre y el ícono de la otra, y la cuenta entre ambas.
create table if not exists public.conexiones (
  id uuid primary key default gen_random_uuid(),
  a uuid not null references public.negocios (id) on delete cascade,
  b uuid not null references public.negocios (id) on delete cascade,
  estado text not null default 'pendiente' check (estado in ('pendiente','activa','rechazada','cerrada')),
  solicitada_por uuid not null references public.negocios (id) on delete cascade,
  creado timestamptz not null default now(),
  aceptada_at timestamptz,
  check (a < b),
  unique (a, b)
);
create index if not exists conexiones_b on public.conexiones (b);

-- "Te presté" o "te pagué" dentro de una conexión. Cuenta solo cuando el otro lo confirma.
create table if not exists public.conexion_movs (
  id uuid primary key,
  conexion uuid not null references public.conexiones (id) on delete cascade,
  autor uuid not null references public.negocios (id) on delete cascade,
  tipo text not null check (tipo in ('presto','pago')),
  monto int not null check (monto between 1 and 99999999),
  descripcion text check (descripcion is null or char_length(descripcion) <= 120),
  estado text not null default 'pendiente' check (estado in ('pendiente','confirmado','rechazado','anulado')),
  motivo text check (motivo is null or char_length(motivo) <= 150),
  creado timestamptz not null default now(),
  resuelto_at timestamptz
);
create index if not exists conexion_movs_con on public.conexion_movs (conexion, creado desc);

-- =====================================================================
--  AYUDANTES INTERNOS (esquema privado: no se pueden llamar desde la app)
-- =====================================================================
create or replace function privado.hoy() returns date language sql stable as
  $$ select (now() at time zone 'America/Santiago')::date $$;

create or replace function privado.colores() returns text[] language sql immutable as $$
  select array['#059669','#2563eb','#4f46e5','#7c3aed','#db2777','#e11d48','#ea580c','#d97706','#0d9488','#0284c7','#92400e','#334155']
$$;

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
create or replace function privado.es_admin() returns boolean language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  -- Administrador o socio (núcleo: cfx_socios, se agregan desde el Centro de Mando). Sin sesión no se llega a cfx_es_socio.
  if auth.uid() is null then return false; end if;
  return auth.uid()::text = (select valor from privado.config where clave = 'admin_id') or public.cfx_es_socio();
end $$;

create or replace function privado.fijar_admin() returns text language plpgsql security definer set search_path = public, pg_temp as $$
declare v uuid;
begin
  select id into v from auth.users where lower(email) = (select valor from privado.config where clave = 'admin_email') and email_confirmed_at is not null
   order by created_at limit 1;
  if v is null then return 'ERROR: primero crea el usuario ' || (select valor from privado.config where clave = 'admin_email') || ' en Authentication → Users (con Auto Confirm User).'; end if;
  insert into privado.config values ('admin_id', v::text) on conflict (clave) do update set valor = excluded.valor;
  return 'Administrador fijado ✓ (' || v || ')';
end $$;

-- Pro pagado (o regalado por el admin), con los días de gracia.
create or replace function privado.pagado(p_neg uuid) returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select n.premium_hasta + make_interval(days => case when n.en_prueba then 0 else a.dias_gracia end) > now()
    from public.negocios n, public.ajustes a where n.id = p_neg and a.id = 1), false)
$$;

-- ¿Tiene las funciones Pro? Sí si pagó o si está en sus días de prueba (la prueba es Pro completo).
create or replace function privado.es_premium(p_neg uuid) returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select privado.pagado(p_neg) or coalesce((select prueba_hasta > now() from public.negocios where id = p_neg), false)
$$;

-- 'pro' (pagado o regalado), 'prueba' (Pro gratis los primeros días) o 'free' (sigue usando su billetera con las funciones básicas).
create or replace function privado.estado_plan(p_neg uuid) returns text language sql stable security definer set search_path = public, pg_temp as $$
  select case when privado.pagado(p_neg) then 'pro'
    when (select prueba_hasta from public.negocios where id = p_neg) > now() then 'prueba' else 'free' end
$$;

create or replace function privado.admin_id() returns uuid language sql stable security definer set search_path = public, pg_temp as
  $$ select nullif((select valor from privado.config where clave = 'admin_id'), '')::uuid $$;

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
drop function if exists privado.exigir(boolean);
create or replace function privado.exigir(p_dueno boolean default false, p_lectura boolean default false) returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
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

-- ---------- v7: pago de un fiado (todo o una parte), con foto del comprobante opcional ----------
-- Cuánto lleva pagado cada fiado (los pagos cubren primero lo más antiguo, igual que el saldo).
create or replace function public.estado_fiados(p_cliente uuid) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(false, true); credito bigint; r record; pag bigint; v_out jsonb := '[]'::jsonb;
begin
  if not exists (select 1 from public.clientes where id = p_cliente and negocio = v_neg) then perform privado.fallo('Cliente no encontrado'); end if;
  select coalesce(sum(monto), 0) into credito from public.movimientos where cliente = p_cliente and anulado_at is null and signo = -1;
  for r in
    select 'm'::text k, m.id, 0 num, m.monto::bigint monto, coalesce(m.vence, (m.fecha at time zone 'America/Santiago')::date) due, m.fecha ord
      from public.movimientos m
     where m.cliente = p_cliente and m.anulado_at is null and m.signo = 1 and m.venta is null
    union all
    select 'c', c.venta, c.numero, c.monto, c.vence, vc.creado
      from public.cuotas c join public.ventas_cuotas vc on vc.id = c.venta
     where vc.cliente = p_cliente and vc.estado <> 'anulada'
    order by due, ord, num
  loop
    pag := least(r.monto, credito); credito := credito - pag;
    if r.k = 'm' then v_out := v_out || jsonb_build_object('id', r.id, 'monto', r.monto, 'pagado', pag, 'vence', r.due); end if;
  end loop;
  return v_out;
end $$;

-- Vista previa (p_confirmar = false) o pago de un fiado. p_monto vacío = paga todo lo que falta para dejarlo al día.
create or replace function public.pagar_fiado(p_id uuid, p_mov uuid, p_monto int, p_medio text, p_foto text, p_confirmar boolean) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(); f record; r record; credito bigint; hasta bigint := 0; v_total bigint; v_pend bigint; v_monto bigint; v_res jsonb;
begin
  select * into f from public.movimientos where id = p_mov and negocio = v_neg and signo = 1 and venta is null and anulado_at is null;
  if not found then perform privado.fallo('Fiado no encontrado'); end if;
  select coalesce(sum(monto), 0) into credito from public.movimientos where cliente = f.cliente and anulado_at is null and signo = -1;
  for r in
    select 'm'::text k, m.id, 0 num, m.monto::bigint monto, coalesce(m.vence, (m.fecha at time zone 'America/Santiago')::date) due, m.fecha ord
      from public.movimientos m
     where m.cliente = f.cliente and m.anulado_at is null and m.signo = 1 and m.venta is null
    union all
    select 'c', c.venta, c.numero, c.monto, c.vence, vc.creado
      from public.cuotas c join public.ventas_cuotas vc on vc.id = c.venta
     where vc.cliente = f.cliente and vc.estado <> 'anulada'
    order by due, ord, num
  loop
    hasta := hasta + r.monto;
    exit when r.k = 'm' and r.id = p_mov;
  end loop;
  v_total := hasta - credito;
  if v_total <= 0 then perform privado.fallo('Este fiado ya está pagado'); end if;
  v_pend := least(f.monto, v_total);
  if not coalesce(p_confirmar, false) then
    return jsonb_build_object('ok', false, 'total', v_total, 'pendiente', v_pend, 'previo', v_total - v_pend, 'monto', f.monto);
  end if;
  v_monto := coalesce(p_monto, v_total);
  if v_monto < 1 or v_monto > v_total then perform privado.fallo('El monto debe ser entre $1 y ' || privado.pesos(v_total::int)); end if;
  if coalesce(p_medio, '') not in ('efectivo', 'transferencia', 'otro') then perform privado.fallo('Medio de pago inválido'); end if;
  if p_foto is not null and p_foto not like v_neg || '/pagos/%' then perform privado.fallo('Archivo inválido'); end if;
  v_res := privado.mov_insertar(v_neg, p_id, f.cliente, 'abono', v_monto::int, null,
    'Pago de ' || coalesce(f.descripcion, 'fiado del ' || to_char(f.fecha at time zone 'America/Santiago', 'DD/MM'))
      || case when v_monto < v_total then ' (abono)' else '' end || case when p_medio = 'otro' then ' · link de pago' else '' end,
    p_medio, null, null, null, false, true);
  if p_foto is not null then update public.movimientos set foto_path = p_foto where id = p_id and negocio = v_neg; end if;
  return v_res || jsonb_build_object('monto', v_monto, 'al_dia', v_monto = v_total);
end $$;

-- Adjuntar la foto del comprobante a un abono ya anotado
create or replace function public.adjuntar_foto(p_mov uuid, p_foto text) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir();
begin
  if p_foto is null or p_foto not like v_neg || '/pagos/%' then perform privado.fallo('Archivo inválido'); end if;
  update public.movimientos set foto_path = p_foto where id = p_mov and negocio = v_neg and signo = -1 and anulado_at is null;
  if not found then perform privado.fallo('Abono no encontrado'); end if;
end $$;

-- ---------- v7: billeteras conectadas (Pro) ----------
create or replace function privado.limite_conexiones(p_neg uuid) returns int language sql stable security definer set search_path = public, pg_temp as $$
  select a.conexiones_incluidas + n.conexiones_extra * a.conexiones_paquete from public.ajustes a, public.negocios n where a.id = 1 and n.id = p_neg
$$;
-- Usadas: conexiones activas + solicitudes que yo envié y siguen pendientes.
create or replace function privado.conexiones_usadas(p_neg uuid) returns int language sql stable security definer set search_path = public, pg_temp as $$
  select count(*)::int from public.conexiones where (a = p_neg or b = p_neg) and (estado = 'activa' or (estado = 'pendiente' and solicitada_por = p_neg))
$$;
-- Saldo de una conexión visto por p_neg: positivo = el otro le debe a p_neg. Toda plata que entrego (préstamo o pago) suma.
create or replace function privado.saldo_conexion(p_con uuid, p_neg uuid) returns bigint language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(sum(case when autor = p_neg then monto else -monto end), 0) from public.conexion_movs where conexion = p_con and estado = 'confirmado'
$$;

create or replace function public.mi_codigo_conexion(p_nuevo boolean) returns text language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true, true); v text; i int := 0;
begin
  if not privado.es_premium(v_neg) then perform privado.fallo('Las billeteras conectadas son Pro.', 'PLAN'); end if;
  select codigo_conexion into v from public.negocios where id = v_neg;
  if v is null or coalesce(p_nuevo, false) then
    perform privado.limitar('codcon:' || v_neg, 20, 86400);
    loop
      v := upper(translate(privado.codigo(8), 'abcdefghijkmnopqrstuvwxyzL', 'ABCDEFGHJKMNPQRSTUVWXYZ234'));
      exit when not exists (select 1 from public.negocios where codigo_conexion = v);
      i := i + 1; if i > 20 then perform privado.fallo('No se pudo generar el código. Intenta de nuevo.'); end if;
    end loop;
    update public.negocios set codigo_conexion = v where id = v_neg;
  end if;
  return v;
end $$;

create or replace function public.conectar(p_codigo text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true); v_cod text := upper(regexp_replace(coalesce(p_codigo, ''), '[^A-Za-z0-9]', '', 'g')); o record; c record; yo text; existe boolean;
begin
  if not privado.es_premium(v_neg) then perform privado.fallo('Las billeteras conectadas son Pro.', 'PLAN'); end if;
  perform privado.limitar('conectar:' || v_neg, 10, 3600);
  select id, nombre, estado into o from public.negocios where codigo_conexion = v_cod and v_cod <> '';
  if not found or o.estado <> 'activo' then perform privado.fallo('No encontramos ese código. Revísalo con la otra persona.'); end if;
  if o.id = v_neg then perform privado.fallo('Ese es tu propio código: compártelo con la otra persona.'); end if;
  select * into c from public.conexiones where a = least(v_neg, o.id) and b = greatest(v_neg, o.id);
  existe := found;
  if existe and c.estado = 'activa' then perform privado.fallo('Ya están conectados.'); end if;
  if existe and c.estado = 'pendiente' and c.solicitada_por = v_neg then perform privado.fallo('Ya le enviaste la solicitud. Falta que la acepte.'); end if;
  if privado.conexiones_usadas(v_neg) >= privado.limite_conexiones(v_neg) then
    perform privado.fallo('Llegaste a tus ' || privado.limite_conexiones(v_neg) || ' conexiones. Suma más en Conexiones → "Más conexiones".');
  end if;
  select nombre into yo from public.negocios where id = v_neg;
  if existe and c.estado = 'pendiente' then
    -- La otra persona ya me había enviado la solicitud: con mi código queda conectada.
    update public.conexiones set estado = 'activa', aceptada_at = now() where id = c.id;
    perform privado.avisar_negocio(o.id, '🤝 Conexión lista', yo || ' aceptó conectar su billetera contigo.', 'app/#conexion/' || c.id, true);
    return jsonb_build_object('ok', true, 'estado', 'activa', 'id', c.id, 'nombre', o.nombre);
  end if;
  if existe then
    update public.conexiones set estado = 'pendiente', solicitada_por = v_neg, creado = now(), aceptada_at = null where id = c.id;
  else
    insert into public.conexiones (a, b, solicitada_por) values (least(v_neg, o.id), greatest(v_neg, o.id), v_neg) returning * into c;
  end if;
  perform privado.avisar_negocio(o.id, '🤝 Solicitud de conexión', yo || ' quiere conectar su billetera contigo para llevar las cuentas entre ustedes.', 'app/#conexiones', true);
  return jsonb_build_object('ok', true, 'estado', 'pendiente', 'id', c.id, 'nombre', o.nombre);
end $$;

create or replace function public.conexion_responder(p_id uuid, p_aceptar boolean) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true); c record; otro uuid; yo text;
begin
  select * into c from public.conexiones where id = p_id and (a = v_neg or b = v_neg) for update;
  if not found or c.estado <> 'pendiente' or c.solicitada_por = v_neg then perform privado.fallo('Solicitud no encontrada'); end if;
  otro := case when c.a = v_neg then c.b else c.a end;
  select nombre into yo from public.negocios where id = v_neg;
  if coalesce(p_aceptar, false) then
    if not privado.es_premium(v_neg) then perform privado.fallo('Las billeteras conectadas son Pro.', 'PLAN'); end if;
    if privado.conexiones_usadas(v_neg) >= privado.limite_conexiones(v_neg) then
      perform privado.fallo('Llegaste a tus ' || privado.limite_conexiones(v_neg) || ' conexiones. Suma más en Conexiones → "Más conexiones".');
    end if;
    update public.conexiones set estado = 'activa', aceptada_at = now() where id = p_id;
    perform privado.avisar_negocio(otro, '🤝 Conexión lista', yo || ' aceptó conectar su billetera contigo.', 'app/#conexion/' || p_id, true);
  else
    update public.conexiones set estado = 'rechazada' where id = p_id;
  end if;
end $$;

-- Cancelar una solicitud enviada o desconectarse. El historial se guarda por si vuelven a conectarse.
create or replace function public.conexion_cerrar(p_id uuid) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true);
begin
  update public.conexiones set estado = 'cerrada' where id = p_id and (a = v_neg or b = v_neg) and estado in ('pendiente', 'activa');
  if not found then perform privado.fallo('Conexión no encontrada'); end if;
end $$;

create or replace function public.mis_conexiones() returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(false, true); a record;
begin
  select * into a from public.ajustes where id = 1;
  return jsonb_build_object(
    'codigo', (select codigo_conexion from public.negocios where id = v_neg),
    'pro', privado.es_premium(v_neg), 'limite', privado.limite_conexiones(v_neg), 'usadas', privado.conexiones_usadas(v_neg),
    'extra', (select conexiones_extra from public.negocios where id = v_neg), 'paquete', a.conexiones_paquete, 'precio_paquete', a.precio_paquete,
    'pago_pendiente', exists (select 1 from public.solicitudes_pago where negocio = v_neg and estado = 'pendiente'),
    'lista', coalesce((select jsonb_agg(x order by x.orden, x.nombre) from (
      select c.id, c.estado, c.solicitada_por = v_neg yo_solicite, o.nombre, o.icono, c.creado,
        privado.saldo_conexion(c.id, v_neg) saldo,
        (select count(*) from public.conexion_movs mv where mv.conexion = c.id and mv.estado = 'pendiente' and mv.autor <> v_neg) por_confirmar,
        (select count(*) from public.conexion_movs mv where mv.conexion = c.id and mv.estado = 'pendiente' and mv.autor = v_neg) esperando,
        case when c.estado = 'pendiente' and c.solicitada_por <> v_neg then 0 when c.estado = 'activa' then 1 else 2 end orden
      from public.conexiones c join public.negocios o on o.id = case when c.a = v_neg then c.b else c.a end
      where (c.a = v_neg or c.b = v_neg) and c.estado in ('pendiente', 'activa')) x), '[]'::jsonb));
end $$;

create or replace function public.conexion_ver(p_id uuid) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(false, true); c record; o record;
begin
  select * into c from public.conexiones where id = p_id and (a = v_neg or b = v_neg) and estado in ('pendiente', 'activa');
  if not found then perform privado.fallo('Conexión no encontrada'); end if;
  select nombre, icono into o from public.negocios where id = case when c.a = v_neg then c.b else c.a end;
  return jsonb_build_object('id', c.id, 'estado', c.estado, 'nombre', o.nombre, 'icono', o.icono, 'saldo', privado.saldo_conexion(c.id, v_neg),
    'pro', privado.es_premium(v_neg),
    'movs', coalesce((select jsonb_agg(x order by x.creado desc) from (
      select id, autor = v_neg mio, tipo, monto, descripcion, estado, motivo, creado, resuelto_at
      from public.conexion_movs where conexion = c.id order by creado desc limit 300) x), '[]'::jsonb));
end $$;

create or replace function public.conexion_anotar(p_conexion uuid, p_id uuid, p_tipo text, p_monto int, p_descripcion text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true); c record; otro uuid; yo text;
begin
  if not privado.es_premium(v_neg) then perform privado.fallo('Las billeteras conectadas son Pro.', 'PLAN'); end if;
  select * into c from public.conexiones where id = p_conexion and (a = v_neg or b = v_neg);
  if not found or c.estado <> 'activa' then perform privado.fallo('Conexión no encontrada'); end if;
  if p_tipo not in ('presto', 'pago') then perform privado.fallo('Tipo inválido'); end if;
  if p_monto is null or p_monto < 1 or p_monto > 99999999 then perform privado.fallo('El monto debe ser entre $1 y $99.999.999'); end if;
  if exists (select 1 from public.conexion_movs where id = p_id) then return; end if;
  perform privado.limitar('conmov:' || v_neg, 200, 3600);
  insert into public.conexion_movs (id, conexion, autor, tipo, monto, descripcion) values (p_id, p_conexion, v_neg, p_tipo, p_monto, privado.limpio(p_descripcion, 120));
  otro := case when c.a = v_neg then c.b else c.a end;
  select nombre into yo from public.negocios where id = v_neg;
  perform privado.avisar_negocio(otro, '🤝 ' || yo || ' anotó que ' || case when p_tipo = 'presto' then 'te prestó ' else 'te pagó ' end || privado.pesos(p_monto),
    'Confírmalo o recházalo en Conexiones.', 'app/#conexion/' || p_conexion, true);
end $$;

-- Confirmar o rechazar lo que anotó la otra persona (se puede aunque ya no tengas Pro).
create or replace function public.conexion_resolver(p_mov uuid, p_confirmar boolean, p_motivo text) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true); m record; c record; yo text;
begin
  select mv.* into m from public.conexion_movs mv join public.conexiones cx on cx.id = mv.conexion
   where mv.id = p_mov and (cx.a = v_neg or cx.b = v_neg) and cx.estado = 'activa' for update of mv;
  if not found or m.estado <> 'pendiente' or m.autor = v_neg then perform privado.fallo('Movimiento no encontrado'); end if;
  if not coalesce(p_confirmar, false) and coalesce(privado.limpio(p_motivo, 150), '') = '' then perform privado.fallo('Escribe el motivo'); end if;
  update public.conexion_movs set estado = case when p_confirmar then 'confirmado' else 'rechazado' end,
    motivo = case when p_confirmar then null else privado.limpio(p_motivo, 150) end, resuelto_at = now() where id = p_mov;
  select nombre into yo from public.negocios where id = v_neg;
  perform privado.avisar_negocio(m.autor, '🤝 ' || yo || case when p_confirmar then ' confirmó ' else ' rechazó ' end || privado.pesos(m.monto),
    case when p_confirmar then 'Ya cuenta en el saldo entre ustedes.' else 'Motivo: ' || privado.limpio(p_motivo, 150) end, 'app/#conexion/' || m.conexion, true);
end $$;

create or replace function public.conexion_anular(p_mov uuid) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true);
begin
  update public.conexion_movs set estado = 'anulado', resuelto_at = now() where id = p_mov and autor = v_neg and estado = 'pendiente';
  if not found then perform privado.fallo('Solo puedes anular lo tuyo mientras no esté confirmado.'); end if;
end $$;

-- Pedir más conexiones (paquetes): queda como pago por revisar; al aprobarlo se suman.
create or replace function public.pedir_conexiones(p_paquetes int, p_nota text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true, true); a record; v_monto int; n record;
begin
  if not privado.es_premium(v_neg) then perform privado.fallo('Las billeteras conectadas son Pro.', 'PLAN'); end if;
  if p_paquetes is null or p_paquetes < 1 or p_paquetes > 10 then perform privado.fallo('Elige entre 1 y 10 paquetes'); end if;
  if exists (select 1 from public.solicitudes_pago where negocio = v_neg and estado = 'pendiente') then
    perform privado.fallo('Ya tienes un pago en revisión. Te avisaremos apenas se apruebe.');
  end if;
  select * into a from public.ajustes where id = 1;
  select nombre, conexiones_extra into n from public.negocios where id = v_neg;
  if n.conexiones_extra + p_paquetes > 200 then perform privado.fallo('Máximo 200 paquetes'); end if;
  v_monto := p_paquetes * a.precio_paquete;
  insert into public.solicitudes_pago (negocio, meses, monto, nota, tipo, paquetes) values (v_neg, 1, v_monto, privado.limpio(p_nota, 200), 'conexiones', p_paquetes);
  perform privado.avisar_usuario(privado.admin_id(), '💳 Pago por revisar', n.nombre || ' pidió ' || p_paquetes * a.conexiones_paquete || ' conexiones más (' || privado.pesos(v_monto) || ').', 'admin/#pagos', true);
  return jsonb_build_object('ok', true, 'monto', v_monto);
end $$;

-- ---------- Planes: aplica la subida o bajada de plan ----------
create or replace function privado.aplicar_plan(p_neg uuid) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare n record; est text := privado.estado_plan(p_neg); nuevo text; v_lim int;
begin
  select * into n from public.negocios where id = p_neg for update;
  if not found then return; end if;
  nuevo := case when est = 'free' then 'normal' else 'premium' end;
  if nuevo = n.plan_aplicado then return; end if;
  update public.negocios set plan_aplicado = nuevo where id = p_neg;
  if nuevo = 'premium' then
    update public.clientes set fuera_de_plan = false where negocio = p_neg and fuera_de_plan;
  else
    -- Pasa a Free: sigue usando su billetera. Los clientes que pasan del límite gratis quedan en "solo cobro" (se respetan los más usados).
    v_lim := (select (lim_normal ->> 'clientes')::int from public.ajustes where id = 1);
    if v_lim is not null then
      update public.clientes set fuera_de_plan = true where id in (
        select id from public.clientes where negocio = p_neg and estado = 'activo' and not fuera_de_plan
         order by ultimo_mov desc nulls last, creado desc offset v_lim);
    end if;
    perform privado.avisar_negocio(p_neg, case when n.activado then 'Tu Pro venció: pasaste a Free' else 'Terminó tu prueba Pro: pasaste a Free' end,
      'Tu billetera sigue funcionando gratis. Las funciones Pro quedan en pausa (no se borra nada) hasta que actives Pro.', 'app/#plan', true);
    perform privado.avisar_usuario(privado.admin_id(), 'Pasó a Free: ' || n.nombre,
      case when n.activado then 'Venció su Pro.' else 'Terminó su prueba Pro.' end, 'admin/#negocios/' || p_neg, false);
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
    if c.fuera_de_plan then perform privado.fallo('Este cliente quedó en "solo cobro" por el límite del plan Free. Activa Pro o archiva clientes saldados.', 'PLAN'); end if;
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
        perform privado.fallo('Llegaste a los ' || privado.limite(p_neg, 'movimientos') || ' fiados y abonos de este mes del plan Free. Los abonos siguen funcionando. Activa Pro para anotar sin límite.', 'PLAN');
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
    perform privado.push(null, null, p_cliente, '🧾 ' || n.nombre || ': nuevo cargo', 'Se anotó ' || privado.pesos(p_monto) || coalesce(' · ' || v_desc, '') || '. Toca para revisarlo.', 'c/');
  elsif v_signo = -1 and p_comprobante is null then
    perform privado.push(null, null, p_cliente, '💰 ' || n.nombre || ': pago recibido', 'Se registró tu pago de ' || privado.pesos(p_monto) || '. ¡Gracias!', 'c/');
  end if;
  return jsonb_build_object('ok', true, 'saldo', (select saldo from public.clientes where id = p_cliente));
end $$;

-- =====================================================================
--  FUNCIONES DE LA APP (negocio)
-- =====================================================================
create or replace function public.ping() returns text language sql stable as $$ select 'ok' $$;

create or replace function public.config_publica() returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object('precio_mensual', a.precio_mensual, 'precio_anual', a.precio_anual, 'precio_activacion', a.precio_activacion, 'link_pago', a.link_pago, 'link_pago_anual', a.link_pago_anual,
    'transferencia', a.transferencia, 'contacto_whatsapp', a.contacto_whatsapp, 'dias_prueba', a.dias_prueba,
    'lim_normal', a.lim_normal, 'lim_premium', a.lim_premium, 'version_legal', a.version_legal, 'version_min', a.version_min,
    'version_liberada', a.version_liberada,
    'version_bd', (select valor::int from privado.config where clave = 'version_bd'),
    'conexiones_incluidas', a.conexiones_incluidas, 'conexiones_paquete', a.conexiones_paquete, 'precio_paquete', a.precio_paquete,
    'textos', a.textos, 'planes', a.planes, 'links_pro', a.links_pro, 'dias_comprobantes', a.dias_comprobantes,
    'dias_referido', a.dias_referido, 'ref_min_registros', a.ref_min_registros, 'ref_max_premios', a.ref_max_premios,
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
      'icono', n.icono, 'color', n.color, 'plantilla_propia', n.plantilla_propia, 'estado', n.estado, 'link_pago', n.link_pago, 'links_pago', n.links_pago,
      'motivo_suspension', n.motivo_suspension, 'creado', n.creado, 'contador_token', case when m.rol = 'dueno' then to_jsonb(n) ->> 'contador_token' end),
    'plan', jsonb_build_object('estado', privado.estado_plan(v_neg), 'premium', prem, 'hasta', n.premium_hasta,
      'en_prueba', privado.estado_plan(v_neg) = 'prueba', 'prueba_hasta', n.prueba_hasta, 'activado', n.activado,
      'en_gracia', privado.pagado(v_neg) and n.premium_hasta < now(), 'dias_gracia', a.dias_gracia,
      'cupon', case when privado.cupon_valido(n.cupon) then n.cupon end, 'descuento', privado.descuento(n.cupon),
      'precio_activacion', privado.precio_activacion(v_neg),
      'conexiones_extra', n.conexiones_extra, 'mensual', a.precio_mensual + n.conexiones_extra * a.precio_paquete,
      'anual', case when a.precio_anual > 0 then a.precio_anual + n.conexiones_extra * a.precio_paquete * 12 end,
      'pago_pendiente', exists (select 1 from public.solicitudes_pago where negocio = v_neg and estado = 'pendiente')),
    'limites', case when prem then a.lim_premium else a.lim_normal end,
    'uso', jsonb_build_object('movimientos', u.movimientos, 'comprobantes', u.comprobantes,
      'clientes', (select count(*) from public.clientes where negocio = v_neg and estado = 'activo' and not fuera_de_plan),
      'fuera_de_plan', (select count(*) from public.clientes where negocio = v_neg and estado = 'activo' and fuera_de_plan),
      'cuotas', (select count(*) from public.ventas_cuotas where negocio = v_neg and estado = 'activa'),
      'productos', (select count(*) from public.productos where negocio = v_neg),
      'caja', u.caja,
      'categorias', (select count(*) from public.categorias where negocio = v_neg),
      'ayudantes', 0),
    'pendientes', jsonb_build_object(
      'comprobantes', (select count(*) from public.comprobantes where negocio = v_neg and estado = 'pendiente'),
      'reclamos', (select count(*) from public.movimientos where negocio = v_neg and confirmacion = 'reclamado' and respuesta is null and anulado_at is null),
      'avisos', (select count(*) from public.notificaciones where (negocio = v_neg or usuario = auth.uid()) and not leido),
      'soporte', (select count(*) from public.soporte where negocio = v_neg and de = 'admin' and not leido)),
    'config', public.config_publica());
end $$;

create or replace function public.aceptar_terminos() returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then perform privado.fallo('Ingresa de nuevo.'); end if;
  insert into public.perfiles (id, terminos_version, terminos_at) values (auth.uid(), (select version_legal from public.ajustes where id = 1), now())
  on conflict (id) do update set terminos_version = excluded.terminos_version, terminos_at = now();
end $$;

create or replace function privado.crear_negocio_para(p_uid uuid, p_nombre text, p_rubro text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_id uuid; v_email text; v_hash text; v_dias int; v_nombre text := privado.limpio(p_nombre, 50); v_prueba boolean := false;
begin
  if exists (select 1 from public.miembros where usuario = p_uid) or exists (select 1 from public.negocios where dueno = p_uid) then
    perform privado.fallo('Esta cuenta ya tiene una billetera');
  end if;
  if v_nombre is null or char_length(v_nombre) < 2 then perform privado.fallo('El nombre del negocio debe tener entre 2 y 50 letras'); end if;
  if coalesce(p_rubro, 'otro') not in ('almacen','feria','catalogo','emprendimiento','servicios','educacion','club','personal','otro') then
    perform privado.fallo('Rubro inválido');
  end if;
  perform privado.limitar('crear_neg', 200, 3600);
  select lower(email) into v_email from auth.users where id = p_uid;
  v_hash := privado.sha(coalesce(v_email, p_uid::text));
  select dias_prueba into v_dias from public.ajustes where id = 1;
  -- G95: la billetera parte FREE; la prueba Pro es con el botón 🎁 (núcleo cfx_pro_probar → cfx_pro_prueba_app, una vez por correo).
  insert into public.negocios (dueno, nombre, rubro, prueba_hasta, en_prueba, plan_aplicado)
  values (p_uid, v_nombre, coalesce(p_rubro, 'otro'), case when v_prueba then now() + make_interval(days => v_dias) else now() end, false,
    case when v_prueba then 'premium' else 'normal' end)
  returning id into v_id;
  insert into public.miembros (negocio, usuario, rol, nombre) values (v_id, p_uid, 'dueno', v_nombre);
  perform privado.avisar_usuario(privado.admin_id(), 'Nueva billetera: ' || v_nombre, 'Rubro: ' || coalesce(p_rubro, 'otro') || coalesce(' · ' || v_email, ''), 'admin/#negocios', true);
  return jsonb_build_object('ok', true, 'id', v_id, 'prueba', v_prueba, 'dias', case when v_prueba then v_dias else 0 end);
end $$;

drop function if exists public.crear_negocio(text, text, boolean);
create or replace function public.crear_negocio(p_nombre text, p_rubro text, p_acepta boolean, p_ref text default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare r jsonb; v_ref record;
begin
  if auth.uid() is null then perform privado.fallo('Ingresa de nuevo.'); end if;
  if not coalesce(p_acepta, false) then perform privado.fallo('Debes aceptar los Términos y la Privacidad'); end if;
  r := privado.crear_negocio_para(auth.uid(), p_nombre, p_rubro);
  perform public.aceptar_terminos();
  -- Invita y gana: se anota quién lo invitó. El premio llega cuando la billetera nueva se usa de verdad (tarea diaria).
  if coalesce(btrim(p_ref), '') <> '' then
    select id, dueno into v_ref from public.negocios where codigo_ref = upper(btrim(p_ref)) and estado = 'activo';
    if v_ref.id is not null and v_ref.dueno <> auth.uid() then
      update public.negocios set referido_por = v_ref.id where id = (r ->> 'id')::uuid;
      perform privado.avisar_negocio(v_ref.id, '🎁 ' || privado.limpio(p_nombre, 50) || ' se unió con tu link',
        'Cuando empiece a usar su billetera ganas ' || (select dias_referido from public.ajustes where id = 1) || ' días de Pro.', 'app/#invita', true);
      r := r || jsonb_build_object('referido', true);
    end if;
  end if;
  return r;
end $$;

-- ---------- Invita y gana ----------
create or replace function public.mi_referidos() returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true, true); v_cod text; i int := 0;
begin
  select codigo_ref into v_cod from public.negocios where id = v_neg;
  while v_cod is null loop
    i := i + 1; if i > 20 then perform privado.fallo('No se pudo crear tu código. Prueba de nuevo.'); end if;
    v_cod := translate(upper(privado.codigo(6)), 'IO', 'WX');  -- sin I ni O (se confunden con 1 y 0)
    if not exists (select 1 from public.negocios where codigo_ref = v_cod) then
      update public.negocios set codigo_ref = v_cod where id = v_neg;
    else v_cod := null; end if;
  end loop;
  return jsonb_build_object('codigo', v_cod,
    'invitados', (select count(*) from public.negocios where referido_por = v_neg),
    'premiados', (select count(*) from public.negocios where referido_por = v_neg and ref_dias > 0),
    'dias_ganados', (select coalesce(sum(ref_dias), 0) from public.negocios where referido_por = v_neg),
    'lista', coalesce((select jsonb_agg(x order by x.creado desc) from (select nombre, creado, ref_dias > 0 premiado, ref_revisado_at is not null revisado
      from public.negocios where referido_por = v_neg order by creado desc limit 50) x), '[]'::jsonb));
end $$;

-- Premia a quien invitó cuando la billetera nueva se usa de verdad (N registros y 3 días de antigüedad), con un tope de premios.
create or replace function privado.premiar_referidos() returns int language plpgsql security definer set search_path = public, pg_temp as $$
declare a record; r record; p record; n int := 0; v_dias int;
begin
  select * into a from public.ajustes where id = 1;
  if a.dias_referido <= 0 then return 0; end if;
  for r in select n2.id, n2.nombre, n2.referido_por from public.negocios n2
    where n2.referido_por is not null and n2.ref_revisado_at is null and n2.estado = 'activo' and n2.creado < now() - interval '3 days'
      and (select count(*) from public.movimientos where negocio = n2.id) + (select count(*) from public.caja where negocio = n2.id) >= a.ref_min_registros
  loop
    select * into p from public.negocios where id = r.referido_por;
    v_dias := case when p.estado = 'activo' and (select count(*) from public.negocios where referido_por = p.id and ref_dias > 0) < a.ref_max_premios then a.dias_referido else 0 end;
    update public.negocios set ref_revisado_at = now(), ref_dias = v_dias where id = r.id;
    if v_dias > 0 then
      if privado.pagado(p.id) then
        update public.negocios set premium_hasta = greatest(premium_hasta, now()) + make_interval(days => v_dias) where id = p.id;
      else
        update public.negocios set prueba_hasta = greatest(coalesce(prueba_hasta, now()), now()) + make_interval(days => v_dias) where id = p.id;
      end if;
      perform privado.aplicar_plan(p.id);
      perform privado.auditar(p.id, 'referido', jsonb_build_object('invitado', r.id, 'dias', v_dias));
      perform privado.avisar_negocio(p.id, '🎉 Ganaste ' || v_dias || ' días de Pro', r.nombre || ' ya usa su billetera. ¡Gracias por recomendarnos!', 'app/#invita', true);
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;

create or replace function public.guardar_negocio(p jsonb) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true, true); prem boolean := privado.es_premium(v_neg); b jsonb := coalesce(p -> 'banco', '{}'::jsonb);
  v_nombre text := privado.limpio(p ->> 'nombre', 50); v_banco jsonb; v_lim int;
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
    v_plant := null;
  else
    if v_plant is not null then
      select w into v_bad from unnest(array['demanda','tribunal','juzgado','embargo','dicom','abogado','policia','carabinero','carcel','denuncia','querella','boletin comercial','cobranza judicial','tus familiares','tu trabajo','tu jefe']) w
       where privado.norm(v_plant) like '%' || w || '%' limit 1;
      if v_bad is not null then perform privado.fallo('El mensaje no puede contener "' || v_bad || '": la ley prohíbe amenazas en la cobranza.'); end if;
    end if;
  end if;
  update public.negocios set nombre = v_nombre, rubro = coalesce(p ->> 'rubro', 'otro'), whatsapp = privado.telefono(p ->> 'whatsapp'),
    banco = v_banco, venc_defecto = coalesce(p ->> 'venc_defecto', '7'), limite_general = v_lim,
    pin_activo = coalesce((p ->> 'pin_activo')::boolean, true), saldo_a_favor = coalesce((p ->> 'saldo_a_favor')::boolean, false),
    link_pago = case when p ? 'links_pago' then privado.link_activo(privado.links_validos(p -> 'links_pago'))
      when p ? 'link_pago' then privado.url_pago(p ->> 'link_pago') else link_pago end,
    links_pago = case when p ? 'links_pago' then privado.links_validos(p -> 'links_pago') else links_pago end,
    plantilla_propia = case when prem then v_plant else plantilla_propia end
   where id = v_neg;
  update public.miembros set nombre = v_nombre where negocio = v_neg and rol = 'dueno';
end $$;

-- Ícono de perfil (un emoji, sin subir imágenes) y color del tema. Gratis para todos; el color sale en el link del cliente solo con Pro.
create or replace function public.guardar_perfil(p_icono text, p_color text) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true, true); v_ico text := nullif(btrim(coalesce(p_icono, '')), '');
begin
  if v_ico is not null and (char_length(v_ico) > 16 or v_ico ~ '[<>&"''a-zA-Z0-9]') then perform privado.fallo('Ícono inválido'); end if;
  if p_color is not null and p_color not in (select unnest(privado.colores())) then perform privado.fallo('Color inválido'); end if;
  update public.negocios set icono = v_ico, color = p_color where id = v_neg;
end $$;

-- Link de pago (Mercado Pago u otro): solo https, sin espacios. Si viene sin https:// se lo agrega.
create or replace function privado.url_pago(p text) returns text language plpgsql as $$
declare v text := nullif(btrim(coalesce(p, '')), '');
begin
  if v is null then return null; end if;
  v := regexp_replace(v, '^http://', '', 'i');
  if v !~* '^https://' then v := 'https://' || v; end if;
  if char_length(v) > 300 or v !~ '^https://[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+(:[0-9]+)?([/?#][^\s<>"]*)?$' then
    perform privado.fallo('El link de pago no es válido. Cópialo completo, por ejemplo https://mpago.la/abc123');
  end if;
  return v;
end $$;

-- 2 espacios de link de pago (texto + link + activo). Devuelve la lista limpia; solo uno queda activo.
create or replace function privado.links_validos(p jsonb) returns jsonb language plpgsql as $$
declare r jsonb := '[]'::jsonb; x jsonb; i int := 0; hay boolean := false; u text;
begin
  if jsonb_typeof(coalesce(p, '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p, '[]'::jsonb)) > 2 then perform privado.fallo('Máximo 2 links de pago'); end if;
  for x in select * from jsonb_array_elements(coalesce(p, '[]'::jsonb)) loop
    i := i + 1;
    u := privado.url_pago(x ->> 'url');
    r := r || jsonb_build_object('texto', coalesce(privado.limpio(x ->> 'texto', 60), ''), 'url', coalesce(u, ''),
      'activo', u is not null and coalesce((x ->> 'activo')::boolean, false) and not hay);
    if u is not null and coalesce((x ->> 'activo')::boolean, false) then hay := true; end if;
  end loop;
  return r;
end $$;
create or replace function privado.link_activo(p jsonb) returns text language sql immutable as $$
  select coalesce((select x ->> 'url' from jsonb_array_elements(coalesce(p, '[]'::jsonb)) x where (x ->> 'activo')::boolean and x ->> 'url' <> '' limit 1),
                  (select x ->> 'url' from jsonb_array_elements(coalesce(p, '[]'::jsonb)) x where x ->> 'url' <> '' limit 1))
$$;

-- Link de pago propio de un cliente (Pro). Vacío = usa el link general del negocio.
create or replace function public.guardar_link_pago_cliente(p_id uuid, p_link text) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir();
begin
  if not privado.es_premium(v_neg) then perform privado.fallo('El link de pago propio por cliente es Pro.', 'PLAN'); end if;
  update public.clientes set link_pago = privado.url_pago(p_link) where id = p_id and negocio = v_neg and estado <> 'borrado';
  if not found then perform privado.fallo('Cliente no encontrado'); end if;
end $$;

-- Marcar pagada una cuota: calcula cuánto falta para dejarla pagada (los abonos pagan primero lo más antiguo)
-- y, si p_confirmar, anota ese abono. La cuota anterior de la misma venta debe estar pagada.
create or replace function public.pagar_cuota(p_id uuid, p_venta uuid, p_numero int, p_medio text, p_confirmar boolean) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(); v record; q record; r record; credito bigint; hasta bigint := 0; v_monto bigint; v_prev bigint;
begin
  select * into v from public.ventas_cuotas where id = p_venta and negocio = v_neg;
  if not found or v.estado = 'anulada' then perform privado.fallo('Venta en cuotas no encontrada'); end if;
  perform privado.recalcular(v.cliente);
  select * into q from public.cuotas where venta = p_venta and numero = p_numero;
  if not found then perform privado.fallo('Cuota no encontrada'); end if;
  if q.pagado >= q.monto then perform privado.fallo('Esa cuota ya está pagada'); end if;
  if exists (select 1 from public.cuotas where venta = p_venta and numero < p_numero and pagado < monto) then
    perform privado.fallo('Primero marca pagada la cuota anterior');
  end if;
  select coalesce(sum(monto), 0) into credito from public.movimientos where cliente = v.cliente and anulado_at is null and signo = -1;
  for r in
    select 'm'::text k, m.id, 0 num, m.monto::bigint monto, coalesce(m.vence, (m.fecha at time zone 'America/Santiago')::date) due, m.fecha ord
      from public.movimientos m
     where m.cliente = v.cliente and m.anulado_at is null and m.signo = 1 and m.venta is null
    union all
    select 'c', c.venta, c.numero, c.monto, c.vence, vc.creado
      from public.cuotas c join public.ventas_cuotas vc on vc.id = c.venta
     where vc.cliente = v.cliente and vc.estado <> 'anulada'
    order by due, ord, num
  loop
    hasta := hasta + r.monto;
    exit when r.k = 'c' and r.id = p_venta and r.num = p_numero;
  end loop;
  v_monto := hasta - credito;
  if v_monto <= 0 then perform privado.fallo('Esa cuota ya está cubierta'); end if;
  if v_monto > 9999999 then perform privado.fallo('El monto supera $9.999.999: anótalo como abonos separados.'); end if;
  v_prev := greatest(v_monto - (q.monto - q.pagado), 0);
  if not coalesce(p_confirmar, false) then
    return jsonb_build_object('ok', false, 'monto', v_monto, 'cuota', q.monto - q.pagado, 'previo', v_prev, 'numero', q.numero, 'n', v.n, 'descripcion', v.descripcion);
  end if;
  if coalesce(p_medio, '') not in ('efectivo', 'transferencia', 'otro') then perform privado.fallo('Medio de pago inválido'); end if;
  return privado.mov_insertar(v_neg, p_id, v.cliente, 'abono', v_monto::int, null,
      'Cuota ' || q.numero || ' de ' || v.n || ' · ' || v.descripcion || case when p_medio = 'otro' then ' (link de pago)' else '' end,
      p_medio, null, null, null, false, true) || jsonb_build_object('monto', v_monto);
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
    perform privado.fallo('Llegaste a los ' || v_lim || ' clientes activos del plan Free. Archiva clientes saldados o activa Pro para tener clientes ilimitados.', 'PLAN');
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
      perform privado.fallo('No hay cupo: el plan Free permite ' || v_lim || ' clientes activos. Archiva otro o activa Pro.', 'PLAN');
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
    perform privado.fallo('El plan Free permite ' || v_lim || ' ventas en cuotas activas. Activa Pro para tener ilimitadas.', 'PLAN');
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
  perform privado.push(null, null, m.cliente, '💬 Respuesta a tu reclamo', v_com, 'c/');
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
  -- G94: con el módulo 📈 Cobranza escalonada, neutral y firme también para Free (el tono lo elige la app según el atraso).
  if p_tono <> 'amable' and not prem and not (p_tono in ('neutral', 'firme') and to_regprocedure('public.cfx_modulo_de(text,uuid)') is not null and public.cfx_modulo_de('escalonado', v_neg))
    then perform privado.fallo('Los tonos neutral, firme y propio son Pro', 'PLAN'); end if;
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
    perform privado.push(null, null, p_cliente, '🔔 ' || n.nombre || ': recordatorio', coalesce(privado.limpio(p_texto, 180), 'Tienes un saldo pendiente de ' || privado.pesos(c.saldo) || '.'), 'c/');
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
    perform privado.push(null, null, k.cliente, '✅ ' || n.nombre || ': pago confirmado', 'Confirmamos tu transferencia de ' || privado.pesos(coalesce(p_monto, k.monto)) || '. ¡Gracias!', 'c/');
    return r;
  else
    if v_mot is null or char_length(v_mot) < 3 then perform privado.fallo('Escribe el motivo del rechazo'); end if;
    update public.comprobantes set estado = 'rechazado', motivo = v_mot, revisado_por = auth.uid(), revisado_at = now() where id = p_id;
    perform privado.push(null, null, k.cliente, '❌ ' || n.nombre || ': comprobante no aprobado', v_mot, 'c/');
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
begin
  perform privado.fallo('Cada billetera es personal: no se pueden agregar ayudantes.');
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

-- ---------- Cupones de descuento en la activación ----------
create or replace function privado.cupon_valido(p_codigo text) returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select activo and (vence is null or vence >= privado.hoy()) and (usos_max is null or usos < usos_max)
    from public.cupones where codigo = p_codigo), false)
$$;

create or replace function privado.descuento(p_codigo text) returns int language sql stable security definer set search_path = public, pg_temp as $$
  select case when privado.cupon_valido(p_codigo) then (select descuento from public.cupones where codigo = p_codigo) else 0 end
$$;

-- Precio de activación que paga este negocio (0 si ya activó), con su cupón.
create or replace function privado.precio_activacion(p_neg uuid) returns int language sql stable security definer set search_path = public, pg_temp as $$
  select case when n.activado then 0 else round(a.precio_activacion * (100 - privado.descuento(n.cupon)) / 100.0)::int end
  from public.negocios n, public.ajustes a where n.id = p_neg and a.id = 1
$$;

create or replace function public.usar_cupon(p_codigo text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true, true); v_cod text := upper(btrim(coalesce(p_codigo, '')));
begin
  perform privado.limitar('cupon:' || v_neg, 10, 3600);
  if (select activado from public.negocios where id = v_neg) then perform privado.fallo('Tu Pro ya está activado: los cupones son para la activación.'); end if;
  if not privado.cupon_valido(v_cod) then perform privado.fallo('Cupón inválido o vencido'); end if;
  update public.negocios set cupon = v_cod where id = v_neg;
  return jsonb_build_object('ok', true, 'descuento', privado.descuento(v_cod), 'precio_activacion', privado.precio_activacion(v_neg));
end $$;

-- ---------- Plan Premium ----------
create or replace function public.usar_key(p_codigo text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true, true); k record; v_hasta timestamptz;
begin
  perform privado.limitar('key:' || v_neg, 10, 3600);
  select * into k from public.keys where codigo = upper(btrim(p_codigo)) for update;
  if not found or k.revocada or k.usada_por is not null then perform privado.fallo('Key inválida o ya usada'); end if;
  update public.negocios set premium_hasta = greatest(coalesce(premium_hasta, now()), now()) + make_interval(months => k.meses), en_prueba = false, activado = true
   where id = v_neg returning premium_hasta into v_hasta;
  update public.keys set usada_por = v_neg, usada_at = now() where codigo = k.codigo;
  perform privado.aplicar_plan(v_neg);
  perform privado.auditar(v_neg, 'key', jsonb_build_object('meses', k.meses));
  return jsonb_build_object('ok', true, 'hasta', v_hasta);
end $$;

create or replace function public.solicitar_pago(p_meses int, p_path text, p_nota text) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true, true); a record; n record; v_monto int;
begin
  if p_meses is null or p_meses not in (1, 12) then perform privado.fallo('Elige el plan mensual o el anual'); end if;
  if exists (select 1 from public.solicitudes_pago where negocio = v_neg and estado = 'pendiente') then
    perform privado.fallo('Ya tienes un pago en revisión. Te avisaremos apenas se apruebe.');
  end if;
  if p_path is not null and p_path not like v_neg || '/%' then perform privado.fallo('Archivo inválido'); end if;
  select * into a from public.ajustes where id = 1;
  if p_meses = 12 and a.precio_anual <= 0 then perform privado.fallo('El plan anual no está disponible'); end if;
  select nombre, activado, cupon, conexiones_extra into n from public.negocios where id = v_neg;
  v_monto := case when p_meses = 12 then a.precio_anual + n.conexiones_extra * a.precio_paquete * 12
    else a.precio_mensual + n.conexiones_extra * a.precio_paquete end + privado.precio_activacion(v_neg);
  insert into public.solicitudes_pago (negocio, meses, monto, comprobante_path, nota, cupon)
  values (v_neg, p_meses, v_monto, p_path, privado.limpio(p_nota, 200), case when not n.activado and privado.cupon_valido(n.cupon) then n.cupon end);
  perform privado.avisar_usuario(privado.admin_id(), '💳 Pago por revisar', n.nombre || ' dice que pagó ' || privado.pesos(v_monto)
    || case when p_meses = 12 then ' (plan anual' else ' (mensualidad' end || case when n.activado then ').' else ' + activación).' end, 'admin/#pagos', true);
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
declare v_neg uuid := privado.exigir(false, true); hoy date := privado.hoy(); m0 timestamptz; m1 timestamptz;
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
declare v_neg uuid := privado.exigir(true, true); prem boolean := privado.es_premium(v_neg); d date := p_desde; h date := p_hasta;
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
        from public.cuotas q join public.ventas_cuotas v on v.id = q.venta join public.clientes c on c.id = v.cliente where v.negocio = v_neg), '[]'::jsonb),
    'caja', coalesce((select jsonb_agg(jsonb_build_object('fecha', fecha, 'tipo', tipo, 'monto', monto, 'categoria', categoria, 'descripcion', descripcion,
        'medio', medio, 'anulado', anulado_at is not null, 'motivo_anulacion', motivo_anulacion) order by fecha)
        from public.caja where negocio = v_neg), '[]'::jsonb));
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

-- ---------- Caja: ingresos y gastos ----------
create or replace function public.registrar_caja(p_id uuid, p_tipo text, p_monto int, p_categoria text, p_descripcion text, p_medio text,
  p_fecha timestamptz, p_confirmar_dup boolean) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(); v_fecha timestamptz := coalesce(p_fecha, now()); v_cat text := privado.limpio(p_categoria, 24);
  u public.uso_mensual; v_lim int;
begin
  if p_id is null then perform privado.fallo('Falta el identificador'); end if;
  if exists (select 1 from public.caja where id = p_id) then
    if not exists (select 1 from public.caja where id = p_id and negocio = v_neg) then perform privado.fallo('Movimiento inválido'); end if;
    return jsonb_build_object('ok', true, 'repetido', true);
  end if;
  if p_tipo not in ('ingreso','gasto') then perform privado.fallo('Elige ingreso o gasto'); end if;
  if p_monto is null or p_monto < 1 or p_monto > 99999999 then perform privado.fallo('El monto debe ser entre $1 y $99.999.999'); end if;
  if v_cat is null or char_length(v_cat) < 2 then perform privado.fallo('Elige una categoría'); end if;
  if coalesce(p_medio, 'efectivo') not in ('efectivo','transferencia','tarjeta','otro') then perform privado.fallo('Medio de pago inválido'); end if;
  if v_fecha > now() + interval '5 minutes' then perform privado.fallo('La fecha no puede ser futura'); end if;
  if v_fecha < now() - interval '1 year' then perform privado.fallo('La fecha puede ser hasta 1 año atrás'); end if;
  if not coalesce(p_confirmar_dup, false) and exists (select 1 from public.caja where negocio = v_neg and tipo = p_tipo and monto = p_monto
      and categoria = v_cat and anulado_at is null and creado_at > now() - interval '60 seconds') then
    return jsonb_build_object('ok', false, 'duplicado', true);
  end if;
  v_lim := privado.limite(v_neg, 'caja');
  u := privado.uso(v_neg);
  if v_lim is not null and u.caja >= v_lim then
    perform privado.fallo('Llegaste a los ' || v_lim || ' ingresos y gastos de este mes del plan Free. Activa Pro para anotar sin límite.', 'PLAN');
  end if;
  perform privado.limitar('caja:' || v_neg, 300, 3600);
  insert into public.caja (id, negocio, tipo, monto, categoria, descripcion, medio, fecha, creado_por)
  values (p_id, v_neg, p_tipo, p_monto, v_cat, privado.limpio(p_descripcion, 120), coalesce(p_medio, 'efectivo'), v_fecha, auth.uid());
  update public.uso_mensual set caja = caja + 1 where negocio = v_neg and mes = date_trunc('month', privado.hoy())::date;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.anular_caja(p_id uuid, p_motivo text) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(); v_mot text := privado.limpio(p_motivo, 100);
begin
  if v_mot is null or char_length(v_mot) < 5 then perform privado.fallo('Escribe el motivo (mínimo 5 letras)'); end if;
  update public.caja set anulado_at = now(), anulado_por = auth.uid(), motivo_anulacion = v_mot where id = p_id and negocio = v_neg and anulado_at is null;
  if not found then perform privado.fallo('Movimiento no encontrado'); end if;
  perform privado.auditar(v_neg, 'anular_caja', jsonb_build_object('id', p_id, 'motivo', v_mot));
end $$;

create or replace function public.guardar_categoria(p_tipo text, p_nombre text) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(); v_nom text := privado.limpio(p_nombre, 24); v_lim int;
begin
  if p_tipo not in ('ingreso','gasto') then perform privado.fallo('Tipo inválido'); end if;
  if v_nom is null or char_length(v_nom) < 2 then perform privado.fallo('El nombre debe tener entre 2 y 24 letras'); end if;
  v_lim := privado.limite(v_neg, 'categorias');
  if v_lim is not null and (select count(*) from public.categorias where negocio = v_neg) >= v_lim then
    perform privado.fallo('Tu plan permite ' || v_lim || ' categorías propias.', case when privado.es_premium(v_neg) then null else 'PLAN' end);
  end if;
  insert into public.categorias (negocio, tipo, nombre) values (v_neg, p_tipo, v_nom) on conflict do nothing;
end $$;

create or replace function public.borrar_categoria(p_id uuid) returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin delete from public.categorias where id = p_id and negocio = privado.exigir(); end $$;

create or replace function public.resumen_caja(p_mes date) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(false, true); m0 date := date_trunc('month', coalesce(p_mes, privado.hoy()))::date;
  t0 timestamptz := m0::timestamp at time zone 'America/Santiago'; t1 timestamptz := (m0 + interval '1 month')::timestamp at time zone 'America/Santiago';
  tp timestamptz := (m0 - interval '1 month')::timestamp at time zone 'America/Santiago';
begin
  return jsonb_build_object('mes', m0,
    'ingresos', (select coalesce(sum(monto), 0) from public.caja where negocio = v_neg and tipo = 'ingreso' and anulado_at is null and fecha >= t0 and fecha < t1),
    'gastos', (select coalesce(sum(monto), 0) from public.caja where negocio = v_neg and tipo = 'gasto' and anulado_at is null and fecha >= t0 and fecha < t1),
    'cobros', (select coalesce(sum(monto), 0) from public.movimientos where negocio = v_neg and tipo = 'abono' and anulado_at is null and fecha >= t0 and fecha < t1),
    'fiado', (select coalesce(sum(monto), 0) from public.movimientos where negocio = v_neg and tipo = 'cargo' and anulado_at is null and fecha >= t0 and fecha < t1),
    'ingresos_ant', (select coalesce(sum(monto), 0) from public.caja where negocio = v_neg and tipo = 'ingreso' and anulado_at is null and fecha >= tp and fecha < t0)
      + (select coalesce(sum(monto), 0) from public.movimientos where negocio = v_neg and tipo = 'abono' and anulado_at is null and fecha >= tp and fecha < t0),
    'gastos_ant', (select coalesce(sum(monto), 0) from public.caja where negocio = v_neg and tipo = 'gasto' and anulado_at is null and fecha >= tp and fecha < t0),
    'por_categoria', coalesce((select jsonb_agg(x order by x.monto desc) from (select tipo, categoria, sum(monto) monto, count(*) n
        from public.caja where negocio = v_neg and anulado_at is null and fecha >= t0 and fecha < t1 group by tipo, categoria) x), '[]'::jsonb),
    'por_medio', coalesce((select jsonb_object_agg(medio, s) from (select medio, sum(monto) s from public.caja
        where negocio = v_neg and tipo = 'ingreso' and anulado_at is null and fecha >= t0 and fecha < t1 group by medio) x), '{}'::jsonb),
    'pro', privado.es_premium(v_neg),
    'meta_ventas', (select meta_ventas from public.negocios where id = v_neg),
    'presupuesto_gastos', (select presupuesto_gastos from public.negocios where id = v_neg));
end $$;

-- ---------- Reportes Pro: comparación con el mes anterior, mejores clientes y días que más vende ----------
create or replace function public.reporte_pro(p_mes date) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true, true); m0 date := date_trunc('month', coalesce(p_mes, privado.hoy()))::date;
  t0 timestamptz := m0::timestamp at time zone 'America/Santiago'; t1 timestamptz := (m0 + interval '1 month')::timestamp at time zone 'America/Santiago';
  tp timestamptz := (m0 - interval '1 month')::timestamp at time zone 'America/Santiago'; t90 timestamptz := now() - interval '90 days';
  dias_mes int := extract(day from (m0 + interval '1 month' - interval '1 day'))::int;
  dias_pasados int := least(dias_mes, greatest(1, privado.hoy() - m0 + 1));
begin
  if not privado.es_premium(v_neg) then perform privado.fallo('Los reportes avanzados son Pro.', 'PLAN'); end if;
  return jsonb_build_object('mes', m0, 'dias_mes', dias_mes, 'dias_pasados', dias_pasados,
    'actual', privado.totales_mes(v_neg, t0, t1),
    'anterior', privado.totales_mes(v_neg, tp, t0),
    'mejores_clientes', coalesce((select jsonb_agg(x order by x.compras desc) from (
        select c.id, c.nombre, sum(m.monto) filter (where m.signo = 1) compras, coalesce(sum(m.monto) filter (where m.signo = -1), 0) pagado, c.saldo
        from public.movimientos m join public.clientes c on c.id = m.cliente
        where m.negocio = v_neg and m.anulado_at is null and m.tipo in ('cargo', 'abono') and m.fecha >= t0 and m.fecha < t1
        group by c.id, c.nombre, c.saldo having sum(m.monto) filter (where m.signo = 1) > 0 order by 3 desc limit 5) x), '[]'::jsonb),
    'por_dia_semana', coalesce((select jsonb_agg(x order by x.dia) from (
        select extract(isodow from fecha at time zone 'America/Santiago')::int dia, sum(monto) monto, count(*) n from (
          select fecha, monto from public.caja where negocio = v_neg and tipo = 'ingreso' and anulado_at is null and fecha >= t90
          union all select fecha, monto from public.movimientos where negocio = v_neg and tipo = 'abono' and anulado_at is null and fecha >= t90) y
        group by 1) x), '[]'::jsonb),
    'gasto_top', coalesce((select jsonb_agg(x order by x.monto desc) from (
        select categoria, sum(monto) monto from public.caja where negocio = v_neg and tipo = 'gasto' and anulado_at is null and fecha >= t0 and fecha < t1
        group by categoria order by 2 desc limit 3) x), '[]'::jsonb));
end $$;

create or replace function privado.totales_mes(p_neg uuid, t0 timestamptz, t1 timestamptz) returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'ventas', (select coalesce(sum(monto), 0) from public.caja where negocio = p_neg and tipo = 'ingreso' and anulado_at is null and fecha >= t0 and fecha < t1),
    'cobros', (select coalesce(sum(monto), 0) from public.movimientos where negocio = p_neg and tipo = 'abono' and anulado_at is null and fecha >= t0 and fecha < t1),
    'gastos', (select coalesce(sum(monto), 0) from public.caja where negocio = p_neg and tipo = 'gasto' and anulado_at is null and fecha >= t0 and fecha < t1),
    'fiado', (select coalesce(sum(monto), 0) from public.movimientos where negocio = p_neg and tipo = 'cargo' and anulado_at is null and fecha >= t0 and fecha < t1),
    'clientes_nuevos', (select count(*) from public.clientes where negocio = p_neg and creado >= t0 and creado < t1))
$$;

-- ---------- Cobrar a todos (Pro): quién debe y si hoy se le puede cobrar según la ley ----------
create or replace function public.cobranza_lote() returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(); r jsonb := '[]'::jsonb; c record; p record;
begin
  if not privado.es_premium(v_neg) then perform privado.fallo('Cobrar a todos de una es Pro.', 'PLAN'); end if;
  for c in select id, nombre, telefono, saldo, prox_venc, atrasado from public.clientes
     where negocio = v_neg and saldo > 0 and estado <> 'borrado' order by atrasado desc, prox_venc nulls last, saldo desc limit 200 loop
    select * into p from privado.cobro_permitido(c.id);
    r := r || jsonb_build_object('id', c.id, 'nombre', c.nombre, 'telefono', c.telefono, 'saldo', c.saldo, 'prox_venc', c.prox_venc,
      'atrasado', c.atrasado, 'ok', p.ok, 'motivo', p.motivo, 'proxima', p.proxima);
  end loop;
  return r;
end $$;

-- Meta de ventas y presupuesto de gastos del mes (Pro)
create or replace function public.guardar_metas(p_meta int, p_presupuesto int) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true);
begin
  if not privado.es_premium(v_neg) then perform privado.fallo('La meta de ventas y el presupuesto de gastos son Pro.', 'PLAN'); end if;
  if coalesce(p_meta, 0) < 0 or coalesce(p_meta, 0) > 999999999 or coalesce(p_presupuesto, 0) < 0 or coalesce(p_presupuesto, 0) > 999999999 then
    perform privado.fallo('Montos inválidos');
  end if;
  update public.negocios set meta_ventas = nullif(p_meta, 0), presupuesto_gastos = nullif(p_presupuesto, 0) where id = v_neg;
end $$;

-- "Quiero Pro": avisa al admin por soporte y deja registrado el interés
create or replace function public.pedir_pro() returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true, true); n record;
begin
  perform privado.limitar('pro:' || v_neg, 5, 86400);
  select nombre, activado, privado.estado_plan(id) est into n from public.negocios where id = v_neg;
  update public.negocios set quiere_pro_at = now() where id = v_neg;
  insert into public.soporte (negocio, de, texto) values (v_neg, 'negocio',
    case when n.est = 'pro' then '💳 Quiero pagar mi mensualidad de Pro.' else '⭐ Quiero activar Pro en mi billetera.' end);
  perform privado.push(privado.admin_id(), null, null, '⭐ ' || n.nombre || ' quiere Pro', 'Escríbele por soporte o WhatsApp.', 'admin/#soporte/' || v_neg);
end $$;

-- ---------- Soporte: chat directo con el administrador ----------
create or replace function public.soporte_enviar(p_texto text) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true, true); v_t text := btrim(coalesce(p_texto, '')); n record;
begin
  if char_length(v_t) < 1 or char_length(v_t) > 1000 then perform privado.fallo('El mensaje debe tener entre 1 y 1000 caracteres'); end if;
  perform privado.limitar('sop:' || v_neg, 30, 3600);
  insert into public.soporte (negocio, de, texto) values (v_neg, 'negocio', v_t);
  select nombre into n from public.negocios where id = v_neg;
  perform privado.push(privado.admin_id(), null, null, 'Soporte · ' || n.nombre, left(v_t, 120), 'admin/#soporte/' || v_neg);
end $$;

create or replace function public.soporte_leer() returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true, true);
begin
  update public.soporte set leido = true where negocio = v_neg and de = 'admin' and not leido;
  return coalesce((select jsonb_agg(x order by x.creado) from (select id, de, texto, leido, creado from public.soporte
    where negocio = v_neg order by creado desc limit 200) x), '[]'::jsonb);
end $$;

create or replace function public.admin_soporte_lista() returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform privado.solo_admin();
  return coalesce((select jsonb_agg(x order by x.ultimo desc) from (
    select n.id negocio, n.nombre, max(s.creado) ultimo,
      (select texto from public.soporte s2 where s2.negocio = n.id order by creado desc limit 1) ultimo_texto,
      count(*) filter (where s.de = 'negocio' and not s.leido) sin_leer
    from public.soporte s join public.negocios n on n.id = s.negocio group by n.id, n.nombre) x), '[]'::jsonb);
end $$;

create or replace function public.admin_soporte_ver(p_negocio uuid) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform privado.solo_admin();
  update public.soporte set leido = true where negocio = p_negocio and de = 'negocio' and not leido;
  return jsonb_build_object('negocio', (select nombre from public.negocios where id = p_negocio),
    'mensajes', coalesce((select jsonb_agg(x order by x.creado) from (select id, de, texto, leido, creado from public.soporte
      where negocio = p_negocio order by creado desc limit 300) x), '[]'::jsonb));
end $$;

create or replace function public.admin_soporte_enviar(p_negocio uuid, p_texto text) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_t text := btrim(coalesce(p_texto, ''));
begin
  perform privado.solo_admin();
  if char_length(v_t) < 1 or char_length(v_t) > 1000 then perform privado.fallo('El mensaje debe tener entre 1 y 1000 caracteres'); end if;
  if not exists (select 1 from public.negocios where id = p_negocio) then perform privado.fallo('Billetera no encontrada'); end if;
  insert into public.soporte (negocio, de, texto) values (p_negocio, 'admin', v_t);
  perform privado.push(null, p_negocio, null, 'Soporte te respondió', left(v_t, 120), 'app/#soporte');
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
  if exists (select 1 from public.clientes c join public.negocios n on n.id = c.negocio where c.id = s.cliente
      and n.estado <> 'activo') then
    perform privado.fallo('Este link está en pausa por ahora. Escríbele al negocio.');
  end if;
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
  return jsonb_build_object('ok', n.estado = 'activo', 'pausa', false, 'negocio', n.nombre, 'pin', n.pin_activo, 'bloqueado', c.link_bloqueado,
    'icono', n.icono, 'color', case when privado.es_premium(n.id) then n.color end);
end $$;

create or replace function public.portal_entrar(p_codigo text, p_pin text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare c record; n record; v_tok text; v_ip text; hoy date := privado.hoy();
begin
  begin v_ip := split_part(coalesce(current_setting('request.headers', true)::json ->> 'x-forwarded-for', ''), ',', 1); exception when others then v_ip := ''; end;
  if v_ip <> '' then perform privado.limitar('ip:' || v_ip, 60, 3600); end if;
  select * into c from public.clientes where link_codigo = coalesce(p_codigo, '') and estado <> 'borrado' for update;
  if not found then perform privado.fallo('Este link no es válido. Pídele al negocio que te lo envíe de nuevo.'); end if;
  select * into n from public.negocios where id = c.negocio;
  if n.estado <> 'activo' then perform privado.fallo('Este link está en pausa. Escríbele a ' || n.nombre || '.'); end if;
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
      'icono', n.icono, 'color', case when prem then n.color end, 'marca', not prem,
      'link_pago', coalesce(case when prem then c.link_pago end, n.link_pago),
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
    'textos', (select textos from public.ajustes where id = 1),
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
  perform privado.avisar_negocio(c.negocio, '💰 ' || c.nombre || ' avisó que pagó', 'Dice que transfirió ' || privado.pesos(p_monto) || '. Revísalo y apruébalo.', 'app/#comprobantes', true);
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
    'premium', (select count(*) from public.negocios n where estado <> 'eliminado' and privado.estado_plan(n.id) = 'pro'),
    'en_prueba', (select count(*) from public.negocios n where estado <> 'eliminado' and privado.estado_plan(n.id) = 'prueba'),
    'free', (select count(*) from public.negocios n where estado <> 'eliminado' and privado.estado_plan(n.id) = 'free'),
    'suspendidos', (select count(*) from public.negocios where estado = 'suspendido'),
    'ingresos_mes', (select coalesce(sum(monto), 0) from public.solicitudes_pago where estado = 'aprobada' and revisado_at >= greatest(m0, public.cfx_ingresos_desde()))
      + (select coalesce(sum(precio), 0) from public.keys where usada_at >= greatest(m0, public.cfx_ingresos_desde())),
    'pagos_pendientes', (select count(*) from public.solicitudes_pago where estado = 'pendiente'),
    'quieren_pro', (select count(*) from public.negocios n where estado = 'activo' and quiere_pro_at > now() - interval '30 days' and privado.estado_plan(n.id) <> 'pro'),
    'nuevos_7d', (select count(*) from public.negocios where creado > now() - interval '7 days'),
    'nuevos_30d', (select count(*) from public.negocios where creado > now() - interval '30 days'),
    'mrr', (select count(*) from public.negocios n where estado <> 'eliminado' and privado.estado_plan(n.id) = 'pro') * (select precio_mensual from public.ajustes where id = 1)
      + (select coalesce(sum(conexiones_extra), 0) from public.negocios n where estado <> 'eliminado' and privado.estado_plan(n.id) = 'pro') * (select precio_paquete from public.ajustes where id = 1),
    'conexiones', (select count(*) from public.conexiones where estado = 'activa'),
    'convertidos', (select count(*) from public.negocios where activado),
    'referidos_30d', (select count(*) from public.negocios where referido_por is not null and creado > now() - interval '30 days'),
    'anuales', (select count(*) from public.solicitudes_pago where estado = 'aprobada' and meses = 12 and revisado_at > now() - interval '365 days'),
    'registros_dia', coalesce((select jsonb_agg(x order by x.dia) from (select (creado at time zone 'America/Santiago')::date dia, count(*) n
        from public.negocios where creado > now() - interval '30 days' group by 1) x), '[]'::jsonb),
    'soporte_sin_leer', (select count(distinct negocio) from public.soporte where de = 'negocio' and not leido),
    'clientes_total', (select count(*) from public.clientes where estado <> 'borrado'),
    'movimientos_mes', (select coalesce(sum(movimientos + caja), 0) from public.uso_mensual where mes = m0),
    'bd_mb', round(pg_database_size(current_database()) / 1048576.0, 1),
    'archivos_mb', (select round(coalesce(sum((metadata ->> 'size')::bigint), 0) / 1048576.0, 1) from storage.objects),
    'cola_push', (select count(*) from public.cola_push where tomado_at is null),
    'cron_ok', (select count(*) from cron.job where jobname like 'lc-%') >= 2,
    'push_ok', exists (select 1 from privado.secretos where nombre = 'vapid_private'),
    'vencen', coalesce((select jsonb_agg(x order by x.fecha) from (
        select n.id, n.nombre, n.whatsapp, case when privado.estado_plan(n.id) = 'pro' then 'pro' else 'prueba' end tipo,
          case when privado.estado_plan(n.id) = 'pro' then n.premium_hasta else n.prueba_hasta end fecha
        from public.negocios n where n.estado = 'activo' and privado.estado_plan(n.id) in ('pro', 'prueba')
          and (case when privado.estado_plan(n.id) = 'pro' then n.premium_hasta else n.prueba_hasta end at time zone 'America/Santiago')::date <= privado.hoy() + 1
        limit 50) x), '[]'::jsonb));
end $$;

create or replace function public.admin_negocios(p_buscar text, p_filtro text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform privado.solo_admin();
  return coalesce((select jsonb_agg(x) from (
    select n.id, n.nombre, n.rubro, n.estado, n.motivo_suspension, n.premium_hasta, n.prueba_hasta, n.activado,
      privado.estado_plan(n.id) plan, privado.es_premium(n.id) premium,
      n.ultimo_uso, n.creado, n.nota_admin, n.whatsapp, u.email, n.conexiones_extra,
      (select count(*) from public.conexiones cx where (cx.a = n.id or cx.b = n.id) and cx.estado = 'activa') conexiones,
      (select count(*) from public.clientes c where c.negocio = n.id and c.estado = 'activo') clientes,
      (select coalesce(movimientos + caja, 0) from public.uso_mensual um where um.negocio = n.id and um.mes = date_trunc('month', privado.hoy())::date) movimientos_mes,
      (select count(*) from public.soporte s where s.negocio = n.id and s.de = 'negocio' and not s.leido) soporte
    from public.negocios n join auth.users u on u.id = n.dueno
    where (coalesce(p_buscar, '') = '' or privado.norm(n.nombre) like '%' || privado.norm(p_buscar) || '%' or lower(u.email) like '%' || lower(p_buscar) || '%')
      and (coalesce(p_filtro, 'todos') = 'todos'
        or (p_filtro in ('premium', 'pro') and privado.estado_plan(n.id) = 'pro' and n.estado <> 'eliminado')
        or (p_filtro = 'prueba' and privado.estado_plan(n.id) = 'prueba' and n.estado <> 'eliminado')
        or (p_filtro in ('free', 'bloqueado') and privado.estado_plan(n.id) = 'free' and n.estado = 'activo')
        or (p_filtro = 'suspendido' and n.estado = 'suspendido')
        or (p_filtro = 'vence' and n.estado = 'activo' and ((privado.estado_plan(n.id) = 'pro' and n.premium_hasta < now() + interval '7 days')
            or (privado.estado_plan(n.id) = 'prueba' and n.prueba_hasta < now() + interval '3 days')))
        or (p_filtro = 'inactivos' and n.estado = 'activo' and coalesce(n.ultimo_uso, n.creado) < now() - interval '7 days')
        or (p_filtro = 'eliminado' and n.estado = 'eliminado'))
    order by n.creado desc limit 300) x), '[]'::jsonb);
end $$;

create or replace function public.admin_oportunidades() returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform privado.solo_admin();
  return jsonb_build_object(
    'quieren_pro', coalesce((select jsonb_agg(x order by x.fecha desc) from (select n.id, n.nombre, n.whatsapp, u.email, n.quiere_pro_at fecha, privado.estado_plan(n.id) plan
        from public.negocios n join auth.users u on u.id = n.dueno where n.estado = 'activo' and n.quiere_pro_at > now() - interval '30 days' and privado.estado_plan(n.id) <> 'pro') x), '[]'::jsonb),
    'prueba_termina', coalesce((select jsonb_agg(x order by x.fecha) from (select n.id, n.nombre, n.whatsapp, u.email, n.prueba_hasta fecha, n.ultimo_uso
        from public.negocios n join auth.users u on u.id = n.dueno where n.estado = 'activo' and privado.estado_plan(n.id) = 'prueba' and n.prueba_hasta < now() + interval '3 days') x), '[]'::jsonb),
    'pro_vence', coalesce((select jsonb_agg(x order by x.fecha) from (select n.id, n.nombre, n.whatsapp, u.email, n.premium_hasta fecha
        from public.negocios n join auth.users u on u.id = n.dueno where n.estado = 'activo' and privado.estado_plan(n.id) = 'pro' and n.premium_hasta < now() + interval '7 days') x), '[]'::jsonb),
    'bloqueados', '[]'::jsonb, -- compatibilidad con el panel v1.3 mientras se actualiza
    'free', coalesce((select jsonb_agg(x order by x.ultimo_uso desc nulls last) from (select n.id, n.nombre, n.whatsapp, u.email, n.ultimo_uso, n.activado
        from public.negocios n join auth.users u on u.id = n.dueno where n.estado = 'activo' and privado.estado_plan(n.id) = 'free' and n.ultimo_uso > now() - interval '30 days' limit 50) x), '[]'::jsonb));
end $$;

create or replace function public.admin_negocio_detalle(p_negocio uuid) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m0 date := date_trunc('month', privado.hoy())::date;
begin
  perform privado.solo_admin();
  return jsonb_build_object(
    'clientes', (select count(*) from public.clientes where negocio = p_negocio and estado = 'activo'),
    'movimientos_mes', (select coalesce(movimientos, 0) from public.uso_mensual where negocio = p_negocio and mes = m0),
    'caja_mes', (select coalesce(caja, 0) from public.uso_mensual where negocio = p_negocio and mes = m0),
    'movimientos_total', (select count(*) from public.movimientos where negocio = p_negocio) + (select count(*) from public.caja where negocio = p_negocio),
    'dias_activo', (select count(distinct (creado_at at time zone 'America/Santiago')::date) from (
        select creado_at from public.movimientos where negocio = p_negocio union all select creado_at from public.caja where negocio = p_negocio) x),
    'pagos', coalesce((select jsonb_agg(x order by x.creado desc) from (select monto, estado, creado, revisado_at from public.solicitudes_pago where negocio = p_negocio limit 24) x), '[]'::jsonb),
    'keys', coalesce((select jsonb_agg(x order by x.usada_at desc) from (select codigo, meses, usada_at from public.keys where usada_por = p_negocio) x), '[]'::jsonb),
    'quiere_pro_at', (select quiere_pro_at from public.negocios where id = p_negocio),
    'invitados', (select count(*) from public.negocios where referido_por = p_negocio),
    'premiados', (select count(*) from public.negocios where referido_por = p_negocio and ref_dias > 0),
    'invitado_por', (select r.nombre from public.negocios n join public.negocios r on r.id = n.referido_por where n.id = p_negocio));
end $$;

create or replace function public.admin_plan(p_negocio uuid, p_accion text, p_dias int) returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform privado.solo_admin();
  if p_accion in ('sumar', 'prueba') and (p_dias is null or p_dias < 1 or p_dias > 3660) then perform privado.fallo('Días inválidos'); end if;
  if p_accion = 'conexiones' then
    -- p_dias = cantidad de paquetes extra de conexiones (0 a 200)
    if p_dias is null or p_dias < 0 or p_dias > 200 then perform privado.fallo('Paquetes inválidos (0 a 200)'); end if;
    update public.negocios set conexiones_extra = p_dias where id = p_negocio;
    perform privado.auditar(p_negocio, 'admin_plan', jsonb_build_object('accion', p_accion, 'paquetes', p_dias));
    return;
  end if;
  if p_accion = 'sumar' then
    update public.negocios set premium_hasta = greatest(coalesce(premium_hasta, now()), now()) + make_interval(days => p_dias), en_prueba = false, activado = true where id = p_negocio;
    perform privado.avisar_negocio(p_negocio, '¡Pro activado!', 'Se sumaron ' || p_dias || ' días de Pro a tu billetera.', 'app/#plan', true);
  elsif p_accion = 'prueba' then
    update public.negocios set prueba_hasta = greatest(coalesce(prueba_hasta, now()), now()) + make_interval(days => p_dias) where id = p_negocio;
    perform privado.avisar_negocio(p_negocio, 'Tu prueba Pro se extendió', 'Tienes ' || p_dias || ' días más de Pro gratis.', 'app/#plan', true);
  elsif p_accion = 'quitar' then
    -- Quita el Pro pagado y la prueba: pasa a Free al instante (no se borra nada).
    update public.negocios set premium_hasta = case when premium_hasta > now() - interval '30 days' then now() - interval '30 days' else premium_hasta end,
      prueba_hasta = least(coalesce(prueba_hasta, now()), now()), en_prueba = false where id = p_negocio;
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
  if p_aprobar and s.tipo = 'conexiones' then
    update public.negocios set conexiones_extra = least(200, conexiones_extra + s.paquetes) where id = s.negocio;
    update public.solicitudes_pago set estado = 'aprobada', revisado_at = now() where id = p_id;
    perform privado.avisar_negocio(s.negocio, '¡Conexiones sumadas!', 'Ya tienes ' || privado.limite_conexiones(s.negocio) || ' conexiones disponibles.', 'app/#conexiones', true);
  elsif p_aprobar then
    if s.cupon is not null and not (select activado from public.negocios where id = s.negocio) then
      update public.cupones set usos = usos + 1 where codigo = s.cupon;
    end if;
    update public.negocios set premium_hasta = greatest(coalesce(premium_hasta, now()), now()) + make_interval(months => s.meses), en_prueba = false, activado = true where id = s.negocio;
    update public.solicitudes_pago set estado = 'aprobada', revisado_at = now() where id = p_id;
    perform privado.aplicar_plan(s.negocio);
    perform privado.avisar_negocio(s.negocio, '¡Pago aprobado!', 'Tu Pro quedó activo por ' || case when s.meses = 12 then '1 año' else '1 mes' end || '. ¡Gracias!', 'app/#plan', true);
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
  if p_destino not in ('todos', 'pro', 'prueba', 'free', 'vencen', 'negocio', 'premium', 'normal') then perform privado.fallo('Destino inválido'); end if;
  for r in select n.id from public.negocios n where n.estado = 'activo' and (
      p_destino = 'todos' or (p_destino = 'negocio' and n.id = p_negocio)
      or (p_destino in ('pro', 'premium') and privado.estado_plan(n.id) = 'pro')
      or (p_destino = 'prueba' and privado.estado_plan(n.id) = 'prueba')
      or (p_destino in ('free', 'normal') and privado.estado_plan(n.id) = 'free')
      or (p_destino = 'vencen' and ((privado.estado_plan(n.id) = 'pro' and n.premium_hasta < now() + interval '7 days')
                                 or (privado.estado_plan(n.id) = 'prueba' and n.prueba_hasta < now() + interval '3 days'))))
  loop
    perform privado.avisar_negocio(r.id, v_t, v_c, 'app/#avisos', true);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- Cuántas billeteras recibirían un aviso masivo según el grupo
create or replace function public.admin_segmentos() returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform privado.solo_admin();
  return (select jsonb_build_object('todos', count(*),
      'pro', count(*) filter (where e = 'pro'), 'prueba', count(*) filter (where e = 'prueba'), 'free', count(*) filter (where e = 'free'),
      'vencen', count(*) filter (where (e = 'pro' and premium_hasta < now() + interval '7 days') or (e = 'prueba' and prueba_hasta < now() + interval '3 days')))
    from (select privado.estado_plan(n.id) e, n.premium_hasta, n.prueba_hasta from public.negocios n where n.estado = 'activo') x);
end $$;

create or replace function public.admin_cupones() returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform privado.solo_admin();
  return coalesce((select jsonb_agg(x order by x.creado desc) from (select c.*, privado.cupon_valido(c.codigo) valido,
      (select count(*) from public.negocios n where n.cupon = c.codigo and not n.activado) aplicados from public.cupones c) x), '[]'::jsonb);
end $$;

create or replace function public.admin_guardar_cupon(p_codigo text, p_descuento int, p_usos_max int, p_vence date) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_cod text := upper(btrim(coalesce(p_codigo, '')));
begin
  perform privado.solo_admin();
  if v_cod !~ '^[A-Z0-9-]{3,20}$' then perform privado.fallo('El código debe tener de 3 a 20 letras, números o guiones'); end if;
  if p_descuento is null or p_descuento < 1 or p_descuento > 100 then perform privado.fallo('El descuento debe ser entre 1% y 100%'); end if;
  if p_usos_max is not null and (p_usos_max < 1 or p_usos_max > 100000) then perform privado.fallo('Usos inválidos'); end if;
  if p_vence is not null and p_vence < privado.hoy() then perform privado.fallo('La fecha de vencimiento ya pasó'); end if;
  insert into public.cupones (codigo, descuento, usos_max, vence) values (v_cod, p_descuento, p_usos_max, p_vence)
  on conflict (codigo) do update set descuento = excluded.descuento, usos_max = excluded.usos_max, vence = excluded.vence, activo = true;
end $$;

create or replace function public.admin_cupon_activo(p_codigo text, p_activo boolean) returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform privado.solo_admin();
  update public.cupones set activo = coalesce(p_activo, false) where codigo = p_codigo;
end $$;

create or replace function public.admin_guardar_ajustes(p jsonb) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare ln jsonb := p -> 'lim_normal'; k text;
begin
  perform privado.solo_admin();
  if ln is not null then
    foreach k in array array['clientes','movimientos','cuotas','productos','comprobantes','historial_meses','caja','categorias'] loop
      if not (ln ? k) or (ln ->> k)::int < 1 or (ln ->> k)::int > 100000 then perform privado.fallo('Límite inválido: ' || k); end if;
    end loop;
  end if;
  if coalesce(p ->> 'version_liberada', '') <> '' and p ->> 'version_liberada' !~ '^\d{1,3}\.\d{1,3}\.\d{1,3}$' then perform privado.fallo('Versión inválida'); end if;
  if coalesce(p ->> 'version_min', '') <> '' and p ->> 'version_min' !~ '^\d{1,3}\.\d{1,3}\.\d{1,3}$' then perform privado.fallo('Versión mínima inválida'); end if;
  if coalesce(p ->> 'link_pago', '') <> '' and p ->> 'link_pago' !~ '^https://' then perform privado.fallo('El link de pago debe empezar con https://'); end if;
  if coalesce(p ->> 'link_pago_anual', '') <> '' and (p ->> 'link_pago_anual' !~ '^https://[^ ]+$' or char_length(p ->> 'link_pago_anual') > 300) then
    perform privado.fallo('El link de pago anual debe empezar con https://');
  end if;
  if p ? 'textos' and (jsonb_typeof(p -> 'textos') <> 'object' or length((p -> 'textos')::text) > 20000) then perform privado.fallo('Textos inválidos'); end if;
  if p ? 'planes' and (jsonb_typeof(p -> 'planes') <> 'object' or length((p -> 'planes')::text) > 20000) then perform privado.fallo('Planes inválidos'); end if;
  update public.ajustes set
    precio_mensual = coalesce((p ->> 'precio_mensual')::int, precio_mensual),
    precio_activacion = coalesce((p ->> 'precio_activacion')::int, precio_activacion),
    precio_anual = coalesce((p ->> 'precio_anual')::int, precio_anual),
    link_pago_anual = coalesce(btrim(p ->> 'link_pago_anual'), link_pago_anual),
    dias_referido = coalesce((p ->> 'dias_referido')::int, dias_referido),
    ref_min_registros = coalesce((p ->> 'ref_min_registros')::int, ref_min_registros),
    ref_max_premios = coalesce((p ->> 'ref_max_premios')::int, ref_max_premios),
    link_pago = coalesce(p ->> 'link_pago', link_pago),
    transferencia = coalesce(p -> 'transferencia', transferencia),
    contacto_whatsapp = coalesce(privado.telefono(nullif(p ->> 'contacto_whatsapp', '')), case when p ? 'contacto_whatsapp' then '' else contacto_whatsapp end),
    dias_prueba = coalesce((p ->> 'dias_prueba')::int, dias_prueba),
    dias_gracia = coalesce((p ->> 'dias_gracia')::int, dias_gracia),
    conexiones_incluidas = coalesce((p ->> 'conexiones_incluidas')::int, conexiones_incluidas),
    conexiones_paquete = coalesce((p ->> 'conexiones_paquete')::int, conexiones_paquete),
    precio_paquete = coalesce((p ->> 'precio_paquete')::int, precio_paquete),
    textos = coalesce(p -> 'textos', textos),
    planes = coalesce(p -> 'planes', planes),
    links_pro = case when p ? 'links_pro' then privado.links_validos(p -> 'links_pro') else links_pro end,
    dias_comprobantes = coalesce((p ->> 'dias_comprobantes')::int, dias_comprobantes),
    dias_aviso = coalesce((p ->> 'dias_aviso')::int, dias_aviso),
    lim_normal = coalesce(ln, lim_normal),
    version_legal = coalesce((p ->> 'version_legal')::int, version_legal),
    version_min = coalesce(nullif(p ->> 'version_min', ''), version_min),
    version_liberada = coalesce(nullif(p ->> 'version_liberada', ''), version_liberada),
    actualizado = now()
   where id = 1;
  if p ? 'links_pro' then update public.ajustes set link_pago = coalesce(privado.link_activo(links_pro), '') where id = 1; end if;
  perform privado.auditar(null, 'ajustes', jsonb_build_object('claves', (select jsonb_agg(ck) from jsonb_object_keys(p) ck)));
end $$;

-- Registro de cambios (lo que hiciste tú y acciones importantes)
create or replace function public.admin_auditoria() returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform privado.solo_admin();
  return coalesce((select jsonb_agg(x order by x.at desc) from (select a.at, a.accion, a.detalle, n.nombre negocio
    from public.auditoria a left join public.negocios n on n.id = a.negocio order by a.at desc limit 200) x), '[]'::jsonb);
end $$;

-- Uso del servidor tabla por tabla
create or replace function public.admin_uso() returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform privado.solo_admin();
  return jsonb_build_object('bd_mb', round(pg_database_size(current_database()) / 1048576.0, 1),
    'tablas', (select jsonb_agg(x order by x.bytes desc) from (select c.relname tabla, pg_total_relation_size(c.oid) bytes, c.reltuples::bigint filas
      from pg_class c join pg_namespace s on s.oid = c.relnamespace where s.nspname = 'public' and c.relkind = 'r') x),
    'archivos', (select jsonb_agg(x) from (select bucket_id bucket, count(*) n, round(coalesce(sum((metadata ->> 'size')::bigint), 0) / 1048576.0, 1) mb
      from storage.objects group by bucket_id) x));
end $$;

-- Botones de limpieza
create or replace function public.admin_limpiar(p_que text) returns int language plpgsql security definer set search_path = public, pg_temp as $$
declare n int := 0; d int := (select dias_comprobantes from public.ajustes where id = 1);
begin
  perform privado.solo_admin();
  if p_que = 'avisos' then
    delete from public.notificaciones where leido and creado < now() - interval '30 days'; get diagnostics n = row_count;
  elsif p_que = 'cola' then
    delete from public.cola_push where tomado_at is not null; get diagnostics n = row_count;
  elsif p_que = 'sesiones' then
    delete from public.sesiones_cliente where vence < now(); get diagnostics n = row_count;
  elsif p_que = 'auditoria' then
    delete from public.auditoria where at < now() - interval '180 days'; get diagnostics n = row_count;
  elsif p_que = 'soporte' then
    delete from public.soporte where creado < now() - interval '30 days'; get diagnostics n = row_count;
  elsif p_que = 'comprobantes' then
    insert into privado.archivos_por_borrar (bucket, ruta) select 'comprobantes', foto_path from public.comprobantes
      where foto_path is not null and estado <> 'pendiente' and revisado_at < now() - make_interval(days => d);
    update public.comprobantes set foto_path = null where foto_path is not null and estado <> 'pendiente' and revisado_at < now() - make_interval(days => d);
    get diagnostics n = row_count;
    insert into privado.archivos_por_borrar (bucket, ruta) select 'comprobantes', foto_path from public.movimientos where foto_path is not null and creado_at < now() - make_interval(days => d);
    update public.movimientos set foto_path = null where foto_path is not null and creado_at < now() - make_interval(days => d);
    perform privado.llamar_funcion('{"accion": "limpiar"}'::jsonb);
  else
    perform privado.fallo('Limpieza desconocida');
  end if;
  perform privado.auditar(null, 'limpiar', jsonb_build_object('que', p_que, 'filas', n));
  return n;
end $$;

-- La billetera borra las fotos de los comprobantes ya revisados (se guardan los datos del pago)
create or replace function public.limpiar_comprobantes() returns int language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true, true); n int;
begin
  insert into privado.archivos_por_borrar (bucket, ruta) select 'comprobantes', foto_path from public.comprobantes where negocio = v_neg and foto_path is not null and estado <> 'pendiente';
  update public.comprobantes set foto_path = null where negocio = v_neg and foto_path is not null and estado <> 'pendiente';
  get diagnostics n = row_count;
  return n;
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
create or replace function public.srv_es_admin(p_uid uuid) returns boolean language sql stable security definer set search_path = public, pg_temp as
  $$ select p_uid is not null and p_uid = privado.admin_id() $$;

create or replace function public.srv_crear_negocio(p_uid uuid, p_nombre text, p_rubro text, p_pro_dias int) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare r jsonb;
begin
  r := privado.crear_negocio_para(p_uid, p_nombre, p_rubro);
  if coalesce(p_pro_dias, 0) > 0 then
    update public.negocios set premium_hasta = now() + make_interval(days => least(p_pro_dias, 3660)), activado = true where id = (r ->> 'id')::uuid;
    perform privado.aplicar_plan((r ->> 'id')::uuid);
  end if;
  return r;
end $$;

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
-- G99 a ⚡ Dónde avisa Mercado Pago (núcleo cfx_mp_notif): la función "enviar".
create or replace function public.cfx_mp_aviso_url_app() returns text language sql stable security definer set search_path = '' as $f$ select valor || '/functions/v1/enviar' from privado.config where clave = 'url_proyecto' $f$;
revoke all on function public.cfx_mp_aviso_url_app() from public, anon, authenticated;
create or replace function privado.llamar_funcion(p_body jsonb) returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  perform net.http_post(url := (select valor from privado.config where clave = 'url_proyecto') || '/functions/v1/enviar',
    body := p_body, headers := jsonb_build_object('Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (select valor from privado.config where clave = 'anon_key'),
      'apikey', (select valor from privado.config where clave = 'anon_key')));
exception when others then raise notice 'llamar_funcion: %', sqlerrm;
end $$;

create or replace function privado.tarea_cola() returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  -- G61 a: también cuando hay avisos sin confirmar que toca reenviar (push insistente del núcleo).
  if exists (select 1 from public.cola_push where tomado_at is null)
     or (to_regclass('public.cfx_push_entrega') is not null and exists (select 1 from public.cfx_push_entrega where recibido_at is null and proximo <= now() and created_at > now() - interval '48 hours'))
  then perform privado.llamar_funcion('{}'::jsonb); end if;
  delete from public.cola_push where tomado_at < now() - interval '2 days';
end $$;

create or replace function privado.tarea_horaria() returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare ahora timestamp := now() at time zone 'America/Santiago'; hoy date := ahora::date; h int := extract(hour from ahora); r record; c record;
  v_txt text; n_hoy int; n_atr int; m_atr bigint; dias int; ok boolean; n_man int;
begin
  -- 1) Diaria (desde las 00:00): vencimientos, planes, limpieza
  if not exists (select 1 from privado.tareas_hechas where tarea = 'diaria' and fecha = hoy) then
    insert into privado.tareas_hechas values ('diaria', hoy);
    for c in select id from public.clientes where estado <> 'borrado' and saldo > 0 and prox_venc < hoy and not atrasado loop
      perform privado.recalcular(c.id);
    end loop;
    for r in select id from public.negocios where estado <> 'eliminado' loop perform privado.aplicar_plan(r.id); end loop;
    perform privado.premiar_referidos();
    for r in select id, dueno from public.negocios where estado = 'eliminado' and eliminar_desde < now() loop
      insert into privado.archivos_por_borrar (bucket, ruta) select 'comprobantes', foto_path from public.comprobantes where negocio = r.id and foto_path is not null;
      insert into privado.archivos_por_borrar (bucket, ruta) select 'comprobantes', foto_path from public.movimientos where negocio = r.id and foto_path is not null;
      insert into privado.archivos_por_borrar (bucket, ruta) select 'pagos', comprobante_path from public.solicitudes_pago where negocio = r.id and comprobante_path is not null;
      delete from public.negocios where id = r.id;
      delete from auth.users where id = r.dueno;
    end loop;
    delete from public.sesiones_cliente where vence < now();
    delete from privado.limites where ventana < floor(extract(epoch from now()) / 86400) - 2 and ventana < floor(extract(epoch from now()) / 3600) - 48;
    delete from public.invitaciones where vence < now() - interval '7 days';
    delete from privado.fotos_pendientes where vence < now();
    -- v12: avisos y chat de soporte se guardan 30 días. Antes se avisa (máx. 1 vez por semana; cuenta lo que se borra en los próximos 9 días).
    for r in select n.id, n.dueno,
               (select count(*) from public.notificaciones x where (x.negocio = n.id or x.usuario = n.dueno) and x.creado < now() - interval '21 days') as av,
               (select count(*) from public.soporte x where x.negocio = n.id and x.creado < now() - interval '21 days') as ch
             from public.negocios n where n.estado <> 'eliminado' and (n.aviso_limpieza_at is null or n.aviso_limpieza_at < now() - interval '7 days')
               and (exists (select 1 from public.notificaciones x where (x.negocio = n.id or x.usuario = n.dueno) and x.creado < now() - interval '28 days')
                 or exists (select 1 from public.soporte x where x.negocio = n.id and x.creado < now() - interval '28 days'))
    loop
      perform privado.avisar_negocio(r.id, 'Limpieza automática',
        concat_ws(' y ', case when r.av = 1 then '1 aviso' when r.av > 1 then r.av || ' avisos' end, case when r.ch = 1 then '1 mensaje de soporte' when r.ch > 1 then r.ch || ' mensajes de soporte' end)
          || ' con más de 30 días se borran solos en los próximos días. Tus clientes, ventas y movimientos no se tocan.', 'app/#avisos', false);
      update public.negocios set aviso_limpieza_at = now() where id = r.id;
    end loop;
    delete from public.notificaciones where creado < now() - interval '30 days';
    delete from public.soporte where creado < now() - interval '30 days';
    -- Fotos de comprobantes: se borran solas a los N días (Ajustes → Reglas)
    insert into privado.archivos_por_borrar (bucket, ruta)
      select 'comprobantes', foto_path from public.comprobantes where foto_path is not null and estado <> 'pendiente'
        and revisado_at < now() - make_interval(days => (select dias_comprobantes from public.ajustes where id = 1));
    update public.comprobantes set foto_path = null where foto_path is not null and estado <> 'pendiente'
      and revisado_at < now() - make_interval(days => (select dias_comprobantes from public.ajustes where id = 1));
    delete from privado.tareas_hechas where fecha < hoy - 30;
  end if;

  -- 2) Resumen de las 09:00 y avisos de plan
  if h >= 9 and not exists (select 1 from privado.tareas_hechas where tarea = 'resumen' and fecha = hoy) then
    insert into privado.tareas_hechas values ('resumen', hoy);
    for r in select n.id, n.premium_hasta, n.prueba_hasta, privado.estado_plan(n.id) est from public.negocios n where n.estado = 'activo' loop
      if true then
        select count(*) filter (where prox_venc = hoy), count(*) filter (where atrasado), coalesce(sum(saldo) filter (where atrasado), 0),
               count(*) filter (where prox_venc = hoy + 1)
          into n_hoy, n_atr, m_atr, n_man from public.clientes where negocio = r.id and saldo > 0 and estado <> 'borrado';
        if n_hoy + n_atr + n_man > 0 then
          v_txt := concat_ws(' · ', case when n_hoy > 0 then n_hoy || ' vencen hoy' end,
                                    case when n_man > 0 then n_man || ' vencen mañana' end,
                                    case when n_atr > 0 then n_atr || ' atrasados por ' || privado.pesos(m_atr) end);
          perform privado.avisar_negocio(r.id, 'Para cobrar hoy', v_txt, 'app/', r.est = 'pro');
        end if;
      end if;
      if r.est = 'prueba' then
        dias := (r.prueba_hasta at time zone 'America/Santiago')::date - hoy;
        if dias in (3, 1, 0) then
          perform privado.avisar_negocio(r.id, case when dias = 0 then 'Hoy termina tu prueba Pro' else 'Te quedan ' || dias || ' días de prueba Pro' end,
            'Después tu billetera sigue gratis, pero las funciones Pro quedan en pausa. Actívalo en Más → Mi plan.', 'app/#plan', true);
        end if;
      elsif r.est = 'pro' and r.premium_hasta is not null then
        dias := (r.premium_hasta at time zone 'America/Santiago')::date - hoy;
        if dias = any (array[(select dias_aviso from public.ajustes where id = 1), 3, 1, 0]) then
          perform privado.avisar_negocio(r.id, case when dias = 0 then 'Tu mensualidad de Pro vence hoy' else 'Tu mensualidad de Pro vence en ' || dias || ' días' end,
            'Paga desde Más → Mi plan para no perder las funciones Pro.', 'app/#plan', true);
        elsif dias < 0 then
          perform privado.avisar_negocio(r.id, 'Mensualidad vencida: estás en días de gracia', 'Paga para no perder las funciones Pro.', 'app/#plan', true);
        end if;
      end if;
    end loop;
    -- Alerta diaria al administrador: a quién se le vence el Pro o la prueba hoy o mañana
    select string_agg(n.nombre, ', ' order by n.nombre), count(*) into v_txt, n_hoy from public.negocios n
     where n.estado = 'activo' and (
       (privado.estado_plan(n.id) = 'pro' and (n.premium_hasta at time zone 'America/Santiago')::date between hoy and hoy + 1)
       or (privado.estado_plan(n.id) = 'prueba' and (n.prueba_hasta at time zone 'America/Santiago')::date between hoy and hoy + 1));
    if n_hoy > 0 then
      perform privado.avisar_usuario(privado.admin_id(), n_hoy || ' billetera' || case when n_hoy > 1 then 's vencen' else ' vence' end || ' hoy o mañana',
        left(v_txt, 250), 'admin/#resumen', true);
    end if;
  end if;

  -- 2b) Resumen semanal de caja (lunes desde las 09:00, Pro)
  if h >= 9 and extract(isodow from ahora) = 1 and not exists (select 1 from privado.tareas_hechas where tarea = 'semana' and fecha = hoy) then
    insert into privado.tareas_hechas values ('semana', hoy);
    for r in select n.id from public.negocios n where n.estado = 'activo' and privado.estado_plan(n.id) = 'pro' loop
      select coalesce(sum(monto) filter (where tipo = 'ingreso'), 0), coalesce(sum(monto) filter (where tipo = 'gasto'), 0) into n_hoy, n_atr
        from public.caja where negocio = r.id and anulado_at is null and fecha >= now() - interval '7 days';
      select coalesce(sum(monto), 0) into m_atr from public.movimientos where negocio = r.id and tipo = 'abono' and anulado_at is null and fecha >= now() - interval '7 days';
      if n_hoy + n_atr + m_atr > 0 then
        perform privado.avisar_negocio(r.id, 'Tu semana', 'Entró ' || privado.pesos(n_hoy + m_atr) || ' · salió ' || privado.pesos(n_atr) || ' · balance ' ||
          case when n_hoy + m_atr - n_atr < 0 then '-' else '' end || privado.pesos(n_hoy + m_atr - n_atr), 'app/#caja', true);
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
    -- Ahorro de espacio: fotos de pagos de Pro ya revisados, recordatorios y auditoría viejos
    insert into privado.archivos_por_borrar (bucket, ruta)
      select 'pagos', comprobante_path from public.solicitudes_pago where comprobante_path is not null and estado <> 'pendiente' and revisado_at < now() - interval '180 days';
    update public.solicitudes_pago set comprobante_path = null where comprobante_path is not null and estado <> 'pendiente' and revisado_at < now() - interval '180 days';
    delete from public.recordatorios where at < now() - interval '400 days';
    insert into privado.archivos_por_borrar (bucket, ruta) select 'comprobantes', foto_path from public.movimientos where foto_path is not null and creado_at < now() - interval '365 days';
    update public.movimientos set foto_path = null where foto_path is not null and creado_at < now() - interval '365 days';
    delete from public.auditoria where at < now() - interval '400 days';
    delete from public.uso_mensual where mes < privado.hoy() - 800;
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
    'keys','feriados','auditoria','caja','categorias','soporte','cupones','conexiones','conexion_movs'] loop
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
create policy lectura on public.caja for select to authenticated using (negocio = (select privado.mi_negocio()));
create policy lectura on public.categorias for select to authenticated using (negocio = (select privado.mi_negocio()));
create policy lectura on public.soporte for select to authenticated using (negocio = (select privado.mi_negocio()) or (select privado.es_admin()));
create policy lectura on public.auditoria for select to authenticated using (negocio = (select privado.mi_negocio()) and (select privado.mi_rol()) = 'dueno');

grant usage on schema public to anon, authenticated, service_role;
grant select (id, dueno, nombre, rubro, whatsapp, banco, venc_defecto, limite_general, pin_activo, saldo_a_favor, logo_url, color,
  plantilla_propia, premium_hasta, en_prueba, plan_aplicado, estado, motivo_suspension, eliminar_desde, ultimo_uso, creado, prueba_hasta, activado, quiere_pro_at, meta_ventas, presupuesto_gastos, icono, cupon, link_pago, links_pago) on public.negocios to authenticated;
grant select on public.ajustes, public.feriados, public.perfiles, public.miembros, public.ventas_cuotas, public.cuotas,
  public.movimientos, public.recordatorios, public.productos, public.uso_mensual, public.notificaciones, public.solicitudes_pago,
  public.auditoria, public.caja, public.categorias, public.soporte to authenticated;
grant select (id, negocio, nombre, apodo, telefono, rut, nota, limite, estado, bloqueado, fuera_de_plan, saldo, prox_venc, atrasado, puntaje,
  ultimo_mov, link_codigo, link_bloqueado, creado, link_pago) on public.clientes to authenticated;
grant select (id, negocio, cliente, monto, fecha, comentario, foto_path, estado, motivo, abono, revisado_at, creado) on public.comprobantes to authenticated;
grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;

-- Funciones: nadie las puede llamar salvo las que se autorizan abajo
revoke all on all functions in schema public from public, anon, authenticated;
revoke all on all functions in schema privado from public, anon, authenticated;
grant execute on function privado.mi_negocio(), privado.mi_rol(), privado.mi_premium(), privado.es_admin(), privado.es_premium(uuid), privado.estado_plan(uuid) to authenticated;
grant execute on function public.ping(), public.config_publica(), public.portal_info(text), public.portal_entrar(text, text), public.portal_ver(text),
  public.portal_confirmar(text, uuid, boolean, text), public.portal_comprobante(text, int, date, text, boolean),
  public.portal_push(text, text, text, text), public.portal_salir(text) to anon, authenticated;
grant execute on function public.mi_estado(), public.aceptar_terminos(), public.crear_negocio(text, text, boolean, text), public.guardar_negocio(jsonb), public.mi_referidos(),
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
  public.admin_set_secret(text, text), public.admin_feriado(date, text, boolean),
  public.registrar_caja(uuid, text, int, text, text, text, timestamptz, boolean), public.anular_caja(uuid, text), public.guardar_categoria(text, text),
  public.borrar_categoria(uuid), public.resumen_caja(date), public.soporte_enviar(text), public.soporte_leer(), public.admin_soporte_lista(),
  public.admin_soporte_ver(uuid), public.admin_soporte_enviar(uuid, text), public.guardar_metas(int, int), public.pedir_pro(),
  public.admin_oportunidades(), public.admin_negocio_detalle(uuid),
  public.guardar_perfil(text, text), public.usar_cupon(text), public.reporte_pro(date), public.cobranza_lote(),
  public.admin_segmentos(), public.admin_cupones(), public.admin_guardar_cupon(text, int, int, date), public.admin_cupon_activo(text, boolean),
  public.guardar_link_pago_cliente(uuid, text), public.pagar_cuota(uuid, uuid, int, text, boolean),
  public.estado_fiados(uuid), public.pagar_fiado(uuid, uuid, int, text, text, boolean), public.adjuntar_foto(uuid, text),
  public.mi_codigo_conexion(boolean), public.conectar(text), public.conexion_responder(uuid, boolean), public.conexion_cerrar(uuid),
  public.mis_conexiones(), public.conexion_ver(uuid), public.conexion_anotar(uuid, uuid, text, int, text), public.conexion_resolver(uuid, boolean, text),
  public.conexion_anular(uuid), public.pedir_conexiones(int, text),
  public.admin_auditoria(), public.admin_uso(), public.admin_limpiar(text), public.limpiar_comprobantes() to authenticated;
grant execute on function public.srv_secretos(), public.srv_cola_tomar(int), public.srv_quitar_endpoint(text), public.srv_foto_validar(uuid, text),
  public.srv_foto_lista(uuid, text), public.srv_archivos_por_borrar(int), public.srv_archivos_borrados(bigint[]),
  public.srv_es_admin(uuid), public.srv_crear_negocio(uuid, text, text, int) to service_role;

-- =====================================================================
--  ARCHIVOS (Storage)
-- =====================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('comprobantes', 'comprobantes', false, 1048576, array['image/webp','image/jpeg','image/png']),
  ('logos', 'logos', true, 102400, array['image/webp','image/png','image/jpeg']),
  ('pagos', 'pagos', false, 1048576, array['image/webp','image/jpeg','image/png'])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists lc_comprobantes_ver on storage.objects;
drop policy if exists lc_comprobantes_subir on storage.objects;
drop policy if exists lc_logos_subir on storage.objects;
drop policy if exists lc_logos_cambiar on storage.objects;
drop policy if exists lc_logos_borrar on storage.objects;
drop policy if exists lc_logos_ver on storage.objects;
drop policy if exists lc_pagos_subir on storage.objects;
drop policy if exists lc_pagos_ver on storage.objects;
create policy lc_comprobantes_ver on storage.objects for select to authenticated
  using (bucket_id = 'comprobantes' and (storage.foldername(name))[1] = (select privado.mi_negocio())::text);
-- El dueño sube la foto del comprobante de un pago que recibió (carpeta <negocio>/pagos/)
create policy lc_comprobantes_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'comprobantes' and (storage.foldername(name))[1] = (select privado.mi_negocio())::text and (storage.foldername(name))[2] = 'pagos');
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
  foreach t in array array['movimientos','notificaciones','soporte'] loop
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

-- =====================================================================
--  v12 · Limpieza y respaldo: borrar avisos y chat de soporte, respaldo del administrador
-- =====================================================================
alter table public.negocios add column if not exists aviso_limpieza_at timestamptz;

-- Borrar avisos: uno (p_id) o todos (p_id null) de los que ves.
create or replace function public.borrar_avisos(p_id bigint default null) returns int language plpgsql security definer set search_path = public, pg_temp as $$
declare n int;
begin
  if auth.uid() is null then perform privado.fallo('Ingresa de nuevo.'); end if;
  delete from public.notificaciones where (usuario = auth.uid() or negocio = privado.mi_negocio()) and (p_id is null or id = p_id);
  get diagnostics n = row_count;
  return n;
end $$;

-- Borrar el chat de soporte (el dueño, o el administrador para una billetera).
create or replace function public.soporte_borrar() returns int language plpgsql security definer set search_path = public, pg_temp as $$
declare v_neg uuid := privado.exigir(true, true); n int;
begin
  delete from public.soporte where negocio = v_neg;
  get diagnostics n = row_count;
  return n;
end $$;
create or replace function public.admin_soporte_borrar(p_negocio uuid) returns int language plpgsql security definer set search_path = public, pg_temp as $$
declare n int;
begin
  perform privado.solo_admin();
  delete from public.soporte where negocio = p_negocio;
  get diagnostics n = row_count;
  perform privado.auditar(p_negocio, 'soporte_borrado', jsonb_build_object('filas', n));
  return n;
end $$;

-- Respaldo del administrador: billeteras, pagos de Pro, keys (sin el código), cupones y registro. No incluye clientes ni movimientos de nadie.
create or replace function public.cfx_respaldo() returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform privado.solo_admin();
  return jsonb_build_object(
    'Billeteras', coalesce((select jsonb_agg(x order by x.creada) from (select n.nombre, u.email as correo, n.rubro, n.whatsapp, privado.estado_plan(n.id) as plan,
        n.premium_hasta as pro_hasta, n.prueba_hasta, n.estado, n.ultimo_uso, n.creado as creada,
        (select count(*) from public.clientes c where c.negocio = n.id and c.estado <> 'borrado') as clientes
      from public.negocios n left join auth.users u on u.id = n.dueno where n.estado <> 'eliminado') x), '[]'::jsonb),
    'Pagos de Pro', coalesce((select jsonb_agg(x order by x.fecha) from (select s.creado as fecha, n.nombre as billetera, s.monto, s.estado, s.cupon,
        s.revisado_at as revisado, (s.comprobante_path is not null) as con_comprobante
      from public.solicitudes_pago s left join public.negocios n on n.id = s.negocio) x), '[]'::jsonb),
    'Keys', coalesce((select jsonb_agg(to_jsonb(k) - 'codigo' - 'hash' - 'codigo_hash') from public.keys k), '[]'::jsonb),
    'Cupones', coalesce((select jsonb_agg(to_jsonb(c)) from public.cupones c), '[]'::jsonb),
    'Registro', coalesce((select jsonb_agg(x order by x.fecha) from (select a.at as fecha, a.accion, a.detalle, n.nombre as billetera
      from public.auditoria a left join public.negocios n on n.id = a.negocio) x), '[]'::jsonb));
end $$;

-- Limpieza (común a las 6 apps): qué se puede borrar y cuántas filas son. cfx_limpiar usa admin_limpiar.
create or replace function public.cfx_limpieza_app() returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare d int := (select dias_comprobantes from public.ajustes where id = 1);
begin
  perform privado.solo_admin();
  return jsonb_build_array(
    jsonb_build_object('clave', 'comprobantes', 'titulo', 'Fotos de comprobantes revisados', 'detalle', 'Más de ' || d || ' días (se borran solas cada día).',
      'filas', (select count(*) from public.comprobantes where foto_path is not null and estado <> 'pendiente' and revisado_at < now() - make_interval(days => d))
             + (select count(*) from public.movimientos where foto_path is not null and creado_at < now() - make_interval(days => d))),
    jsonb_build_object('clave', 'avisos', 'titulo', 'Avisos leídos', 'detalle', 'Más de 30 días.', 'filas', (select count(*) from public.notificaciones where leido and creado < now() - interval '30 days')),
    jsonb_build_object('clave', 'soporte', 'titulo', 'Chat de soporte', 'detalle', 'Mensajes de más de 30 días.', 'filas', (select count(*) from public.soporte where creado < now() - interval '30 days')),
    jsonb_build_object('clave', 'cola', 'titulo', 'Cola de push enviada', 'detalle', 'Ya entregada.', 'filas', (select count(*) from public.cola_push where tomado_at is not null)),
    jsonb_build_object('clave', 'sesiones', 'titulo', 'Sesiones vencidas', 'detalle', 'Links de clientes ya vencidos.', 'filas', (select count(*) from public.sesiones_cliente where vence < now())),
    jsonb_build_object('clave', 'auditoria', 'titulo', 'Registro de cambios', 'detalle', 'Más de 180 días.', 'filas', (select count(*) from public.auditoria where at < now() - interval '180 days')));
end $$;
create or replace function public.cfx_limpiar_app(p_clave text) returns int language sql security definer set search_path = public, pg_temp as $$
  select public.admin_limpiar(p_clave) $$;
grant execute on function public.cfx_limpieza_app(), public.cfx_limpiar_app(text) to authenticated;

grant execute on function public.borrar_avisos(bigint), public.soporte_borrar(), public.admin_soporte_borrar(uuid), public.cfx_respaldo() to authenticated;



-- =====================================================================
--  Ganchos para el núcleo (pagos): la cuenta principal es la billetera del dueño; el Premium se aplica a su billetera.
-- =====================================================================
create or replace function public.cfx_yo() returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(
    (select jsonb_build_object('id', auth.uid(), 'email', u.email, 'nombre', n.nombre, 'premium_hasta', n.premium_hasta, 'creado', n.creado, 'rol', 'negocio')
       from public.negocios n join auth.users u on u.id = n.dueno where n.dueno = auth.uid() and n.estado <> 'eliminado' limit 1),
    (select jsonb_build_object('id', u.id, 'email', u.email, 'nombre', '', 'creado', u.created_at, 'rol', case when privado.es_admin() then 'admin' else 'otro' end)
       from auth.users u where u.id = auth.uid()))
$$;
create or replace function public.cfx_dar_premium(p_cuenta uuid, p_rol text, p_dias int) returns timestamptz language plpgsql security definer set search_path = public, pg_temp as $$
declare n record;
begin
  update public.negocios set premium_hasta = greatest(coalesce(premium_hasta, now()), now()) + make_interval(days => p_dias), activado = true, en_prueba = false
  where dueno = p_cuenta and estado <> 'eliminado' returning id, premium_hasta into n;
  if n.id is null then raise exception 'La cuenta no tiene billetera'; end if;
  perform privado.aplicar_plan(n.id);
  return n.premium_hasta;
end $$;
create or replace function public.cfx_avisar(p_cuenta uuid, p_titulo text, p_cuerpo text) returns void language sql security definer set search_path = public, pg_temp as
  $$ select privado.avisar_usuario(p_cuenta, p_titulo, p_cuerpo, 'app/#plan', true) $$;
create or replace function public.cfx_avisar_admin(p_titulo text, p_cuerpo text) returns void language sql security definer set search_path = public, pg_temp as
  $$ select privado.avisar_usuario(privado.admin_id(), p_titulo, p_cuerpo, 'admin/', true) $$;

-- G87 A · Lista de cuentas para el Centro de Mando → Control → Negocios (antes decía "aún no tiene la lista de negocios").
-- Negocio = cada billetera (con el correo de su dueño). Los clientes entran por el portal con código, sin cuenta: esa lista va vacía.
create or replace function public.cfx_cuentas_app(p_rol text, p_q text) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select case when p_rol = 'cliente' then '[]'::jsonb else
    (select coalesce(jsonb_agg(jsonb_build_object('id', n.dueno, 'email', coalesce(n.correo, ''), 'nombre', n.nombre, 'rol', 'negocio',
        'premium_hasta', case when n.premium_hasta > now() then n.premium_hasta end, 'creado', n.creado, 'suspendido', n.estado = 'suspendido') order by n.creado desc), '[]'::jsonb)
     from (select x.*, u.email::text as correo from public.negocios x left join auth.users u on u.id = x.dueno
           where x.estado <> 'eliminado' and (coalesce(p_q, '') = '' or x.nombre ilike '%' || p_q || '%' or coalesce(u.email::text, '') ilike '%' || p_q || '%')
           order by x.creado desc limit 300) n) end
$$;
create or replace function public.cfx_quitar_premium(p_cuenta uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v uuid;
begin
  update public.negocios set premium_hasta = null where dueno = p_cuenta and estado <> 'eliminado' returning id into v;
  if v is not null then perform privado.aplicar_plan(v); end if;
end $$;
revoke all on function public.cfx_cuentas_app(text, text), public.cfx_quitar_premium(uuid) from public, anon, authenticated;

-- Ganchos de administración para el núcleo (planes, textos, a quién avisar y verificación).
create or replace function public.cfx_planes_app() returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object('grupo', 'negocio', 'clave', k, 'free', a.lim_normal -> k, 'premium', a.lim_premium -> k) order by k), '[]')
  from public.ajustes a, lateral (select jsonb_object_keys(a.lim_normal || a.lim_premium) as k) x where a.id = 1
$$;
create or replace function public.cfx_plan_guardar_app(p_grupo text, p_clave text, p_free jsonb, p_premium jsonb) returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if p_grupo <> 'negocio' or p_clave !~ '^[a-z_]{2,40}$' then raise exception 'Plan no válido'; end if;
  update public.ajustes set lim_normal = lim_normal || jsonb_build_object(p_clave, p_free), lim_premium = lim_premium || jsonb_build_object(p_clave, p_premium) where id = 1;
end $$;
-- Textos: los guardados en ajustes.textos (los que no cambiaste salen con el texto de la app).
create or replace function public.cfx_textos_app() returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object('clave', d.k, 'valor', coalesce(a.textos ->> d.k, d.v)) order by d.k), '[]')
  from (values ('landing_titulo', 'Tu negocio en el bolsillo. Cobra sin vergüenza.'),
    ('landing_bajada', 'Ventas, gastos y fiado en 3 segundos. Tu cliente ve lo que debe con un link y te paga por transferencia.'),
    ('pro_titulo', 'Esto es Pro ⭐'),
    ('pago_instrucciones', 'Paga con el botón y después sube la foto del comprobante. {negocio} lo revisa y te avisa apenas lo apruebe.')) d(k, v), public.ajustes a where a.id = 1
$$;
create or replace function public.cfx_texto_guardar_app(p_clave text, p_valor text) returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if p_clave not in ('landing_titulo', 'landing_bajada', 'pro_titulo', 'pago_instrucciones') then raise exception 'Texto no encontrado'; end if;
  update public.ajustes set textos = textos || jsonb_build_object(p_clave, p_valor) where id = 1;
end $$;
create or replace function public.cfx_destinatarios(p_destino text) returns setof uuid language sql stable security definer set search_path = public, pg_temp as $$
  -- Todas las cuentas de cada billetera (dueño y ayudantes); "negocios" = solo los dueños.
  select distinct m.usuario from public.miembros m join public.negocios n on n.id = m.negocio where m.activo and n.estado <> 'eliminado' and p_destino <> 'clientes'
    and (p_destino = 'todos' or (p_destino = 'negocios' and m.rol = 'dueno') or (p_destino = 'premium' and privado.estado_plan(n.id) = 'pro') or (p_destino = 'gratis' and privado.estado_plan(n.id) <> 'pro'))
$$;
create or replace function public.cfx_marcar_verificado(p_cuenta uuid, p_si boolean) returns void
language sql security definer set search_path = '' as $$ select null::void $$;

-- Guía para partir (núcleo · ayuda): lo que le falta configurar al negocio. Se marca solo cuando lo hace.
create or replace function public.cfx_guia_app() returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select jsonb_build_array(
    jsonb_build_object('k', 'whatsapp', 't', 'Tu WhatsApp', 'd', 'Para enviar los recordatorios de cobro.', 'ir', 'app/#ajustes', 'ok', coalesce(n.whatsapp, '') <> ''),
    jsonb_build_object('k', 'cobro', 't', 'Cómo te pagan', 'd', 'Tus datos de transferencia o tu link de pago: van en cada recordatorio.', 'ir', 'app/#ajustes',
      'ok', (coalesce(n.banco ->> 'numero', '') <> '' and coalesce(n.banco ->> 'rut', '') <> '') or coalesce(n.link_pago, '') <> '' or n.links_pago <> '[]'::jsonb),
    jsonb_build_object('k', 'logo', 't', 'Tu logo', 'd', 'Se ve en los comprobantes que envías.', 'ir', 'app/#ajustes', 'ok', n.logo_url is not null),
    jsonb_build_object('k', 'cliente', 't', 'Tu primer cliente', 'd', 'Anota a quien te debe o te paga en cuotas.', 'ir', 'app/#clientes/nuevo',
      'ok', exists (select 1 from public.clientes c where c.negocio = n.id)))
  from public.negocios n where n.dueno = auth.uid() and n.estado <> 'eliminado' limit 1), '[]'::jsonb)
$$;

-- >>> CFX núcleo (no editar aquí: se copia de saas/nucleo/sql con sincronizar.py)
-- ---------------------------------------------------------------------
-- CodeFix · Pagos (igual en las 6 apps; lo reparte nucleo/sincronizar.py). Se administra desde el Centro de Mando → Pagos.
--   Precios iguales en las 6: negocio (inicio, mensual, anual) y cliente (mensual, anual). Link de pago SIN monto (la persona
--   escribe el monto; se le suma el cargo por pago online, visible como una línea aparte), tarjeta (otro link, con su propio cargo)
--   o transferencia (precio exacto, sin cargo), y foto del comprobante. Tú apruebas y se activa el Premium por días enteros.
--   Liberar: por N días nadie queda bloqueado y las cuentas creadas en ese tiempo no pagan el primer pago (quedan en gratis).
--   El comprobante se borra al aprobar o rechazar (ya no sirve). Negocios nuevos: bloqueados hasta su primer pago (si está activado).
--   Cada app define antes: cfx_yo(), cfx_dar_premium(uuid, text, int), cfx_avisar(uuid, text, text) y cfx_avisar_admin(text, text).
-- ---------------------------------------------------------------------
create table if not exists public.cfx_config (clave text primary key, valor jsonb not null);

-- G112 c1 · 🔒 Llaves en Supabase Vault (cifradas DENTRO de la base: ni un respaldo ni una consulta a la tabla las muestra).
-- La tabla guarda solo la marca 'vault:<nombre>'; la llave real vive en vault.secrets. Sin Vault (base vieja o local) queda como antes.
create or replace function public.cfx_vault_hay() returns boolean
language plpgsql stable security definer set search_path = '' as $$
begin
  return to_regclass('vault.decrypted_secrets') is not null and to_regclass('vault.secrets') is not null and exists (select 1 from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace s on s.oid = p.pronamespace where s.nspname = 'vault' and p.proname = 'create_secret');
end $$;
-- Guarda p_valor en Vault con el nombre p_nombre y devuelve la marca (o el mismo valor si no hay Vault o algo falla: nunca se pierde la llave).
create or replace function public.cfx_secreto_poner(p_nombre text, p_valor text) returns text
language plpgsql security definer set search_path = '' as $$
declare i uuid;
begin
  if p_valor is null or p_valor = '' or p_valor like 'vault:%' or not public.cfx_vault_hay() then return p_valor; end if;
  begin
    execute 'select id from vault.secrets where name = $1' into i using p_nombre;
    if i is null then execute 'select vault.create_secret($1, $2, $3)' using p_valor, p_nombre, 'CodeFix (G112 c1)';
    else execute 'select vault.update_secret($1, $2)' using i, p_valor; end if;
    return 'vault:' || p_nombre;
  exception when others then
    raise notice 'Vault no disponible (%): la llave queda como antes.', sqlerrm;
    return p_valor;
  end;
end $$;
-- Abre una llave guardada (si es la marca 'vault:…' la busca en Vault; si no, es la llave tal cual).
create or replace function public.cfx_secreto(p_valor text) returns text
language plpgsql stable security definer set search_path = '' as $$
declare v text;
begin
  if p_valor is null or p_valor not like 'vault:%' then return p_valor; end if;
  if not public.cfx_vault_hay() then return null; end if;
  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1' into v using substr(p_valor, 7);
  return v;
end $$;
-- Borra de Vault las llaves cuyo nombre parte con p_prefijo (al desconectar).
create or replace function public.cfx_secreto_quitar(p_prefijo text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(p_prefijo, '') = '' or not public.cfx_vault_hay() then return; end if;
  execute 'delete from vault.secrets where name like $1' using replace(replace(p_prefijo, '%', ''), '_', '\_') || '%';
exception when others then null;
end $$;
-- Abre los campos de llave de una configuración (token / apikey / secret).
create or replace function public.cfx_llaves(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare k text; r jsonb := p;
begin
  if p is null then return null; end if;
  foreach k in array array['token', 'apikey', 'secret'] loop
    if r ? k then r := jsonb_set(r, array[k], coalesce(to_jsonb(public.cfx_secreto(r ->> k)), 'null'::jsonb)); end if;
  end loop;
  return r;
end $$;
revoke all on function public.cfx_vault_hay(), public.cfx_secreto_poner(text, text), public.cfx_secreto(text), public.cfx_secreto_quitar(text),
  public.cfx_llaves(jsonb) from public, anon, authenticated;
alter table public.cfx_config enable row level security;
insert into public.cfx_config (clave, valor) values ('pagos', jsonb_build_object(
  'negocio', jsonb_build_object('inicio', 4900, 'inicio_dias', 30, 'mensual', 4900, 'anual', 49900, 'exigir_inicio', true),
  'cliente', jsonb_build_object('mensual', 3000, 'anual', 29900),
  'link', '', 'comision_pct', 0, 'whatsapp', '', 'tarjeta', jsonb_build_object('link', '', 'comision_pct', 0),
  'transferencia', jsonb_build_object('banco', '', 'tipo', '', 'numero', '', 'rut', '', 'titular', '', 'correo', ''),
  'inicio_desde', now()))
on conflict (clave) do nothing;

create table if not exists public.cfx_pagos (
  id          uuid primary key default gen_random_uuid(),
  cuenta      uuid not null,
  email       text not null default '',
  nombre      text not null default '',
  rol         text not null check (rol in ('negocio', 'cliente', 'otro')),
  periodo     text not null check (periodo in ('inicio', 'mensual', 'anual', 'otro')),
  monto       int not null check (monto between 1 and 100000000),
  medio       text not null check (medio in ('link', 'transferencia')),
  nota        text not null default '' check (length(nota) <= 300),
  comprobante text check (comprobante is null or (comprobante ~ '^data:image/(jpeg|png|webp);base64,' and length(comprobante) <= 400000)),
  estado      text not null default 'pendiente' check (estado in ('pendiente', 'aprobado', 'rechazado')),
  dias        int,
  motivo      text not null default '',
  creado      timestamptz not null default now(),
  resuelto    timestamptz
);
alter table public.cfx_pagos add column if not exists cupon text;
alter table public.cfx_pagos add column if not exists meses int check (meses is null or meses between 1 and 24);
-- G19: pago de un módulo o pack (null = Premium).
alter table public.cfx_pagos add column if not exists producto text check (producto is null or producto ~ '^[a-z_]{2,30}$');
alter table public.cfx_pagos drop constraint if exists cfx_pagos_medio_check;
alter table public.cfx_pagos add constraint cfx_pagos_medio_check check (medio in ('link', 'transferencia', 'tarjeta', 'mp', 'flow'));
-- G85 ⚡ Mercado Pago automático: cuándo se abrió y el n° de pago que lo confirmó (un pago de MP sirve una sola vez).
alter table public.cfx_pagos add column if not exists mp_desde timestamptz;
alter table public.cfx_pagos add column if not exists mp_pago text;
-- G87 K: hasta cuándo quedó activo · 🎁 regalo (en vez de activarse, crea una key de 1 uso) · key_regalo = la key (solo la ve quien pagó y el admin).
alter table public.cfx_pagos add column if not exists hasta timestamptz;
alter table public.cfx_pagos add column if not exists regalo boolean not null default false;
alter table public.cfx_pagos add column if not exists key_regalo text;
create unique index if not exists cfx_pagos_mp_pago_idx on public.cfx_pagos (mp_pago) where mp_pago is not null;
alter table public.cfx_pagos drop constraint if exists cfx_pagos_periodo_check;
alter table public.cfx_pagos add constraint cfx_pagos_periodo_check check (periodo in ('inicio', 'mensual', 'meses', 'anual', 'otro'));
create index if not exists cfx_pagos_cuenta_idx on public.cfx_pagos (cuenta, creado desc);
create index if not exists cfx_pagos_estado_idx on public.cfx_pagos (estado, creado);
alter table public.cfx_pagos enable row level security;
create table if not exists public.cfx_exentos (cuenta uuid primary key, nota text not null default '', creado timestamptz not null default now());
alter table public.cfx_exentos enable row level security;
revoke all on public.cfx_config, public.cfx_pagos, public.cfx_exentos from anon, authenticated;

-- G85: ¿Está prendido el pago automático con Mercado Pago? (el token nunca sale de la base)
create or replace function public.cfx_mp_on() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select coalesce(valor ->> 'token', '') <> '' and coalesce((valor ->> 'activo')::boolean, false) from public.cfx_config where clave = 'mp'), false)
$$;
revoke all on function public.cfx_mp_on() from public, anon, authenticated;
-- G38 ⚡ Flow (Webpay + transferencia + MACH en una sola cuenta): ¿está prendido? (las llaves nunca salen de la base)
create or replace function public.cfx_flow_on() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select coalesce(valor ->> 'apikey', '') <> '' and coalesce(valor ->> 'secret', '') <> '' and coalesce((valor ->> 'activo')::boolean, false)
    from public.cfx_config where clave = 'flow'), false)
$$;
revoke all on function public.cfx_flow_on() from public, anon, authenticated;

-- ¿Cómo estoy? Precios, mi rol, si debo el primer pago y mi último pago.
create or replace function public.cfx_pago_estado() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare c jsonb := (select valor from public.cfx_config where clave = 'pagos'); y jsonb := public.cfx_yo(); pagado boolean; debe boolean; bloq boolean;
        lib jsonb := (select valor from public.cfx_config where clave = 'liberar'); ld timestamptz := (lib ->> 'desde')::timestamptz; lh timestamptz := (lib ->> 'hasta')::timestamptz;
begin
  if y is null or (y ->> 'id') is null then raise exception 'Inicia sesión'; end if;
  pagado := exists (select 1 from public.cfx_pagos where cuenta = (y ->> 'id')::uuid and estado = 'aprobado')
    or exists (select 1 from public.cfx_exentos where cuenta = (y ->> 'id')::uuid);
  -- debe_inicio: cuenta nueva (desde que activaste la regla) sin primer pago. bloqueado: además es un negocio.
  -- Solo si ya hay una forma de pago configurada (si no, nadie podría pagar).
  debe := coalesce((c #>> '{negocio,exigir_inicio}')::boolean, false) and not pagado
     and (coalesce(c ->> 'link', '') <> '' or coalesce(c #>> '{transferencia,numero}', '') <> '' or coalesce(c #>> '{tarjeta,link}', '') <> '' or public.cfx_mp_on() or public.cfx_flow_on())
     and (y ->> 'creado')::timestamptz > coalesce((c ->> 'inicio_desde')::timestamptz, now())
     -- Liberado: mientras dure nadie queda bloqueado; las cuentas creadas en ese tiempo quedan en gratis sin primer pago.
     and not (lh is not null and (now() < lh or (y ->> 'creado')::timestamptz between coalesce(ld, '-infinity') and lh));
  bloq := debe and y ->> 'rol' = 'negocio';
  return jsonb_build_object('config', c - 'inicio_desde', 'yo', y, 'pagado', pagado, 'bloqueado', bloq, 'debe_inicio', debe,
    'liberado_hasta', case when lh > now() then lh end, 'mp', public.cfx_mp_on(), 'flow', public.cfx_flow_on(),
    'prueba_pro', public.cfx_pro_prueba(y),  -- G95
    'subs', public.cfx_mp_subs_de((y ->> 'id')::uuid),  -- G108 🔁
    'ultimo', (select to_jsonb(x) from (select id, periodo, monto, medio, estado, dias, motivo, creado, resuelto, hasta, producto, regalo from public.cfx_pagos
               where cuenta = (y ->> 'id')::uuid order by creado desc limit 1) x),
    -- G87 K: 🔑 keys que compré (🎁 regalo o respaldo), con si ya se usaron.
    'keys', (select coalesce(jsonb_agg(jsonb_build_object('key', p.key_regalo, 'producto', p.producto, 'dias', p.dias, 'regalo', p.regalo, 'creado', p.resuelto,
               'usada', k.usada_at is not null) order by p.resuelto desc), '[]') from public.cfx_pagos p
               left join public.cfx_keys k on k.hash = encode(sha256(convert_to(p.key_regalo, 'UTF8')), 'hex')
               where p.cuenta = (y ->> 'id')::uuid and p.key_regalo is not null and p.resuelto > now() - interval '1 year'));
end $$;

drop function if exists public.cfx_pago_pedir(text, int, text, text, text);
drop function if exists public.cfx_pago_pedir(text, int, text, text, text, text);
drop function if exists public.cfx_pago_pedir(text, int, text, text, text, text, int);  -- G36: la de 7 dejaba 2 versiones ("Could not choose the best candidate")
drop function if exists public.cfx_pago_pedir(text, int, text, text, text, text, int, text);
create or replace function public.cfx_pago_pedir(p_periodo text, p_monto int, p_medio text, p_comprobante text, p_nota text default '', p_cupon text default null, p_meses int default null, p_producto text default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare y jsonb := public.cfx_yo(); i uuid; cup text := nullif(upper(trim(coalesce(p_cupon, ''))), '');
begin
  if y is null or (y ->> 'id') is null then raise exception 'Inicia sesión'; end if;
  if y ->> 'rol' not in ('negocio', 'cliente') and p_periodo <> 'otro' then raise exception 'Pide al dueño de la cuenta que haga el pago'; end if;
  if p_periodo not in ('inicio', 'mensual', 'meses', 'anual', 'otro') or p_medio not in ('link', 'transferencia', 'tarjeta') then raise exception 'Datos no válidos'; end if;
  if p_periodo = 'meses' and coalesce(p_meses, 0) not between 2 and 11 then raise exception 'Elige de 2 a 11 meses'; end if;
  -- Módulo o pack (G19): solo el dueño del negocio, 1 mes o 1 año, y que se venda en esta app.
  if p_producto is not null then
    if public.cfx_negocio_cuenta((y ->> 'id')::uuid) is distinct from (y ->> 'id')::uuid then raise exception 'Pide al dueño del negocio que haga el pago'; end if;
    if p_periodo not in ('mensual', 'anual') or not coalesce((public.cfx_venta() ->> 'activo')::boolean, false) or cardinality(public.cfx_venta_modulos(p_producto)) = 0 then raise exception 'Módulo no válido'; end if;
  end if;
  if coalesce(p_monto, 0) < 1 then raise exception 'Escribe el monto que pagaste'; end if;
  if coalesce(length(p_comprobante), 0) < 200 then raise exception 'Sube la foto del comprobante'; end if;
  if cup is not null then perform public.cfx_cupon_ver(cup); end if;
  if exists (select 1 from public.cfx_pagos where cuenta = (y ->> 'id')::uuid and estado = 'pendiente' and medio not in ('mp', 'flow')) then raise exception 'Ya tienes un pago en revisión. Te avisamos apenas se apruebe.'; end if;
  if (select count(*) from public.cfx_pagos where cuenta = (y ->> 'id')::uuid and creado > now() - interval '1 day' and medio not in ('mp', 'flow')) >= 5 then raise exception 'Demasiados intentos hoy. Escribe a soporte.'; end if;
  insert into public.cfx_pagos (cuenta, email, nombre, rol, periodo, monto, medio, nota, comprobante, cupon, meses, producto)
  values ((y ->> 'id')::uuid, coalesce(y ->> 'email', ''), left(coalesce(y ->> 'nombre', ''), 80), case when y ->> 'rol' in ('negocio', 'cliente') then y ->> 'rol' else 'otro' end,
          p_periodo, p_monto, p_medio, left(coalesce(p_nota, ''), 300), p_comprobante, cup, case when p_periodo = 'meses' then p_meses end, p_producto)
  returning id into i;
  -- Aviso al tiro: al Centro de Mando si la app está vinculada (si no, al administrador de esta app).
  perform public.cfx_al_cm('💳 Pago por revisar', coalesce(nullif(y ->> 'nombre', ''), y ->> 'email') || ' · $' || p_monto || coalesce(' · 🧩 ' || p_producto, '') || ' (' || case p_periodo when 'meses' then p_meses || ' meses' else p_periodo end || ', ' || p_medio || ')' || coalesce(' · cupón ' || cup, ''), 'pago');
  return i;
end $$;

-- Precios públicos (para la portada, sin iniciar sesión).
create or replace function public.cfx_precios() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('negocio', valor -> 'negocio', 'cliente', valor -> 'cliente', 'comision_pct', valor -> 'comision_pct',
    'liberado_hasta', (select case when (l.valor ->> 'hasta')::timestamptz > now() then l.valor -> 'hasta' end from public.cfx_config l where l.clave = 'liberar'))
  from public.cfx_config where clave = 'pagos'
$$;
revoke all on function public.cfx_precios() from public;
grant execute on function public.cfx_precios() to anon, authenticated;

-- ---------- Administrador (lo llama el Centro de Mando) ----------
create or replace function public.cfx_pagos_config() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  return (select valor from public.cfx_config where clave = 'pagos');
end $$;

create or replace function public.cfx_pagos_config_guardar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v jsonb := (select valor from public.cfx_config where clave = 'pagos');
begin
  perform privado.solo_admin();
  if jsonb_typeof(p) <> 'object' then raise exception 'Datos no válidos'; end if;
  if coalesce(p ->> 'link', '') <> '' and (p ->> 'link') !~ '^https://[^ ]+$' then raise exception 'El link de pago debe empezar con https://'; end if;
  if coalesce((p ->> 'comision_pct')::numeric, 0) not between 0 and 20 or coalesce((p #>> '{tarjeta,comision_pct}')::numeric, 0) not between 0 and 20 then raise exception 'El cargo por pago online va de 0 a 20 %%'; end if;
  if coalesce(p #>> '{tarjeta,link}', '') <> '' and (p #>> '{tarjeta,link}') !~ '^https://[^ ]+$' then raise exception 'El link de tarjeta debe empezar con https://'; end if;
  -- Al activar "bloquear hasta el primer pago", solo aplica a los negocios que se registren desde ahora.
  -- También cuando se configura la primera forma de pago (antes nadie podía pagar, así que nadie quedó obligado).
  if coalesce((p #>> '{negocio,exigir_inicio}')::boolean, false) and (not coalesce((v #>> '{negocio,exigir_inicio}')::boolean, false)
     or (coalesce(v ->> 'link', '') = '' and coalesce(v #>> '{transferencia,numero}', '') = '' and coalesce(v #>> '{tarjeta,link}', '') = ''
         and (coalesce(p ->> 'link', '') <> '' or coalesce(p #>> '{transferencia,numero}', '') <> '' or coalesce(p #>> '{tarjeta,link}', '') <> ''))) then
    p := p || jsonb_build_object('inicio_desde', now());
  end if;
  v := v || (p - 'inicio_desde') || case when p ? 'inicio_desde' then jsonb_build_object('inicio_desde', p -> 'inicio_desde') else '{}'::jsonb end;
  update public.cfx_config set valor = v where clave = 'pagos';
  return v;
end $$;

create or replace function public.cfx_pagos_lista(p_estado text default 'pendiente') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  return (select coalesce(jsonb_agg(x order by x.creado desc), '[]') from (
    select id, cuenta, email, nombre, rol, periodo, meses, producto, monto, medio, mp_pago, nota, estado, dias, motivo, creado, resuelto, comprobante is not null as con_comprobante, hasta, regalo, key_regalo,
      public.cfx_dias_sugeridos(g) as sugeridos,
      (select count(*) from public.cfx_pagos z where z.cuenta = g.cuenta and z.estado = 'aprobado') as aprobados
    from public.cfx_pagos g where p_estado = 'todos' or estado = p_estado order by creado desc limit 200) x);
end $$;

create or replace function public.cfx_pago_comprobante(p_id uuid) returns text
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  return (select comprobante from public.cfx_pagos where id = p_id);
end $$;

-- Días que corresponden a un pago (siempre días enteros): mensual 30, anual 365, N meses = N × 30, primer pago lo configurado,
-- y "otro monto" en proporción al precio mensual (sin contar el cargo por pago online).
create or replace function public.cfx_dias_sugeridos(g public.cfx_pagos) returns int
language plpgsql stable security definer set search_path = '' as $$
declare c jsonb := (select valor from public.cfx_config where clave = 'pagos'); m numeric; pct numeric; neto numeric;
begin
  if g.periodo = 'inicio' then return coalesce((c #>> '{negocio,inicio_dias}')::int, 30); end if;
  if g.periodo = 'mensual' then return 30; end if;
  if g.periodo = 'anual' then return 365; end if;
  if g.periodo = 'meses' then return 30 * coalesce(g.meses, 1); end if;
  m := nullif((c #>> array[case when g.rol = 'cliente' then 'cliente' else 'negocio' end, 'mensual'])::numeric, 0);
  pct := case g.medio when 'link' then coalesce((c ->> 'comision_pct')::numeric, 0) when 'tarjeta' then coalesce((c #>> '{tarjeta,comision_pct}')::numeric, 0) else 0 end;
  neto := g.monto / (1 + pct / 100);
  return case when m is null then 0 else least(3660, floor(neto * 30 / m))::int end;
end $$;
revoke all on function public.cfx_dias_sugeridos(public.cfx_pagos) from public, anon, authenticated;

-- G87 K · 🔑 Key de 1 uso con lo que se pagó (Premium o módulo/pack, los mismos días). Sirve para 🎁 regalar a otra cuenta y de
-- respaldo si la activación automática falla: el pago queda aprobado con su key (la persona la canjea en Premium/🧩 Módulos).
create or replace function public.cfx_pago_key(g public.cfx_pagos, p_dias int, p_estado text, p_motivo text) returns text
language plpgsql security definer set search_path = '' as $$
declare c text := upper(replace(gen_random_uuid()::text, '-', ''));
begin
  c := 'CFX-' || substr(c, 1, 4) || '-' || substr(c, 5, 4) || '-' || substr(c, 9, 4);
  insert into public.cfx_keys (hash, ultimos, rol, dias, nota, item)
  values (encode(sha256(convert_to(c, 'UTF8')), 'hex'), right(c, 4), case when g.producto is not null then 'negocio' when g.rol = 'cliente' then 'cliente' else 'negocio' end,
          greatest(1, least(3660, p_dias)), left(case when g.regalo then '🎁 Regalo de ' else '🔑 Respaldo de ' end || coalesce(nullif(g.email, ''), g.cuenta::text), 120), coalesce(g.producto, ''));
  update public.cfx_pagos set estado = p_estado, dias = p_dias, key_regalo = c, motivo = left(coalesce(p_motivo, ''), 200), resuelto = now(), comprobante = null where id = g.id;
  perform public.cfx_avisar(g.cuenta, case when g.regalo then '🎁 Tu key de regalo está lista' else '🔑 Tu pago quedó con una key' end,
    'Key ' || c || ' (' || case when g.producto is not null then '🧩 ' || g.producto else 'Premium' end || ', ' || p_dias || ' días). Se canjea en Premium → ¿Tienes una key?');
  return c;
end $$;
revoke all on function public.cfx_pago_key(public.cfx_pagos, int, text, text) from public, anon, authenticated;

-- Aprueba un pago pendiente y activa lo que pagó (lo usan el administrador y el pago automático de Mercado Pago).
create or replace function public.cfx_pago_aprobar(p_id uuid, p_dias int default null, p_motivo text default '') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare g public.cfx_pagos; d int; h timestamptz;
begin
  select * into g from public.cfx_pagos where id = p_id and estado = 'pendiente' for update;
  if g.id is null then raise exception 'Pago no encontrado o ya resuelto'; end if;
  d := coalesce(p_dias, public.cfx_dias_sugeridos(g));
  if d < 0 or d > 3660 then raise exception 'Días no válidos'; end if;
  if g.regalo and d > 0 then
    perform public.cfx_pago_key(g, d, 'aprobado', p_motivo);
    return jsonb_build_object('estado', 'aprobado', 'dias', d, 'hasta', null, 'regalo', true);
  end if;
  if d > 0 and g.producto is not null then h := public.cfx_modulos_dar(public.cfx_negocio_cuenta(g.cuenta), g.producto, d, 'pago');
  elsif d > 0 then h := public.cfx_dar_premium(g.cuenta, g.rol, d); end if;
  update public.cfx_pagos set estado = 'aprobado', dias = d, hasta = h, motivo = left(coalesce(p_motivo, ''), 200), resuelto = now(), comprobante = null where id = p_id;
  perform public.cfx_avisar(g.cuenta, '✅ Pago aprobado', case when h is not null then case when g.producto is not null then '🧩 Módulo activo' else 'Premium activo' end || ' hasta el ' || to_char(h at time zone 'America/Santiago', 'DD/MM/YYYY') || '. ¡Gracias!' else 'Gracias, tu pago quedó registrado.' end);
  return jsonb_build_object('estado', 'aprobado', 'dias', d, 'hasta', h);
end $$;
revoke all on function public.cfx_pago_aprobar(uuid, int, text) from public, anon, authenticated;

create or replace function public.cfx_pago_resolver(p_id uuid, p_aprobar boolean, p_dias int default null, p_motivo text default '') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare g public.cfx_pagos; d int; hasta timestamptz;
begin
  perform privado.solo_admin();
  select * into g from public.cfx_pagos where id = p_id and estado = 'pendiente' for update;
  if g.id is null then raise exception 'Pago no encontrado o ya resuelto'; end if;
  d := coalesce(p_dias, public.cfx_dias_sugeridos(g));
  if p_aprobar then
    return public.cfx_pago_aprobar(p_id, d, p_motivo);
  else
    update public.cfx_pagos set estado = 'rechazado', motivo = left(coalesce(nullif(p_motivo, ''), 'No pudimos validar el comprobante'), 200), resuelto = now(), comprobante = null where id = p_id;
    perform public.cfx_avisar(g.cuenta, '⚠️ Pago rechazado', left(coalesce(nullif(p_motivo, ''), 'No pudimos validar el comprobante'), 200) || '. Puedes subirlo de nuevo.');
  end if;
  return jsonb_build_object('estado', case when p_aprobar then 'aprobado' else 'rechazado' end, 'dias', d, 'hasta', hasta);
end $$;

-- Liberar el registro por N días (0 = terminar ahora). Sin p_dias solo devuelve cómo está.
create or replace function public.cfx_liberar(p_dias int default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v jsonb := (select valor from public.cfx_config where clave = 'liberar');
begin
  perform privado.solo_admin();
  if p_dias is not null then
    if p_dias < 0 or p_dias > 90 then raise exception 'De 0 a 90 días'; end if;
    v := case when p_dias = 0 then coalesce(v, '{}'::jsonb) || jsonb_build_object('hasta', least(coalesce((v ->> 'hasta')::timestamptz, now()), now()))
         else jsonb_build_object('desde', case when (v ->> 'hasta')::timestamptz > now() then v -> 'desde' else to_jsonb(now()) end, 'hasta', now() + make_interval(days => p_dias)) end;
    insert into public.cfx_config (clave, valor) values ('liberar', v) on conflict (clave) do update set valor = excluded.valor;
  end if;
  return jsonb_build_object('desde', v -> 'desde', 'hasta', v -> 'hasta', 'activo', coalesce((v ->> 'hasta')::timestamptz > now(), false));
end $$;
revoke all on function public.cfx_liberar(int) from public, anon;
grant execute on function public.cfx_liberar(int) to authenticated;

-- Cuentas que no pagan el inicio (por ejemplo, las que creas tú de regalo).
create or replace function public.cfx_exento(p_cuenta uuid, p_si boolean, p_nota text default '') returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  if p_si then insert into public.cfx_exentos (cuenta, nota) values (p_cuenta, left(coalesce(p_nota, ''), 200)) on conflict (cuenta) do update set nota = excluded.nota;
  else delete from public.cfx_exentos where cuenta = p_cuenta; end if;
end $$;

create or replace function public.cfx_exento_email(p_email text, p_si boolean) returns text
language plpgsql security definer set search_path = '' as $$
declare u uuid;
begin
  perform privado.solo_admin();
  select id into u from auth.users where lower(email) = lower(trim(coalesce(p_email, '')));
  if u is null then raise exception 'No hay una cuenta con ese correo en esta app'; end if;
  perform public.cfx_exento(u, p_si, 'Desde el Centro de Mando');
  return lower(trim(p_email));
end $$;

revoke all on function public.cfx_exento_email(text, boolean) from public, anon;
grant execute on function public.cfx_exento_email(text, boolean) to authenticated;
revoke all on function public.cfx_pago_estado(), public.cfx_pago_pedir(text, int, text, text, text, text, int, text), public.cfx_pagos_config(), public.cfx_pagos_config_guardar(jsonb),
  public.cfx_pagos_lista(text), public.cfx_pago_comprobante(uuid), public.cfx_pago_resolver(uuid, boolean, int, text), public.cfx_exento(uuid, boolean, text) from public, anon;
grant execute on function public.cfx_pago_estado(), public.cfx_pago_pedir(text, int, text, text, text, text, int, text), public.cfx_pagos_config(), public.cfx_pagos_config_guardar(jsonb),
  public.cfx_pagos_lista(text), public.cfx_pago_comprobante(uuid), public.cfx_pago_resolver(uuid, boolean, int, text), public.cfx_exento(uuid, boolean, text) to authenticated;
revoke all on function public.cfx_yo(), public.cfx_dar_premium(uuid, text, int), public.cfx_avisar(uuid, text, text), public.cfx_avisar_admin(text, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- G85 ⚡ Pago AUTOMÁTICO con Mercado Pago (Checkout Pro) para pagar la app: Premium, primer pago y módulos.
--   CodeFix pega SU Access Token una vez en CM → Pagos (se guarda en las 7 apps; nadie lo puede leer después).
--   La persona toca "⚡ Pagar con Mercado Pago" → paga → al volver (o cada 2 min) la base lo confirma con Mercado Pago,
--   activa el plan sola, le llega push "✅ Pago aprobado" y al Centro de Mando "⚡ Pago automático". Sin comprobante.
--   El link general (abierto, con pantallazo) sigue igual: ese lo revisa el administrador.
-- ---------------------------------------------------------------------
do $$ begin create extension if not exists http with schema extensions; exception when others then raise notice 'http: %', sqlerrm; end $$;

create or replace function public.cfx_mp_api(p_token text, p_metodo text, p_ruta text, p_cuerpo jsonb default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare st int; c text;
begin
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '10');
  execute 'select status, content from extensions.http(row($1, $2, $3, $4, $5)::extensions.http_request)' into st, c
    using p_metodo, 'https://api.mercadopago.com' || p_ruta, array[row('Authorization', 'Bearer ' || p_token)::extensions.http_header],
          'application/json', p_cuerpo::text;
  return jsonb_build_object('status', st, 'body', case when c ~ '^\s*[\{\[]' then c::jsonb end);
exception when others then
  return jsonb_build_object('status', 0, 'error', sqlerrm);
end $$;

-- G99 a ⚡ AVISO INSTANTÁNEO de Mercado Pago (webhook). Cada cobro lleva notification_url = función de la app + ?cfx_mp=<ref>.
--   La función solo llama cfx_mp_aviso(ref): NO se confía en lo que manda MP; la base vuelve a preguntarle por ESE cobro.
--   Si no hay URL (o el aviso no llega), todo sigue igual: se confirma al volver y con el cron de cada 1 min.
--   URL: cfx_config 'mp_aviso' → {"url": ...} (opcional) · si no, gancho de la app cfx_mp_aviso_url_app().
create table if not exists public.cfx_mp_avisos (ref text primary key, at timestamptz not null default now());
alter table public.cfx_mp_avisos enable row level security;
revoke all on public.cfx_mp_avisos from anon, authenticated;

create or replace function public.cfx_mp_notif(p_ref text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare u text := (select valor ->> 'url' from public.cfx_config where clave = 'mp_aviso');
begin
  if coalesce(u, '') = '' and to_regprocedure('public.cfx_mp_aviso_url_app()') is not null then
    begin execute 'select public.cfx_mp_aviso_url_app()' into u; exception when others then u := null; end;
  end if;
  if coalesce(u, '') !~ '^https://[^\s"<>?#]+$' or p_ref is null then return '{}'::jsonb; end if;
  return jsonb_build_object('notification_url', u || '?cfx_mp=' || p_ref);
end $$;
revoke all on function public.cfx_mp_notif(text) from public, anon, authenticated;

-- p:<id> = pago de la app (cfx_pagos) · n:<id> = cobro del negocio (mp_negocio.sql) · otra letra = gancho cfx_mp_aviso_app(ref).
create or replace function public.cfx_mp_aviso(p_ref text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare r text := lower(left(coalesce(p_ref, ''), 80)); i uuid; ok boolean := false;
begin
  if r !~ '^[a-z]:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return false; end if;
  i := substr(r, 3)::uuid;
  -- Freno: el mismo cobro se pregunta a MP como mucho 1 vez cada 5 s (MP manda varios avisos por pago).
  if exists (select 1 from public.cfx_mp_avisos where ref = r and at > now() - interval '5 seconds') then return false; end if;
  insert into public.cfx_mp_avisos (ref) values (r) on conflict (ref) do update set at = now();
  delete from public.cfx_mp_avisos where at < now() - interval '3 days';
  if left(r, 1) in ('p', 'f') then
    if exists (select 1 from public.cfx_pagos where id = i and medio in ('mp', 'flow') and estado = 'pendiente') then ok := public.cfx_mp_confirmar(i) = 'aprobado'; end if;
  elsif left(r, 1) = 'n' then
    if to_regprocedure('public.cfx_mp_neg_confirmar(uuid)') is not null then execute 'select public.cfx_mp_neg_confirmar($1)' into ok using i; end if;
  elsif to_regprocedure('public.cfx_mp_aviso_app(text)') is not null then
    execute 'select public.cfx_mp_aviso_app($1)' into ok using r;
  end if;
  return coalesce(ok, false);
exception when others then return false;
end $$;
revoke all on function public.cfx_mp_aviso(text) from public, anon, authenticated;
grant execute on function public.cfx_mp_aviso(text) to service_role;

-- Lo que cuesta el plan (igual que lo muestra la app): precio (− cupón, o − descuento Premium en módulos) + cargo por pago online.
create or replace function public.cfx_mp_monto(p_periodo text, p_meses int, p_producto text, p_cupon text) returns int
language plpgsql stable security definer set search_path = '' as $$
declare c jsonb := (select valor from public.cfx_config where clave = 'pagos'); y jsonb := public.cfx_yo(); g jsonb; v jsonb; b numeric; d int := 0;
begin
  if p_producto is not null then
    v := public.cfx_venta();
    if public.cfx_negocio_premium(public.cfx_negocio_cuenta((y ->> 'id')::uuid)) then d := greatest(0, least(90, coalesce((v ->> 'descuento_premium')::int, 0))); end if;
    b := round(public.cfx_venta_precio(p_producto) * (100 - d) / 100.0);
    if p_periodo = 'anual' then b := b * greatest(1, least(12, coalesce((v ->> 'anual_meses')::int, 10))); end if;
  else
    g := case when y ->> 'rol' = 'cliente' then c -> 'cliente' else c -> 'negocio' end;
    b := case p_periodo when 'inicio' then coalesce(nullif((c #>> '{negocio,inicio}')::numeric, 0), (c #>> '{negocio,mensual}')::numeric)
                        when 'mensual' then (g ->> 'mensual')::numeric when 'meses' then (g ->> 'mensual')::numeric * coalesce(p_meses, 1)
                        when 'anual' then (g ->> 'anual')::numeric end;
    if p_cupon is not null then b := round(b * (100 - public.cfx_cupon_ver(p_cupon)) / 100.0); end if;
  end if;
  b := coalesce(b, 0);
  return (b + ceil(b * coalesce((c ->> 'comision_pct')::numeric, 0) / 100))::int;
end $$;

-- Busca en Mercado Pago el pago aprobado de este cobro; si está (monto completo), lo aprueba y avisa (push a la persona y al CM).
create or replace function public.cfx_mp_confirmar(p_id uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare g public.cfx_pagos; tk text := public.cfx_secreto((select valor ->> 'token' from public.cfx_config where clave = 'mp')); r jsonb; pg jsonb;
begin
  select * into g from public.cfx_pagos where id = p_id for update;
  if g.medio = 'flow' and g.estado = 'pendiente' then return public.cfx_flow_confirmar(p_id); end if;  -- G38
  if g.id is null or g.medio <> 'mp' or g.estado <> 'pendiente' then return g.estado; end if;
  if coalesce(tk, '') = '' then return g.estado; end if;
  r := public.cfx_mp_api(tk, 'GET', '/v1/payments/search?sort=date_created&criteria=desc&external_reference=' || g.id::text);
  select e into pg from jsonb_array_elements(coalesce(r #> '{body,results}', '[]'::jsonb)) e
  where e ->> 'status' = 'approved' and e ->> 'external_reference' = g.id::text
    and coalesce(e ->> 'currency_id', 'CLP') = 'CLP' and (e ->> 'transaction_amount')::numeric >= g.monto
    and not exists (select 1 from public.cfx_pagos z where z.mp_pago = e ->> 'id') limit 1;
  if pg is null then
    -- Abrió Mercado Pago y no pagó en 2 días: se cierra (queda en el historial, nada se borra).
    if g.creado < now() - interval '2 days' then
      update public.cfx_pagos set estado = 'rechazado', motivo = 'No se completó el pago en Mercado Pago', resuelto = now() where id = g.id;
      return 'rechazado';
    end if;
    return g.estado;
  end if;
  update public.cfx_pagos set mp_pago = left(pg ->> 'id', 40) where id = g.id;
  begin
    perform public.cfx_pago_aprobar(g.id, null, '⚡ Mercado Pago n° ' || left(pg ->> 'id', 40));
  exception when others then
    -- G87 K: no se pudo activar solo → el pago igual queda aprobado con una 🔑 key de respaldo (nunca se pierde lo pagado).
    select * into g from public.cfx_pagos where id = p_id;
    perform public.cfx_pago_key(g, public.cfx_dias_sugeridos(g), 'aprobado', '⚡ Mercado Pago n° ' || left(pg ->> 'id', 40) || ' · activación falló (' || left(sqlerrm, 80) || '): key de respaldo');
  end;
  begin
    perform public.cfx_al_cm('⚡ Pago automático aprobado', coalesce(nullif(g.nombre, ''), g.email) || ' · $' || g.monto || coalesce(' · 🧩 ' || g.producto, '') ||
      ' (' || case g.periodo when 'meses' then g.meses || ' meses' else g.periodo end || ', Mercado Pago)' || coalesce(' · cupón ' || g.cupon, ''), 'pago');
  exception when others then null; end;
  return 'aprobado';
end $$;

-- La persona paga: crea el cobro y devuelve la página de Mercado Pago (G38: o la de Flow; p_medio 'mp' | 'flow').
drop function if exists public.cfx_mp_pagar(text, int, text, text, text);
create or replace function public.cfx_auto_pagar(p_medio text, p_periodo text, p_meses int, p_producto text, p_cupon text, p_volver text, p_regalo boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare y jsonb := public.cfx_yo(); m jsonb := public.cfx_llaves((select valor from public.cfx_config where clave = 'mp')); cup text := nullif(upper(trim(coalesce(p_cupon, ''))), '');
        v text := left(coalesce(p_volver, ''), 500); monto int; i uuid; r jsonb; x uuid; tit text;
begin
  if y is null or (y ->> 'id') is null then raise exception 'Inicia sesión'; end if;
  if p_medio not in ('mp', 'flow') or (p_medio = 'mp' and not public.cfx_mp_on()) or (p_medio = 'flow' and not public.cfx_flow_on()) then
    raise exception 'El pago automático no está disponible. Usa el link de pago o la transferencia.'; end if;
  if y ->> 'rol' not in ('negocio', 'cliente') then raise exception 'Pide al dueño de la cuenta que haga el pago'; end if;
  if p_periodo not in ('inicio', 'mensual', 'meses', 'anual') then raise exception 'Elige un plan'; end if;
  if p_periodo = 'meses' and coalesce(p_meses, 0) not between 2 and 11 then raise exception 'Elige de 2 a 11 meses'; end if;
  if coalesce(p_regalo, false) and p_periodo = 'inicio' then raise exception 'El primer pago es para tu cuenta: elige otro plan para regalar'; end if;
  if coalesce(p_regalo, false) and p_producto is not null and y ->> 'rol' <> 'negocio' then raise exception 'Los módulos se regalan desde una cuenta de negocio'; end if;
  if p_producto is not null and not coalesce(p_regalo, false) then
    if public.cfx_negocio_cuenta((y ->> 'id')::uuid) is distinct from (y ->> 'id')::uuid then raise exception 'Pide al dueño del negocio que haga el pago'; end if;
    if p_periodo not in ('mensual', 'anual') or not coalesce((public.cfx_venta() ->> 'activo')::boolean, false) or cardinality(public.cfx_venta_modulos(p_producto)) = 0 then raise exception 'Módulo no válido'; end if;
    cup := null;
  elsif p_producto is not null then
    if p_periodo not in ('mensual', 'anual') or not coalesce((public.cfx_venta() ->> 'activo')::boolean, false) or cardinality(public.cfx_venta_modulos(p_producto)) = 0 then raise exception 'Módulo no válido'; end if;
    cup := null;
  end if;
  if exists (select 1 from public.cfx_pagos where cuenta = (y ->> 'id')::uuid and estado = 'pendiente' and medio not in ('mp', 'flow')) then raise exception 'Ya tienes un pago en revisión. Te avisamos apenas se apruebe.'; end if;
  if (select count(*) from public.cfx_pagos where cuenta = (y ->> 'id')::uuid and medio in ('mp', 'flow') and creado > now() - interval '1 day') >= 10 then raise exception 'Demasiados intentos hoy. Escribe a soporte.'; end if;
  monto := public.cfx_mp_monto(p_periodo, p_meses, p_producto, cup);
  if monto < 1 then raise exception 'Este plan aún no tiene precio'; end if;
  -- Un intento anterior sin pagar: se revisa (por si sí pagó) y se cierra; nunca se borra.
  for x in select id from public.cfx_pagos where cuenta = (y ->> 'id')::uuid and estado = 'pendiente' and medio in ('mp', 'flow') loop
    if public.cfx_mp_confirmar(x) = 'aprobado' then return jsonb_build_object('ok', true, 'aprobado', true); end if;
    update public.cfx_pagos set estado = 'rechazado', motivo = 'Volviste a pagar en línea', resuelto = now() where id = x and estado = 'pendiente' and mp_pago is null;
  end loop;
  insert into public.cfx_pagos (cuenta, email, nombre, rol, periodo, monto, medio, nota, cupon, meses, producto, mp_desde, regalo)
  values ((y ->> 'id')::uuid, coalesce(y ->> 'email', ''), left(coalesce(y ->> 'nombre', ''), 80), y ->> 'rol', p_periodo, monto, p_medio,
          case when coalesce(p_regalo, false) then '🎁 Regalo · ' else '' end || case p_medio when 'flow' then '⚡ Flow automático' else '⚡ Mercado Pago automático' end, cup,
          case when p_periodo = 'meses' then p_meses end, p_producto, now(), coalesce(p_regalo, false))
  returning id into i;
  tit := case when coalesce(p_regalo, false) then '🎁 Regalo · ' else '' end || case when p_producto is not null then 'Módulo ' || p_producto else 'Premium' end || ' · ' ||
         case p_periodo when 'anual' then '1 año' when 'meses' then p_meses || ' meses' else '1 mes' end;
  if v !~ '^https://[^\s"<>]+$' then v := null; end if;
  if p_medio = 'flow' then return public.cfx_flow_cobro(i, tit, monto, coalesce(y ->> 'email', ''), v); end if;
  r := public.cfx_mp_api(m ->> 'token', 'POST', '/checkout/preferences', jsonb_build_object(
    'items', jsonb_build_array(jsonb_build_object('id', i, 'title', left('CodeFix · ' || tit, 120), 'quantity', 1, 'currency_id', 'CLP', 'unit_price', monto)),
    'external_reference', i::text, 'statement_descriptor', 'CODEFIX',
    'payer', jsonb_build_object('email', coalesce(y ->> 'email', '')),
    'payment_methods', jsonb_build_object('excluded_payment_types', jsonb_build_array(jsonb_build_object('id', 'ticket'))))
    || public.cfx_mp_notif('p:' || i::text)
    || case when v is null then '{}'::jsonb else jsonb_build_object('back_urls', jsonb_build_object('success', v, 'pending', v, 'failure', v), 'auto_return', 'approved') end);
  if coalesce((r ->> 'status')::int, 0) not in (200, 201) or r #>> '{body,init_point}' is null then
    update public.cfx_pagos set estado = 'rechazado', motivo = 'Mercado Pago no respondió', resuelto = now() where id = i;
    return jsonb_build_object('ok', false, 'error', 'Mercado Pago no respondió. Intenta de nuevo o usa el link de pago.');
  end if;
  return jsonb_build_object('ok', true, 'url', r #>> '{body,init_point}', 'id', i, 'monto', monto);
end $$;
revoke all on function public.cfx_auto_pagar(text, text, int, text, text, text, boolean) from public, anon, authenticated;
create or replace function public.cfx_mp_pagar(p_periodo text, p_meses int default null, p_producto text default null, p_cupon text default null, p_volver text default null, p_regalo boolean default false) returns jsonb
language sql security definer set search_path = '' as $$ select public.cfx_auto_pagar('mp', p_periodo, p_meses, p_producto, p_cupon, p_volver, p_regalo) $$;
create or replace function public.cfx_flow_pagar(p_periodo text, p_meses int default null, p_producto text default null, p_cupon text default null, p_volver text default null, p_regalo boolean default false) returns jsonb
language sql security definer set search_path = '' as $$ select public.cfx_auto_pagar('flow', p_periodo, p_meses, p_producto, p_cupon, p_volver, p_regalo) $$;

-- Al volver de Mercado Pago (o al tocar "Ya pagué"): revisa mis cobros abiertos.
create or replace function public.cfx_mp_revisar() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare y jsonb := public.cfx_yo(); x uuid; e text; ok boolean := false;
begin
  if y is null or (y ->> 'id') is null then raise exception 'Inicia sesión'; end if;
  for x in select id from public.cfx_pagos where cuenta = (y ->> 'id')::uuid and estado = 'pendiente' and medio in ('mp', 'flow') loop
    e := public.cfx_mp_confirmar(x); ok := ok or e = 'aprobado';
  end loop;
  -- G108 🔁 renovación automática: al volver de MP también revisa mis suscripciones (cobro nuevo = aprobado).
  begin ok := public.cfx_mp_subs_revisar_mias((y ->> 'id')::uuid) > 0 or ok; exception when others then null; end;
  return jsonb_build_object('aprobado', ok, 'pendiente', exists (select 1 from public.cfx_pagos where cuenta = (y ->> 'id')::uuid and estado = 'pendiente' and medio in ('mp', 'flow')),
    -- G87 K: el último pago automático aprobado (para 🎉 "Activo hasta…", 🧾 comprobante y la 🎁 key).
    'pago', case when ok then (select to_jsonb(q) from (select id, periodo, meses, monto, producto, hasta, dias, regalo, key_regalo, mp_pago, cupon, resuelto, email, nombre
      from public.cfx_pagos where cuenta = (y ->> 'id')::uuid and estado = 'aprobado' and medio in ('mp', 'flow') order by resuelto desc nulls last limit 1) q) end,
    'subs', public.cfx_mp_subs_de((y ->> 'id')::uuid));
end $$;

-- "Pagar de otra forma": cierra el cobro de Mercado Pago sin pagar (queda en el historial).
create or replace function public.cfx_mp_cancelar() returns void
language plpgsql security definer set search_path = '' as $$
declare y jsonb := public.cfx_yo();
begin
  if y is null or (y ->> 'id') is null then raise exception 'Inicia sesión'; end if;
  perform public.cfx_mp_revisar();
  update public.cfx_pagos set estado = 'rechazado', motivo = 'Elegiste otra forma de pago', resuelto = now()
  where cuenta = (y ->> 'id')::uuid and estado = 'pendiente' and medio in ('mp', 'flow') and mp_pago is null;
end $$;

-- Cada 2 minutos: por si la persona pagó y no volvió a la app.
create or replace function public.cfx_mp_revisar_pendientes() returns int
language plpgsql security definer set search_path = '' as $$
declare x uuid; n int := 0;
begin
  if not (public.cfx_mp_on() or public.cfx_flow_on()) then return 0; end if;
  for x in select id from public.cfx_pagos where estado = 'pendiente' and medio in ('mp', 'flow') order by creado desc limit 60 loop
    begin if public.cfx_mp_confirmar(x) = 'aprobado' then n := n + 1; end if; exception when others then null; end;
  end loop;
  return n;
end $$;

-- ---------- Administrador (CM → Pagos → ⚡ Mercado Pago automático) ----------
create or replace function public.cfx_mp_estado() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare m jsonb := (select valor from public.cfx_config where clave = 'mp');
begin
  perform privado.solo_admin();
  return jsonb_build_object('conectado', coalesce(m ->> 'token', '') <> '', 'activo', public.cfx_mp_on(), 'nick', m ->> 'nick', 'fin', right(public.cfx_secreto(m ->> 'token'), 4),
    'desde', m -> 'desde', 'rotar', coalesce((m ->> 'desde')::timestamptz < now() - interval '365 days', false));
end $$;

-- Conecta (token), prende/pausa (p_activo) o desconecta (sin token y p_activo null).
create or replace function public.cfx_mp_guardar(p_token text, p_activo boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare tk text := nullif(regexp_replace(coalesce(p_token, ''), '\s', '', 'g'), ''); m jsonb := (select valor from public.cfx_config where clave = 'mp'); r jsonb;
begin
  perform privado.solo_admin();
  if tk is null then
    if p_activo is null then delete from public.cfx_config where clave = 'mp';
    elsif coalesce(m ->> 'token', '') = '' then raise exception 'Pega tu Access Token de Mercado Pago';
    else update public.cfx_config set valor = valor || jsonb_build_object('activo', p_activo) where clave = 'mp'; end if;
    return public.cfx_mp_estado();
  end if;
  if tk !~ '^(APP_USR|TEST)-[A-Za-z0-9-]{20,}$' or length(tk) > 300 then raise exception 'Ese no es un Access Token: empieza con APP_USR-'; end if;
  r := public.cfx_mp_api(tk, 'GET', '/users/me');
  if coalesce((r ->> 'status')::int, 0) = 0 then raise exception 'No se pudo conectar con Mercado Pago. Intenta de nuevo.'; end if;
  if (r ->> 'status')::int <> 200 then raise exception 'Mercado Pago no aceptó el token: copia el Access Token de producción'; end if;
  insert into public.cfx_config (clave, valor) values ('mp', jsonb_build_object('token', tk, 'activo', coalesce(p_activo, true),
    'nick', left(coalesce(r #>> '{body,nickname}', r #>> '{body,email}', ''), 80)))
  on conflict (clave) do update set valor = excluded.valor;
  return public.cfx_mp_estado();
end $$;

-- "🔄 Revisar" un cobro de Mercado Pago desde CM → Pagos.
create or replace function public.cfx_mp_revisar_admin(p_id uuid) returns text
language plpgsql security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  return public.cfx_mp_confirmar(p_id);
end $$;

revoke all on function public.cfx_mp_api(text, text, text, jsonb), public.cfx_mp_monto(text, int, text, text), public.cfx_mp_confirmar(uuid), public.cfx_mp_revisar_pendientes() from public, anon, authenticated;
revoke all on function public.cfx_mp_pagar(text, int, text, text, text, boolean), public.cfx_mp_revisar(), public.cfx_mp_cancelar(), public.cfx_mp_estado(), public.cfx_mp_guardar(text, boolean), public.cfx_mp_revisar_admin(uuid) from public, anon;
revoke all on function public.cfx_flow_pagar(text, int, text, text, text, boolean) from public, anon;
grant execute on function public.cfx_flow_pagar(text, int, text, text, text, boolean) to authenticated;
grant execute on function public.cfx_mp_pagar(text, int, text, text, text, boolean), public.cfx_mp_revisar(), public.cfx_mp_cancelar(), public.cfx_mp_estado(), public.cfx_mp_guardar(text, boolean), public.cfx_mp_revisar_admin(uuid) to authenticated;
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'cfx-mp';
  perform cron.schedule('cfx-mp', '* * * * *', 'select public.cfx_mp_revisar_pendientes()');
exception when others then
  raise notice 'Revisión de Mercado Pago no programada (%).', sqlerrm;
end $$;

-- ---------------------------------------------------------------------
-- G38 ⚡ FLOW (flow.cl): segundo pago automático para pagar la app, igual que Mercado Pago. Decisión Claude (G33): Flow trae en
--   UNA sola cuenta Webpay (débito/crédito/prepago), transferencia (Khipu) y MACH → Khipu y Webpay directo no hacen falta aparte.
--   CodeFix pega su API Key + Secret Key en CM → Pagos (se guardan en las 7; nadie los lee después). Cobro: medio 'flow' en cfx_pagos;
--   se confirma preguntándole a Flow (getStatusByCommerceId: pagado + monto completo + n° de Flow usado 1 vez) al volver, con el
--   aviso de Flow (función de la app ?cfx_mp=f:<id>, el mismo de MP) y con el cron de cada 1 min. Flow vuelve con POST: la función
--   de la app lo pasa a la página con ?cfx_volver=1 (cfx_pago_volver); si no hay función, vuelve directo a la app.
-- ---------------------------------------------------------------------
alter table public.cfx_pagos add column if not exists volver text;

create or replace function public.cfx_url_cod(p text) returns text
language sql immutable set search_path = '' as $$
  select coalesce(string_agg(case when ch ~ '^[A-Za-z0-9_.~-]$' then ch else regexp_replace(upper(encode(convert_to(ch, 'UTF8'), 'hex')), '(..)', '%\1', 'g') end, '' order by n), '')
  from regexp_split_to_table(coalesce(p, ''), '') with ordinality t(ch, n)
$$;

-- Llama a Flow firmando (HMAC-SHA256 de los parámetros ordenados: nombre+valor). p_cfg: llaves a probar (si no, las guardadas).
create or replace function public.cfx_flow_api(p_metodo text, p_ruta text, p_params jsonb, p_cfg jsonb default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare f jsonb := public.cfx_llaves(coalesce(p_cfg, (select valor from public.cfx_config where clave = 'flow'))); pr jsonb; firma text; q text; st int; c text;
        base text := case when coalesce((f ->> 'sandbox')::boolean, false) then 'https://sandbox.flow.cl/api' else 'https://www.flow.cl/api' end;
begin
  if coalesce(f ->> 'apikey', '') = '' or coalesce(f ->> 'secret', '') = '' then return jsonb_build_object('status', 0, 'error', 'Flow sin llaves'); end if;
  pr := coalesce(p_params, '{}'::jsonb) || jsonb_build_object('apiKey', f ->> 'apikey');
  select string_agg(k || v, '' order by k collate "C"), string_agg(k || '=' || public.cfx_url_cod(v), '&' order by k collate "C") into firma, q from jsonb_each_text(pr) t(k, v);
  q := q || '&s=' || encode(extensions.hmac(convert_to(firma, 'UTF8'), convert_to(f ->> 'secret', 'UTF8'), 'sha256'), 'hex');
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '10');
  if upper(p_metodo) = 'GET' then
    execute 'select status, content from extensions.http(row($1, $2, $3, $4, $5)::extensions.http_request)' into st, c
      using 'GET', base || p_ruta || '?' || q, array[]::extensions.http_header[], null::text, null::text;
  else
    execute 'select status, content from extensions.http(row($1, $2, $3, $4, $5)::extensions.http_request)' into st, c
      using 'POST', base || p_ruta, array[]::extensions.http_header[], 'application/x-www-form-urlencoded', q;
  end if;
  return jsonb_build_object('status', st, 'body', case when c ~ '^\s*[\{\[]' then c::jsonb end);
exception when others then
  return jsonb_build_object('status', 0, 'error', sqlerrm);
end $$;

-- Crea el cobro en Flow (lo llama cfx_auto_pagar con el cobro ya anotado) y devuelve la página de pago.
create or replace function public.cfx_flow_cobro(p_id uuid, p_titulo text, p_monto int, p_email text, p_volver text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n text := public.cfx_mp_notif('f:' || p_id::text) ->> 'notification_url'; r jsonb;
begin
  if coalesce(p_email, '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    update public.cfx_pagos set estado = 'rechazado', motivo = 'Falta un correo válido para Flow', resuelto = now() where id = p_id;
    return jsonb_build_object('ok', false, 'error', 'Tu cuenta no tiene un correo válido. Usa otra forma de pago.');
  end if;
  if n is null and p_volver is null then
    update public.cfx_pagos set estado = 'rechazado', motivo = 'Sin dirección de regreso', resuelto = now() where id = p_id;
    return jsonb_build_object('ok', false, 'error', 'Flow no está listo en esta app. Usa otra forma de pago.');
  end if;
  update public.cfx_pagos set volver = p_volver where id = p_id;
  r := public.cfx_flow_api('POST', '/payment/create', jsonb_build_object('commerceOrder', p_id::text, 'subject', left('CodeFix · ' || p_titulo, 120),
    'currency', 'CLP', 'amount', p_monto::text, 'email', p_email, 'paymentMethod', '9',
    'urlConfirmation', coalesce(n, p_volver), 'urlReturn', coalesce(n || '&cfx_volver=1', p_volver)));
  if coalesce((r ->> 'status')::int, 0) <> 200 or coalesce(r #>> '{body,url}', '') !~ '^https://' or coalesce(r #>> '{body,token}', '') = '' then
    update public.cfx_pagos set estado = 'rechazado', motivo = 'Flow no respondió', resuelto = now() where id = p_id;
    return jsonb_build_object('ok', false, 'error', 'Flow no respondió. Intenta de nuevo o usa otra forma de pago.');
  end if;
  return jsonb_build_object('ok', true, 'url', (r #>> '{body,url}') || '?token=' || public.cfx_url_cod(r #>> '{body,token}'), 'id', p_id, 'monto', p_monto);
end $$;

-- Pregunta a Flow por ESTE cobro; pagado (status 2) con el monto completo y un n° de Flow no usado → aprueba y avisa.
create or replace function public.cfx_flow_confirmar(p_id uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare g public.cfx_pagos; r jsonb; b jsonb; nro text;
begin
  select * into g from public.cfx_pagos where id = p_id for update;
  if g.id is null or g.medio <> 'flow' or g.estado <> 'pendiente' then return g.estado; end if;
  r := public.cfx_flow_api('GET', '/payment/getStatusByCommerceId', jsonb_build_object('commerceId', g.id::text));
  b := r -> 'body';
  if coalesce((r ->> 'status')::int, 0) <> 200 or b is null or coalesce((b ->> 'status')::int, 0) <> 2 or b ->> 'commerceOrder' is distinct from g.id::text
     or coalesce(b ->> 'currency', 'CLP') <> 'CLP' or coalesce((b ->> 'amount')::numeric, 0) < g.monto
     or exists (select 1 from public.cfx_pagos z where z.mp_pago = 'flow:' || (b ->> 'flowOrder')) then
    if g.creado < now() - interval '2 days' then
      update public.cfx_pagos set estado = 'rechazado', motivo = 'No se completó el pago en Flow', resuelto = now() where id = g.id;
      return 'rechazado';
    end if;
    return g.estado;
  end if;
  nro := left(b ->> 'flowOrder', 30);
  update public.cfx_pagos set mp_pago = 'flow:' || nro where id = g.id;
  begin
    perform public.cfx_pago_aprobar(g.id, null, '⚡ Flow n° ' || nro);
  exception when others then
    select * into g from public.cfx_pagos where id = p_id;
    perform public.cfx_pago_key(g, public.cfx_dias_sugeridos(g), 'aprobado', '⚡ Flow n° ' || nro || ' · activación falló (' || left(sqlerrm, 80) || '): key de respaldo');
  end;
  begin
    perform public.cfx_al_cm('⚡ Pago automático aprobado', coalesce(nullif(g.nombre, ''), g.email) || ' · $' || g.monto || coalesce(' · 🧩 ' || g.producto, '') ||
      ' (' || case g.periodo when 'meses' then g.meses || ' meses' else g.periodo end || ', Flow)' || coalesce(' · cupón ' || g.cupon, ''), 'pago');
  exception when others then null; end;
  return 'aprobado';
end $$;

-- La función de la app: a dónde vuelve la persona después de Flow (solo cobros de Flow de los últimos 2 días).
create or replace function public.cfx_pago_volver(p_ref text) returns text
language plpgsql stable security definer set search_path = '' as $$
declare r text := lower(left(coalesce(p_ref, ''), 80));
begin
  if r !~ '^[fn]:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return null; end if;
  if left(r, 1) = 'n' then  -- G107 💳 Flow propio del negocio
    return (select volver from public.cfx_mp_neg_cobros where id = substr(r, 3)::uuid and medio = 'flow' and created_at > now() - interval '2 days' and volver ~ '^https://[^\s"<>]+$');
  end if;
  return (select volver from public.cfx_pagos where id = substr(r, 3)::uuid and medio = 'flow' and creado > now() - interval '2 days' and volver ~ '^https://[^\s"<>]+$');
end $$;

-- ---------- Administrador (CM → Pagos → ⚡ Flow) ----------
create or replace function public.cfx_flow_estado() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare f jsonb := (select valor from public.cfx_config where clave = 'flow');
begin
  perform privado.solo_admin();
  return jsonb_build_object('conectado', coalesce(f ->> 'apikey', '') <> '', 'activo', public.cfx_flow_on(), 'sandbox', coalesce((f ->> 'sandbox')::boolean, false), 'fin', right(public.cfx_secreto(f ->> 'apikey'), 4),
    'desde', f -> 'desde', 'rotar', coalesce((f ->> 'desde')::timestamptz < now() - interval '365 days', false));
end $$;

-- Conecta (llaves), prende/pausa (p_activo) o desconecta (sin llaves y p_activo null). p_sandbox = cuenta de pruebas de Flow.
create or replace function public.cfx_flow_guardar(p_apikey text, p_secret text, p_activo boolean, p_sandbox boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare k text := nullif(regexp_replace(coalesce(p_apikey, ''), '\s', '', 'g'), ''); sc text := nullif(regexp_replace(coalesce(p_secret, ''), '\s', '', 'g'), '');
        f jsonb := (select valor from public.cfx_config where clave = 'flow'); cfg jsonb; r jsonb;
begin
  perform privado.solo_admin();
  if k is null and sc is null then
    if p_activo is null then delete from public.cfx_config where clave = 'flow';
    elsif coalesce(f ->> 'apikey', '') = '' then raise exception 'Pega tu API Key y tu Secret Key de Flow';
    else update public.cfx_config set valor = valor || jsonb_build_object('activo', p_activo) where clave = 'flow'; end if;
    return public.cfx_flow_estado();
  end if;
  if k is null or sc is null then raise exception 'Pega las 2 llaves: API Key y Secret Key'; end if;
  if k !~ '^[A-Za-z0-9-]{20,80}$' then raise exception 'Esa no parece una API Key de Flow (Integración → API Keys)'; end if;
  if sc !~ '^[A-Za-z0-9]{20,100}$' then raise exception 'Esa no parece una Secret Key de Flow'; end if;
  cfg := jsonb_build_object('apikey', k, 'secret', sc, 'activo', coalesce(p_activo, true), 'sandbox', coalesce(p_sandbox, false));
  -- Prueba las llaves con un cobro que no existe: 401/403 = llaves malas; cualquier otra respuesta = Flow las aceptó.
  r := public.cfx_flow_api('GET', '/payment/getStatusByCommerceId', jsonb_build_object('commerceId', 'cfx-prueba'), cfg);
  if coalesce((r ->> 'status')::int, 0) = 0 then raise exception 'No se pudo conectar con Flow. Intenta de nuevo.'; end if;
  if (r ->> 'status')::int in (401, 403) then raise exception 'Flow no aceptó las llaves: cópialas de nuevo (¿son de producción o de pruebas?)'; end if;
  insert into public.cfx_config (clave, valor) values ('flow', cfg) on conflict (clave) do update set valor = excluded.valor;
  return public.cfx_flow_estado();
end $$;

revoke all on function public.cfx_url_cod(text), public.cfx_flow_api(text, text, jsonb, jsonb), public.cfx_flow_cobro(uuid, text, int, text, text), public.cfx_flow_confirmar(uuid), public.cfx_pago_volver(text) from public, anon, authenticated;
grant execute on function public.cfx_pago_volver(text) to service_role;
revoke all on function public.cfx_flow_estado(), public.cfx_flow_guardar(text, text, boolean, boolean) from public, anon;
grant execute on function public.cfx_flow_estado(), public.cfx_flow_guardar(text, text, boolean, boolean) to authenticated;

-- G87 E · ↺ Volver a cero los ingresos (solo admin, con registro). NO borra pagos: los ingresos de los resúmenes se cuentan
-- desde esta fecha (los de prueba quedan en el historial). "Contar todo" lo deshace.
create or replace function public.cfx_ingresos_desde() returns timestamptz
language sql stable security definer set search_path = '' as $$
  select coalesce((select (valor ->> 'desde')::timestamptz from public.cfx_config where clave = 'ingresos_cero'), '-infinity'::timestamptz)
$$;
create or replace function public.cfx_ingresos_cero(p_cero boolean default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  if p_cero is true then
    insert into public.cfx_config (clave, valor) values ('ingresos_cero', jsonb_build_object('desde', now()))
      on conflict (clave) do update set valor = excluded.valor;
    perform public.cfx_anotar('ingresos a cero', 'Los resúmenes cuentan desde ' || to_char(now() at time zone 'America/Santiago', 'DD-MM-YYYY HH24:MI'));
  elsif p_cero is false then
    delete from public.cfx_config where clave = 'ingresos_cero';
    perform public.cfx_anotar('ingresos a cero', 'Deshecho: vuelve a contar todo el historial');
  end if;
  return jsonb_build_object('desde', nullif(public.cfx_ingresos_desde(), '-infinity'::timestamptz));
end $$;
revoke all on function public.cfx_ingresos_cero(boolean) from public, anon;
grant execute on function public.cfx_ingresos_desde() to anon, authenticated;
grant execute on function public.cfx_ingresos_cero(boolean) to authenticated;

-- ---------------------------------------------------------------------
-- G95 🎁 PRUEBA 7 DÍAS POR BOTÓN: todos parten FREE. "🎁 Probar Pro 7 días" (hoja ⭐ Premium) y "🎁 Probar 7 días" en cada módulo,
--   UNA vez por correo. cfx_pruebas_usadas guarda el hash del correo (no el correo) y NO se borra al eliminar la cuenta ni en la limpieza:
--   si la persona se borra y vuelve con el mismo correo, ya no ve el botón y el servidor lo rechaza. item: 'pro', la clave del módulo o 'pack'.
--   Días: cfx_config 'pagos' → 'prueba_pro_dias' (si no está, los de 🧩 Módulos 'prueba_dias'; 7). 0 = sin prueba.
--   Gancho opcional de la app: cfx_pro_prueba_app(uuid, text, int) → timestamptz (si no está, usa cfx_dar_premium).
-- ---------------------------------------------------------------------
create table if not exists public.cfx_pruebas_usadas (
  hash   text not null,
  item   text not null check (item ~ '^[a-z_:]{2,40}$'),
  creado timestamptz not null default now(),
  primary key (hash, item)
);
alter table public.cfx_pruebas_usadas enable row level security;
revoke all on public.cfx_pruebas_usadas from anon, authenticated;
create or replace function public.cfx_hash_correo(p_email text) returns text
language sql immutable as $$ select encode(sha256(convert_to(lower(btrim(p_email)), 'UTF8')), 'hex') $$;
create or replace function public.cfx_prueba_hash(p_cuenta uuid) returns text
language sql stable security definer set search_path = '' as $$
  select case when nullif(btrim(u.email), '') is not null then public.cfx_hash_correo(u.email) else public.cfx_hash_correo('id:' || u.id::text) end
  from auth.users u where u.id = p_cuenta
$$;
create or replace function public.cfx_prueba_usada(p_cuenta uuid, p_item text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.cfx_pruebas_usadas where hash = public.cfx_prueba_hash(p_cuenta) and item = p_item)
$$;
create or replace function public.cfx_prueba_marcar(p_cuenta uuid, p_item text) returns void
language sql security definer set search_path = '' as $$
  insert into public.cfx_pruebas_usadas (hash, item) select h, p_item from (select public.cfx_prueba_hash(p_cuenta) h) x where h is not null
  on conflict do nothing
$$;
create or replace function public.cfx_pro_prueba_dias() returns int
language sql stable security definer set search_path = '' as $$
  select greatest(0, least(30, coalesce((select (valor ->> 'prueba_pro_dias')::int from public.cfx_config where clave = 'pagos'),
    (select (valor ->> 'prueba_dias')::int from public.cfx_config where clave = 'modulos_venta'), 7)))
$$;
-- ¿Esta cuenta puede tocar 🎁 Probar Pro? (para la hoja ⭐ Premium)
create or replace function public.cfx_pro_prueba(y jsonb) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('dias', d, 'usada', u, 'puede', d > 0 and not u and coalesce(y ->> 'rol', '') in ('negocio', 'cliente')
    and not coalesce((y ->> 'premium_hasta')::timestamptz > now(), false))
  from (select public.cfx_pro_prueba_dias() d, public.cfx_prueba_usada((y ->> 'id')::uuid, 'pro') u) x
$$;
create or replace function public.cfx_pro_probar() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare y jsonb := public.cfx_yo(); u uuid := (y ->> 'id')::uuid; d int := public.cfx_pro_prueba_dias(); h timestamptz;
begin
  if u is null or u <> auth.uid() then raise exception 'Inicia sesión'; end if;
  if coalesce(y ->> 'rol', '') not in ('negocio', 'cliente') then raise exception 'Esta cuenta no puede probar Premium'; end if;
  if d <= 0 then raise exception 'La prueba gratis no está disponible ahora'; end if;
  if coalesce((y ->> 'premium_hasta')::timestamptz > now(), false) then raise exception 'Ya tienes Premium activo'; end if;
  if public.cfx_prueba_usada(u, 'pro') then raise exception 'Ya usaste tu prueba gratis de Premium con este correo'; end if;
  perform public.cfx_prueba_marcar(u, 'pro');
  if to_regprocedure('public.cfx_pro_prueba_app(uuid,text,integer)') is not null then
    execute 'select public.cfx_pro_prueba_app($1, $2, $3)' into h using u, y ->> 'rol', d;
  else h := public.cfx_dar_premium(u, y ->> 'rol', d); end if;
  if h is null then raise exception 'No se pudo activar la prueba'; end if;
  perform public.cfx_anotar('premium', 'prueba gratis ' || d || ' días · ' || u);
  return jsonb_build_object('ok', true, 'hasta', h, 'dias', d);
end $$;
-- Centro de Mando → Control → 🎁 Pruebas: quién probó qué y cuándo (correo solo si la cuenta sigue existiendo).
create or replace function public.cfx_pruebas_admin() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  return jsonb_build_object('total', (select count(*) from public.cfx_pruebas_usadas),
    'items', (select coalesce(jsonb_object_agg(item, n), '{}') from (select item, count(*) n from public.cfx_pruebas_usadas group by item) x),
    'ultimas', (select coalesce(jsonb_agg(jsonb_build_object('item', p.item, 'creado', p.creado, 'email', coalesce(u.email, '')) order by p.creado desc), '[]')
      from (select * from public.cfx_pruebas_usadas order by creado desc limit 200) p
      left join (select distinct on (h) h, email from (select public.cfx_hash_correo(x.email) h, x.email from auth.users x where nullif(btrim(x.email), '') is not null) y) u on u.h = p.hash));
end $$;
revoke all on function public.cfx_hash_correo(text), public.cfx_prueba_hash(uuid), public.cfx_prueba_usada(uuid, text), public.cfx_prueba_marcar(uuid, text),
  public.cfx_pro_prueba_dias(), public.cfx_pro_prueba(jsonb) from public, anon, authenticated;
revoke all on function public.cfx_pro_probar(), public.cfx_pruebas_admin() from public, anon;
grant execute on function public.cfx_pro_probar(), public.cfx_pruebas_admin() to authenticated;

-- ---------------------------------------------------------------------
-- G108 🔁 RENOVACIÓN AUTOMÁTICA de ⭐ Premium y 🧩 módulos (suscripción "preapproval" de Mercado Pago con la cuenta de CodeFix,
--   el mismo motor de G106). La persona autoriza su tarjeta 1 vez; MP cobra solo cada mes (o cada año). Cada cobro aprobado
--   (CLP, monto completo, n° usado 1 sola vez) crea un pago en cfx_pagos ('🔁 Renovación automática') y se aprueba con
--   cfx_pago_aprobar → suma 30/365 días igual que un pago normal. Si el plan sigue activo, el 1.er cobro es 1 día antes de que venza.
--   Quitar = se apaga EN Mercado Pago (MP caído: no se marca y se reintenta). Sin cupón (el cupón es para un pago suelto).
-- ---------------------------------------------------------------------
create table if not exists public.cfx_mp_subs (
  id          uuid primary key default gen_random_uuid(),
  cuenta      uuid not null,
  email       text not null default '',
  nombre      text not null default '',
  rol         text not null,
  producto    text check (producto is null or producto ~ '^[a-z_]{2,30}$'),
  periodo     text not null check (periodo in ('mensual', 'anual')),
  monto       int not null check (monto > 0),
  pagador     text not null default '',
  preapproval text unique,
  estado      text not null default 'pendiente' check (estado in ('pendiente', 'activa', 'pausada', 'cancelada')),
  inicio      timestamptz,
  cobros      int not null default 0,
  ultimo_at   timestamptz,
  revisado_at timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists cfx_mp_subs_cuenta on public.cfx_mp_subs (cuenta, created_at desc);
create index if not exists cfx_mp_subs_viva on public.cfx_mp_subs (revisado_at) where estado <> 'cancelada';
alter table public.cfx_mp_subs enable row level security;
revoke all on public.cfx_mp_subs from anon, authenticated;

create table if not exists public.cfx_mp_sub_cobros (
  id   text primary key,           -- n° del cobro autorizado de MP (1 sola vez)
  sub  uuid not null,
  pago uuid,
  at   timestamptz not null default now()
);
alter table public.cfx_mp_sub_cobros enable row level security;
revoke all on public.cfx_mp_sub_cobros from anon, authenticated;

-- Mis renovaciones vivas (para la ventana de pago): [{ producto, periodo, monto, estado, inicio, cobros, ultimo }]
create or replace function public.cfx_mp_subs_de(p_cuenta uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('producto', producto, 'periodo', periodo, 'monto', monto, 'estado', estado, 'inicio', inicio,
    'cobros', cobros, 'ultimo', ultimo_at) order by created_at desc), '[]')
  from public.cfx_mp_subs where cuenta = p_cuenta and estado <> 'cancelada'
$$;

-- La persona prende la renovación automática: devuelve { ok, url } (página de MP para autorizar la tarjeta) o { ok: false, error }.
create or replace function public.cfx_mp_suscribir(p_periodo text, p_producto text default null, p_email text default null, p_volver text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare y jsonb := public.cfx_yo(); u uuid; tk text := public.cfx_secreto((select valor ->> 'token' from public.cfx_config where clave = 'mp'));
        m text := lower(trim(coalesce(p_email, ''))); v text := left(coalesce(p_volver, ''), 500); pr text := nullif(trim(coalesce(p_producto, '')), '');
        monto int; h timestamptz; ini timestamptz; s public.cfx_mp_subs; r jsonb; tit text;
begin
  if y is null or (y ->> 'id') is null then raise exception 'Inicia sesión'; end if;
  u := (y ->> 'id')::uuid;
  if not public.cfx_mp_on() then raise exception 'La renovación automática necesita Mercado Pago. Usa otra forma de pago.'; end if;
  if y ->> 'rol' not in ('negocio', 'cliente') then raise exception 'Pide al dueño de la cuenta que lo active'; end if;
  if p_periodo not in ('mensual', 'anual') then raise exception 'La renovación automática es para 1 mes o 1 año'; end if;
  if pr is not null then
    if public.cfx_negocio_cuenta(u) is distinct from u then raise exception 'Pide al dueño del negocio que lo active'; end if;
    if not coalesce((public.cfx_venta() ->> 'activo')::boolean, false) or cardinality(public.cfx_venta_modulos(pr)) = 0 then raise exception 'Módulo no válido'; end if;
  end if;
  if m !~ '^[^@\s"<>]+@[^@\s"<>]+\.[a-z]{2,}$' or length(m) > 120 then raise exception 'Escribe el correo de tu cuenta de Mercado Pago'; end if;
  if v !~ '^https://[^\s"<>]+$' then raise exception 'Falta la dirección de regreso'; end if;
  if exists (select 1 from public.cfx_mp_subs where cuenta = u and producto is not distinct from pr and estado in ('activa', 'pausada')) then
    raise exception 'Ya se renueva solo'; end if;
  if (select count(*) from public.cfx_mp_subs where cuenta = u and created_at > now() - interval '1 day') >= 10 then raise exception 'Demasiados intentos hoy. Escribe a soporte.'; end if;
  monto := public.cfx_mp_monto(p_periodo, null, pr, null);
  if monto < 1 then raise exception 'Este plan aún no tiene precio'; end if;
  -- Si lo que pagó sigue activo, el 1.er cobro es 1 día antes de que venza (no paga 2 veces lo mismo).
  if pr is null then h := (select max(hasta) from public.cfx_pagos where cuenta = u and producto is null and estado = 'aprobado' and not regalo);
  else h := (select max(hasta) from public.cfx_modulos_negocio where negocio = u and modulo = any (public.cfx_venta_modulos(pr))); end if;
  ini := greatest(now() + interval '5 minutes', coalesce(h - interval '1 day', now()));
  update public.cfx_mp_subs set estado = 'cancelada', updated_at = now() where cuenta = u and producto is not distinct from pr and estado = 'pendiente';  -- intento sin autorizar
  insert into public.cfx_mp_subs (cuenta, email, nombre, rol, producto, periodo, monto, pagador, inicio)
  values (u, coalesce(y ->> 'email', ''), left(coalesce(y ->> 'nombre', ''), 80), y ->> 'rol', pr, p_periodo, monto, m, ini)
  returning * into s;
  tit := 'CodeFix · ' || case when pr is not null then 'Módulo ' || pr else 'Premium' end || case p_periodo when 'anual' then ' · cada año' else ' · cada mes' end;
  r := public.cfx_mp_api(tk, 'POST', '/preapproval', jsonb_build_object(
    'reason', left(tit, 120), 'external_reference', 's:' || s.id::text, 'payer_email', m, 'back_url', v, 'status', 'pending',
    'auto_recurring', jsonb_build_object('frequency', case p_periodo when 'anual' then 12 else 1 end, 'frequency_type', 'months', 'currency_id', 'CLP',
      'transaction_amount', monto, 'start_date', to_char(ini at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS".000+00:00"'))));
  if coalesce((r ->> 'status')::int, 0) not in (200, 201) or r #>> '{body,init_point}' is null or r #>> '{body,id}' is null then
    delete from public.cfx_mp_subs where id = s.id;
    return jsonb_build_object('ok', false, 'error', coalesce('Mercado Pago: ' || left(r #>> '{body,message}', 160), 'Mercado Pago no respondió. Intenta de nuevo.'));
  end if;
  update public.cfx_mp_subs set preapproval = left(r #>> '{body,id}', 60), revisado_at = now() where id = s.id;
  return jsonb_build_object('ok', true, 'url', r #>> '{body,init_point}', 'monto', monto, 'inicio', ini);
end $$;

-- Un cobro aprobado de la suscripción → pago aprobado (activa/extiende). Si la activación falla, queda con 🔑 key de respaldo.
create or replace function public.cfx_mp_sub_cobro(p_sub uuid, p_cobro text, p_pago text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare s public.cfx_mp_subs; i uuid; g public.cfx_pagos; mot text;
begin
  select * into s from public.cfx_mp_subs where id = p_sub;
  if s.id is null then return false; end if;
  insert into public.cfx_mp_sub_cobros (id, sub) values (left(p_cobro, 40), s.id) on conflict do nothing;
  if not found then return false; end if;
  mot := '🔁 Renovación automática · Mercado Pago n° ' || left(coalesce(p_pago, p_cobro), 40);
  insert into public.cfx_pagos (cuenta, email, nombre, rol, periodo, monto, medio, nota, producto, mp_desde, mp_pago)
  values (s.cuenta, s.email, s.nombre, s.rol, s.periodo, s.monto, 'mp', '🔁 Renovación automática', s.producto, now(),
          case when p_pago is not null and not exists (select 1 from public.cfx_pagos where mp_pago = left(p_pago, 40)) then left(p_pago, 40) end)
  returning id into i;
  update public.cfx_mp_sub_cobros set pago = i where id = left(p_cobro, 40);
  begin
    perform public.cfx_pago_aprobar(i, null, mot);
  exception when others then
    select * into g from public.cfx_pagos where id = i;
    perform public.cfx_pago_key(g, public.cfx_dias_sugeridos(g), 'aprobado', left(mot || ' · activación falló (' || left(sqlerrm, 60) || '): key de respaldo', 200));
  end;
  begin
    perform public.cfx_al_cm('🔁 Renovación automática cobrada', coalesce(nullif(s.nombre, ''), s.email) || ' · $' || s.monto || ' · ' ||
      coalesce('🧩 ' || s.producto, '⭐ Premium') || ' (' || s.periodo || ', Mercado Pago)', 'pago');
  exception when others then null; end;
  return true;
end $$;

-- Pregunta a MP por UNA suscripción: estado + cobros nuevos. Devuelve cuántos cobros nuevos encontró.
create or replace function public.cfx_mp_sub_revisar(p_id uuid) returns int
language plpgsql security definer set search_path = '' as $$
declare s public.cfx_mp_subs; tk text := public.cfx_secreto((select valor ->> 'token' from public.cfx_config where clave = 'mp')); r jsonb; e jsonb; nuevo text; n int := 0;
begin
  select * into s from public.cfx_mp_subs where id = p_id for update skip locked;
  if s.id is null or s.preapproval is null or s.estado = 'cancelada' or coalesce(tk, '') = '' then return 0; end if;
  update public.cfx_mp_subs set revisado_at = now() where id = s.id;
  r := public.cfx_mp_api(tk, 'GET', '/preapproval/' || s.preapproval);
  if coalesce((r ->> 'status')::int, 0) = 200 then
    nuevo := case r #>> '{body,status}' when 'authorized' then 'activa' when 'paused' then 'pausada' when 'cancelled' then 'cancelada' else s.estado end;
    if nuevo <> s.estado then
      update public.cfx_mp_subs set estado = nuevo, updated_at = now() where id = s.id;
      begin
        if nuevo = 'activa' and s.estado = 'pendiente' then
          perform public.cfx_avisar(s.cuenta, '🔁 Renovación automática activa', coalesce('🧩 ' || s.producto, '⭐ Premium') || ': se paga solo ' ||
            case s.periodo when 'anual' then 'cada año' else 'cada mes' end || ' ($' || s.monto || '). 1.er cobro el ' || to_char(s.inicio at time zone 'America/Santiago', 'DD/MM/YYYY') || '.');
          perform public.cfx_al_cm('🔁 Renovación automática nueva', coalesce(nullif(s.nombre, ''), s.email) || ' · ' || coalesce('🧩 ' || s.producto, '⭐ Premium') || ' · $' || s.monto || ' (' || s.periodo || ')', 'pago');
        elsif nuevo = 'cancelada' and s.estado <> 'pendiente' then
          perform public.cfx_avisar(s.cuenta, '🔁 Renovación automática apagada', coalesce('🧩 ' || s.producto, '⭐ Premium') || ' ya no se paga solo. Lo que pagaste sigue activo hasta que venza.');
        end if;
      exception when others then null; end;
      if nuevo = 'cancelada' then return n; end if;
    end if;
  end if;
  r := public.cfx_mp_api(tk, 'GET', '/authorized_payments/search?preapproval_id=' || s.preapproval);
  for e in select x from jsonb_array_elements(coalesce(r #> '{body,results}', '[]'::jsonb)) x
           where coalesce(x #>> '{payment,status}', '') = 'approved' and coalesce(x ->> 'preapproval_id', s.preapproval) = s.preapproval
             and coalesce(x ->> 'currency_id', 'CLP') = 'CLP' and coalesce((x ->> 'transaction_amount')::numeric, 0) >= s.monto
             and x ->> 'id' is not null loop
    if public.cfx_mp_sub_cobro(s.id, e ->> 'id', e #>> '{payment,id}') then
      n := n + 1;
      update public.cfx_mp_subs set cobros = cobros + 1, ultimo_at = now(), estado = case when estado = 'pendiente' then 'activa' else estado end, updated_at = now() where id = s.id;
    end if;
  end loop;
  return n;
end $$;

-- Quitar la renovación automática (lo pagado sigue activo hasta que venza). false = MP no respondió (se reintenta).
create or replace function public.cfx_mp_sub_quitar(p_producto text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare y jsonb := public.cfx_yo(); s public.cfx_mp_subs; tk text := public.cfx_secreto((select valor ->> 'token' from public.cfx_config where clave = 'mp')); r jsonb; todo boolean := true;
        pr text := nullif(trim(coalesce(p_producto, '')), '');
begin
  if y is null or (y ->> 'id') is null then raise exception 'Inicia sesión'; end if;
  for s in select * from public.cfx_mp_subs where cuenta = (y ->> 'id')::uuid and producto is not distinct from pr and estado <> 'cancelada' for update loop
    if s.preapproval is not null and coalesce(tk, '') <> '' then
      r := public.cfx_mp_api(tk, 'PUT', '/preapproval/' || s.preapproval, jsonb_build_object('status', 'cancelled'));
      if coalesce((r ->> 'status')::int, 0) not in (200, 201) and coalesce(r #>> '{body,status}', '') <> 'cancelled' then todo := false; continue; end if;
    end if;
    update public.cfx_mp_subs set estado = 'cancelada', updated_at = now() where id = s.id;
  end loop;
  if not todo then return jsonb_build_object('ok', false, 'error', 'Mercado Pago no respondió. Intenta de nuevo en un rato.'); end if;
  return jsonb_build_object('ok', true);
end $$;

-- Mis suscripciones (al volver de MP / "Ya autoricé"): revisa y devuelve cuántos cobros nuevos hubo.
create or replace function public.cfx_mp_subs_revisar_mias(p_cuenta uuid) returns int
language plpgsql security definer set search_path = '' as $$
declare i uuid; n int := 0;
begin
  for i in select id from public.cfx_mp_subs where cuenta = p_cuenta and estado <> 'cancelada' and preapproval is not null order by created_at desc limit 5 loop
    n := n + public.cfx_mp_sub_revisar(i);
  end loop;
  return n;
end $$;

-- Cron: pendientes (cada 1 min, 2 días; después se dan por abandonadas) · vivas (cada 30 min).
create or replace function public.cfx_mp_subs_revisar() returns int
language plpgsql security definer set search_path = '' as $$
declare i uuid; n int := 0;
begin
  update public.cfx_mp_subs set estado = 'cancelada', updated_at = now() where estado = 'pendiente' and created_at < now() - interval '2 days' and cobros = 0;
  if not public.cfx_mp_on() then return 0; end if;
  for i in select id from public.cfx_mp_subs where estado <> 'cancelada' and preapproval is not null
             and (revisado_at is null or revisado_at < now() - case when estado = 'pendiente' then interval '1 minute' else interval '30 minutes' end)
           order by revisado_at nulls first limit 30 loop
    begin n := n + public.cfx_mp_sub_revisar(i); exception when others then null; end;
  end loop;
  return n;
end $$;

-- CM → Pagos: cuántas renovaciones automáticas hay vivas (y las últimas).
create or replace function public.cfx_mp_subs_admin() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  return jsonb_build_object('activas', (select count(*) from public.cfx_mp_subs where estado = 'activa'),
    'items', (select coalesce(jsonb_agg(jsonb_build_object('email', email, 'nombre', nombre, 'producto', producto, 'periodo', periodo, 'monto', monto,
      'estado', estado, 'cobros', cobros, 'ultimo', ultimo_at, 'inicio', inicio) order by created_at desc), '[]')
      from (select * from public.cfx_mp_subs where estado <> 'cancelada' order by created_at desc limit 100) x));
end $$;

revoke all on function public.cfx_mp_subs_de(uuid), public.cfx_mp_sub_cobro(uuid, text, text), public.cfx_mp_sub_revisar(uuid),
  public.cfx_mp_subs_revisar_mias(uuid), public.cfx_mp_subs_revisar() from public, anon, authenticated;
revoke all on function public.cfx_mp_suscribir(text, text, text, text), public.cfx_mp_sub_quitar(text), public.cfx_mp_subs_admin() from public, anon;
grant execute on function public.cfx_mp_suscribir(text, text, text, text), public.cfx_mp_sub_quitar(text), public.cfx_mp_subs_admin() to authenticated;
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'cfx-mp-subs';
  perform cron.schedule('cfx-mp-subs', '* * * * *', 'select public.cfx_mp_subs_revisar()');
exception when others then
  raise notice 'Revisión de renovaciones automáticas no programada (%).', sqlerrm;
end $$;
-- ---------------------------------------------------------------------
-- CodeFix · Administración común (igual en las 6 apps; se maneja desde el Centro de Mando → Control).
--   Planes (interruptores sí/no y límites), textos, aviso a todos, keys de Premium, cupones de descuento,
--   verificación de identidad y registro de lo que hace el administrador.
--   Cada app define antes: cfx_planes_app(), cfx_plan_guardar_app(text, text, jsonb, jsonb), cfx_textos_app(),
--   cfx_texto_guardar_app(text, text), cfx_destinatarios(text) y cfx_marcar_verificado(uuid, boolean).
-- ---------------------------------------------------------------------
create table if not exists public.cfx_registro (
  id bigserial primary key, quien text not null default '', accion text not null, detalle text not null default '', creado timestamptz not null default now());
create table if not exists public.cfx_keys (
  id uuid primary key default gen_random_uuid(), hash text not null unique, ultimos text not null, rol text not null check (rol in ('negocio', 'cliente')),
  dias int not null check (dias between 1 and 3660), nota text not null default '', creado timestamptz not null default now(),
  usada_por uuid, usada_email text, usada_at timestamptz, revocada boolean not null default false);
-- G81 d: item '' = Premium · clave de un módulo o de un pack = activa ese módulo/pack (solo negocios). 1 uso cada key.
alter table public.cfx_keys add column if not exists item text not null default '';
create table if not exists public.cfx_cupones (
  codigo text primary key check (codigo ~ '^[A-Z0-9-]{3,20}$'), pct int not null check (pct between 1 and 100), usos_max int, usos int not null default 0,
  vence date, activo boolean not null default true, creado timestamptz not null default now());
create table if not exists public.cfx_verificaciones (
  cuenta uuid primary key, email text not null default '', nombre text not null default '', rut text not null, documento text not null default '',
  frente text, reverso text, selfie text, estado text not null default 'pendiente' check (estado in ('pendiente', 'aprobada', 'rechazada')),
  motivo text not null default '', creado timestamptz not null default now(), resuelto timestamptz);
alter table public.cfx_registro enable row level security;
alter table public.cfx_keys enable row level security;
alter table public.cfx_cupones enable row level security;
alter table public.cfx_verificaciones enable row level security;
revoke all on public.cfx_registro, public.cfx_keys, public.cfx_cupones, public.cfx_verificaciones from anon, authenticated;

create or replace function public.cfx_anotar(p_accion text, p_detalle text) returns void
language sql security definer set search_path = '' as $$
  insert into public.cfx_registro (quien, accion, detalle) values (coalesce((select email from auth.users where id = auth.uid()), 'sistema'), left(p_accion, 60), left(coalesce(p_detalle, ''), 400))
$$;
create or replace function public.cfx_registro_lista(p_limite int default 200) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  return (select coalesce(jsonb_agg(x order by x.id desc), '[]') from (select * from public.cfx_registro order by id desc limit greatest(1, least(coalesce(p_limite, 200), 2000))) x);
end $$;

-- ---------- Planes: [{grupo, clave, free, premium}] (números o sí/no) ----------
-- Borrar el registro de cambios (el común y el propio de la app, si tiene): lo de más de N días, o todo con 0. Solo el administrador.
create or replace function public.cfx_registro_borrar(p_dias int default 30) returns int
language plpgsql security definer set search_path = '' as $$
declare n int := 0; k int; col text; desde timestamptz := case when coalesce(p_dias, 0) <= 0 then 'infinity'::timestamptz else now() - make_interval(days => p_dias) end;
begin
  perform privado.solo_admin();
  delete from public.cfx_registro where creado < desde; get diagnostics n = row_count;
  if to_regclass('public.auditoria') is not null then
    select c.column_name into col from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'auditoria'
      and c.column_name in ('created_at', 'at', 'creado', 'fecha') and c.data_type like 'timestamp%' order by c.ordinal_position limit 1;
    if col is not null then execute format('delete from public.auditoria where %I < $1', col) using desde; get diagnostics k = row_count; n := n + k; end if;
  end if;
  insert into public.cfx_registro (quien, accion, detalle) values (coalesce((select email from auth.users where id = auth.uid()), 'sistema'), 'registro borrado',
    case when coalesce(p_dias, 0) <= 0 then 'todo' else 'más de ' || p_dias || ' días' end || ' (' || n || ' filas)');
  return n;
end $$;
revoke all on function public.cfx_registro_borrar(int) from public, anon;
grant execute on function public.cfx_registro_borrar(int) to authenticated;

create or replace function public.cfx_planes() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  return public.cfx_planes_app();
end $$;
create or replace function public.cfx_plan_guardar(p_grupo text, p_clave text, p_free jsonb, p_premium jsonb) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  if jsonb_typeof(p_free) not in ('number', 'boolean') or jsonb_typeof(p_premium) not in ('number', 'boolean') then raise exception 'Valor no válido'; end if;
  perform public.cfx_plan_guardar_app(p_grupo, p_clave, p_free, p_premium);
  perform public.cfx_anotar('plan', p_grupo || '.' || p_clave || ': gratis ' || p_free::text || ' · premium ' || p_premium::text);
end $$;

-- ---------- Textos: [{clave, valor}] ----------
create or replace function public.cfx_textos() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  return public.cfx_textos_app();
end $$;
create or replace function public.cfx_texto_guardar(p_clave text, p_valor text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  perform public.cfx_texto_guardar_app(p_clave, left(coalesce(p_valor, ''), 2000));
  perform public.cfx_anotar('texto', p_clave);
end $$;

-- ---------- Aviso a todos: destino todos | negocios | clientes | premium | gratis ----------
create or replace function public.cfx_aviso_masivo(p_destino text, p_titulo text, p_cuerpo text) returns int
language plpgsql security definer set search_path = '' as $$
declare u uuid; n int := 0;
begin
  perform privado.solo_admin();
  if trim(coalesce(p_titulo, '')) = '' then raise exception 'Escribe el título'; end if;
  if p_destino not in ('todos', 'negocios', 'clientes', 'premium', 'gratis', 'ofertas') then raise exception 'Destino no válido'; end if;
  -- 'ofertas' = publicidad: solo a quienes aceptaron recibir ofertas (consentimiento, sql/legal.sql).
  for u in select d from public.cfx_destinatarios(case when p_destino = 'ofertas' then 'todos' else p_destino end) d where p_destino <> 'ofertas' or public.cfx_acepta(d, 'ofertas') loop
    perform public.cfx_avisar(u, left(p_titulo, 80), left(coalesce(p_cuerpo, ''), 240));
    n := n + 1;
  end loop;
  perform public.cfx_anotar('aviso', p_destino || ' (' || n || '): ' || p_titulo);
  return n;
end $$;

-- ---------- Nueva versión disponible: push a todos al liberar (una sola vez por versión) ----------
-- G44b: el aviso dice SOLO categorías (🔒 Seguridad · ⚙️ Funcionamiento · 🖥️ Sistema · ✏️ Mejoras · 🎁 Premios/novedades), nunca qué se hizo.
-- p_notas trae las categorías (claves seg/func/sis/mej/pre o sus nombres); el texto libre NO llega a los usuarios.
-- El detalle (p_detalle) queda solo para el administrador: en cfx_versiones (sin políticas = nadie lo lee) y en el 📜 Registro.
create table if not exists public.cfx_versiones (version text primary key, notas text not null default '', avisados int not null default 0, creado timestamptz not null default now());
alter table public.cfx_versiones add column if not exists detalle text not null default '';
alter table public.cfx_versiones enable row level security;
create or replace function public.cfx_version_categorias(p text) returns text
language sql immutable set search_path = '' as $$
  select coalesce(string_agg(c.nombre, ' · ' order by c.orden), '')
  from (values (1, '🔒 Seguridad', '(^|[^a-z])seg([^a-z]|$)|🔒|seguridad'), (2, '⚙️ Funcionamiento', '(^|[^a-z])func([^a-z]|$)|⚙|funcionamiento'),
               (3, '🖥️ Sistema', '(^|[^a-z])sis([^a-z]|$)|🖥|sistema'), (4, '✏️ Mejoras', '(^|[^a-z])mej([^a-z]|$)|✏|mejora'),
               (5, '🎁 Premios/novedades', '(^|[^a-z])pre([^a-z]|$)|🎁|premio|novedad')) c(orden, nombre, patron)
  where lower(coalesce(p, '')) ~ c.patron
$$;
drop function if exists public.cfx_avisar_version(text, text, text);
create or replace function public.cfx_avisar_version(p_version text, p_notas text default '', p_app text default '', p_detalle text default '') returns int
language plpgsql security definer set search_path = '' as $$
declare u uuid; n int := 0; v text := trim(coalesce(p_version, '')); cat text := public.cfx_version_categorias(p_notas);
  det text := left(trim(coalesce(nullif(trim(coalesce(p_detalle, '')), ''), p_notas, '')), 400);
begin
  perform privado.solo_admin();
  if v !~ '^[0-9]+(\.[0-9]+){0,3}$' then raise exception 'Versión no válida'; end if;
  if exists (select 1 from public.cfx_versiones where version = v) then return 0; end if;
  for u in select * from public.cfx_destinatarios('todos') loop
    perform public.cfx_avisar(u, '🔄 Nueva versión', left(coalesce(nullif(trim(p_app), '') || ' ', '') || 'v' || v || case when cat <> '' then ': ' || cat else '' end || '. Se actualiza sola al abrirla.', 240));
    n := n + 1;
  end loop;
  insert into public.cfx_versiones (version, notas, avisados, detalle) values (v, cat, n, det);
  perform public.cfx_anotar('version', left('v' || v || ' avisada a ' || n || case when cat <> '' then ' · ' || cat else '' end || case when det <> '' then ' — ' || det else '' end, 500));
  return n;
end $$;
revoke execute on function public.cfx_avisar_version(text, text, text, text) from public, anon;
grant execute on function public.cfx_avisar_version(text, text, text, text) to authenticated;
revoke all on function public.cfx_version_categorias(text) from public, anon, authenticated;

-- ---------- Keys de Premium (de un solo uso). Se guardan cifradas: el código completo solo se ve al crearlas. ----------
drop function if exists public.cfx_keys_crear(int, text, int, text);
create or replace function public.cfx_keys_crear(p_n int, p_rol text, p_dias int, p_nota text default '', p_item text default '') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare c text; out jsonb := '[]'::jsonb; it text := trim(coalesce(p_item, ''));
begin
  perform privado.solo_admin();
  if p_rol not in ('negocio', 'cliente') or coalesce(p_dias, 0) not between 1 and 3660 or coalesce(p_n, 0) not between 1 and 50 then raise exception 'Datos no válidos'; end if;
  if it <> '' and (p_rol <> 'negocio' or cardinality(public.cfx_venta_modulos(it)) = 0) then raise exception 'Módulo o pack no válido (las keys de módulos son para negocios)'; end if;
  for i in 1..p_n loop
    c := upper(replace(gen_random_uuid()::text, '-', ''));
    c := 'CFX-' || substr(c, 1, 4) || '-' || substr(c, 5, 4) || '-' || substr(c, 9, 4);
    insert into public.cfx_keys (hash, ultimos, rol, dias, nota, item) values (encode(sha256(convert_to(c, 'UTF8')), 'hex'), right(c, 4), p_rol, p_dias, left(coalesce(p_nota, ''), 120), it);
    out := out || to_jsonb(c);
  end loop;
  perform public.cfx_anotar('keys', p_n || ' keys ' || case when it = '' then 'Premium ' || p_rol else it end || ' de ' || p_dias || ' días');
  return out;
end $$;
-- G81 d: aplica una key ya validada a una cuenta (Premium o módulo/pack). Si el negocio ya tiene todo lo de la key activo, no la gasta.
create or replace function public.cfx_key_dar(k public.cfx_keys, p_cuenta uuid, p_email text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare h timestamptz; n uuid; nom text;
begin
  if coalesce(k.item, '') = '' then
    h := public.cfx_dar_premium(p_cuenta, k.rol, k.dias);
    if h is null then return jsonb_build_object('error', 'No se encontró la cuenta'); end if;
    insert into public.cfx_exentos (cuenta, nota) values (p_cuenta, 'Key ' || k.ultimos) on conflict (cuenta) do nothing;
    nom := 'Premium';
  else
    n := public.cfx_negocio_cuenta(p_cuenta);
    if n is null then return jsonb_build_object('error', 'Esta key es para negocios'); end if;
    nom := coalesce((select c.nombre from public.cfx_modulos_catalogo() c where c.clave = k.item), public.cfx_venta() #>> array['packs', k.item, 'nombre'], k.item);
    if cardinality(public.cfx_venta_modulos(k.item)) = 0 then return jsonb_build_object('error', 'Este módulo ya no está disponible'); end if;
    if not exists (select 1 from unnest(public.cfx_venta_modulos(k.item)) x where not exists (
        select 1 from public.cfx_modulos_negocio m where m.negocio = n and m.modulo = x and m.hasta > now())) then
      return jsonb_build_object('error', 'Ya tienes ' || nom || ' activo. Guarda la key para cuando venza o para otro negocio.');
    end if;
    h := public.cfx_modulos_dar(n, k.item, k.dias, 'pago');
  end if;
  update public.cfx_keys set usada_por = p_cuenta, usada_email = left(coalesce(p_email, ''), 200), usada_at = now() where id = k.id;
  return jsonb_build_object('hasta', h, 'dias', k.dias, 'item', coalesce(k.item, ''), 'nombre', nom);
end $$;
revoke all on function public.cfx_key_dar(public.cfx_keys, uuid, text) from public, anon, authenticated;
create or replace function public.cfx_keys_lista() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  return (select coalesce(jsonb_agg(to_jsonb(k) - 'hash' order by k.creado desc), '[]') from (select * from public.cfx_keys order by creado desc limit 300) k);
end $$;
create or replace function public.cfx_key_revocar(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  update public.cfx_keys set revocada = true where id = p_id and usada_por is null;
  perform public.cfx_anotar('key revocada', p_id::text);
end $$;
create or replace function public.cfx_key_canjear(p_codigo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare y jsonb := public.cfx_yo(); k public.cfx_keys; r jsonb; c text := upper(trim(coalesce(p_codigo, '')));
begin
  if y is null or (y ->> 'id') is null then raise exception 'Inicia sesión'; end if;
  if (select count(*) from public.cfx_registro where accion = 'key fallida' and detalle = (y ->> 'id') and creado > now() - interval '1 hour') >= 10 then
    raise exception 'Demasiados intentos. Prueba en una hora.';
  end if;
  select * into k from public.cfx_keys where hash = encode(sha256(convert_to(c, 'UTF8')), 'hex') for update;
  if k.id is null or k.revocada or k.usada_por is not null then
    -- Sin raise: si no, el registro se deshace y el límite de 10 por hora nunca cuenta (núcleo 2.48).
    insert into public.cfx_registro (quien, accion, detalle) values (coalesce(y ->> 'email', ''), 'key fallida', y ->> 'id');
    return jsonb_build_object('error', 'Key no válida o ya usada');
  end if;
  if k.rol <> coalesce(y ->> 'rol', '') then raise exception 'Esta key es para cuentas de %', case when k.rol = 'negocio' then 'negocio' else 'cliente' end; end if;
  r := public.cfx_key_dar(k, (y ->> 'id')::uuid, y ->> 'email');
  if r ? 'error' then return r; end if;
  perform public.cfx_avisar_admin('🔑 Key canjeada', coalesce(y ->> 'email', '') || ' · ' || (r ->> 'nombre') || ' · ' || k.dias || ' días');
  return r;
end $$;

-- ---------- Cupones de descuento (se aplican al pagar Premium) ----------
create or replace function public.cfx_cupon_ver(p_codigo text) returns int
language plpgsql stable security definer set search_path = '' as $$
declare c public.cfx_cupones;
begin
  if auth.uid() is null then raise exception 'Inicia sesión'; end if;
  select * into c from public.cfx_cupones where codigo = upper(trim(coalesce(p_codigo, '')));
  if c.codigo is null or not c.activo or (c.vence is not null and c.vence < current_date) or (c.usos_max is not null and c.usos >= c.usos_max) then
    raise exception 'Cupón no válido o vencido';
  end if;
  return c.pct;
end $$;
create or replace function public.cfx_cupones_lista() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  return (select coalesce(jsonb_agg(to_jsonb(c) order by c.creado desc), '[]') from public.cfx_cupones c);
end $$;
create or replace function public.cfx_cupon_guardar(p_codigo text, p_pct int, p_usos_max int default null, p_vence date default null, p_activo boolean default true) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  insert into public.cfx_cupones (codigo, pct, usos_max, vence, activo) values (upper(trim(p_codigo)), p_pct, p_usos_max, p_vence, coalesce(p_activo, true))
  on conflict (codigo) do update set pct = excluded.pct, usos_max = excluded.usos_max, vence = excluded.vence, activo = excluded.activo;
  perform public.cfx_anotar('cupón', upper(trim(p_codigo)) || ' ' || p_pct || '%');
end $$;
create or replace function public.cfx_cupon_borrar(p_codigo text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  delete from public.cfx_cupones where codigo = upper(trim(p_codigo));
end $$;

-- ---------- Verificación de identidad (RUT, N° de documento, fotos de la cédula y selfie). Las fotos se borran al revisar. ----------
create or replace function public.cfx_rut_ok(r text) returns boolean
language plpgsql immutable as $$
declare s text := upper(regexp_replace(coalesce(r, ''), '[^0-9kK]', '', 'g')); cuerpo text; dv text; suma int := 0; m int := 2; res text;
begin
  if length(s) < 2 then return false; end if;
  cuerpo := left(s, length(s) - 1); dv := right(s, 1);
  if cuerpo !~ '^[0-9]+$' then return false; end if;
  for i in reverse length(cuerpo)..1 loop
    suma := suma + substr(cuerpo, i, 1)::int * m; m := case when m = 7 then 2 else m + 1 end;
  end loop;
  res := case 11 - suma % 11 when 11 then '0' when 10 then 'K' else (11 - suma % 11)::text end;
  return res = dv;
end $$;
create or replace function public.cfx_verif_estado() returns jsonb
language sql stable security definer set search_path = '' as $$
  select (select jsonb_build_object('estado', estado, 'motivo', motivo, 'creado', creado, 'resuelto', resuelto) from public.cfx_verificaciones where cuenta = auth.uid())
$$;
create or replace function public.cfx_verif_enviar(p_rut text, p_documento text, p_frente text, p_reverso text, p_selfie text) returns void
language plpgsql security definer set search_path = '' as $$
declare y jsonb := public.cfx_yo(); r text := upper(regexp_replace(coalesce(p_rut, ''), '[^0-9kK]', '', 'g'));
begin
  if y is null or (y ->> 'id') is null then raise exception 'Inicia sesión'; end if;
  if not public.cfx_rut_ok(r) then raise exception 'RUT no válido'; end if;
  if exists (select 1 from public.cfx_verificaciones where rut = r and cuenta <> (y ->> 'id')::uuid and estado <> 'rechazada') then raise exception 'Ese RUT ya está en otra cuenta'; end if;
  if exists (select 1 from public.cfx_verificaciones where cuenta = (y ->> 'id')::uuid and estado = 'aprobada') then raise exception 'Tu identidad ya está verificada'; end if;
  if coalesce(length(p_frente), 0) < 200 or coalesce(length(p_reverso), 0) < 200 or coalesce(length(p_selfie), 0) < 200 then raise exception 'Faltan fotos'; end if;
  if length(p_frente) > 500000 or length(p_reverso) > 500000 or length(p_selfie) > 500000 then raise exception 'Fotos muy pesadas'; end if;
  insert into public.cfx_verificaciones (cuenta, email, nombre, rut, documento, frente, reverso, selfie, estado, motivo, creado, resuelto)
  values ((y ->> 'id')::uuid, coalesce(y ->> 'email', ''), left(coalesce(y ->> 'nombre', ''), 80), r, left(coalesce(p_documento, ''), 20), p_frente, p_reverso, p_selfie, 'pendiente', '', now(), null)
  on conflict (cuenta) do update set rut = excluded.rut, documento = excluded.documento, frente = excluded.frente, reverso = excluded.reverso, selfie = excluded.selfie,
    estado = 'pendiente', motivo = '', creado = now(), resuelto = null;
  perform public.cfx_avisar_admin('🪪 Verificación por revisar', coalesce(nullif(y ->> 'nombre', ''), y ->> 'email'));
end $$;
create or replace function public.cfx_verif_lista(p_estado text default 'pendiente') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  return (select coalesce(jsonb_agg(x order by x.creado desc), '[]') from (select cuenta, email, nombre, rut, documento, estado, motivo, creado, resuelto
    from public.cfx_verificaciones where p_estado = 'todos' or estado = p_estado order by creado desc limit 200) x);
end $$;
create or replace function public.cfx_verif_fotos(p_cuenta uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  return (select jsonb_build_object('frente', frente, 'reverso', reverso, 'selfie', selfie) from public.cfx_verificaciones where cuenta = p_cuenta);
end $$;
create or replace function public.cfx_verif_resolver(p_cuenta uuid, p_aprobar boolean, p_motivo text default '') returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  update public.cfx_verificaciones set estado = case when p_aprobar then 'aprobada' else 'rechazada' end, motivo = left(coalesce(p_motivo, ''), 200),
    resuelto = now(), frente = null, reverso = null, selfie = null where cuenta = p_cuenta and estado = 'pendiente';
  if not found then raise exception 'No hay una verificación pendiente'; end if;
  perform public.cfx_marcar_verificado(p_cuenta, p_aprobar);
  perform public.cfx_avisar(p_cuenta, case when p_aprobar then '🪪 Identidad verificada' else '🪪 Verificación rechazada' end,
    case when p_aprobar then 'Ya apareces como persona verificada.' else coalesce(nullif(p_motivo, ''), 'Revisa las fotos') || '. Puedes enviarla de nuevo.' end);
  perform public.cfx_anotar(case when p_aprobar then 'verificación aprobada' else 'verificación rechazada' end, p_cuenta::text);
end $$;

create or replace function public.cfx_cupon_usado() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.estado = 'aprobado' and old.estado = 'pendiente' and new.cupon is not null then update public.cfx_cupones set usos = usos + 1 where codigo = new.cupon; end if;
  return new;
end $$;
drop trigger if exists cfx_cupon_usado on public.cfx_pagos;
create trigger cfx_cupon_usado after update of estado on public.cfx_pagos for each row execute function public.cfx_cupon_usado();

-- ---------- Verificación humana (Cloudflare Turnstile): la site key es pública; la secret key va en Supabase → Authentication → CAPTCHA ----------
-- y, para las compras/reservas sin cuenta, también aquí (cfx_secretos, nunca sale de la base): la base revisa el token con Cloudflare.
insert into public.cfx_config (clave, valor) values ('humano', '{"site_key": ""}') on conflict (clave) do nothing;
create table if not exists public.cfx_secretos (clave text primary key, valor text not null, updated_at timestamptz not null default now());
alter table public.cfx_secretos enable row level security;
revoke all on public.cfx_secretos from anon, authenticated;
create or replace function public.cfx_humano() returns jsonb
language sql stable security definer set search_path = '' as $$
  select valor || jsonb_build_object('invitados', exists (select 1 from public.cfx_secretos where clave = 'turnstile'))
  from public.cfx_config where clave = 'humano' $$;
drop function if exists public.cfx_humano_guardar(text);
create or replace function public.cfx_humano_guardar(p_site_key text, p_secreto text default null) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  if coalesce(p_site_key, '') <> '' and p_site_key !~ '^[0-9A-Za-z_-]{10,60}$' then raise exception 'Site key no válida'; end if;
  if coalesce(p_secreto, '') <> '' and p_secreto !~ '^[0-9A-Za-z_-]{10,80}$' then raise exception 'Secret key no válida'; end if;
  update public.cfx_config set valor = jsonb_build_object('site_key', coalesce(p_site_key, '')) where clave = 'humano';
  -- null = dejar la secret key como está; '' = quitarla (o si se apaga la site key).
  if coalesce(p_site_key, '') = '' or p_secreto = '' then delete from public.cfx_secretos where clave = 'turnstile';
  elsif p_secreto is not null then
    insert into public.cfx_secretos (clave, valor) values ('turnstile', p_secreto)
    on conflict (clave) do update set valor = excluded.valor, updated_at = now();
  end if;
  perform public.cfx_anotar('humano', case when coalesce(p_site_key, '') = '' then 'apagado' else 'site key ' || right(p_site_key, 4) ||
    case when exists (select 1 from public.cfx_secretos where clave = 'turnstile') then ' + compras sin cuenta' else '' end end);
end $$;
-- ¿El token de Turnstile es de una persona? Sin secret key no se exige. Si Cloudflare no responde, no frena la venta.
create or replace function public.cfx_humano_ok(p_token text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare k text := public.cfx_secreto((select valor from public.cfx_secretos where clave = 'turnstile')); st int; c text;
begin
  if k is null then return true; end if;
  if coalesce(p_token, '') = '' or length(p_token) > 4000 then return false; end if;
  begin
    perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '5');
    execute 'select status, content from extensions.http(row($1, $2, $3, $4, $5)::extensions.http_request)' into st, c
      using 'POST', 'https://challenges.cloudflare.com/turnstile/v0/siteverify', array[]::extensions.http_header[],
            'application/x-www-form-urlencoded', 'secret=' || k || '&response=' || p_token;
  exception when others then return true;
  end;
  if st is distinct from 200 or c !~ '^\s*\{' then return true; end if;
  return coalesce((c::jsonb ->> 'success')::boolean, false);
end $$;
revoke all on function public.cfx_humano(), public.cfx_humano_guardar(text, text), public.cfx_humano_ok(text) from public, anon, authenticated;
grant execute on function public.cfx_humano() to anon, authenticated;
grant execute on function public.cfx_humano_guardar(text, text) to authenticated;

revoke all on function public.cfx_anotar(text, text), public.cfx_cupon_usado() from public, anon, authenticated;
revoke all on function public.cfx_registro_lista(int), public.cfx_planes(), public.cfx_plan_guardar(text, text, jsonb, jsonb), public.cfx_textos(), public.cfx_texto_guardar(text, text),
  public.cfx_aviso_masivo(text, text, text), public.cfx_keys_crear(int, text, int, text, text), public.cfx_keys_lista(), public.cfx_key_revocar(uuid), public.cfx_key_canjear(text),
  public.cfx_cupon_ver(text), public.cfx_cupones_lista(), public.cfx_cupon_guardar(text, int, int, date, boolean), public.cfx_cupon_borrar(text),
  public.cfx_verif_estado(), public.cfx_verif_enviar(text, text, text, text, text), public.cfx_verif_lista(text), public.cfx_verif_fotos(uuid), public.cfx_verif_resolver(uuid, boolean, text) from public, anon;
grant execute on function public.cfx_registro_lista(int), public.cfx_planes(), public.cfx_plan_guardar(text, text, jsonb, jsonb), public.cfx_textos(), public.cfx_texto_guardar(text, text),
  public.cfx_aviso_masivo(text, text, text), public.cfx_keys_crear(int, text, int, text, text), public.cfx_keys_lista(), public.cfx_key_revocar(uuid), public.cfx_key_canjear(text),
  public.cfx_cupon_ver(text), public.cfx_cupones_lista(), public.cfx_cupon_guardar(text, int, int, date, boolean), public.cfx_cupon_borrar(text),
  public.cfx_verif_estado(), public.cfx_verif_enviar(text, text, text, text, text), public.cfx_verif_lista(text), public.cfx_verif_fotos(uuid), public.cfx_verif_resolver(uuid, boolean, text) to authenticated;
revoke all on function public.cfx_planes_app(), public.cfx_plan_guardar_app(text, text, jsonb, jsonb), public.cfx_textos_app(), public.cfx_texto_guardar_app(text, text),
  public.cfx_destinatarios(text), public.cfx_marcar_verificado(uuid, boolean) from public, anon, authenticated;

-- ---------- Series para el Resumen del Centro de Mando: por mes, cuentas nuevas y pagos/ingresos aprobados (últimos N meses) ----------
create or replace function public.cfx_series(p_meses int default 6) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare n int := greatest(1, least(coalesce(p_meses, 6), 24));
begin
  perform privado.solo_admin();
  return (select jsonb_agg(jsonb_build_object('mes', to_char(m, 'YYYY-MM'),
      'cuentas', (select count(*) from auth.users u where u.created_at >= m and u.created_at < m + interval '1 month'),
      'pagos', (select count(*) from public.cfx_pagos p where p.estado = 'aprobado' and p.creado >= m and p.creado < m + interval '1 month' and p.creado >= public.cfx_ingresos_desde()),
      'ingresos', (select coalesce(sum(p.monto), 0) from public.cfx_pagos p where p.estado = 'aprobado' and p.creado >= m and p.creado < m + interval '1 month' and p.creado >= public.cfx_ingresos_desde())) order by m)
    from generate_series(date_trunc('month', now()) - make_interval(months => n - 1), date_trunc('month', now()), interval '1 month') m);
end $$;
revoke all on function public.cfx_series(int) from public, anon;
grant execute on function public.cfx_series(int) to authenticated;

-- ---------- Servidor (igual en las 7 apps): uso de la base, cuentas, tablas más pesadas y tareas automáticas ----------
-- El Centro de Mando lo muestra en el carrusel de servidores. "tareas" sirve para ver si el envío de push está corriendo.
create or replace function public.cfx_servidor() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare t jsonb := '[]'; tb jsonb;
begin
  perform privado.solo_admin();
  select coalesce(jsonb_agg(x), '[]') into tb from (
    select jsonb_build_object('tabla', c.relname, 'bytes', pg_total_relation_size(c.oid), 'filas', greatest(c.reltuples, 0)::bigint) x
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' order by pg_total_relation_size(c.oid) desc limit 6) q;
  begin
    execute $q$ select coalesce(jsonb_agg(jsonb_build_object('nombre', j.jobname, 'activa', j.active, 'cada', j.schedule,
        'ultima', r.end_time, 'ok', r.status = 'succeeded', 'error', left(r.return_message, 160)) order by j.jobname), '[]')
      from cron.job j left join lateral (select end_time, status, return_message from cron.job_run_details d where d.jobid = j.jobid order by d.runid desc limit 1) r on true $q$ into t;
  exception when others then t := '[]';
  end;
  return jsonb_build_object('db_bytes', pg_database_size(current_database()), 'limite_bytes', 500 * 1024 * 1024,
    'cuentas', (select count(*) from auth.users), 'tablas', tb, 'tareas', t, 'hora', now());
end $$;
revoke all on function public.cfx_servidor() from public, anon;
grant execute on function public.cfx_servidor() to authenticated;

-- ---------- Actualizar la base ahora (núcleo 2.31, igual en las 7 apps) ----------
-- El Centro de Mando lo usa cuando una base quedó atrás ("se está actualizando sola" que no avanza).
-- Programa una tarea de un solo uso (en máx. 1 minuto, sin el límite de tiempo de la app) que corre auto_actualizar() y anota
-- su resultado en cfx_registro ('auto'): así se ve la causa real si falla (la tarea de cada 10 min siempre figura "ok").
drop function if exists public.cfx_actualizar_ahora();
create or replace function public.cfx_actualizar_ahora(p_programar boolean default true) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare prog text := 'ok'; t jsonb := '[]'; ult jsonb;
begin
  perform privado.solo_admin();
  if p_programar then begin
    execute $q$ select cron.schedule('cfx-ahora', '* * * * *', $c$do $d$ declare r text; begin r := public.auto_actualizar(); perform public.cfx_anotar('auto', r); end $d$; select cron.unschedule('cfx-ahora')$c$) $q$;
  exception when others then prog := sqlerrm;
  end; else prog := ''; end if;
  begin
    execute $q$ select coalesce(jsonb_agg(jsonb_build_object('nombre', j.jobname, 'activa', j.active, 'cada', j.schedule, 'ultima', r.end_time, 'ok', r.status = 'succeeded', 'error', left(r.return_message, 160)) order by j.jobname), '[]')
      from cron.job j left join lateral (select end_time, status, return_message from cron.job_run_details d where d.jobid = j.jobid order by d.runid desc limit 1) r on true
      where j.jobname ~ 'auto|ahora' $q$ into t;
  exception when others then t := '[]';
  end;
  select coalesce(jsonb_agg(jsonb_build_object('detalle', detalle, 'creado', creado) order by id desc), '[]') into ult
    from (select * from public.cfx_registro where accion = 'auto' order by id desc limit 3) q;
  if p_programar then perform public.cfx_anotar('version', 'Actualizar base ahora: ' || left(prog, 200)); end if;
  return jsonb_build_object('programada', prog, 'tareas', t, 'ultimos', ult, 'hora', now());
end $$;
revoke all on function public.cfx_actualizar_ahora(boolean) from public, anon;
grant execute on function public.cfx_actualizar_ahora(boolean) to authenticated;

-- ---------- G20 · 🏪 Negocios desde el Centro de Mando (Control → app → Negocios) ----------
-- Lista de cuentas de la app, Premium 1 mes / 3 meses / 1 año o quitarlo, e ingresar una key a nombre de esa cuenta.
-- Ganchos de cada app (opcionales: sin ellos se avisa que llega en su turno):
--   cfx_cuentas_app(p_rol text, p_q text) → jsonb [{ id, email, nombre, rol, premium_hasta, creado }] · cfx_quitar_premium(p_cuenta uuid)
create or replace function public.cfx_negocios(p_q text default '', p_rol text default 'negocio') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r jsonb;
begin
  perform privado.solo_admin();
  if to_regprocedure('public.cfx_cuentas_app(text,text)') is null then return jsonb_build_object('error', 'Esta app aún no tiene la lista de negocios: llega cuando le toque su turno.'); end if;
  execute 'select public.cfx_cuentas_app($1, $2)' into r using case when p_rol = 'cliente' then 'cliente' else 'negocio' end, left(coalesce(p_q, ''), 80);
  return coalesce(r, '[]'::jsonb);
end $$;
create or replace function public.cfx_premium_cuenta(p_cuenta uuid, p_rol text, p_dias int) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare h timestamptz;
begin
  perform privado.solo_admin();
  if p_cuenta is null or coalesce(p_rol, '') not in ('negocio', 'cliente') or p_dias is null or p_dias > 3660 then return jsonb_build_object('error', 'Datos no válidos'); end if;
  if p_dias > 0 then
    h := public.cfx_dar_premium(p_cuenta, p_rol, p_dias);
    if h is null then return jsonb_build_object('error', 'No se encontró la cuenta'); end if;
    perform public.cfx_avisar(p_cuenta, '⭐ Premium activado', 'Tienes Premium hasta el ' || to_char(h at time zone 'America/Santiago', 'DD-MM-YYYY') || '.');
    perform public.cfx_anotar('premium', p_dias || ' días a ' || p_cuenta);
    return jsonb_build_object('hasta', h);
  end if;
  if to_regprocedure('public.cfx_quitar_premium(uuid)') is null then return jsonb_build_object('error', 'Esta app aún no permite quitar Premium desde aquí.'); end if;
  execute 'select public.cfx_quitar_premium($1)' using p_cuenta;
  perform public.cfx_anotar('premium quitado', p_cuenta::text);
  return jsonb_build_object('hasta', null);
end $$;
create or replace function public.cfx_key_aplicar(p_cuenta uuid, p_rol text, p_email text, p_codigo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare k public.cfx_keys; r jsonb; c text := upper(trim(coalesce(p_codigo, '')));
begin
  perform privado.solo_admin();
  if p_cuenta is null or coalesce(p_rol, '') not in ('negocio', 'cliente') then return jsonb_build_object('error', 'Datos no válidos'); end if;
  select * into k from public.cfx_keys where hash = encode(sha256(convert_to(c, 'UTF8')), 'hex') for update;
  if k.id is null or k.revocada or k.usada_por is not null then return jsonb_build_object('error', 'Key no válida o ya usada'); end if;
  if k.rol <> p_rol then return jsonb_build_object('error', 'Esta key es para cuentas de ' || k.rol); end if;
  r := public.cfx_key_dar(k, p_cuenta, p_email);
  if r ? 'error' then return r; end if;
  perform public.cfx_avisar(p_cuenta, '🔑 ' || (r ->> 'nombre') || ' activado', 'Tienes ' || (r ->> 'nombre') || ' por ' || k.dias || ' días.');
  perform public.cfx_anotar('key aplicada', '…' || k.ultimos || ' (' || (r ->> 'nombre') || ') a ' || coalesce(p_email, p_cuenta::text));
  return r;
end $$;
revoke all on function public.cfx_negocios(text, text), public.cfx_premium_cuenta(uuid, text, int), public.cfx_key_aplicar(uuid, text, text, text) from public, anon;
grant execute on function public.cfx_negocios(text, text), public.cfx_premium_cuenta(uuid, text, int), public.cfx_key_aplicar(uuid, text, text, text) to authenticated;

-- ---------- G38 · 💰 Dinero (CM → Resumen): ingresos del mes por Premium/módulo, pruebas por vencer y morosos con su WhatsApp ----------
-- Moroso = su último pago aprobado (Premium o módulo) dejó de cubrir en los últimos 60 días, no tiene otro pago en revisión,
-- no está exento y hoy no tiene Premium activo. Solo lee: no cambia nada.
create or replace function public.cfx_tel_de(p_cuenta uuid) returns text
language plpgsql stable security definer set search_path = '' as $$
declare t text; x record;
begin
  for x in select c.table_name, c.column_name from information_schema.columns c
    where c.table_schema = 'public' and c.table_name in ('perfiles', 'profiles') and c.column_name in ('telefono', 'whatsapp', 'phone') order by c.table_name, c.column_name loop
    begin
      execute format('select nullif(trim(%I::text), %L) from public.%I where id = $1', x.column_name, '', x.table_name) into t using p_cuenta;
    exception when others then t := null; end;
    if t is not null then return left(t, 30); end if;
  end loop;
  select coalesce(nullif(u.phone, ''), u.raw_user_meta_data ->> 'telefono', u.raw_user_meta_data ->> 'whatsapp') into t from auth.users u where u.id = p_cuenta;
  return left(nullif(trim(t), ''), 30);
end $$;
create or replace function public.cfx_dinero() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare z text := 'America/Santiago'; m0 timestamptz := date_trunc('month', now() at time zone z) at time zone z;
        m1 timestamptz := date_trunc('month', (now() at time zone z) - interval '1 month') at time zone z;
        d timestamptz := public.cfx_ingresos_desde(); cu jsonb := '[]'; activos uuid[] := '{}'; ve jsonb; mo jsonb;
begin
  perform privado.solo_admin();
  if to_regprocedure('public.cfx_cuentas_app(text,text)') is not null then
    begin
      execute 'select coalesce(public.cfx_cuentas_app(''negocio'', ''''), ''[]''::jsonb) || coalesce(public.cfx_cuentas_app(''cliente'', ''''), ''[]''::jsonb)' into cu;
    exception when others then cu := '[]'; end;
  end if;
  select coalesce(array_agg((e ->> 'id')::uuid), '{}') into activos from jsonb_array_elements(cu) e
    where e ->> 'premium_hasta' is not null and (e ->> 'premium_hasta')::timestamptz > now();
  -- Por vencer en 7 días (sin "para siempre"): prueba = nunca ha pagado; renovación = ya pagó antes.
  select coalesce(jsonb_agg(jsonb_build_object('id', e ->> 'id', 'nombre', coalesce(nullif(e ->> 'nombre', ''), e ->> 'email'), 'email', e ->> 'email', 'rol', e ->> 'rol',
      'hasta', e ->> 'premium_hasta', 'tel', public.cfx_tel_de((e ->> 'id')::uuid),
      'pago', exists (select 1 from public.cfx_pagos p where p.cuenta = (e ->> 'id')::uuid and p.estado = 'aprobado')) order by (e ->> 'premium_hasta')::timestamptz), '[]')
    into ve from (select e from jsonb_array_elements(cu) e where e ->> 'premium_hasta' is not null and e ->> 'premium_hasta' <> 'infinity'
      and (e ->> 'premium_hasta')::timestamptz between now() and now() + interval '7 days' and coalesce((e ->> 'suspendido')::boolean, false) = false limit 100) q;
  select coalesce(jsonb_agg(jsonb_build_object('id', u.cuenta, 'nombre', coalesce(nullif(u.nombre, ''), u.email), 'email', u.email, 'rol', u.rol, 'producto', u.prod,
      'vencio', u.fin, 'monto', u.monto, 'periodo', u.periodo, 'tel', public.cfx_tel_de(u.cuenta)) order by u.fin desc), '[]') into mo
  from (select distinct on (p.cuenta, coalesce(p.producto, '')) p.cuenta, p.nombre, p.email, p.rol, p.producto as prod, p.monto, p.periodo,
          coalesce(p.resuelto, p.creado) + make_interval(days => coalesce(p.dias, 0)) as fin
        from public.cfx_pagos p where p.estado = 'aprobado' and coalesce(p.dias, 0) > 0 and not coalesce(p.regalo, false) and p.key_regalo is null
        order by p.cuenta, coalesce(p.producto, ''), coalesce(p.resuelto, p.creado) + make_interval(days => coalesce(p.dias, 0)) desc) u
  where u.fin between now() - interval '60 days' and now()
    and not (u.prod is null and u.cuenta = any (activos))
    and not exists (select 1 from public.cfx_pagos g where g.cuenta = u.cuenta and g.estado = 'pendiente')
    and not exists (select 1 from public.cfx_exentos x where x.cuenta = u.cuenta);
  return jsonb_build_object('desde', nullif(d, '-infinity'::timestamptz),
    'mes', (select jsonb_build_object('monto', coalesce(sum(monto), 0), 'n', count(*)) from public.cfx_pagos where estado = 'aprobado' and creado >= greatest(m0, d)),
    'anterior', (select jsonb_build_object('monto', coalesce(sum(monto), 0), 'n', count(*)) from public.cfx_pagos where estado = 'aprobado' and creado >= greatest(m1, d) and creado < m0),
    'por', (select coalesce(jsonb_agg(jsonb_build_object('producto', k, 'monto', s, 'n', n) order by s desc), '[]') from (
      select coalesce(producto, 'premium') k, sum(monto) s, count(*) n from public.cfx_pagos where estado = 'aprobado' and creado >= greatest(m0, d) group by 1) q),
    'medios', (select coalesce(jsonb_object_agg(medio, s), '{}') from (select medio, sum(monto) s from public.cfx_pagos where estado = 'aprobado' and creado >= greatest(m0, d) group by 1) q),
    'pendientes', (select count(*) from public.cfx_pagos where estado = 'pendiente' and medio not in ('mp', 'flow')),
    'premium', coalesce(cardinality(activos), 0), 'vencen', ve, 'morosos', mo);
end $$;
revoke all on function public.cfx_tel_de(uuid) from public, anon, authenticated;
revoke all on function public.cfx_dinero() from public, anon;
grant execute on function public.cfx_dinero() to authenticated;
-- ---------------------------------------------------------------------
-- CodeFix · Ayuda (igual en las 6 apps; lo reparte nucleo/sincronizar.py).
--   1) Puente al Centro de Mando: los avisos importantes (pagos por revisar, mensajes de soporte) le llegan al tiro
--      al Centro de Mando. El Centro de Mando vincula cada app solo (cfx_cm_vincular) al abrir Pagos o Mensajes.
--   2) Chat de soporte: cada persona escribe desde su app y tú respondes desde el Centro de Mando → Mensajes.
--   3) Guía para partir: lo que le falta configurar a cada negocio (cfx_guia_app() de cada app). No se marca
--      como listo hasta que de verdad lo hace, y se le recuerda cada vez que entra.
--   Cada app define antes: cfx_guia_app() → [{ k, t, d, ok, ir }].
-- ---------------------------------------------------------------------

-- ---------- 1) Puente al Centro de Mando ----------
create or replace function public.cfx_cm_vincular(p_url text, p_key text, p_secreto text, p_app text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  if coalesce(p_url, '') !~ '^https://[a-z0-9.-]+$' or length(coalesce(p_key, '')) < 20 or length(coalesce(p_secreto, '')) < 24 or coalesce(p_app, '') !~ '^[a-z]{2,20}$' then
    raise exception 'Datos de vínculo no válidos';
  end if;
  insert into public.cfx_config (clave, valor) values ('cm', jsonb_build_object('url', p_url, 'key', p_key, 'secreto', p_secreto, 'app', p_app, 'desde', now()))
  on conflict (clave) do update set valor = excluded.valor;
  return jsonb_build_object('vinculado', true, 'app', p_app);
end $$;

create or replace function public.cfx_cm_estado() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v jsonb := (select valor from public.cfx_config where clave = 'cm');
begin
  perform privado.solo_admin();
  return jsonb_build_object('vinculado', coalesce(v ->> 'secreto', '') <> '', 'app', v ->> 'app', 'url', v ->> 'url', 'desde', v -> 'desde');
end $$;

-- Avisa al Centro de Mando (si la app está vinculada); si no, al administrador de esta app. Nunca hace fallar lo que la llama.
create or replace function public.cfx_al_cm(p_titulo text, p_cuerpo text, p_tipo text default 'aviso') returns void
language plpgsql security definer set search_path = '' as $$
declare v jsonb := (select valor from public.cfx_config where clave = 'cm');
begin
  if coalesce(v ->> 'secreto', '') = '' then
    perform public.cfx_avisar_admin(p_titulo, p_cuerpo);
    return;
  end if;
  begin
    perform net.http_post(
      url := (v ->> 'url') || '/rest/v1/rpc/cfx_aviso_externo',
      body := jsonb_build_object('p_app', v ->> 'app', 'p_secreto', v ->> 'secreto', 'p_titulo', left(p_titulo, 90), 'p_cuerpo', left(coalesce(p_cuerpo, ''), 240), 'p_tipo', p_tipo),
      headers := jsonb_build_object('apikey', v ->> 'key', 'Authorization', 'Bearer ' || (v ->> 'key'), 'Content-Type', 'application/json'));
  exception when others then
    begin perform public.cfx_avisar_admin(p_titulo, p_cuerpo); exception when others then null; end;
  end;
end $$;

-- ---------- 2) Chat de soporte ----------
create table if not exists public.cfx_chat (
  id      bigserial primary key,
  cuenta  uuid not null,
  email   text not null default '',
  nombre  text not null default '',
  rol     text not null default '',
  de      text not null check (de in ('persona', 'soporte')),
  texto   text not null check (length(texto) between 1 and 1000),
  leido   boolean not null default false,
  creado  timestamptz not null default now()
);
create index if not exists cfx_chat_cuenta_idx on public.cfx_chat (cuenta, id);
create index if not exists cfx_chat_sin_leer_idx on public.cfx_chat (de, leido) where not leido;
alter table public.cfx_chat enable row level security;
revoke all on public.cfx_chat from anon, authenticated;

create or replace function public.cfx_chat_mio() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare y jsonb := public.cfx_yo(); u uuid := (y ->> 'id')::uuid;
begin
  if u is null then raise exception 'Inicia sesión'; end if;
  update public.cfx_chat set leido = true where cuenta = u and de = 'soporte' and not leido;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'de', de, 'texto', texto, 'creado', creado) order by id), '[]')
          from (select * from public.cfx_chat where cuenta = u order by id desc limit 100) x);
end $$;

create or replace function public.cfx_chat_sin_leer() returns int
language sql stable security definer set search_path = '' as $$
  select count(*)::int from public.cfx_chat where cuenta = auth.uid() and de = 'soporte' and not leido
$$;

create or replace function public.cfx_chat_enviar(p_texto text) returns bigint
language plpgsql security definer set search_path = '' as $$
declare y jsonb := public.cfx_yo(); u uuid := (y ->> 'id')::uuid; t text := trim(coalesce(p_texto, '')); i bigint;
begin
  if u is null then raise exception 'Inicia sesión'; end if;
  if t = '' then raise exception 'Escribe tu mensaje'; end if;
  if length(t) > 1000 then raise exception 'Máximo 1000 letras'; end if;
  if (select count(*) from public.cfx_chat where cuenta = u and de = 'persona' and creado > now() - interval '1 hour') >= 20 then
    raise exception 'Muchos mensajes seguidos. Espera un poco y te respondemos.';
  end if;
  insert into public.cfx_chat (cuenta, email, nombre, rol, de, texto)
  values (u, coalesce(y ->> 'email', ''), left(coalesce(y ->> 'nombre', ''), 80), coalesce(y ->> 'rol', ''), 'persona', t) returning id into i;
  delete from public.cfx_chat where cuenta = u and creado < now() - interval '365 days';
  perform public.cfx_al_cm('💬 ' || coalesce(nullif(y ->> 'nombre', ''), y ->> 'email', 'Mensaje'), left(t, 200), 'chat');
  return i;
end $$;

-- Administrador: bandeja (una fila por persona), conversación y respuesta.
create or replace function public.cfx_chat_bandeja() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  return (select coalesce(jsonb_agg(x order by x.ultimo desc), '[]') from (
    select c.cuenta, max(c.email) as email, max(c.nombre) as nombre, max(c.rol) as rol, max(c.creado) as ultimo,
      (array_agg(c.texto order by c.id desc))[1] as texto, (array_agg(c.de order by c.id desc))[1] as de,
      count(*) filter (where c.de = 'persona' and not c.leido) as sin_leer
    from public.cfx_chat c group by c.cuenta order by max(c.creado) desc limit 200) x);
end $$;

create or replace function public.cfx_chat_hilo(p_cuenta uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  update public.cfx_chat set leido = true where cuenta = p_cuenta and de = 'persona' and not leido;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'de', de, 'texto', texto, 'creado', creado) order by id), '[]')
          from (select * from public.cfx_chat where cuenta = p_cuenta order by id desc limit 200) x);
end $$;

create or replace function public.cfx_chat_responder(p_cuenta uuid, p_texto text) returns bigint
language plpgsql security definer set search_path = '' as $$
declare t text := trim(coalesce(p_texto, '')); i bigint; o public.cfx_chat;
begin
  perform privado.solo_admin();
  if t = '' or length(t) > 1000 then raise exception 'Escribe la respuesta (máx. 1000 letras)'; end if;
  select * into o from public.cfx_chat where cuenta = p_cuenta order by id desc limit 1;
  if o.id is null then raise exception 'Conversación no encontrada'; end if;
  insert into public.cfx_chat (cuenta, email, nombre, rol, de, texto, leido) values (p_cuenta, o.email, o.nombre, o.rol, 'soporte', t, false) returning id into i;
  update public.cfx_chat set leido = true where cuenta = p_cuenta and de = 'persona' and not leido;
  perform public.cfx_avisar(p_cuenta, '💬 Soporte te respondió', left(t, 200));
  return i;
end $$;

-- El administrador escribe primero a una cuenta (consejos o recomendaciones): queda en su chat de soporte (🛟) y en CM → Mensajes.
create or replace function public.cfx_chat_iniciar(p_cuenta uuid, p_texto text, p_email text default '', p_nombre text default '', p_rol text default 'negocio') returns bigint
language plpgsql security definer set search_path = '' as $$
declare t text := trim(coalesce(p_texto, '')); i bigint; o public.cfx_chat;
begin
  perform privado.solo_admin();
  if t = '' or length(t) > 1000 then raise exception 'Escribe el mensaje (máx. 1000 letras)'; end if;
  select * into o from public.cfx_chat where cuenta = p_cuenta order by id desc limit 1;
  insert into public.cfx_chat (cuenta, email, nombre, rol, de, texto, leido)
  values (p_cuenta, coalesce(o.email, left(coalesce(p_email, ''), 200)), coalesce(o.nombre, left(coalesce(p_nombre, ''), 120)), coalesce(o.rol, left(coalesce(p_rol, 'negocio'), 20)), 'soporte', t, false)
  returning id into i;
  perform public.cfx_avisar(p_cuenta, '💬 Soporte te escribió', left(t, 200));
  return i;
end $$;
revoke all on function public.cfx_chat_iniciar(uuid, text, text, text, text) from public, anon;
grant execute on function public.cfx_chat_iniciar(uuid, text, text, text, text) to authenticated;

-- ---------- 3) Guía para partir ----------
-- Pendientes de configuración del negocio (los arma cada app) + verificar identidad. Solo para negocios.
create or replace function public.cfx_guia() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare y jsonb := public.cfx_yo(); l jsonb;
begin
  if y is null or (y ->> 'id') is null then raise exception 'Inicia sesión'; end if;
  if y ->> 'rol' <> 'negocio' then return jsonb_build_object('items', '[]'::jsonb, 'sin_leer', public.cfx_chat_sin_leer()); end if;
  l := coalesce(public.cfx_guia_app(), '[]'::jsonb);
  -- Sin guía propia (Centro de Mando): nada que mostrar.
  if jsonb_array_length(l) > 0 and not exists (select 1 from jsonb_array_elements(l) e where e ->> 'k' = 'verificar') then l := l || jsonb_build_array(jsonb_build_object('k', 'verificar', 't', 'Verifica tu identidad',
    'd', 'Tus clientes confían más en un negocio verificado. Toma 2 minutos.',
    'ok', exists (select 1 from public.cfx_verificaciones v where v.cuenta = (y ->> 'id')::uuid and v.estado = 'aprobada'), 'ir', 'verificar')); end if;
  return jsonb_build_object('items', l, 'sin_leer', public.cfx_chat_sin_leer());
end $$;

revoke all on function public.cfx_al_cm(text, text, text) from public, anon, authenticated;
revoke all on function public.cfx_cm_vincular(text, text, text, text), public.cfx_cm_estado(), public.cfx_chat_mio(), public.cfx_chat_sin_leer(), public.cfx_chat_enviar(text),
  public.cfx_chat_bandeja(), public.cfx_chat_hilo(uuid), public.cfx_chat_responder(uuid, text), public.cfx_guia() from public, anon;
grant execute on function public.cfx_cm_vincular(text, text, text, text), public.cfx_cm_estado(), public.cfx_chat_mio(), public.cfx_chat_sin_leer(), public.cfx_chat_enviar(text),
  public.cfx_chat_bandeja(), public.cfx_chat_hilo(uuid), public.cfx_chat_responder(uuid, text), public.cfx_guia() to authenticated;
revoke all on function public.cfx_guia_app() from public, anon, authenticated;

-- ---------- 4) G55 🐞🎁 Reporte de fallas con premio ----------
-- Cualquiera con cuenta (Más → Cuenta y ayuda → 🐞 Reportar una falla) cuenta qué pasó, con foto opcional; la app adjunta sola
-- versión, pantalla, celular y sus últimos errores. Le llega al Centro de Mando (aviso + push) y se ve en CM → Mensajes → 🐞 Fallas.
-- "🎁 Es real" suma 15 días de Premium al negocio (clientes y equipo: solo las gracias, no pagan), una vez por reporte.
create table if not exists public.cfx_fallas (
  id        bigserial primary key,
  cuenta    uuid not null,
  email     text not null default '',
  nombre    text not null default '',
  rol       text not null default '',
  texto     text not null check (length(texto) between 5 and 1500),
  foto      text check (foto is null or (foto ~ '^data:image/(webp|jpeg|png);base64,' and length(foto) <= 400000)),
  datos     jsonb not null default '{}',
  estado    text not null default 'nuevo' check (estado in ('nuevo', 'revisando', 'real', 'no')),
  respuesta text not null default '',
  dias      int not null default 0,
  creado    timestamptz not null default now(),
  resuelto  timestamptz
);
create index if not exists cfx_fallas_cuenta_idx on public.cfx_fallas (cuenta, creado);
create index if not exists cfx_fallas_estado_idx on public.cfx_fallas (estado, id);
alter table public.cfx_fallas enable row level security;
revoke all on public.cfx_fallas from anon, authenticated;

create or replace function public.cfx_falla_enviar(p_texto text, p_foto text default null, p_datos jsonb default '{}') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare y jsonb := public.cfx_yo(); u uuid := (y ->> 'id')::uuid; t text := trim(coalesce(p_texto, '')); f text := nullif(trim(coalesce(p_foto, '')), ''); d jsonb := coalesce(p_datos, '{}'); i bigint;
begin
  if u is null then raise exception 'Inicia sesión'; end if;
  if length(t) < 5 then raise exception 'Cuéntanos qué pasó (mínimo 5 letras)'; end if;
  if length(t) > 1500 then raise exception 'Máximo 1500 letras'; end if;
  if f is not null and (f !~ '^data:image/(webp|jpeg|png);base64,' or length(f) > 400000) then raise exception 'La foto no sirve: usa una captura o foto JPG/PNG'; end if;
  if jsonb_typeof(d) <> 'object' or length(d::text) > 8000 then d := '{}'; end if;
  if exists (select 1 from public.cfx_fallas where cuenta = u and creado > now() - interval '2 minutes') then raise exception 'Espera 2 minutos antes de enviar otro reporte'; end if;
  if (select count(*) from public.cfx_fallas where cuenta = u and creado > now() - interval '1 day') >= 3 then raise exception 'Ya enviaste 3 reportes hoy. Mañana puedes enviar más 🙏'; end if;
  if (select count(*) from public.cfx_fallas where estado in ('nuevo', 'revisando')) >= 500 then raise exception 'Recibimos muchos reportes. Prueba de nuevo mañana 🙏'; end if;
  delete from public.cfx_fallas where estado in ('real', 'no') and resuelto < now() - interval '180 days';
  insert into public.cfx_fallas (cuenta, email, nombre, rol, texto, foto, datos)
  values (u, coalesce(y ->> 'email', ''), left(coalesce(y ->> 'nombre', ''), 80), coalesce(y ->> 'rol', ''), t, f, d) returning id into i;
  perform public.cfx_al_cm('🐞 Falla: ' || coalesce(nullif(y ->> 'nombre', ''), y ->> 'email', 'reporte'), left(t, 200), 'falla');
  return jsonb_build_object('id', i);
end $$;

-- Mis últimos reportes (para que la persona vea en qué van).
-- premio: si a esta cuenta le tocan los 15 días (solo negocios: clientes y equipo no pagan).
create or replace function public.cfx_fallas_mias() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('premio', coalesce(public.cfx_yo() ->> 'rol', '') = 'negocio', 'lista',
    (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'texto', left(texto, 80), 'estado', estado, 'dias', dias, 'creado', creado) order by id desc), '[]')
     from (select * from public.cfx_fallas where cuenta = auth.uid() order by id desc limit 5) x))
$$;

-- Administrador: lista (sin la foto), detalle (con la foto; lo marca "revisando") y respuesta.
create or replace function public.cfx_fallas_lista(p_estado text default 'abiertos') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  return (select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'cuenta', f.cuenta, 'email', f.email, 'nombre', f.nombre, 'rol', f.rol, 'texto', f.texto,
      'con_foto', f.foto is not null, 'datos', f.datos, 'estado', f.estado, 'respuesta', f.respuesta, 'dias', f.dias, 'creado', f.creado, 'resuelto', f.resuelto,
      'premiados', (select count(*) from public.cfx_fallas g where g.cuenta = f.cuenta and g.estado = 'real')) order by f.id desc), '[]')
    from (select * from public.cfx_fallas where case coalesce(p_estado, 'abiertos') when 'abiertos' then estado in ('nuevo', 'revisando') when 'todos' then true else estado = p_estado end
          order by id desc limit 200) f);
end $$;

create or replace function public.cfx_falla_ver(p_id bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare f public.cfx_fallas;
begin
  perform privado.solo_admin();
  update public.cfx_fallas set estado = 'revisando' where id = p_id and estado = 'nuevo';
  select * into f from public.cfx_fallas where id = p_id;
  if f.id is null then raise exception 'Reporte no encontrado'; end if;
  return jsonb_build_object('id', f.id, 'estado', f.estado, 'foto', f.foto);
end $$;

create or replace function public.cfx_falla_resolver(p_id bigint, p_real boolean, p_mensaje text default '', p_dias int default 15) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare f public.cfx_fallas; m text := left(trim(coalesce(p_mensaje, '')), 500); n int := 0; h timestamptz;
begin
  perform privado.solo_admin();
  select * into f from public.cfx_fallas where id = p_id for update;
  if f.id is null then raise exception 'Reporte no encontrado'; end if;
  if f.estado in ('real', 'no') then raise exception 'Este reporte ya se respondió'; end if;
  if p_real then
    if f.rol = 'negocio' then
      n := coalesce(p_dias, 15);
      if n not between 1 and 60 then raise exception 'De 1 a 60 días'; end if;
      h := public.cfx_dar_premium(f.cuenta, f.rol, n);
      if h is null then raise exception 'No se encontró la cuenta (¿la borró?)'; end if;
      perform public.cfx_avisar(f.cuenta, '🎁 Gracias: tu reporte era real', 'Sumamos ' || n || ' días de Premium (hasta el ' || to_char(h at time zone 'America/Santiago', 'DD-MM-YYYY') || '). ' ||
        coalesce(nullif(m, ''), '¡Gracias por ayudarnos a mejorar!'));
    else
      perform public.cfx_avisar(f.cuenta, '🙌 Gracias: tu reporte era real', coalesce(nullif(m, ''), 'Ya lo estamos arreglando. ¡Gracias por ayudarnos a mejorar!'));
    end if;
  else
    perform public.cfx_avisar(f.cuenta, '🐞 Revisamos tu reporte', coalesce(nullif(m, ''),
      'Gracias por avisarnos. Lo revisamos y en ese punto la app funciona bien. Si vuelve a pasar, escríbenos al 💬 Chat con soporte.'));
  end if;
  update public.cfx_fallas set estado = case when p_real then 'real' else 'no' end, respuesta = m, dias = n, resuelto = now() where id = f.id;
  perform public.cfx_anotar('falla', case when p_real then 'real' || case when n > 0 then ' (+' || n || ' días Premium)' else '' end else 'no es falla' end || ' · #' || f.id || ' ' || f.email);
  return jsonb_build_object('estado', case when p_real then 'real' else 'no' end, 'dias', n, 'hasta', h);
end $$;
revoke all on function public.cfx_falla_enviar(text, text, jsonb), public.cfx_fallas_mias(), public.cfx_fallas_lista(text), public.cfx_falla_ver(bigint),
  public.cfx_falla_resolver(bigint, boolean, text, int) from public, anon;
grant execute on function public.cfx_falla_enviar(text, text, jsonb), public.cfx_fallas_mias(), public.cfx_fallas_lista(text), public.cfx_falla_ver(bigint),
  public.cfx_falla_resolver(bigint, boolean, text, int) to authenticated;

-- ---------- PIN de la app (4 a 6 números), guardado en la cuenta. Se pide al abrir la app y tras 5 min sin usarla. ----------
create table if not exists public.cfx_pin (
  usuario    uuid primary key references auth.users (id) on delete cascade,
  hash       text not null,
  fallos     int not null default 0,
  espera     timestamptz,
  actualizado timestamptz not null default now()
);
alter table public.cfx_pin enable row level security;
revoke all on public.cfx_pin from anon, authenticated;

create or replace function public.cfx_pin_estado() returns boolean
language sql stable security definer set search_path = '' as $$ select exists (select 1 from public.cfx_pin where usuario = auth.uid()) $$;

create or replace function public.cfx_pin_guardar(p_pin text) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Inicia sesión'; end if;
  if coalesce(p_pin, '') = '' then delete from public.cfx_pin where usuario = auth.uid(); return false; end if;
  if p_pin !~ '^[0-9]{4,6}$' then raise exception 'El PIN debe tener de 4 a 6 números'; end if;
  insert into public.cfx_pin (usuario, hash) values (auth.uid(), encode(sha256(convert_to(auth.uid()::text || ':' || p_pin, 'UTF8')), 'hex'))
  on conflict (usuario) do update set hash = excluded.hash, fallos = 0, espera = null, actualizado = now();
  return true;
end $$;

create or replace function public.cfx_pin_verificar(p_pin text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r public.cfx_pin;
begin
  select * into r from public.cfx_pin where usuario = auth.uid();
  if not found then return jsonb_build_object('ok', true); end if;
  if r.espera is not null and r.espera > now() then return jsonb_build_object('ok', false, 'espera', ceil(extract(epoch from r.espera - now()))); end if;
  if r.hash = encode(sha256(convert_to(auth.uid()::text || ':' || coalesce(p_pin, ''), 'UTF8')), 'hex') then
    update public.cfx_pin set fallos = 0, espera = null where usuario = auth.uid(); return jsonb_build_object('ok', true);
  end if;
  update public.cfx_pin set fallos = case when r.fallos + 1 >= 5 then 0 else r.fallos + 1 end,
    espera = case when r.fallos + 1 >= 5 then now() + interval '5 minutes' else null end where usuario = auth.uid();
  return jsonb_build_object('ok', false, 'quedan', greatest(0, 4 - r.fallos), 'espera', case when r.fallos + 1 >= 5 then 300 else 0 end);
end $$;
revoke all on function public.cfx_pin_estado(), public.cfx_pin_guardar(text), public.cfx_pin_verificar(text) from public, anon;
grant execute on function public.cfx_pin_estado(), public.cfx_pin_guardar(text), public.cfx_pin_verificar(text) to authenticated;
-- ---------------------------------------------------------------------
-- CodeFix · Legal (igual en las 7 apps; lo reparte nucleo/sincronizar.py).
--   Términos y Política de privacidad con versión (Ley 19.628 modificada por la Ley 21.719, vigente desde el 1-dic-2026).
--   El texto vive en nucleo/ayuda.js (CFX_LEGAL.version). Aquí solo queda la prueba de quién aceptó qué versión y cuándo.
--   cfx_legal_estado()          → última versión aceptada por la cuenta (0 = ninguna).
--   cfx_legal_aceptar(version)  → guarda la aceptación (una fila por versión, nunca se pisa).
--   cfx_legal_resumen()         → admin: cuántas cuentas aceptaron cada versión.
-- ---------------------------------------------------------------------
create table if not exists public.cfx_legal (
  cuenta    uuid not null,
  version   int  not null check (version between 1 and 10000),
  aceptado  timestamptz not null default now(),
  agente    text not null default '',
  primary key (cuenta, version)
);
alter table public.cfx_legal enable row level security;
revoke all on public.cfx_legal from anon, authenticated;

create or replace function public.cfx_legal_estado() returns int
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(max(version), 0) from public.cfx_legal where cuenta = auth.uid()
$$;

create or replace function public.cfx_legal_aceptar(p_version int) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare u uuid := auth.uid();
begin
  if u is null then raise exception 'Inicia sesión para aceptar.'; end if;
  if p_version is null or p_version < 1 or p_version > 10000 then raise exception 'Versión no válida.'; end if;
  insert into public.cfx_legal (cuenta, version, agente)
  values (u, p_version, left(coalesce(current_setting('request.headers', true)::jsonb ->> 'user-agent', ''), 300))
  on conflict (cuenta, version) do nothing;
end $$;

create or replace function public.cfx_legal_resumen() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform privado.solo_admin();
  return coalesce((select jsonb_agg(jsonb_build_object('version', version, 'cuentas', n, 'ultima', u) order by version desc)
    from (select version, count(*) n, max(aceptado) u from public.cfx_legal group by version) x), '[]'::jsonb);
end $$;

revoke all on function public.cfx_legal_estado(), public.cfx_legal_aceptar(int), public.cfx_legal_resumen() from public, anon;
grant execute on function public.cfx_legal_estado(), public.cfx_legal_aceptar(int), public.cfx_legal_resumen() to authenticated;

-- ---------------------------------------------------------------------
-- A2 · Consentimientos aparte de los términos (se dan y se retiran cuando quieras; queda el historial).
--   'ofertas'  = novedades y ofertas de CodeFix (parte en NO: solo con consentimiento expreso).
--   'negocios' = ofertas de los negocios donde eres cliente (parte en SÍ por la relación de cliente; se puede retirar).
--   cfx_consent_estado() · cfx_consent_guardar(tipo, si) · cfx_acepta(cuenta, tipo) (uso interno) · admin cfx_consent_resumen().
-- A3 · Derechos del titular (acceso, rectificación, supresión, oposición, portabilidad y bloqueo) con plazo de 30 días (+30 una vez).
--   cfx_mis_datos() → copia de todo lo de la cuenta (acceso y portabilidad al instante; queda registrado como solicitud respondida).
--   cfx_derecho_pedir(tipo, detalle) · cfx_derechos_mios() · admin cfx_derechos_lista(todas) y cfx_derecho_responder(id, accion, respuesta).
-- Brechas de seguridad (registro y aviso a la Agencia y a los afectados): admin cfx_brechas_lista(), cfx_brecha_guardar(jsonb),
--   cfx_brecha_marcar(id, 'agencia' | 'cerrar'), cfx_brecha_avisar(id, destino, titulo, cuerpo). Resumen: cfx_privacidad_resumen().
-- ---------------------------------------------------------------------
create table if not exists public.cfx_consent (
  cuenta uuid not null, tipo text not null check (tipo in ('ofertas', 'negocios')), si boolean not null,
  cambiado timestamptz not null default now(), agente text not null default '', primary key (cuenta, tipo));
create table if not exists public.cfx_consent_hist (
  id bigserial primary key, cuenta uuid not null, tipo text not null, si boolean not null, creado timestamptz not null default now(), agente text not null default '');
create table if not exists public.cfx_derechos (
  id bigserial primary key, cuenta uuid not null, email text not null default '',
  tipo text not null check (tipo in ('acceso', 'rectificacion', 'supresion', 'oposicion', 'portabilidad', 'bloqueo')),
  detalle text not null default '', estado text not null default 'pendiente' check (estado in ('pendiente', 'prorrogada', 'respondida', 'rechazada')),
  creado timestamptz not null default now(), vence timestamptz not null default now() + interval '30 days', respuesta text not null default '', respondido timestamptz);
create index if not exists cfx_derechos_cuenta on public.cfx_derechos (cuenta, creado desc);
create table if not exists public.cfx_brechas (
  id bigserial primary key, detectada timestamptz not null default now(), descripcion text not null, datos text not null default '',
  afectados int not null default 0, riesgo text not null default 'medio' check (riesgo in ('bajo', 'medio', 'alto')), medidas text not null default '',
  agencia timestamptz, titulares timestamptz, avisados int not null default 0, cerrada timestamptz, creado timestamptz not null default now());
alter table public.cfx_consent enable row level security;
alter table public.cfx_consent_hist enable row level security;
alter table public.cfx_derechos enable row level security;
alter table public.cfx_brechas enable row level security;
revoke all on public.cfx_consent, public.cfx_consent_hist, public.cfx_derechos, public.cfx_brechas from anon, authenticated;

create or replace function public.cfx_agente() returns text language sql stable set search_path = '' as $$
  select left(coalesce(current_setting('request.headers', true)::jsonb ->> 'user-agent', ''), 300) $$;
create or replace function public.cfx_acepta(p_cuenta uuid, p_tipo text) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select si from public.cfx_consent where cuenta = p_cuenta and tipo = p_tipo), p_tipo = 'negocios') $$;
create or replace function public.cfx_consent_estado() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('ofertas', public.cfx_acepta(auth.uid(), 'ofertas'), 'negocios', public.cfx_acepta(auth.uid(), 'negocios'),
    'cambiado', coalesce((select jsonb_object_agg(tipo, cambiado) from public.cfx_consent where cuenta = auth.uid()), '{}'::jsonb)) $$;
create or replace function public.cfx_consent_guardar(p_tipo text, p_si boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid := auth.uid();
begin
  if u is null then raise exception 'Inicia sesión.'; end if;
  if p_tipo not in ('ofertas', 'negocios') or p_si is null then raise exception 'Opción no válida.'; end if;
  insert into public.cfx_consent (cuenta, tipo, si, agente) values (u, p_tipo, p_si, public.cfx_agente())
  on conflict (cuenta, tipo) do update set si = excluded.si, cambiado = now(), agente = excluded.agente;
  insert into public.cfx_consent_hist (cuenta, tipo, si, agente) values (u, p_tipo, p_si, public.cfx_agente());
  return public.cfx_consent_estado();
end $$;
create or replace function public.cfx_consent_resumen() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  return coalesce((select jsonb_agg(jsonb_build_object('tipo', tipo, 'si', s, 'no', n) order by tipo)
    from (select tipo, count(*) filter (where si) s, count(*) filter (where not si) n from public.cfx_consent group by tipo) x), '[]'::jsonb);
end $$;

-- Copia de los datos de la cuenta: cada tabla con una columna de dueño (cuenta, owner_id, user_id, cliente_id…) = la cuenta.
-- No incluye claves, PIN, tokens ni llaves de API (se quitan esas columnas). Máx. 1000 filas por tabla.
create or replace function public.cfx_mis_datos() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid := auth.uid(); r record; filas jsonb; out jsonb := '{}'::jsonb; quitar text[];
begin
  if u is null then raise exception 'Inicia sesión.'; end if;
  for r in
    select c.table_schema s, c.table_name t, c.column_name col
    from information_schema.columns c join information_schema.tables tb on tb.table_schema = c.table_schema and tb.table_name = c.table_name and tb.table_type = 'BASE TABLE'
    where c.table_schema in ('public', 'privado') and c.data_type = 'uuid'
      and (c.column_name in ('cuenta', 'owner_id', 'user_id', 'usuario_id', 'cliente_id', 'target_id', 'autor_id', 'creado_por', 'created_by')
        or (c.column_name = 'id' and c.table_name in ('profiles', 'perfiles', 'usuarios', 'cuentas')))
      and c.table_name not in ('cfx_pin', 'cfx_keys', 'boleta_cuentas', 'push_subscriptions', 'app_secrets', 'cfx_verificaciones')
      and c.table_name !~ '(secret|clave|token)'
    order by 1, 2, 3
  loop
    select coalesce(array_agg(column_name::text), '{}') into quitar from information_schema.columns
      where table_schema = r.s and table_name = r.t and column_name ~* '(hash|^pin|pass|token|apikey|api_key|secret|clave|endpoint|^p256dh|^auth$)';
    execute format('select coalesce(jsonb_agg(to_jsonb(x) - $2), ''[]''::jsonb) from (select * from %I.%I where %I = $1 limit 1000) x', r.s, r.t, r.col) into filas using u, quitar;
    if jsonb_array_length(filas) > 0 then
      out := jsonb_set(out, array[r.s || '.' || r.t], coalesce(out -> (r.s || '.' || r.t), '[]'::jsonb) || filas);
    end if;
  end loop;
  insert into public.cfx_derechos (cuenta, email, tipo, detalle, estado, respuesta, respondido)
  values (u, coalesce((select email from auth.users where id = u), ''), 'portabilidad', 'Descarga desde la app', 'respondida', 'Copia entregada al instante (archivo JSON).', now());
  return jsonb_build_object('generado', now(), 'cuenta', jsonb_build_object('id', u, 'email', (select email from auth.users where id = u)),
    'consentimientos', public.cfx_consent_estado(), 'terminos_aceptados', (select coalesce(jsonb_agg(jsonb_build_object('version', version, 'aceptado', aceptado)), '[]'::jsonb) from public.cfx_legal where cuenta = u),
    'datos', out);
end $$;

create or replace function public.cfx_derecho_pedir(p_tipo text, p_detalle text default '') returns bigint
language plpgsql security definer set search_path = '' as $$
declare u uuid := auth.uid(); e text; i bigint; nom text;
begin
  if u is null then raise exception 'Inicia sesión.'; end if;
  if p_tipo not in ('acceso', 'rectificacion', 'supresion', 'oposicion', 'portabilidad', 'bloqueo') then raise exception 'Tipo de solicitud no válido.'; end if;
  if p_tipo in ('rectificacion', 'oposicion') and length(trim(coalesce(p_detalle, ''))) < 3 then raise exception 'Cuéntanos qué dato o qué uso (en pocas palabras).'; end if;
  if (select count(*) from public.cfx_derechos where cuenta = u and estado in ('pendiente', 'prorrogada')) >= 5 then raise exception 'Ya tienes 5 solicitudes en curso: espera la respuesta.'; end if;
  select email into e from auth.users where id = u;
  insert into public.cfx_derechos (cuenta, email, tipo, detalle) values (u, coalesce(e, ''), p_tipo, left(trim(coalesce(p_detalle, '')), 600)) returning id into i;
  nom := case p_tipo when 'acceso' then 'acceso' when 'rectificacion' then 'rectificación' when 'supresion' then 'supresión (borrar)' when 'oposicion' then 'oposición'
    when 'portabilidad' then 'portabilidad' else 'bloqueo' end;
  perform public.cfx_anotar('derecho', 'Solicitud de ' || nom || ' #' || i || ' de ' || coalesce(e, u::text));
  begin perform public.cfx_avisar_admin('🔒 Solicitud de datos: ' || nom, coalesce(e, '') || ' · responder antes del ' || to_char(now() + interval '30 days', 'DD-MM-YYYY')); exception when others then null; end;
  return i;
end $$;
create or replace function public.cfx_derechos_mios() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'tipo', tipo, 'detalle', detalle, 'estado', estado, 'creado', creado, 'vence', vence, 'respuesta', respuesta, 'respondido', respondido) order by creado desc), '[]'::jsonb)
  from (select * from public.cfx_derechos where cuenta = auth.uid() order by creado desc limit 50) x $$;
create or replace function public.cfx_derechos_lista(p_todas boolean default false) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'cuenta', cuenta, 'email', email, 'tipo', tipo, 'detalle', detalle, 'estado', estado, 'creado', creado, 'vence', vence,
      'dias', ceil(extract(epoch from vence - now()) / 86400)::int, 'respuesta', respuesta, 'respondido', respondido) order by (estado in ('pendiente', 'prorrogada')) desc, vence)
    from (select * from public.cfx_derechos where p_todas or estado in ('pendiente', 'prorrogada') order by creado desc limit 300) x), '[]'::jsonb);
end $$;
create or replace function public.cfx_derecho_responder(p_id bigint, p_accion text, p_respuesta text) returns void
language plpgsql security definer set search_path = '' as $$
declare d public.cfx_derechos; t text := left(trim(coalesce(p_respuesta, '')), 800);
begin
  perform privado.solo_admin();
  select * into d from public.cfx_derechos where id = p_id for update;
  if d.id is null then raise exception 'No existe esa solicitud.'; end if;
  if d.estado not in ('pendiente', 'prorrogada') then raise exception 'Esa solicitud ya se respondió.'; end if;
  if length(t) < 3 then raise exception 'Escribe la respuesta (o el motivo).'; end if;
  if p_accion = 'prorrogar' then
    if d.estado = 'prorrogada' then raise exception 'Solo se puede prorrogar una vez.'; end if;
    update public.cfx_derechos set estado = 'prorrogada', vence = vence + interval '30 days', respuesta = t where id = p_id;
    perform public.cfx_avisar(d.cuenta, '🔒 Tu solicitud de datos tomará más tiempo', left('Respondemos antes del ' || to_char(d.vence + interval '30 days', 'DD-MM-YYYY') || '. ' || t, 240));
  elsif p_accion in ('responder', 'rechazar') then
    update public.cfx_derechos set estado = case when p_accion = 'responder' then 'respondida' else 'rechazada' end, respuesta = t, respondido = now() where id = p_id;
    perform public.cfx_avisar(d.cuenta, case when p_accion = 'responder' then '🔒 Respondimos tu solicitud de datos' else '🔒 Tu solicitud de datos no se pudo acoger' end, left(t, 240));
  else raise exception 'Acción no válida.'; end if;
  perform public.cfx_anotar('derecho', p_accion || ' #' || p_id || ' (' || d.tipo || ', ' || d.email || ')');
end $$;

create or replace function public.cfx_brechas_lista() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  return coalesce((select jsonb_agg(to_jsonb(b) order by b.detectada desc) from public.cfx_brechas b), '[]'::jsonb);
end $$;
create or replace function public.cfx_brecha_guardar(p jsonb) returns bigint
language plpgsql security definer set search_path = '' as $$
declare i bigint := nullif(p ->> 'id', '')::bigint; d text := left(trim(coalesce(p ->> 'descripcion', '')), 1000);
begin
  perform privado.solo_admin();
  if length(d) < 5 then raise exception 'Describe qué pasó.'; end if;
  if coalesce(p ->> 'riesgo', 'medio') not in ('bajo', 'medio', 'alto') then raise exception 'Riesgo no válido.'; end if;
  if i is null then
    insert into public.cfx_brechas (detectada, descripcion, datos, afectados, riesgo, medidas)
    values (coalesce(nullif(p ->> 'detectada', '')::timestamptz, now()), d, left(coalesce(p ->> 'datos', ''), 500), greatest(coalesce(nullif(p ->> 'afectados', '')::int, 0), 0),
      coalesce(p ->> 'riesgo', 'medio'), left(coalesce(p ->> 'medidas', ''), 1000)) returning id into i;
    perform public.cfx_anotar('brecha', 'Nueva #' || i || ' (' || coalesce(p ->> 'riesgo', 'medio') || '): ' || d);
  else
    update public.cfx_brechas set descripcion = d, datos = left(coalesce(p ->> 'datos', ''), 500), afectados = greatest(coalesce(nullif(p ->> 'afectados', '')::int, 0), 0),
      riesgo = coalesce(p ->> 'riesgo', 'medio'), medidas = left(coalesce(p ->> 'medidas', ''), 1000) where id = i;
    if not found then raise exception 'No existe ese registro.'; end if;
    perform public.cfx_anotar('brecha', 'Editada #' || i);
  end if;
  return i;
end $$;
create or replace function public.cfx_brecha_marcar(p_id bigint, p_que text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  if p_que = 'agencia' then update public.cfx_brechas set agencia = coalesce(agencia, now()) where id = p_id;
  elsif p_que = 'cerrar' then update public.cfx_brechas set cerrada = coalesce(cerrada, now()) where id = p_id;
  else raise exception 'Acción no válida.'; end if;
  if not found then raise exception 'No existe ese registro.'; end if;
  perform public.cfx_anotar('brecha', p_que || ' #' || p_id);
end $$;
create or replace function public.cfx_brecha_avisar(p_id bigint, p_destino text, p_titulo text, p_cuerpo text) returns int
language plpgsql security definer set search_path = '' as $$
declare u uuid; n int := 0;
begin
  perform privado.solo_admin();
  if not exists (select 1 from public.cfx_brechas where id = p_id) then raise exception 'No existe ese registro.'; end if;
  if trim(coalesce(p_titulo, '')) = '' or trim(coalesce(p_cuerpo, '')) = '' then raise exception 'Escribe el título y el mensaje.'; end if;
  if p_destino not in ('todos', 'negocios', 'clientes', 'premium', 'gratis') then raise exception 'Destino no válido'; end if;
  for u in select * from public.cfx_destinatarios(p_destino) loop
    perform public.cfx_avisar(u, left(p_titulo, 80), left(p_cuerpo, 240)); n := n + 1;
  end loop;
  update public.cfx_brechas set titulares = now(), avisados = avisados + n where id = p_id;
  perform public.cfx_anotar('brecha', 'Aviso a ' || p_destino || ' (' || n || ') #' || p_id);
  return n;
end $$;
create or replace function public.cfx_privacidad_resumen() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  return jsonb_build_object('pendientes', (select count(*) from public.cfx_derechos where estado in ('pendiente', 'prorrogada')),
    'vencen', (select count(*) from public.cfx_derechos where estado in ('pendiente', 'prorrogada') and vence < now() + interval '5 days'),
    'brechas', (select count(*) from public.cfx_brechas where cerrada is null), 'consent', public.cfx_consent_resumen(), 'legal', public.cfx_legal_resumen());
end $$;

revoke all on function public.cfx_agente(), public.cfx_acepta(uuid, text) from public, anon, authenticated;
revoke all on function public.cfx_consent_estado(), public.cfx_consent_guardar(text, boolean), public.cfx_consent_resumen(), public.cfx_mis_datos(),
  public.cfx_derecho_pedir(text, text), public.cfx_derechos_mios(), public.cfx_derechos_lista(boolean), public.cfx_derecho_responder(bigint, text, text),
  public.cfx_brechas_lista(), public.cfx_brecha_guardar(jsonb), public.cfx_brecha_marcar(bigint, text), public.cfx_brecha_avisar(bigint, text, text, text), public.cfx_privacidad_resumen() from public, anon;
grant execute on function public.cfx_consent_estado(), public.cfx_consent_guardar(text, boolean), public.cfx_consent_resumen(), public.cfx_mis_datos(),
  public.cfx_derecho_pedir(text, text), public.cfx_derechos_mios(), public.cfx_derechos_lista(boolean), public.cfx_derecho_responder(bigint, text, text),
  public.cfx_brechas_lista(), public.cfx_brecha_guardar(jsonb), public.cfx_brecha_marcar(bigint, text), public.cfx_brecha_avisar(bigint, text, text, text), public.cfx_privacidad_resumen() to authenticated;
-- ---------------------------------------------------------------------
-- CodeFix · Referidos (igual en las 7 apps; lo reparte nucleo/sincronizar.py). Se administra desde CM → Control → Referidos.
--   Cada usuario (negocio o cliente, nunca el admin) tiene su código. Quien se registra con él queda asociado a esa cuenta.
--   El admin ve quién invitó a quién, da días de Premium o manda un sticker de ánimo. Premio automático (opcional):
--   cuando el invitado paga su primer Premium, quien lo invitó recibe N días (cfx_config 'referidos' → dias_auto; 0 = apagado).
--   Usa lo que cada app define para los pagos: cfx_yo(), cfx_dar_premium(uuid, text, int) y cfx_avisar(uuid, text, text).
-- ---------------------------------------------------------------------
create table if not exists public.cfx_ref_codigos (cuenta uuid primary key, codigo text not null unique check (codigo ~ '^[A-Z0-9]{4,12}$'), creado timestamptz not null default now());
create table if not exists public.cfx_referidos (
  invitado uuid primary key, invito uuid not null, codigo text not null, email text not null default '', nombre text not null default '',
  creado timestamptz not null default now(), premiado boolean not null default false, dias_dados int not null default 0, stickers int not null default 0);
create index if not exists cfx_referidos_invito_idx on public.cfx_referidos (invito);
alter table public.cfx_ref_codigos enable row level security;
alter table public.cfx_referidos enable row level security;
revoke all on public.cfx_ref_codigos, public.cfx_referidos from anon, authenticated;
insert into public.cfx_config (clave, valor) values ('referidos', '{"dias_auto": 0}') on conflict (clave) do nothing;

-- Mi código para invitar (y cuántos se registraron con él). El admin no tiene.
create or replace function public.cfx_ref_mio() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare y jsonb := public.cfx_yo(); c text; i int := 0;
begin
  if y is null or y ->> 'rol' = 'admin' then return null; end if;
  select codigo into c from public.cfx_ref_codigos where cuenta = (y ->> 'id')::uuid;
  while c is null and i < 20 loop
    c := upper(left(regexp_replace(translate(coalesce(nullif(y ->> 'nombre', ''), split_part(y ->> 'email', '@', 1)), 'áéíóúñÁÉÍÓÚÑ', 'aeiounAEIOUN'), '[^A-Za-z]', '', 'g'), 6));
    c := (case when length(c) < 2 then 'CF' else c end) || lpad((floor(random() * 10000))::int::text, 4, '0'); i := i + 1;
    begin insert into public.cfx_ref_codigos (cuenta, codigo) values ((y ->> 'id')::uuid, c); exception when unique_violation then c := null; end;
  end loop;
  return jsonb_build_object('codigo', c, 'invitados', (select count(*) from public.cfx_referidos where invito = (y ->> 'id')::uuid),
    'pagaron', (select count(*) from public.cfx_referidos r where r.invito = (y ->> 'id')::uuid and r.premiado));
end $$;
-- La cuenta nueva que llegó con un código queda asociada (una sola vez, solo en sus primeros 3 días, nunca consigo misma).
create or replace function public.cfx_ref_registrar(p_codigo text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare y jsonb := public.cfx_yo(); o uuid; quien text;
begin
  if y is null or y ->> 'rol' = 'admin' then return false; end if;
  if (select created_at from auth.users where id = (y ->> 'id')::uuid) < now() - interval '3 days' then return false; end if;
  select cuenta into o from public.cfx_ref_codigos where codigo = upper(trim(p_codigo));
  if o is null or o = (y ->> 'id')::uuid then return false; end if;
  insert into public.cfx_referidos (invitado, invito, codigo, email, nombre) values ((y ->> 'id')::uuid, o, upper(trim(p_codigo)), coalesce(y ->> 'email', ''), coalesce(y ->> 'nombre', ''))
    on conflict (invitado) do nothing;
  if not found then return false; end if;
  quien := coalesce(nullif(y ->> 'nombre', ''), split_part(y ->> 'email', '@', 1));
  perform public.cfx_avisar(o, '🎉 ' || quien || ' se registró con tu código', 'Gracias por recomendarnos. ¡Sigue invitando!');
  return true;
end $$;
-- Panel: quién invitó a quién (con correo de ambos), si el invitado ya pagó y lo que se le ha dado a quien invitó.
create or replace function public.cfx_ref_lista() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  return jsonb_build_object('config', (select valor from public.cfx_config where clave = 'referidos'), 'filas', coalesce((select jsonb_agg(x order by x.creado desc) from (
    select r.invitado, r.email, r.nombre, r.creado, r.codigo, r.invito, u.email invito_email, r.premiado, r.dias_dados, r.stickers,
      exists (select 1 from public.cfx_pagos g where g.cuenta = r.invitado and g.estado = 'aprobado') pago
    from public.cfx_referidos r left join auth.users u on u.id = r.invito limit 1000) x), '[]'));
end $$;
-- Dar días de Premium y/o mandar un sticker (mensaje de ánimo) a quien invita.
create or replace function public.cfx_ref_premiar(p_cuenta uuid, p_dias int default 0, p_mensaje text default '') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare hasta timestamptz; d int := greatest(0, least(coalesce(p_dias, 0), 365)); n int;
begin
  perform privado.solo_admin();
  select count(*) into n from public.cfx_referidos where invito = p_cuenta;
  if n = 0 then raise exception 'Esa cuenta no ha invitado a nadie'; end if;
  if d > 0 then
    hasta := public.cfx_dar_premium(p_cuenta, 'otro', d);
    update public.cfx_referidos set dias_dados = dias_dados + d where invitado = (select invitado from public.cfx_referidos where invito = p_cuenta order by creado desc limit 1);
  end if;
  if coalesce(trim(p_mensaje), '') <> '' or d > 0 then
    perform public.cfx_avisar(p_cuenta, left(coalesce(nullif(trim(p_mensaje), ''), '🏆 ¡Gracias por invitar!'), 90),
      case when d > 0 then '🎁 Te regalamos ' || d || ' días de Premium por recomendarnos (' || n || ' invitado' || case when n > 1 then 's' else '' end || ').' else 'Vas en ' || n || ' invitado' || case when n > 1 then 's' else '' end || '. ¡Sigue así!' end);
    update public.cfx_referidos set stickers = stickers + 1 where invitado = (select invitado from public.cfx_referidos where invito = p_cuenta order by creado desc limit 1);
  end if;
  perform public.cfx_anotar('referido', 'premio a ' || coalesce((select email from auth.users where id = p_cuenta), p_cuenta::text) || ': ' || d || ' días');
  return jsonb_build_object('dias', d, 'hasta', hasta);
end $$;
create or replace function public.cfx_ref_config_guardar(p_dias_auto int) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  insert into public.cfx_config (clave, valor) values ('referidos', jsonb_build_object('dias_auto', greatest(0, least(coalesce(p_dias_auto, 0), 365))))
    on conflict (clave) do update set valor = excluded.valor;
  return (select valor from public.cfx_config where clave = 'referidos');
end $$;
-- Premio automático: al aprobarse el primer pago del invitado, quien lo invitó recibe dias_auto días (una sola vez por invitado).
create or replace function public.cfx_ref_al_pagar() returns trigger
language plpgsql security definer set search_path = '' as $$
declare r public.cfx_referidos; d int := coalesce(((select valor from public.cfx_config where clave = 'referidos') ->> 'dias_auto')::int, 0);
begin
  if new.estado <> 'aprobado' or old.estado = 'aprobado' then return new; end if;
  select * into r from public.cfx_referidos where invitado = new.cuenta and not premiado for update;
  if r.invitado is null then return new; end if;
  update public.cfx_referidos set premiado = true, dias_dados = dias_dados + case when d > 0 then d else 0 end where invitado = r.invitado;
  if d > 0 then
    perform public.cfx_dar_premium(r.invito, 'otro', d);
    perform public.cfx_avisar(r.invito, '🎁 ¡Ganaste ' || d || ' días de Premium!', coalesce(nullif(r.nombre, ''), split_part(r.email, '@', 1)) || ' pagó su Premium gracias a tu invitación.');
  end if;
  return new;
end $$;
drop trigger if exists cfx_ref_al_pagar on public.cfx_pagos;
create trigger cfx_ref_al_pagar after update of estado on public.cfx_pagos for each row execute function public.cfx_ref_al_pagar();
revoke all on function public.cfx_ref_al_pagar() from public, anon, authenticated;
revoke all on function public.cfx_ref_mio(), public.cfx_ref_registrar(text), public.cfx_ref_lista(), public.cfx_ref_premiar(uuid, int, text), public.cfx_ref_config_guardar(int) from public, anon;
grant execute on function public.cfx_ref_mio(), public.cfx_ref_registrar(text), public.cfx_ref_lista(), public.cfx_ref_premiar(uuid, int, text), public.cfx_ref_config_guardar(int) to authenticated;

-- ---------------------------------------------------------------------
-- CodeFix · Socios comunes (lo reparte nucleo/sincronizar.py). Los usan Billetera, Órbita y Estaciona (las otras apps tienen
-- sus propios socios). El socio entra con su correo y administra igual que el admin (cada app lo reconoce en su función de
-- administrador), pero solo el administrador dueño agrega o quita socios (CM → Control → 🤝 Socios). Lo que hace queda en el registro.
-- ---------------------------------------------------------------------
create table if not exists public.cfx_socios (email text primary key check (email = lower(email) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  nombre text not null default '' check (length(nombre) <= 60), creado timestamptz not null default now());
alter table public.cfx_socios enable row level security;
revoke all on public.cfx_socios from anon, authenticated;
create or replace function public.cfx_es_socio() returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (select 1 from public.cfx_socios s join auth.users u on lower(u.email) = s.email where u.id = auth.uid())
$$;
create or replace function public.cfx_socios_lista() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  return coalesce((select jsonb_agg(jsonb_build_object('email', s.email, 'nombre', s.nombre, 'creado', s.creado, 'tiene_cuenta', exists (select 1 from auth.users u where lower(u.email) = s.email)) order by s.creado) from public.cfx_socios s), '[]');
end $$;
create or replace function public.cfx_socio_guardar(p_email text, p_nombre text default '', p_si boolean default true) returns void
language plpgsql security definer set search_path = '' as $$
declare e text := lower(trim(p_email));
begin
  perform privado.solo_admin();
  if public.cfx_es_socio() then raise exception 'Solo el administrador agrega o quita socios'; end if;
  if coalesce(p_si, true) then
    insert into public.cfx_socios (email, nombre) values (e, left(coalesce(trim(p_nombre), ''), 60)) on conflict (email) do update set nombre = excluded.nombre;
    perform public.cfx_anotar('socio', 'agregó a ' || e);
  else
    delete from public.cfx_socios where email = e;
    perform public.cfx_anotar('socio', 'quitó a ' || e);
  end if;
end $$;
revoke all on function public.cfx_es_socio(), public.cfx_socios_lista(), public.cfx_socio_guardar(text, text, boolean) from public, anon;
grant execute on function public.cfx_es_socio(), public.cfx_socios_lista(), public.cfx_socio_guardar(text, text, boolean) to authenticated;

-- ---------------------------------------------------------------------
-- CodeFix · Inventario (igual en las 6 apps; lo usa el Centro de Mando → Apps → Respaldo y limpieza).
--   Muestra las tablas que esta versión ya NO usa (restos de versiones antiguas) con cuántas filas tienen.
--   Nada se borra solo: las vacías se borran con un toque; las que tienen datos piden descargar el respaldo y escribir "sí".
--   cfx_tablas() = las tablas que crea este archivo (la revisa pruebas/inventario.py --verificar).
-- ---------------------------------------------------------------------
create or replace function public.cfx_tablas() returns text[] language sql immutable as $$ select array['privado.archivos_por_borrar', 'privado.config', 'privado.fotos_pendientes', 'privado.limites', 'privado.pruebas_usadas', 'privado.secretos', 'privado.tareas_hechas', 'public.acuerdos', 'public.ajustes', 'public.auditoria', 'public.caja', 'public.categorias', 'public.cfx_analisis', 'public.cfx_anuncio_vistos', 'public.cfx_anuncios', 'public.cfx_bloqueos', 'public.cfx_boleta_cuentas', 'public.cfx_boletas', 'public.cfx_brechas', 'public.cfx_calificaciones', 'public.cfx_cargas', 'public.cfx_carritos', 'public.cfx_chat', 'public.cfx_clave_temporal', 'public.cfx_config', 'public.cfx_consent', 'public.cfx_consent_hist', 'public.cfx_cupones', 'public.cfx_derechos', 'public.cfx_descuentos', 'public.cfx_errores', 'public.cfx_estudio', 'public.cfx_exentos', 'public.cfx_fallas', 'public.cfx_flow_negocio', 'public.cfx_hilos', 'public.cfx_keys', 'public.cfx_legal', 'public.cfx_login_fallos', 'public.cfx_login_qr', 'public.cfx_mensajes', 'public.cfx_modulos_negocio', 'public.cfx_modulos_pruebas', 'public.cfx_mp_avisos', 'public.cfx_mp_neg_cobros', 'public.cfx_mp_neg_sub_pagos', 'public.cfx_mp_neg_subs', 'public.cfx_mp_negocio', 'public.cfx_mp_sub_cobros', 'public.cfx_mp_subs', 'public.cfx_pagos', 'public.cfx_pin', 'public.cfx_pruebas_usadas', 'public.cfx_push_entrega', 'public.cfx_ref_codigos', 'public.cfx_referidos', 'public.cfx_registro', 'public.cfx_reportes', 'public.cfx_salud', 'public.cfx_secretos', 'public.cfx_sellos', 'public.cfx_sellos_cfg', 'public.cfx_socios', 'public.cfx_verificaciones', 'public.cfx_versiones', 'public.cierres_caja', 'public.clientes', 'public.cola_push', 'public.comprobantes', 'public.conexion_movs', 'public.conexiones', 'public.cuentas_pagar', 'public.cuotas', 'public.cupones', 'public.feriados', 'public.gastos_fijos', 'public.invitaciones', 'public.keys', 'public.miembros', 'public.movimientos', 'public.negocios', 'public.notificaciones', 'public.perfiles', 'public.productos', 'public.push_subs', 'public.recordatorios', 'public.sesiones_cliente', 'public.solicitudes_pago', 'public.soporte', 'public.uso_mensual', 'public.ventas_cuotas'] $$;
create or replace function public.cfx_inventario() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r record; n bigint; out jsonb := '[]'::jsonb;
begin
  perform privado.solo_admin();
  for r in select s.nspname || '.' || c.relname as t, pg_total_relation_size(c.oid) as b from pg_class c join pg_namespace s on s.oid = c.relnamespace
           where s.nspname in ('public', 'privado') and c.relkind in ('r', 'p') and not (s.nspname || '.' || c.relname = any (public.cfx_tablas()))
           and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e') order by 1
  loop
    execute 'select count(*) from ' || r.t into n;
    out := out || jsonb_build_object('tabla', r.t, 'filas', n, 'bytes', r.b);
  end loop;
  return out;
end $$;
create or replace function public.cfx_inventario_datos(p_tabla text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare j jsonb;
begin
  perform privado.solo_admin();
  if not exists (select 1 from jsonb_array_elements(public.cfx_inventario()) x where x ->> 'tabla' = p_tabla) then raise exception 'Esa tabla no está en la lista de sobrantes'; end if;
  execute 'select coalesce(jsonb_agg(to_jsonb(t)), ''[]'') from (select * from ' || p_tabla || ' limit 20000) t' into j;
  return j;
end $$;
create or replace function public.cfx_inventario_borrar(p_tabla text, p_confirmacion text default '') returns text
language plpgsql security definer set search_path = '' as $$
declare x jsonb;
begin
  perform privado.solo_admin();
  select e into x from jsonb_array_elements(public.cfx_inventario()) e where e ->> 'tabla' = p_tabla;
  if x is null then raise exception 'Esa tabla no está en la lista de sobrantes'; end if;
  if (x ->> 'filas')::bigint > 0 and lower(trim(coalesce(p_confirmacion, ''))) not in ('sí', 'si') then
    raise exception 'La tabla tiene % filas: descarga el respaldo y escribe "sí" para borrarla', x ->> 'filas';
  end if;
  execute 'drop table ' || p_tabla || ' cascade';
  return p_tabla || ' borrada';
end $$;
revoke all on function public.cfx_tablas(), public.cfx_inventario(), public.cfx_inventario_datos(text), public.cfx_inventario_borrar(text, text) from public, anon;
grant execute on function public.cfx_inventario(), public.cfx_inventario_datos(text), public.cfx_inventario_borrar(text, text) to authenticated;

-- ---------- Salud (G8): errores de la app en los teléfonos, ping anti-pausa y último respaldo ----------
-- Errores: carga.js manda cada error de JavaScript (agrupado por mensaje + lugar). Se guardan hasta 300 distintos y 30 días.
create table if not exists public.cfx_errores (
  id bigint generated always as identity primary key, firma text not null unique, mensaje text not null, donde text not null default '',
  pagina text not null default '', navegador text not null default '', version text not null default '', veces int not null default 1,
  con_cuenta boolean not null default false, creado timestamptz not null default now(), ultimo timestamptz not null default now());
-- Salud: 'ping' (lo toca GitHub Actions para que Supabase no pause la base) y 'respaldo' (lo anota el respaldo diario).
create table if not exists public.cfx_salud (clave text primary key, valor jsonb not null default '{}', cuando timestamptz not null default now());
-- B13 Carga real: cuánto demora en abrir cada página en los teléfonos (carga.js, 1 vez por página y sesión). Por día y página; 30 días.
create table if not exists public.cfx_cargas (dia date not null default current_date, pagina text not null, veces int not null default 0, ms bigint not null default 0,
  lcp bigint not null default 0, con_lcp int not null default 0, lentas int not null default 0, cache int not null default 0, primary key (dia, pagina));
alter table public.cfx_cargas enable row level security;
revoke all on public.cfx_cargas from anon, authenticated;
alter table public.cfx_errores enable row level security;
alter table public.cfx_salud enable row level security;
revoke all on public.cfx_errores, public.cfx_salud from anon, authenticated;

-- Sin cuenta también (el error puede pasar antes de entrar). Sin captcha: no crea cuentas ni avisa a nadie,
-- se agrupa por firma, tiene tope de filas y de veces, y se borra solo a los 30 días.
create or replace function public.cfx_error_anotar(p_mensaje text, p_donde text default '', p_pagina text default '', p_navegador text default '', p_version text default '')
returns void language plpgsql security definer set search_path = '' as $$
declare m text := left(coalesce(p_mensaje, ''), 300); d text := left(coalesce(p_donde, ''), 600); f text;
begin
  if m = '' then return; end if;
  f := md5(m || '|' || split_part(d, E'\n', 1));
  update public.cfx_errores set veces = least(veces + 1, 1000000), ultimo = now(), pagina = left(coalesce(p_pagina, ''), 200),
    navegador = left(coalesce(p_navegador, ''), 120), version = left(coalesce(p_version, ''), 20), con_cuenta = con_cuenta or auth.uid() is not null
    where firma = f and ultimo < now() - interval '2 seconds';
  if found or exists (select 1 from public.cfx_errores where firma = f) then return; end if;
  delete from public.cfx_errores where ultimo < now() - interval '30 days';
  if (select count(*) from public.cfx_errores) >= 300 then return; end if;
  insert into public.cfx_errores (firma, mensaje, donde, pagina, navegador, version, con_cuenta)
    values (f, m, d, left(coalesce(p_pagina, ''), 200), left(coalesce(p_navegador, ''), 120), left(coalesce(p_version, ''), 20), auth.uid() is not null)
    on conflict (firma) do nothing;
end $$;
grant execute on function public.cfx_error_anotar(text, text, text, text, text) to anon, authenticated;

-- B13: sin cuenta también (la vitrina la abren clientes sin cuenta). Valores acotados, máximo 40 páginas por día y 1 fila por día y página.
create or replace function public.cfx_carga_anotar(p_pagina text, p_ms int, p_lcp int default null, p_cache boolean default false)
returns void language plpgsql security definer set search_path = '' as $$
declare pg text := left(regexp_replace(lower(coalesce(p_pagina, '')), '[^a-z0-9/_.-]', '', 'g'), 60); m int := least(greatest(coalesce(p_ms, 0), 0), 60000);
  l int := least(greatest(coalesce(p_lcp, 0), 0), 60000);
begin
  if pg = '' or m = 0 then return; end if;
  if not exists (select 1 from public.cfx_cargas where dia = current_date and pagina = pg) then
    if (select count(*) from public.cfx_cargas where dia = current_date) >= 40 then return; end if;
    delete from public.cfx_cargas where dia < current_date - 30;
  end if;
  insert into public.cfx_cargas as c (dia, pagina, veces, ms, lcp, con_lcp, lentas, cache)
    values (current_date, pg, 1, m, l, (l > 0)::int, (m > 3000)::int, coalesce(p_cache, false)::int)
    on conflict (dia, pagina) do update set veces = c.veces + 1, ms = c.ms + excluded.ms, lcp = c.lcp + excluded.lcp, con_lcp = c.con_lcp + excluded.con_lcp,
      lentas = c.lentas + excluded.lentas, cache = c.cache + excluded.cache
    where c.veces < 100000;
end $$;
revoke all on function public.cfx_carga_anotar(text, int, int, boolean) from public;
grant execute on function public.cfx_carga_anotar(text, int, int, boolean) to anon, authenticated;

-- Marca de salud (solo la base: GitHub Actions la llama con la conexión del respaldo; ping la usa por dentro).
create or replace function public.cfx_salud_marca(p_clave text, p_valor jsonb default '{}') returns void
language sql security definer set search_path = '' as $$
  insert into public.cfx_salud (clave, valor, cuando) values (left(p_clave, 40), coalesce(p_valor, '{}'), now())
  on conflict (clave) do update set valor = excluded.valor, cuando = now()
$$;
revoke all on function public.cfx_salud_marca(text, jsonb) from public, anon, authenticated;

-- Ping anti-pausa: el plan gratis de Supabase pausa la base tras 7 días sin uso. GitHub Actions (SaaS: salud.yml) lo llama cada día.
create or replace function public.cfx_ping() returns text
language plpgsql security definer set search_path = '' as $$
begin
  if coalesce((select cuando from public.cfx_salud where clave = 'ping'), '-infinity') < now() - interval '10 minutes' then
    perform public.cfx_salud_marca('ping', '{}');
  end if;
  return 'ok';
end $$;
grant execute on function public.cfx_ping() to anon, authenticated;

-- Centro de Mando → Control → 🩺 Salud.
create or replace function public.cfx_salud() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  return jsonb_build_object(
    'ping', (select cuando from public.cfx_salud where clave = 'ping'),
    'respaldo', (select valor || jsonb_build_object('cuando', cuando) from public.cfx_salud where clave = 'respaldo'),
    'analisis', (select valor || jsonb_build_object('cuando', cuando) from public.cfx_salud where clave = 'analisis'),
    'carga', coalesce((select jsonb_agg(c order by c.veces desc) from (select pagina, sum(veces)::int veces, (sum(ms) / nullif(sum(veces), 0))::int ms,
        (sum(lcp) / nullif(sum(con_lcp), 0))::int lcp, sum(lentas)::int lentas, sum(cache)::int cache
      from public.cfx_cargas where dia > current_date - 7 group by pagina order by sum(veces) desc limit 20) c), '[]'),
    'errores_24h', (select coalesce(sum(veces), 0) from public.cfx_errores where ultimo > now() - interval '24 hours'),
    'errores', coalesce((select jsonb_agg(to_jsonb(e) - 'firma' order by e.ultimo desc) from (select * from public.cfx_errores order by ultimo desc limit 100) e), '[]'));
end $$;
revoke all on function public.cfx_salud() from public, anon;
grant execute on function public.cfx_salud() to authenticated;

create or replace function public.cfx_errores_borrar(p_id bigint default null) returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  perform privado.solo_admin();
  delete from public.cfx_errores where p_id is null or id = p_id;
  get diagnostics n = row_count;
  perform public.cfx_anotar('errores borrados', case when p_id is null then 'todos (' || n || ')' else '#' || p_id end);
  return n;
end $$;
revoke all on function public.cfx_errores_borrar(bigint) from public, anon;
grant execute on function public.cfx_errores_borrar(bigint) to authenticated;

-- ---------- G38 · 🔔 Alertas al celular del admin (vía Centro de Mando): negocio nuevo y errores nuevos ----------
-- Cada 15 minutos mira lo nuevo desde la última vez (la primera vez solo marca, no avisa de lo viejo). Un aviso por tipo y vuelta.
-- Los pagos ya avisan solos (💳 por revisar / ⚡ aprobado). La caída de una app la ve 🩺 salud diaria (GitHub) y el carrusel de servidores.
create or replace function public.cfx_alertas_revisar() returns int
language plpgsql security definer set search_path = '' as $$
declare v jsonb := (select valor from public.cfx_salud where clave = 'alertas'); h timestamptz := now(); desde timestamptz; cu jsonb := '[]';
        n int := 0; k int; t text;
begin
  if v is null or (v ->> 'desde') is null then perform public.cfx_salud_marca('alertas', jsonb_build_object('desde', h)); return 0; end if;
  desde := (v ->> 'desde')::timestamptz;
  if to_regprocedure('public.cfx_cuentas_app(text,text)') is not null then
    begin execute 'select coalesce(public.cfx_cuentas_app(''negocio'', ''''), ''[]''::jsonb)' into cu; exception when others then cu := '[]'; end;
    select count(*), min(coalesce(nullif(e ->> 'nombre', ''), e ->> 'email')) into k, t from jsonb_array_elements(cu) e
      where (e ->> 'creado')::timestamptz > desde and (e ->> 'creado')::timestamptz <= h;
    if k > 0 then perform public.cfx_al_cm('🆕 Negocio nuevo', coalesce(t, '') || case when k > 1 then ' y ' || (k - 1) || ' más' else '' end, 'negocio'); n := n + 1; end if;
  end if;
  select count(*), min(left(mensaje, 120)) into k, t from public.cfx_errores where creado > desde and creado <= h;
  if k > 0 then perform public.cfx_al_cm('🩺 ' || k || case when k = 1 then ' error nuevo' else ' errores nuevos' end, coalesce(t, ''), 'error'); n := n + 1; end if;
  perform public.cfx_salud_marca('alertas', jsonb_build_object('desde', h));
  return n;
end $$;
revoke all on function public.cfx_alertas_revisar() from public, anon, authenticated;
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'cfx-alertas';
  perform cron.schedule('cfx-alertas', '*/15 * * * *', 'select public.cfx_alertas_revisar()');
exception when others then
  raise notice 'Alertas no programadas (%).', sqlerrm;
end $$;
-- ---------- Módulos enchufables (C19): se prenden y apagan desde el Centro de Mando → Mis aplicaciones → 🧩 Módulos ----------
-- Cada app dice qué módulos tiene con el gancho cfx_modulos_app() → text[] (si no lo tiene: ninguno). Por defecto quedan prendidos.
insert into public.cfx_config (clave, valor) values ('modulos', '{}') on conflict (clave) do nothing;

create or replace function public.cfx_modulos_de_app() returns text[]
language plpgsql stable security definer set search_path = '' as $$
declare r text[];
begin
  if to_regprocedure('public.cfx_modulos_app()') is null then return '{}'; end if;
  execute 'select public.cfx_modulos_app()' into r;
  return coalesce(r, '{}');
end $$;

create or replace function public.cfx_modulo(p_clave text) returns boolean
language plpgsql stable security definer set search_path = '' as $$
begin
  return p_clave = any(public.cfx_modulos_de_app())
    and coalesce(((select valor from public.cfx_config where clave = 'modulos') ->> p_clave)::boolean, true);
end $$;

-- Para la app (esconde lo apagado): {"chat": true, ...}. Un negocio (o su equipo) ve lo que tiene activo (G19: módulos de pago).
create or replace function public.cfx_modulos() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare n uuid := public.cfx_negocio_cuenta(auth.uid());
begin
  if n is not null and coalesce((public.cfx_venta() ->> 'activo')::boolean, false) then return public.cfx_modulos_de(n); end if;
  return coalesce((select jsonb_object_agg(k, public.cfx_modulo(k)) from unnest(public.cfx_modulos_de_app()) k), '{}');
end $$;

-- Para el Centro de Mando: con nombre y para qué sirve.
create or replace function public.cfx_modulos_admin() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  return coalesce((select jsonb_agg(jsonb_build_object('clave', k, 'nombre', coalesce(c.nombre, k), 'detalle', coalesce(c.detalle, ''),
      'activo', public.cfx_modulo(k), 'precio', public.cfx_venta_precio(k),
      'negocios', (select count(*) from public.cfx_modulos_negocio m where m.modulo = k and m.hasta > now())) order by o)
    from unnest(public.cfx_modulos_de_app()) with ordinality u(k, o)
    left join public.cfx_modulos_catalogo() c on c.clave = k), '[]');
end $$;

create or replace function public.cfx_modulo_guardar(p_clave text, p_activo boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  if not coalesce(p_clave = any(public.cfx_modulos_de_app()), false) then raise exception 'Esta app no tiene ese módulo'; end if;
  insert into public.cfx_config (clave, valor) values ('modulos', jsonb_build_object(p_clave, coalesce(p_activo, true)))
  on conflict (clave) do update set valor = public.cfx_config.valor || excluded.valor;
  perform public.cfx_anotar('módulo', p_clave || case when coalesce(p_activo, true) then ' prendido' else ' apagado' end);
  return public.cfx_modulos_admin();
end $$;

revoke all on function public.cfx_modulos_de_app(), public.cfx_modulo(text) from public, anon, authenticated;
revoke all on function public.cfx_modulos(), public.cfx_modulos_admin(), public.cfx_modulo_guardar(text, boolean) from public, anon;
grant execute on function public.cfx_modulos() to anon, authenticated;
grant execute on function public.cfx_modulos_admin(), public.cfx_modulo_guardar(text, boolean) to authenticated;
-- ---------- Módulos de pago por negocio (G19) ----------
-- Cada negocio compra (o prueba 7 días) los módulos que quiere, sea Free o Premium. Se venden sueltos o en packs
-- (Básico, Crecer, Completo). Si "Vender módulos" está apagado en esta app (Centro de Mando → Apps → 🧩), todo sigue como antes:
-- el módulo prendido sirve a todos. Precio 0 = incluido gratis para todos.
-- Gancho opcional de la app: cfx_negocio_cuenta(uuid) → el negocio de esa cuenta (dueño o su equipo); null = no es negocio.
--                            cfx_es_premium(uuid) → si el negocio tiene Premium (descuento en módulos).
create table if not exists public.cfx_modulos_negocio (
  negocio uuid not null,
  modulo  text not null check (modulo ~ '^[a-z_]{2,30}$'),
  hasta   timestamptz not null,
  origen  text not null default 'pago' check (origen in ('prueba', 'pago', 'regalo')),
  avisado timestamptz,
  creado  timestamptz not null default now(),
  primary key (negocio, modulo)
);
create index if not exists cfx_modulos_negocio_hasta_idx on public.cfx_modulos_negocio (hasta);
create table if not exists public.cfx_modulos_pruebas (
  negocio uuid not null,
  item    text not null,
  creado  timestamptz not null default now(),
  primary key (negocio, item)
);
alter table public.cfx_modulos_negocio enable row level security;
alter table public.cfx_modulos_pruebas enable row level security;
revoke all on public.cfx_modulos_negocio, public.cfx_modulos_pruebas from anon, authenticated;

-- Precios en pesos al mes. Anual = 10 meses (2 de regalo). Premium paga 20 % menos en módulos y packs.
insert into public.cfx_config (clave, valor) values ('modulos_venta', jsonb_build_object(
  'activo', false, 'prueba_dias', 7, 'descuento_premium', 20, 'anual_meses', 10, 'precio', 990, 'precios', '{}'::jsonb, 'links', '{}'::jsonb,
  'packs', jsonb_build_object(
    'basico',   jsonb_build_object('nombre', '🌱 Básico',   'detalle', 'Para que vuelvan a comprarte', 'precio', 1990, 'modulos', jsonb_build_array('cupones', 'sellos', 'calificaciones')),
    'crecer',   jsonb_build_object('nombre', '🚀 Crecer',   'detalle', 'Vende más todos los días', 'precio', 2990, 'destacado', true,
                                   'modulos', jsonb_build_array('cupones', 'sellos', 'calificaciones', 'chat', 'carrito', 'redes', 'estadisticas')),
    'completo', jsonb_build_object('nombre', '💎 Completo', 'detalle', 'Todos los módulos, también los nuevos', 'precio', 3990, 'modulos', '*'))))
on conflict (clave) do nothing;

-- Nombre y para qué sirve cada módulo (lo usan el Centro de Mando y la pantalla 🧩 Módulos del negocio).
create or replace function public.cfx_modulos_catalogo() returns table (clave text, nombre text, detalle text)
language sql immutable as $$
  values ('chat', '💬 Chat', 'Conversa con tus clientes dentro de la app, con límites contra el spam.'),
         ('calificaciones', '⭐ Calificaciones', 'Tus clientes te califican y tú a ellos: más confianza para comprar.'),
         ('cupones', '🏷️ Cupones', 'Crea códigos de descuento para tus clientes.'),
         ('sellos', '🎟️ Tarjeta de sellos', 'Cada compra suma un sello; al completar la meta, premio.'),
         ('carrito', '🛒 Recordar carrito', 'Si un cliente deja productos en el carrito, al día siguiente le llega un aviso.'),
         ('analisis', '🔎 Para vender más', 'Cada noche: clientes en riesgo, productos quietos, stock que se acaba y grupos de clientes.'),
         ('estadisticas', '📈 Estadísticas', 'Ventas, productos que más dejan y gráficos en vivo.'),
         ('equipo', '🧑‍🍳 Mi equipo', 'Suma vendedores y bodega con su propia cuenta y permisos.'),
         ('campanas', '📣 Campañas automáticas', 'Mensajes automáticos a tus clientes: ofertas, cumpleaños y los que hace tiempo no vuelven.'),
         ('redes', '📲 Vender en redes', 'Pedir por WhatsApp, catálogo para Google e Instagram.'),
         ('webhooks', '🔗 Avisos a tu sistema', 'Cada pedido llega firmado a tu sistema o planilla (webhooks).'),
         ('medicion', '📊 Medir anuncios', 'Meta Pixel y Google Analytics en tu tienda: mide qué anuncio te trae ventas.'),
         ('dominio', '🌐 Dominio propio', 'Tu tienda en tu dirección (mitienda.cl) en vez del link de Despega Pyme.'),
         ('reservas', '📅 Reservas', 'Agenda en línea para tus clientes.'),
         ('recordatorios', '⏰ Recordatorios', 'Avisos automáticos antes de cada cita o vencimiento.'),
         -- G53: módulos de agenda (Barbería primero; sirven para cualquier app con reservas).
         ('antifalta', '💳 Anti-falta', 'Abono obligatorio y bloqueo automático para los clientes que reservan y no llegan.'),
         ('espera', '⏳ Lista de espera', 'Si no hay horas, el cliente se anota y le avisamos apenas se libere una.'),
         ('resenas', '⭐ Reseñas en Google', 'Al cliente feliz le pedimos su reseña en Google: más gente te encuentra.'),
         ('portafolio', '🖼️ Portafolio', 'Fotos de tus mejores trabajos en tu página de reservas.'),
         ('giftcards', '🎁 Gift cards', 'Vende tarjetas de regalo con código para canjear en tu negocio.'),
         ('membresia', '🔁 Membresía', 'Plan mensual para tus clientes (ej. 4 cortes al mes): plata segura cada mes.'),
         ('productos', '🛍️ Productos y stock', 'Vende productos en la caja y lleva su stock.'),
         ('agenda_redes', '🤖 Reservas por WhatsApp e Instagram', 'Link y respuestas listas para que reserven desde tus redes.'),
         -- G59: módulos de taller (BiciTaller primero; sirven para cualquier app con órdenes de trabajo).
         ('presupuesto', '✅ Presupuesto por link', 'El cliente aprueba o rechaza cada arreglo desde su celular: sin llamadas ni reclamos.'),
         ('aviso_lista', '🔔 Aviso "bici lista"', 'Al dejarla lista, el cliente recibe el aviso por WhatsApp con el total y el link; si no la retira, se lo recordamos.'),
         ('mantencion', '⏰ Recordatorio de mantención', 'Cada X meses le avisamos al cliente que le toca mantención: vuelve solo.'),
         ('stock', '📦 Repuestos y stock', 'Stock de repuestos que baja solo con cada orden y pedido a tu proveedor por WhatsApp con un toque.'),
         ('certificadas', '🏷️ Bicis usadas certificadas', 'Vende bicis usadas con informe de 50 puntos, fotos y garantía: se publican en tu página y te escriben por WhatsApp.'),
         ('tradein', '🔄 Parte de pago', 'Calculadora: cuánto ofrecer por la bici usada del cliente para que se lleve una nueva o un arreglo.'),
         ('pasaporte', '🪪 Pasaporte de la bici', 'Sticker QR para el cuadro: historial de mantenciones, dueño y aviso de robo. Quien la escanea sabe si es robada.'),
         ('domicilio', '🚐 Mecánico a domicilio', 'El cliente reserva con su dirección (+ recargo de visita); armas la ruta del día y le avisas “Voy en camino”.'),
         ('garantias', '🛡️ Garantías', 'Garantía del trabajo, repuestos o bici usada, con vencimiento: el cliente la ve en su link y la usa en 1 toque.'),
         ('plan_mant', '🔁 Plan de mantención', 'Tus clientes pagan al mes y tienen visitas incluidas y descuento: plata segura cada mes y vuelven siempre.'),
         -- G94: módulos de cobranza (Billetera primero).
         ('acuerdo', '📝 Acuerdo de pago firmado', 'Armas un plan de pago y el cliente lo acepta desde su link con su nombre: queda firmado, con fecha y calendario.'),
         ('contador', '🧮 Link para el contador', 'Un link de solo lectura con ventas, gastos y cobros del mes y su planilla: sin mandar pantallazos.'),
         ('escalonado', '📈 Cobranza escalonada', 'El mensaje de cobro sube de tono solo según los días de atraso: amable → neutral → firme, respetando la ley.'),
         ('gastos_fijos', '🔁 Gastos fijos automáticos', 'Arriendo, luz o sueldos se anotan solos cada mes en tu caja, el día que elijas.'),
         -- G94: módulos de estacionamientos (Estaciona primero).
         ('destacar', '⭐ Destacado en el mapa', 'Tus estacionamientos salen primero y resaltados en el mapa y la lista: más reservas.'),
         ('acceso', '🔑 Control de acceso con QR', 'Cada reserva trae su pase QR: lo escaneas al entrar y salir y ves si está vigente y su patente.'),
         ('descuentos', '🏷️ Descuento por estadía larga', 'Premia a quien reserva más tiempo: un % menos desde las horas, días o meses que elijas.'),
         ('ganancias', '📊 Ganancias y ocupación', 'Cuánto ganaste por mes, ocupación de cada lugar, mejores días y planilla para Excel.'),
         -- G96: módulos de tienda (Despega primero).
         ('suscripciones', '🔁 Compras recurrentes', 'Tu cliente recibe su pedido solo cada semana o cada mes (café, alimento, agua…): venta segura sin tener que pedirla.'),
         ('proveedores', '📦 Stock mínimo y proveedores', 'Te avisa cuando un producto baja de su mínimo y arma el pedido a tu proveedor por WhatsApp con un toque.'),
         -- G96 b: 🏬 sucursales (Despega) y 📣 promos en la app de tus clientes (Despega, Barbería, BiciTaller).
         ('sucursales', '🏬 Sucursales y bodegas', 'Stock separado por local o bodega: vendes en la Caja desde cada sucursal y mueves mercadería entre ellas.'),
         ('promos', '📣 Promo destacada', 'Al abrir la app, tus clientes ven tu oferta en una tarjeta con foto y botón (además de tus ofertas de siempre). Ves cuántos la vieron y la tocaron.'),
         -- G101: 🛒 Mercado Libre (Despega).
         ('mercadolibre', '🛒 Mercado Libre', 'Une tus productos con tus publicaciones de Mercado Libre: vendes allá y se descuenta aquí; cambias el stock aquí y se actualiza allá.'),
         -- G102: 🚚 Courier Chilexpress (Despega).
         ('courier', '🚚 Courier Chilexpress', 'Cotiza el envío y saca la etiqueta de Chilexpress desde el pedido: el código de seguimiento le llega solo a tu cliente.'),
         -- G104: más módulos de cobranza (Billetera).
         ('cuentas_pagar', '📤 Cuentas por pagar', 'Lo que debes a tus proveedores con su vencimiento: te avisamos antes y al pagar queda como gasto en tu caja.'),
         ('cierre_caja', '💵 Cierre de caja', 'Al cerrar cuentas el efectivo y ves al tiro si cuadra, sobra o falta. Queda el historial de cada día.'),
         ('aviso_vence', '🔔 Aviso de vencimiento automático', 'El día antes y el día que vence, a tu cliente le llega el aviso en su celular con su saldo y link para pagar. Solo, respetando la ley.'),
         -- G104: más módulos de estacionamientos (Estaciona).
         ('tarifas', '🌙 Tarifa fin de semana y noche', 'Cobra distinto el sábado, domingo y de noche: un % más (o menos) que se calcula solo al reservar.'),
         ('frecuentes', '🔁 Clientes frecuentes', 'Ve quién te arrienda más y prémialo solo: un % menos desde su reserva número N. Vuelven siempre.'),
         ('calendario', '📅 Cerrar fechas', 'Cierra días por vacaciones o uso propio: nadie puede reservar esas fechas y la ficha lo muestra.'),
         ('avisame', '🔔 Lista de espera', 'Si tu lugar está ocupado, la gente se anota y le avisamos apenas lo marques disponible: no pierdes al próximo cliente.'),
         -- G112 d: 🎬 Estudio de contenido (las 5 apps con negocios; mismo motor del Centro de Mando, sin IA de pago).
         ('estudio', '🎬 Estudio de contenido', 'Ideas para TikTok, Instagram y Facebook con gancho, guión, copy y hashtags listos para copiar. Arma tu semana y aprende de TUS métricas qué funciona.')
$$;

create or replace function public.cfx_venta() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce((select valor from public.cfx_config where clave = 'modulos_venta'), '{}'::jsonb)
$$;
-- Precio al mes de un módulo o pack (0 = incluido gratis).
create or replace function public.cfx_venta_precio(p_item text) returns int
language sql stable security definer set search_path = '' as $$
  select coalesce((v #>> array['packs', p_item, 'precio'])::int, (v #>> array['precios', p_item])::int, (v ->> 'precio')::int, 0)
  from (select public.cfx_venta() v) x
$$;
-- ¿Está prendida la venta de módulos en esta app? (si no, todo funciona como antes del G19)
create or replace function public.cfx_venta_on() returns boolean
language sql stable security definer set search_path = '' as $$ select coalesce((public.cfx_venta() ->> 'activo')::boolean, false) $$;
-- ¿Este módulo se vende aparte en esta app? (venta prendida y precio > 0)
create or replace function public.cfx_venta_activa(p_modulo text) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.cfx_venta_on() and p_modulo = any(public.cfx_modulos_de_app()) and public.cfx_venta_precio(p_modulo) > 0
$$;
-- Módulos que trae un pack ('*' = todos los de la app) o el módulo mismo.
create or replace function public.cfx_venta_modulos(p_item text) returns text[]
language plpgsql stable security definer set search_path = '' as $$
declare p jsonb := public.cfx_venta() #> array['packs', p_item];
begin
  if p is null then return case when p_item = any(public.cfx_modulos_de_app()) then array[p_item] else '{}'::text[] end; end if;
  if p ->> 'modulos' = '*' then return public.cfx_modulos_de_app(); end if;
  return array(select x from jsonb_array_elements_text(coalesce(p -> 'modulos', '[]')) x where x = any(public.cfx_modulos_de_app()));
end $$;

-- G74 b · 🎁 Campaña de lanzamiento: {"modulos": [...], "meses": 3, "hasta": "AAAA-MM-DD"} en cfx_venta() -> 'campana'.
-- Activa hasta el día "hasta" incluido (hora de Chile): sin cron, se apaga sola al pasar la fecha.
create or replace function public.cfx_campana() returns jsonb
language sql stable security definer set search_path = '' as $$
  select case when public.cfx_venta_on() and jsonb_typeof(c) = 'object' and (c ->> 'hasta') ~ '^\d{4}-\d{2}-\d{2}$'
    and (c ->> 'hasta')::date >= (now() at time zone 'America/Santiago')::date and coalesce((c ->> 'meses')::int, 0) between 1 and 12
    and jsonb_typeof(c -> 'modulos') = 'array' and jsonb_array_length(c -> 'modulos') > 0 then c end
  from (select public.cfx_venta() -> 'campana' c) x
$$;
create or replace function public.cfx_negocio_cuenta(p_cuenta uuid) returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare n uuid;
begin
  if p_cuenta is null then return null; end if;
  if to_regprocedure('public.cfx_negocio_de_cuenta(uuid)') is not null then execute 'select public.cfx_negocio_de_cuenta($1)' into n using p_cuenta;
  elsif to_regprocedure('public.cfx_analisis_negocio(uuid)') is not null then execute 'select public.cfx_analisis_negocio($1)' into n using p_cuenta;
  else n := p_cuenta; end if;
  return n;
end $$;
-- G95: la cuenta del dueño de un negocio. Gancho opcional de la app: cfx_negocio_dueno_app(uuid) → uuid (Billetera: el negocio no es la cuenta).
create or replace function public.cfx_negocio_dueno(p_negocio uuid) returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare d uuid;
begin
  if p_negocio is null then return null; end if;
  if to_regprocedure('public.cfx_negocio_dueno_app(uuid)') is not null then execute 'select public.cfx_negocio_dueno_app($1)' into d using p_negocio; return d; end if;
  return p_negocio;
end $$;
create or replace function public.cfx_negocio_premium(p_negocio uuid) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare r boolean;
begin
  if p_negocio is null or to_regprocedure('public.cfx_es_premium(uuid)') is null then return false; end if;
  execute 'select public.cfx_es_premium($1)' into r using p_negocio;
  return coalesce(r, false);
end $$;

-- ¿El negocio puede usar el módulo ahora? (prendido en la app + comprado, en prueba, regalado o incluido gratis)
create or replace function public.cfx_modulo_de(p_modulo text, p_negocio uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.cfx_modulo(p_modulo) and (not public.cfx_venta_activa(p_modulo)
    or exists (select 1 from public.cfx_modulos_negocio m where m.negocio = p_negocio and m.modulo = p_modulo and m.hasta > now()))
$$;
create or replace function public.cfx_modulo_mio(p_modulo text) returns boolean
language sql stable security definer set search_path = '' as $$ select public.cfx_modulo_de(p_modulo, public.cfx_negocio_cuenta(auth.uid())) $$;

-- Lo que puede usar cada negocio: {"chat": true, ...}. Para una tienda que ve un cliente.
create or replace function public.cfx_modulos_de(p_negocio uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce((select jsonb_object_agg(k, public.cfx_modulo_de(k, p_negocio)) from unnest(public.cfx_modulos_de_app()) k), '{}')
$$;

-- Activa (o alarga) los módulos de un item por N días; N <= 0 los quita. Devuelve hasta cuándo.
create or replace function public.cfx_modulos_dar(p_negocio uuid, p_item text, p_dias int, p_origen text default 'pago') returns timestamptz
language plpgsql security definer set search_path = '' as $$
declare k text; h timestamptz; mx timestamptz;
begin
  if p_negocio is null or cardinality(public.cfx_venta_modulos(p_item)) = 0 then raise exception 'Módulo no válido'; end if;
  foreach k in array public.cfx_venta_modulos(p_item) loop
    if coalesce(p_dias, 0) <= 0 then delete from public.cfx_modulos_negocio where negocio = p_negocio and modulo = k; continue; end if;
    insert into public.cfx_modulos_negocio as m (negocio, modulo, hasta, origen) values (p_negocio, k, now() + make_interval(days => p_dias), p_origen)
    on conflict (negocio, modulo) do update set hasta = greatest(m.hasta, now()) + make_interval(days => p_dias),
      origen = case when excluded.origen = 'prueba' then m.origen else excluded.origen end, avisado = null
    returning hasta into h;
    mx := greatest(mx, h);
  end loop;
  return mx;
end $$;

-- G53: ¿el plan del negocio ya trae este módulo? (ej. Barbería: Premium incluye los 3 primeros). Gancho opcional de cada app:
-- cfx_modulo_plan_app(text, uuid) → boolean. Sin gancho: ninguno viene en el plan.
create or replace function public.cfx_modulo_plan(p_modulo text, p_negocio uuid) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare r boolean;
begin
  if p_negocio is null or to_regprocedure('public.cfx_modulo_plan_app(text,uuid)') is null then return false; end if;
  execute 'select public.cfx_modulo_plan_app($1, $2)' into r using p_modulo, p_negocio;
  return coalesce(r, false);
end $$;

-- ¿Este negocio puede activar gratis este módulo con la campaña? (una vez por módulo)
create or replace function public.cfx_campana_puede(p_modulo text, p_negocio uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select p_negocio is not null and public.cfx_campana() is not null and public.cfx_campana() -> 'modulos' ? p_modulo
    and public.cfx_modulo(p_modulo) and public.cfx_venta_activa(p_modulo) and not public.cfx_modulo_plan(p_modulo, p_negocio)
    and not exists (select 1 from public.cfx_modulos_pruebas p where p.negocio = p_negocio and p.item = 'campana:' || p_modulo)
$$;

-- Pantalla 🧩 Módulos del negocio: catálogo, precios (con su descuento Premium), lo que tiene y hasta cuándo.
create or replace function public.cfx_modulos_tienda() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v jsonb := public.cfx_venta(); n uuid := public.cfx_negocio_cuenta(auth.uid()); dn uuid := public.cfx_negocio_dueno(public.cfx_negocio_cuenta(auth.uid())); pre boolean; d int; am int;
begin
  if n is null then raise exception 'Solo para negocios'; end if;
  pre := public.cfx_negocio_premium(n);
  d := case when pre then greatest(0, least(90, coalesce((v ->> 'descuento_premium')::int, 0))) else 0 end;
  am := greatest(1, least(12, coalesce((v ->> 'anual_meses')::int, 10)));
  return jsonb_build_object('activo', coalesce((v ->> 'activo')::boolean, false), 'premium', pre, 'descuento', d, 'anual_meses', am,
    'descuento_pro', case when pre then 0 else greatest(0, least(90, coalesce((v ->> 'descuento_premium')::int, 0))) end,
    'prueba_dias', coalesce((v ->> 'prueba_dias')::int, 7), 'dueno', dn = auth.uid(),
    'campana', (select jsonb_build_object('meses', (c ->> 'meses')::int, 'hasta', c ->> 'hasta') from (select public.cfx_campana() c) x where c is not null),
    'prueba_pack', exists (select 1 from public.cfx_modulos_pruebas p where p.negocio = n and p.item like 'pack:%') or public.cfx_prueba_usada(dn, 'pack'),  -- G95: por correo
    'modulos', coalesce((select jsonb_agg(jsonb_build_object('clave', k, 'nombre', coalesce(c.nombre, k), 'detalle', coalesce(c.detalle, ''),
        'precio', round(public.cfx_venta_precio(k) * (100 - d) / 100.0)::int, 'lista', public.cfx_venta_precio(k),
        'vende', public.cfx_venta_activa(k), 'activo', public.cfx_modulo_de(k, n) or public.cfx_modulo_plan(k, n), 'plan', public.cfx_modulo_plan(k, n),
        'hasta', m.hasta, 'origen', m.origen, 'regalo', public.cfx_campana_puede(k, n), 'prueba_usada', exists (select 1 from public.cfx_modulos_pruebas p where p.negocio = n and p.item = k) or public.cfx_prueba_usada(dn, k),
        'links', v #> array['links', k]) order by o)
      from unnest(public.cfx_modulos_de_app()) with ordinality u(k, o)
      left join public.cfx_modulos_catalogo() c on c.clave = k
      left join public.cfx_modulos_negocio m on m.negocio = n and m.modulo = k
      where public.cfx_modulo(k)), '[]'),
    'packs', coalesce((select jsonb_agg(jsonb_build_object('clave', p.key, 'nombre', p.value ->> 'nombre', 'detalle', coalesce(p.value ->> 'detalle', ''),
        'destacado', coalesce((p.value ->> 'destacado')::boolean, false), 'modulos', to_jsonb(public.cfx_venta_modulos(p.key)),
        'precio', round(coalesce((p.value ->> 'precio')::int, 0) * (100 - d) / 100.0)::int, 'lista', coalesce((p.value ->> 'precio')::int, 0),
        'suelto', (select coalesce(sum(public.cfx_venta_precio(x)), 0) from unnest(public.cfx_venta_modulos(p.key)) x),
        'links', v #> array['links', p.key]) order by coalesce((p.value ->> 'precio')::int, 0))
      from jsonb_each(coalesce(v -> 'packs', '{}')) p where cardinality(public.cfx_venta_modulos(p.key)) > 0), '[]'));
end $$;

-- Probar gratis: cada módulo una vez, y un solo pack por negocio. Solo el dueño. G95: también una vez por CORREO (cfx_pruebas_usadas, no se borra).
-- prueba_dias = 0 → sin prueba gratis.
create or replace function public.cfx_modulo_probar(p_item text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v jsonb := public.cfx_venta(); n uuid := public.cfx_negocio_cuenta(auth.uid()); pack boolean := (public.cfx_venta() #> array['packs', p_item]) is not null;
        dias int := least(30, coalesce((v ->> 'prueba_dias')::int, 7)); h timestamptz;
begin
  if n is null or public.cfx_negocio_dueno(n) is distinct from auth.uid() then raise exception 'Solo el dueño del negocio'; end if;
  if dias <= 0 then raise exception 'La prueba gratis no está disponible ahora'; end if;
  if not coalesce((v ->> 'activo')::boolean, false) or cardinality(public.cfx_venta_modulos(p_item)) = 0 then raise exception 'Módulo no válido'; end if;
  if pack and exists (select 1 from public.cfx_modulos_pruebas where negocio = n and item like 'pack:%') then raise exception 'Ya usaste la prueba gratis de un pack'; end if;
  if not pack and exists (select 1 from public.cfx_modulos_pruebas where negocio = n and item = p_item) then raise exception 'Ya usaste la prueba gratis de este módulo'; end if;
  if public.cfx_prueba_usada(auth.uid(), case when pack then 'pack' else p_item end) then
    raise exception '%', case when pack then 'Ya usaste la prueba gratis de un pack con este correo' else 'Ya usaste la prueba gratis de este módulo con este correo' end; end if;
  if not pack and public.cfx_modulo_de(p_item, n) then raise exception 'Ya tienes este módulo activo'; end if;
  insert into public.cfx_modulos_pruebas (negocio, item) values (n, case when pack then 'pack:' || p_item else p_item end);
  perform public.cfx_prueba_marcar(auth.uid(), case when pack then 'pack' else p_item end);
  -- La prueba no alarga lo que ya está pagado: solo prende lo que no tiene.
  insert into public.cfx_modulos_negocio as m (negocio, modulo, hasta, origen)
  select n, k, now() + make_interval(days => dias), 'prueba' from unnest(public.cfx_venta_modulos(p_item)) k
  on conflict (negocio, modulo) do update set hasta = greatest(m.hasta, excluded.hasta), origen = case when m.hasta > now() then m.origen else 'prueba' end, avisado = null;
  select max(hasta) into h from public.cfx_modulos_negocio where negocio = n and modulo = any(public.cfx_venta_modulos(p_item));
  perform public.cfx_anotar('módulo', 'prueba ' || p_item || ' · ' || n);
  return jsonb_build_object('ok', true, 'hasta', h);
end $$;

-- G74 b: el dueño toca 🎁 Activar → queda al tiro con el módulo N meses (origen 'regalo'). Una vez por módulo y negocio.
create or replace function public.cfx_modulo_campana(p_modulo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n uuid := public.cfx_negocio_cuenta(auth.uid()); c jsonb := public.cfx_campana(); h timestamptz;
begin
  if n is null or public.cfx_negocio_dueno(n) is distinct from auth.uid() then raise exception 'Solo el dueño del negocio'; end if;
  if c is null then raise exception 'La campaña ya terminó'; end if;
  if not public.cfx_campana_puede(p_modulo, n) then
    raise exception '%', case when exists (select 1 from public.cfx_modulos_pruebas p where p.negocio = n and p.item = 'campana:' || p_modulo)
      then 'Ya activaste este regalo' else 'Este módulo no está en la campaña' end;
  end if;
  insert into public.cfx_modulos_pruebas (negocio, item) values (n, 'campana:' || p_modulo);
  insert into public.cfx_modulos_negocio as m (negocio, modulo, hasta, origen)
  values (n, p_modulo, now() + make_interval(months => (c ->> 'meses')::int), 'regalo')
  on conflict (negocio, modulo) do update set hasta = greatest(m.hasta, now()) + make_interval(months => (c ->> 'meses')::int), origen = 'regalo', avisado = null
  returning hasta into h;
  perform public.cfx_anotar('módulo', 'campaña ' || p_modulo || ' · ' || n);
  return jsonb_build_object('ok', true, 'hasta', h);
end $$;

-- Aviso 3 días antes de que venza (7 días si es regalo, G74 b; una vez por vencimiento). Lo corre el cron diario.
create or replace function public.cfx_modulos_avisar() returns int
language plpgsql security definer set search_path = '' as $$
declare r record; c int := 0;
begin
  for r in select m.negocio, min(m.hasta) hasta, string_agg(coalesce(k.nombre, m.modulo), ', ' order by m.modulo) nombres
           from public.cfx_modulos_negocio m left join public.cfx_modulos_catalogo() k on k.clave = m.modulo
           where m.avisado is null and m.hasta between now() and now() + case when m.origen = 'regalo' then interval '7 days' else interval '3 days' end
           group by m.negocio limit 500 loop
    perform public.cfx_avisar(r.negocio, '🧩 Tus módulos vencen pronto', left(r.nombres, 120) || ' · vence el ' ||
      to_char(r.hasta at time zone 'America/Santiago', 'DD/MM') || '. Renuévalos en Ajustes → 🧩 Módulos y no pierdes nada.');
    update public.cfx_modulos_negocio set avisado = now() where negocio = r.negocio and avisado is null
      and hasta between now() and now() + case when origen = 'regalo' then interval '7 days' else interval '3 days' end;
    c := c + 1;
  end loop;
  return c;
end $$;

-- Al borrar un negocio (lo llama la app): sus módulos y sus pruebas.
create or replace function public.cfx_modulos_borrar(p_negocio uuid) returns void
language sql security definer set search_path = '' as $$
  delete from public.cfx_modulos_negocio where negocio = p_negocio;
  delete from public.cfx_modulos_pruebas where negocio = p_negocio;
$$;

-- ---------- Centro de Mando ----------
create or replace function public.cfx_venta_admin() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  return jsonb_build_object('config', public.cfx_venta(), 'app', to_jsonb(public.cfx_modulos_de_app()),
    'catalogo', (select coalesce(jsonb_agg(jsonb_build_object('clave', c.clave, 'nombre', c.nombre)), '[]') from public.cfx_modulos_catalogo() c where c.clave = any(public.cfx_modulos_de_app())),
    'activos', (select count(distinct negocio) from public.cfx_modulos_negocio where hasta > now() and origen = 'pago'),
    'pruebas', (select count(distinct negocio) from public.cfx_modulos_negocio where hasta > now() and origen = 'prueba'),
    'campana_on', public.cfx_campana() is not null,
    'campana_usos', (select count(distinct negocio) from public.cfx_modulos_pruebas where item like 'campana:%'),
    'negocios', coalesce((select jsonb_agg(x order by x.hasta) from (
      select m.negocio, coalesce((select u.email from auth.users u where u.id = m.negocio), '') email, min(m.hasta) hasta,
        jsonb_agg(jsonb_build_object('modulo', m.modulo, 'hasta', m.hasta, 'origen', m.origen) order by m.modulo) modulos
      from public.cfx_modulos_negocio m where m.hasta > now() - interval '30 days' group by m.negocio limit 300) x), '[]'));
end $$;

create or replace function public.cfx_venta_guardar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v jsonb := public.cfx_venta(); l record; u record;
begin
  perform privado.solo_admin();
  if jsonb_typeof(p) <> 'object' then raise exception 'Datos no válidos'; end if;
  v := v || jsonb_strip_nulls(p - 'packs' - 'precios' - 'links' - 'campana')
         || jsonb_build_object('precios', coalesce(p -> 'precios', v -> 'precios', '{}'),   -- llegan completos desde el CM
                               'links', coalesce(p -> 'links', v -> 'links', '{}'),
                               'packs', coalesce(p -> 'packs', v -> 'packs', '{}'));
  if p ? 'campana' then  -- G74 b: null o {} = terminar la campaña ahora
    if coalesce((p #>> '{campana,fin}')::boolean, false) then  -- ⏹️ Terminar hoy: la fecha pasa a ayer (queda el historial)
      if jsonb_typeof(v -> 'campana') = 'object' then
        v := jsonb_set(v, '{campana,hasta}', to_jsonb(to_char((now() at time zone 'America/Santiago')::date - 1, 'YYYY-MM-DD')));
      end if;
    else v := v - 'campana'; end if;
    if jsonb_typeof(p -> 'campana') = 'object' and p -> 'campana' <> '{}'::jsonb and not (p -> 'campana' ? 'fin') then
      if coalesce(p #>> '{campana,meses}', '') !~ '^\d{1,2}$' or (p #>> '{campana,meses}')::int not between 1 and 12 then raise exception 'Meses de regalo: de 1 a 12'; end if;
      if coalesce(p #>> '{campana,hasta}', '') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Elige la fecha de término'; end if;
      if (p #>> '{campana,hasta}')::date < (now() at time zone 'America/Santiago')::date or (p #>> '{campana,hasta}')::date > (now() at time zone 'America/Santiago')::date + 366 then
        raise exception 'La fecha de término va de hoy a un año más'; end if;
      if jsonb_typeof(p #> '{campana,modulos}') <> 'array' or not exists (select 1 from jsonb_array_elements_text(p #> '{campana,modulos}') x where x = any(public.cfx_modulos_de_app())) then
        raise exception 'Elige al menos un módulo'; end if;
      v := v || jsonb_build_object('campana', jsonb_build_object('meses', (p #>> '{campana,meses}')::int, 'hasta', p #>> '{campana,hasta}',
        'modulos', (select jsonb_agg(distinct x) from jsonb_array_elements_text(p #> '{campana,modulos}') x where x = any(public.cfx_modulos_de_app()))));
    end if;
  end if;
  if coalesce((v ->> 'precio')::numeric, 0) not between 0 and 1000000 or coalesce((v ->> 'descuento_premium')::numeric, 0) not between 0 and 90
     or coalesce((v ->> 'prueba_dias')::numeric, 7) not between 0 and 30 or coalesce((v ->> 'anual_meses')::numeric, 10) not between 1 and 12 then
    raise exception 'Revisa los números: precio de 0 a 1.000.000, descuento de 0 a 90 %%, prueba de 0 a 30 días, anual de 1 a 12 meses';
  end if;
  for l in select key, value from jsonb_each(coalesce(v -> 'precios', '{}')) loop
    if jsonb_typeof(l.value) <> 'number' or l.value::numeric not between 0 and 1000000 then raise exception 'Precio no válido: %', l.key; end if;
  end loop;
  for l in select key, value from jsonb_each(coalesce(v -> 'links', '{}')) loop
    for u in select key, value from jsonb_each_text(case when jsonb_typeof(l.value) = 'object' then l.value else '{}' end) loop
      if coalesce(u.value, '') <> '' and u.value !~ '^https://[^ ]+$' then raise exception 'El link de % debe empezar con https://', l.key; end if;
    end loop;
  end loop;
  update public.cfx_config set valor = v where clave = 'modulos_venta';
  perform public.cfx_anotar('módulos', 'venta ' || case when coalesce((v ->> 'activo')::boolean, false) then 'prendida' else 'apagada' end);
  return public.cfx_venta_admin();
end $$;

-- Regalar o quitar (p_dias = 0) un módulo o pack a un negocio por su correo.
create or replace function public.cfx_modulo_regalar(p_email text, p_item text, p_dias int) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid; n uuid; h timestamptz;
begin
  perform privado.solo_admin();
  select id into u from auth.users where lower(email) = lower(trim(coalesce(p_email, '')));
  if u is null then raise exception 'No hay una cuenta con ese correo en esta app'; end if;
  n := public.cfx_negocio_cuenta(u);
  if n is null then raise exception 'Esa cuenta no es un negocio'; end if;
  if coalesce(p_dias, 0) not between 0 and 3660 then raise exception 'De 0 a 3660 días'; end if;
  h := public.cfx_modulos_dar(n, p_item, p_dias, 'regalo');
  if h is not null then perform public.cfx_avisar(n, '🎁 Te regalamos un módulo', coalesce((select c.nombre from public.cfx_modulos_catalogo() c where c.clave = p_item), public.cfx_venta() #>> array['packs', p_item, 'nombre'], p_item) ||
    ' activo hasta el ' || to_char(h at time zone 'America/Santiago', 'DD/MM/YYYY') || '.'); end if;
  perform public.cfx_anotar('módulo', case when h is null then 'quitó ' else 'regaló ' || p_dias || ' días de ' end || p_item || ' a ' || lower(trim(p_email)));
  return public.cfx_venta_admin();
end $$;

revoke all on function public.cfx_modulos_catalogo(), public.cfx_venta(), public.cfx_venta_on(), public.cfx_venta_precio(text), public.cfx_venta_activa(text), public.cfx_venta_modulos(text),
  public.cfx_negocio_cuenta(uuid), public.cfx_negocio_dueno(uuid), public.cfx_negocio_premium(uuid), public.cfx_modulo_plan(text, uuid), public.cfx_modulo_de(text, uuid), public.cfx_modulo_mio(text),
  public.cfx_modulos_dar(uuid, text, int, text), public.cfx_modulos_avisar(), public.cfx_modulos_borrar(uuid),
  public.cfx_campana(), public.cfx_campana_puede(text, uuid) from public, anon, authenticated;
revoke all on function public.cfx_modulos_de(uuid), public.cfx_modulos_tienda(), public.cfx_modulo_probar(text), public.cfx_modulo_campana(text), public.cfx_venta_admin(),
  public.cfx_venta_guardar(jsonb), public.cfx_modulo_regalar(text, text, int) from public, anon;
grant execute on function public.cfx_modulos_de(uuid) to anon, authenticated;
grant execute on function public.cfx_modulos_tienda(), public.cfx_modulo_probar(text), public.cfx_modulo_campana(text), public.cfx_venta_admin(), public.cfx_venta_guardar(jsonb),
  public.cfx_modulo_regalar(text, text, int) to authenticated;
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'cfx-modulos';
  perform cron.schedule('cfx-modulos', '17 13 * * *', 'select public.cfx_modulos_avisar()');
exception when others then
  raise notice 'Aviso de módulos por vencer no programado (%).', sqlerrm;
end $$;
-- ---------- Chat entre personas (C14): las mismas reglas en todas las apps (módulo 'chat') ----------
-- Reglas: hasta N mensajes seguidos sin respuesta (el gancho decide N; null = sin límite, p. ej. el admin), 100 al día,
-- bloquear (ninguno de los dos escribe), reportar (le llega al admin) y borrar la conversación (para los dos).
-- Ganchos que pone cada app que usa el chat (y 'chat' en cfx_modulos_app()):
--   cfx_chat_puede(a, b) boolean         ¿a puede escribirle a b?
--   cfx_chat_seguidos(a, b) int          mensajes seguidos sin respuesta (null = sin límite)
--   cfx_chat_quien(u) jsonb              {"nombre": ..., "rol": ...} para la lista y los reportes
--   cfx_chat_aviso(para, de, texto) void push al que recibe (con el link a la conversación)
--   cfx_chat_suspender(u) void           el admin suspende una cuenta reportada
create table if not exists public.cfx_mensajes (
  id      uuid primary key default gen_random_uuid(),
  de      uuid not null references auth.users (id) on delete cascade,
  para    uuid not null references auth.users (id) on delete cascade,
  texto   text not null check (char_length(texto) between 1 and 1000),
  creado  timestamptz not null default now(),
  leido   timestamptz
);
create index if not exists cfx_mensajes_par_idx on public.cfx_mensajes (least(de, para), greatest(de, para), creado desc);
create index if not exists cfx_mensajes_para_idx on public.cfx_mensajes (para) where leido is null;
create index if not exists cfx_mensajes_de_idx on public.cfx_mensajes (de, creado);
create index if not exists cfx_mensajes_creado_idx on public.cfx_mensajes (creado);
create table if not exists public.cfx_bloqueos (
  quien   uuid not null references auth.users (id) on delete cascade,
  a       uuid not null references auth.users (id) on delete cascade,
  creado  timestamptz not null default now(),
  primary key (quien, a)
);
create table if not exists public.cfx_reportes (
  id        uuid primary key default gen_random_uuid(),
  quien     uuid not null references auth.users (id) on delete cascade,
  a         uuid not null references auth.users (id) on delete cascade,
  mensaje   uuid references public.cfx_mensajes (id) on delete set null,
  motivo    text not null,
  extracto  text not null default '',
  resuelto  boolean not null default false,
  creado    timestamptz not null default now()
);
alter table public.cfx_mensajes enable row level security;
alter table public.cfx_bloqueos enable row level security;
alter table public.cfx_reportes enable row level security;
revoke all on public.cfx_mensajes, public.cfx_bloqueos, public.cfx_reportes from anon, authenticated;

create or replace function public.cfx_msg_listo() returns uuid
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Inicia sesión primero'; end if;
  if not public.cfx_modulo('chat') then raise exception 'El chat no está disponible en esta app'; end if;
  return auth.uid();
end $$;

create or replace function public.cfx_msg_bloqueado(p_uno uuid, p_otro uuid) returns boolean
language plpgsql stable security definer set search_path = '' as $$
begin
  return exists (select 1 from public.cfx_bloqueos x where (x.quien = p_uno and x.a = p_otro) or (x.quien = p_otro and x.a = p_uno));
end $$;

-- Cuántos me quedan seguidos con "otro": {"restantes": n, "limite": n} (null = sin límite).
create or replace function public.cfx_msg_restantes(p_otro uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare u uuid := public.cfx_msg_listo(); lim int := public.cfx_chat_seguidos(u, p_otro); n int;
begin
  if lim is null then return jsonb_build_object('restantes', null, 'limite', null); end if;
  select count(*) into n from public.cfx_mensajes m where m.de = u and m.para = p_otro
    and m.creado > coalesce((select max(x.creado) from public.cfx_mensajes x where x.de = p_otro and x.para = u), '-infinity');
  return jsonb_build_object('restantes', greatest(0, lim - n), 'limite', lim);
end $$;

-- Enviar: {"ok": true, "id", "restantes"} o {"ok": false, "error"}.
create or replace function public.cfx_msg_enviar(p_para uuid, p_texto text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid := public.cfx_msg_listo(); t text := trim(coalesce(p_texto, '')); lim int; r jsonb; i uuid;
begin
  if t = '' then return jsonb_build_object('ok', false, 'error', 'Escribe un mensaje'); end if;
  if char_length(t) > 1000 then return jsonb_build_object('ok', false, 'error', 'Máximo 1000 caracteres por mensaje'); end if;
  if p_para is null or not coalesce(public.cfx_chat_puede(u, p_para), false) then
    return jsonb_build_object('ok', false, 'error', 'No puedes escribirle a esta cuenta');
  end if;
  lim := public.cfx_chat_seguidos(u, p_para);
  -- G19: con el chat a la venta, el negocio de la conversación debe tenerlo (con soporte siempre se puede).
  if lim is not null and public.cfx_chat_seguidos(p_para, u) is not null and public.cfx_venta_activa('chat') then
    if public.cfx_negocio_cuenta(u) is not null and not public.cfx_modulo_de('chat', public.cfx_negocio_cuenta(u)) then
      return jsonb_build_object('ok', false, 'error', 'El chat es un módulo. Actívalo en Ajustes → 🧩 Módulos');
    end if;
    if public.cfx_negocio_cuenta(p_para) is not null and not public.cfx_modulo_de('chat', public.cfx_negocio_cuenta(p_para)) then
      return jsonb_build_object('ok', false, 'error', 'Esta tienda no tiene chat. Escríbele por WhatsApp');
    end if;
  end if;
  if lim is not null then
    if public.cfx_msg_bloqueado(u, p_para) then return jsonb_build_object('ok', false, 'error', 'La conversación está bloqueada'); end if;
    if (public.cfx_msg_restantes(p_para) ->> 'restantes')::int <= 0 then
      return jsonb_build_object('ok', false, 'error', case when lim = 1
        then 'Envías 1 mensaje a la vez. Espera la respuesta para escribir de nuevo.'
        else 'Ya enviaste ' || lim || ' mensajes seguidos. Espera la respuesta para escribir de nuevo.' end);
    end if;
    if (select count(*) from public.cfx_mensajes where de = u and creado > now() - interval '1 day') >= 100 then
      return jsonb_build_object('ok', false, 'error', 'Llegaste al máximo de 100 mensajes por día');
    end if;
  end if;
  insert into public.cfx_mensajes (de, para, texto) values (u, p_para, t) returning id into i;
  perform public.cfx_chat_aviso(p_para, u, t);
  r := public.cfx_msg_restantes(p_para);
  return jsonb_build_object('ok', true, 'id', i, 'restantes', r -> 'restantes');
end $$;

-- Mis conversaciones: [{otro, nombre, rol, ultimo, ultimo_at, mio, no_leidos, bloqueado}] (las 100 más recientes).
create or replace function public.cfx_msg_lista() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare u uuid := public.cfx_msg_listo();
begin
  return coalesce((with z as (select case when m.de = u then m.para else m.de end as otro, m.texto, m.creado, m.de = u as mio
                               from public.cfx_mensajes m where m.de = u or m.para = u),
                          l as (select distinct on (otro) * from z order by otro, creado desc),
                          t as (select * from l order by creado desc limit 100)
    select jsonb_agg(jsonb_build_object('otro', t.otro, 'nombre', coalesce(q.v ->> 'nombre', 'Cuenta'), 'rol', coalesce(q.v ->> 'rol', ''),
      'ultimo', t.texto, 'ultimo_at', t.creado, 'mio', t.mio,
      'no_leidos', (select count(*) from public.cfx_mensajes x where x.de = t.otro and x.para = u and x.leido is null),
      'bloqueado', exists (select 1 from public.cfx_bloqueos b where b.quien = u and b.a = t.otro)) order by t.creado desc)
    from t cross join lateral (select public.cfx_chat_quien(t.otro) as v) q), '[]');
end $$;

create or replace function public.cfx_msg_sin_leer() returns int
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or not public.cfx_modulo('chat') then return 0; end if;
  return (select count(*)::int from public.cfx_mensajes where para = auth.uid() and leido is null);
end $$;

-- Una conversación (las últimas 200; marca como leídos los recibidos): [{id, mio, texto, creado, leido}].
create or replace function public.cfx_msg_hilo(p_otro uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid := public.cfx_msg_listo();
begin
  update public.cfx_mensajes set leido = now() where de = p_otro and para = u and leido is null;
  return coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'mio', m.de = u, 'texto', m.texto, 'creado', m.creado, 'leido', m.leido) order by m.creado)
    from (select * from public.cfx_mensajes x where (x.de = u and x.para = p_otro) or (x.de = p_otro and x.para = u)
          order by x.creado desc limit 200) m), '[]');
end $$;

create or replace function public.cfx_msg_bloquear(p_otro uuid, p_bloquear boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare u uuid := public.cfx_msg_listo();
begin
  if p_otro is null or p_otro = u then raise exception 'Cuenta no válida'; end if;
  if p_bloquear then insert into public.cfx_bloqueos (quien, a) values (u, p_otro) on conflict do nothing;
  else delete from public.cfx_bloqueos where quien = u and a = p_otro; end if;
end $$;

create or replace function public.cfx_msg_reportar(p_mensaje uuid, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid := public.cfx_msg_listo(); m public.cfx_mensajes;
begin
  select * into m from public.cfx_mensajes where id = p_mensaje and para = u;
  if m.id is null then return jsonb_build_object('ok', false, 'error', 'Mensaje no encontrado'); end if;
  if (select count(*) from public.cfx_reportes where quien = u and creado > now() - interval '1 day') >= 10 then
    return jsonb_build_object('ok', false, 'error', 'Máximo 10 reportes por día');
  end if;
  insert into public.cfx_reportes (quien, a, mensaje, motivo, extracto)
  values (u, m.de, m.id, left(coalesce(nullif(trim(p_motivo), ''), 'Sin motivo'), 300), left(m.texto, 300));
  perform public.cfx_avisar_admin('🚩 Nuevo reporte en el chat', left(m.texto, 100));
  return jsonb_build_object('ok', true);
end $$;

-- Borra la conversación completa (para los dos).
create or replace function public.cfx_msg_borrar(p_otro uuid) returns int
language plpgsql security definer set search_path = '' as $$
declare u uuid := public.cfx_msg_listo(); n int;
begin
  delete from public.cfx_mensajes where (de = u and para = p_otro) or (de = p_otro and para = u);
  get diagnostics n = row_count;
  return n;
end $$;

-- Administrador: reportes sin resolver y resolverlos (descartar o suspender a la cuenta reportada).
create or replace function public.cfx_msg_reportes() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  return coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'motivo', r.motivo, 'extracto', r.extracto, 'creado', r.creado,
      'quien', coalesce(public.cfx_chat_quien(r.quien) ->> 'nombre', ''), 'a', coalesce(public.cfx_chat_quien(r.a) ->> 'nombre', ''),
      'quien_email', (select email from auth.users where id = r.quien), 'a_email', (select email from auth.users where id = r.a)) order by r.creado desc)
    from public.cfx_reportes r where not r.resuelto), '[]');
end $$;

create or replace function public.cfx_msg_resolver(p_id uuid, p_suspender boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare r public.cfx_reportes;
begin
  perform privado.solo_admin();
  update public.cfx_reportes set resuelto = true where id = p_id and not resuelto returning * into r;
  if r.id is null then raise exception 'El reporte ya fue atendido'; end if;
  if p_suspender then perform public.cfx_chat_suspender(r.a); end if;
  perform public.cfx_anotar('reporte chat', case when p_suspender then 'suspendida ' else 'descartado ' end || coalesce((select email from auth.users where id = r.a), ''));
end $$;

revoke all on function public.cfx_msg_listo(), public.cfx_msg_bloqueado(uuid, uuid) from public, anon, authenticated;
revoke all on function public.cfx_msg_restantes(uuid), public.cfx_msg_enviar(uuid, text), public.cfx_msg_lista(), public.cfx_msg_sin_leer(),
  public.cfx_msg_hilo(uuid), public.cfx_msg_bloquear(uuid, boolean), public.cfx_msg_reportar(uuid, text), public.cfx_msg_borrar(uuid),
  public.cfx_msg_reportes(), public.cfx_msg_resolver(uuid, boolean) from public, anon;
grant execute on function public.cfx_msg_restantes(uuid), public.cfx_msg_enviar(uuid, text), public.cfx_msg_lista(), public.cfx_msg_sin_leer(),
  public.cfx_msg_hilo(uuid), public.cfx_msg_bloquear(uuid, boolean), public.cfx_msg_reportar(uuid, text), public.cfx_msg_borrar(uuid),
  public.cfx_msg_reportes(), public.cfx_msg_resolver(uuid, boolean) to authenticated;

-- ---------- G128 💬 Chat DEL PEDIDO (hilo ligado a una referencia, no aparece en Mensajes) ----------
-- Solo para clientes CON cuenta y su tienda. Sin cuenta: el enlace /r/ + WhatsApp. Es parte del pedido (no es el módulo 'chat').
-- A los 7 días de cerrado el pedido se borran sus mensajes (cron diario 'cfx-hilos'); el pedido queda como registro.
-- Ganchos que pone cada app que lo usa (sin ganchos todo responde "no disponible"):
--   cfx_hilo_app(ref, u) jsonb   {"ok": bool, "tienda": bool, "cerrado": timestamptz|null, "existe": bool}
--                                 ¿u participa en el hilo ref? (u null = la limpieza pregunta si existe y cuándo cerró)
--   cfx_hilo_aviso_app(ref, de, texto) void  push al otro lado (con el link al pedido)
create table if not exists public.cfx_hilos (
  id      uuid primary key default gen_random_uuid(),
  ref     text not null check (char_length(ref) between 3 and 80),
  de      uuid not null references auth.users (id) on delete cascade,
  tienda  boolean not null default false,
  texto   text not null check (char_length(texto) between 1 and 1000),
  creado  timestamptz not null default now(),
  leido   timestamptz
);
create index if not exists cfx_hilos_ref_idx on public.cfx_hilos (ref, creado);
create index if not exists cfx_hilos_de_idx on public.cfx_hilos (de, creado);
alter table public.cfx_hilos enable row level security;
revoke all on public.cfx_hilos from anon, authenticated;

create or replace function public.cfx_hilo_quien(p_ref text, u uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r jsonb;
begin
  if to_regprocedure('public.cfx_hilo_app(text,uuid)') is null or coalesce(p_ref, '') = '' then return jsonb_build_object('ok', false, 'existe', false); end if;
  execute 'select public.cfx_hilo_app($1, $2)' into r using left(p_ref, 80), u;
  return coalesce(r, jsonb_build_object('ok', false, 'existe', false));
end $$;

-- Ver el hilo (marca como leídos los del otro lado): {"ok", "abierto", "mensajes": [{id, mio, tienda, texto, creado, leido}]}.
create or replace function public.cfx_hilo_ver(p_ref text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare q jsonb := public.cfx_hilo_quien(p_ref, auth.uid()); t boolean;
begin
  if auth.uid() is null or not coalesce((q ->> 'ok')::boolean, false) then return jsonb_build_object('ok', false, 'error', 'Chat no disponible para este pedido'); end if;
  t := coalesce((q ->> 'tienda')::boolean, false);
  update public.cfx_hilos set leido = now() where ref = p_ref and tienda <> t and leido is null;
  return jsonb_build_object('ok', true, 'abierto', q ->> 'cerrado' is null, 'cerrado', q -> 'cerrado',
    'mensajes', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'mio', m.de = auth.uid(), 'tienda', m.tienda, 'texto', m.texto,
      'creado', m.creado, 'leido', m.leido) order by m.creado)
      from (select * from public.cfx_hilos where ref = p_ref order by creado desc limit 200) m), '[]'));
end $$;

-- Escribir: hasta 1000 caracteres, 60 al día por persona y 200 por pedido. Se puede hasta que se borra (7 días después de cerrar).
create or replace function public.cfx_hilo_enviar(p_ref text, p_texto text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare q jsonb := public.cfx_hilo_quien(p_ref, auth.uid()); t text := trim(coalesce(p_texto, '')); i uuid;
begin
  if auth.uid() is null or not coalesce((q ->> 'ok')::boolean, false) then return jsonb_build_object('ok', false, 'error', 'Chat no disponible para este pedido'); end if;
  if t = '' then return jsonb_build_object('ok', false, 'error', 'Escribe un mensaje'); end if;
  if char_length(t) > 1000 then return jsonb_build_object('ok', false, 'error', 'Máximo 1000 caracteres por mensaje'); end if;
  if (q ->> 'cerrado') is not null and (q ->> 'cerrado')::timestamptz < now() - interval '7 days' then
    return jsonb_build_object('ok', false, 'error', 'Este pedido cerró hace más de 7 días');
  end if;
  if (select count(*) from public.cfx_hilos where de = auth.uid() and creado > now() - interval '1 day') >= 60 then
    return jsonb_build_object('ok', false, 'error', 'Llegaste al máximo de 60 mensajes por día');
  end if;
  if (select count(*) from public.cfx_hilos where ref = p_ref) >= 200 then
    return jsonb_build_object('ok', false, 'error', 'Este pedido llegó a 200 mensajes: sigue por WhatsApp');
  end if;
  insert into public.cfx_hilos (ref, de, tienda, texto) values (p_ref, auth.uid(), coalesce((q ->> 'tienda')::boolean, false), t) returning id into i;
  if to_regprocedure('public.cfx_hilo_aviso_app(text,uuid,text)') is not null then
    begin execute 'select public.cfx_hilo_aviso_app($1, $2, $3)' using p_ref, auth.uid(), t; exception when others then null; end;
  end if;
  return jsonb_build_object('ok', true, 'id', i);
end $$;

-- Sin leer por hilo, para las listas: [{ref, n}] (solo los refs donde participo; máx. 300).
create or replace function public.cfx_hilos_sin_leer(p_refs text[]) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then return '[]'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('ref', z.ref, 'n', z.n)) from (
    select r.ref, (select count(*)::int from public.cfx_hilos h where h.ref = r.ref and h.leido is null and h.tienda <> (w.q ->> 'tienda')::boolean) n
    from (select distinct x as ref from unnest((coalesce(p_refs, '{}'::text[]))[1:300]) x
          where exists (select 1 from public.cfx_hilos h where h.ref = x and h.leido is null)) r
    cross join lateral (select public.cfx_hilo_quien(r.ref, auth.uid()) q) w
    where coalesce((w.q ->> 'ok')::boolean, false)) z where z.n > 0), '[]');
end $$;

-- Cada noche: borra los mensajes de pedidos cerrados hace más de 7 días (o que ya no existen).
create or replace function public.cfx_hilos_limpiar() returns int
language plpgsql security definer set search_path = '' as $$
declare r text; q jsonb; n int := 0; k int;
begin
  for r in select distinct ref from public.cfx_hilos loop
    q := public.cfx_hilo_quien(r, null);
    if not coalesce((q ->> 'existe')::boolean, false) or ((q ->> 'cerrado') is not null and (q ->> 'cerrado')::timestamptz < now() - interval '7 days') then
      delete from public.cfx_hilos where ref = r;
      get diagnostics k = row_count; n := n + k;
    end if;
  end loop;
  return n;
end $$;
revoke all on function public.cfx_hilo_quien(text, uuid), public.cfx_hilos_limpiar() from public, anon, authenticated;
revoke all on function public.cfx_hilo_ver(text), public.cfx_hilo_enviar(text, text), public.cfx_hilos_sin_leer(text[]) from public, anon;
grant execute on function public.cfx_hilo_ver(text), public.cfx_hilo_enviar(text, text), public.cfx_hilos_sin_leer(text[]) to authenticated;
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'cfx-hilos';
  perform cron.schedule('cfx-hilos', '52 7 * * *', 'select public.cfx_hilos_limpiar()');
exception when others then
  raise notice 'Limpieza del chat de pedidos no programada (%).', sqlerrm;
end $$;
-- ---------- Calificaciones en dos direcciones (C15): el cliente califica al negocio y el negocio al cliente (módulo 'calificaciones') ----------
-- Una calificación por "ref" (pedido, reserva, arriendo…) y por lado. Estrellas 1-5 y comentario opcional (300).
-- Gancho que pone cada app que las usa (y 'calificaciones' en cfx_modulos_app()):
--   cfx_calif_ref(ref, u) jsonb   quién califica esa ref: {"ref": text, "negocio": uuid, "cliente": uuid|null, "cliente_ref": text|null, "de_negocio": bool}
--                                 ("ref" = la referencia de verdad, p. ej. el id del pedido cuando llega su token)
--                                 o {"error": "..."} (no existe, aún no se puede, no es tuyo). u puede ser null (invitado con token).
-- Para mostrar: cfx_calif_negocio(n) y cfx_calif_cliente(c, ref) → {"promedio", "total"}; cfx_calif_hecha(ref, de_negocio).
-- Si el módulo está apagado no se califica, los promedios vuelven null y cfx_calif_hecha dice true (no aparece "Califica").
create table if not exists public.cfx_calificaciones (
  ref          text not null,
  de_negocio   boolean not null,
  negocio_id   uuid not null,
  cliente_id   uuid references auth.users (id) on delete set null,
  cliente_ref  text,
  estrellas    int not null check (estrellas between 1 and 5),
  comentario   text not null default '' check (char_length(comentario) <= 300),
  creado       timestamptz not null default now(),
  primary key (ref, de_negocio)
);
create index if not exists cfx_calif_negocio_idx on public.cfx_calificaciones (negocio_id) where not de_negocio;
create index if not exists cfx_calif_cliente_idx on public.cfx_calificaciones (cliente_id) where de_negocio;
create index if not exists cfx_calif_cref_idx on public.cfx_calificaciones (cliente_ref) where de_negocio and cliente_ref is not null;
alter table public.cfx_calificaciones enable row level security;
revoke all on public.cfx_calificaciones from anon, authenticated;

-- Calificar: {"ok": true} o {"ok": false, "error"}.
create or replace function public.cfx_calificar(p_ref text, p_estrellas int, p_comentario text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r jsonb;
begin
  if not public.cfx_modulo('calificaciones') then return jsonb_build_object('ok', false, 'error', 'Las calificaciones no están disponibles'); end if;
  if p_estrellas is null or p_estrellas < 1 or p_estrellas > 5 then return jsonb_build_object('ok', false, 'error', 'Elige de 1 a 5 estrellas'); end if;
  if coalesce(trim(p_ref), '') = '' then return jsonb_build_object('ok', false, 'error', 'No encontrado'); end if;
  r := public.cfx_calif_ref(p_ref, auth.uid());
  if r is null or r ? 'error' or r ->> 'negocio' is null then return jsonb_build_object('ok', false, 'error', coalesce(r ->> 'error', 'No encontrado')); end if;
  if not public.cfx_modulo_de('calificaciones', (r ->> 'negocio')::uuid) then return jsonb_build_object('ok', false, 'error', 'Las calificaciones no están disponibles'); end if;
  insert into public.cfx_calificaciones (ref, de_negocio, negocio_id, cliente_id, cliente_ref, estrellas, comentario)
  values (coalesce(r ->> 'ref', p_ref), coalesce((r ->> 'de_negocio')::boolean, false), (r ->> 'negocio')::uuid, (r ->> 'cliente')::uuid,
          nullif(left(r ->> 'cliente_ref', 60), ''), p_estrellas, left(trim(coalesce(p_comentario, '')), 300))
  on conflict (ref, de_negocio) do nothing;
  if not found then return jsonb_build_object('ok', false, 'error', 'Ya fue calificado'); end if;
  return jsonb_build_object('ok', true);
end $$;

-- ¿Ya calificó ese lado? (con el módulo apagado: true, para no pedirlo)
create or replace function public.cfx_calif_hecha(p_ref text, p_de_negocio boolean) returns boolean
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.cfx_modulo('calificaciones') then return true; end if;
  if public.cfx_venta_activa('calificaciones') and not coalesce(public.cfx_modulo_de('calificaciones', (public.cfx_calif_ref(p_ref, auth.uid()) ->> 'negocio')::uuid), false) then return true; end if;
  return exists (select 1 from public.cfx_calificaciones where ref = p_ref and de_negocio = p_de_negocio);
end $$;

-- Lo que los clientes dicen del negocio.
create or replace function public.cfx_calif_negocio(p_negocio uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.cfx_modulo_de('calificaciones', p_negocio) then return null; end if;
  return (select jsonb_build_object('promedio', round(avg(estrellas), 1), 'total', count(*))
          from public.cfx_calificaciones where negocio_id = p_negocio and not de_negocio);
end $$;

-- Lo que los negocios dicen del cliente (por su cuenta o, si es invitado, por su referencia: teléfono…).
create or replace function public.cfx_calif_cliente(p_cliente uuid, p_cliente_ref text default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.cfx_modulo_mio('calificaciones') or (p_cliente is null and coalesce(p_cliente_ref, '') = '') then return null; end if;
  return (select jsonb_build_object('promedio', round(avg(estrellas), 1), 'total', count(*))
          from public.cfx_calificaciones where de_negocio
            and ((p_cliente is not null and cliente_id = p_cliente) or (p_cliente is null and cliente_ref = p_cliente_ref)));
end $$;

-- Al borrar un negocio o una ref (lo llama la app).
create or replace function public.cfx_calif_borrar(p_negocio uuid, p_ref text default null) returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.cfx_calificaciones where negocio_id = p_negocio and (p_ref is null or ref = p_ref);
end $$;

revoke all on function public.cfx_calif_hecha(text, boolean), public.cfx_calif_negocio(uuid), public.cfx_calif_cliente(uuid, text),
  public.cfx_calif_borrar(uuid, text) from public, anon, authenticated;
revoke all on function public.cfx_calificar(text, int, text) from public;
grant execute on function public.cfx_calificar(text, int, text) to anon, authenticated;
-- ---------- Cupones del negocio y tarjeta de sellos (C16): módulos 'cupones' y 'sellos' ----------
-- OJO: no son los cupones del Premium (cfx_cupones / cfx_cupon_ver, los crea el admin). Estos los crea cada negocio para SUS clientes.
-- Ganchos que pone cada app que los usa (y 'cupones' / 'sellos' en cfx_modulos_app()):
--   cfx_fid_dueno(u) uuid                  negocio que administra la cuenta u (null = no es negocio)
--   cfx_fid_activo(negocio, modulo) bool   ¿el plan del negocio incluye ese módulo? (p. ej. solo Pro)
--   cfx_fid_cliente(u, negocio) bool       ¿u es cliente de ese negocio? (ve sus sellos y prueba cupones)
--   cfx_sellos_aviso(negocio, cliente, premio) void   push al cliente que completó la tarjeta
-- La app usa, dentro de sus funciones: cfx_desc_pct + cfx_desc_usar (al crear el pedido), cfx_sello_sumar (al entregar)
-- y cfx_sellos_cfg_de (para mostrar la tarjeta). cfx_fid_borrar al borrar un negocio.
create table if not exists public.cfx_descuentos (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null,
  codigo      text not null check (codigo ~ '^[A-Z0-9]{3,20}$'),
  porcentaje  int not null check (porcentaje between 1 and 90),
  hasta       date,
  activo      boolean not null default true,
  usos        int not null default 0,
  creado      timestamptz not null default now(),
  unique (owner_id, codigo)
);
create table if not exists public.cfx_sellos_cfg (
  owner_id  uuid primary key,
  meta      int not null check (meta between 2 and 30),
  premio    text check (char_length(premio) <= 80),
  creado    timestamptz not null default now()
);
create table if not exists public.cfx_sellos (
  negocio_id  uuid not null,
  cliente_id  uuid not null references auth.users (id) on delete cascade,
  cantidad    int not null default 0,
  premios     int not null default 0,
  actualizado timestamptz not null default now(),
  primary key (negocio_id, cliente_id)
);
create index if not exists cfx_sellos_cliente_idx on public.cfx_sellos (cliente_id);
alter table public.cfx_descuentos enable row level security;
alter table public.cfx_sellos_cfg enable row level security;
alter table public.cfx_sellos enable row level security;
revoke all on public.cfx_descuentos, public.cfx_sellos_cfg, public.cfx_sellos from anon, authenticated;

create or replace function public.cfx_desc_codigo(p_codigo text) returns text
language sql immutable set search_path = '' as $$ select upper(regexp_replace(coalesce(p_codigo, ''), '[^A-Za-z0-9]', '', 'g')) $$;

-- El negocio de la cuenta, si el módulo está prendido y su plan lo incluye.
create or replace function public.cfx_fid_mio(p_modulo text) returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare n uuid;
begin
  if not public.cfx_modulo(p_modulo) then
    raise exception '% no está disponible en esta app', case p_modulo when 'cupones' then 'Los cupones' else 'La tarjeta de sellos' end;
  end if;
  n := public.cfx_fid_dueno(auth.uid());
  if n is null then raise exception 'Solo el negocio'; end if;
  if public.cfx_venta_on() then
    if not public.cfx_modulo_de(p_modulo, n) then
      raise exception '% Actívalo en Ajustes → 🧩 Módulos', case p_modulo when 'cupones' then 'Los cupones son un módulo.' else 'La tarjeta de sellos es un módulo.' end;
    end if;
  elsif not coalesce(public.cfx_fid_activo(n, p_modulo), false) then
    raise exception '% de la versión Pro', case p_modulo when 'cupones' then 'Los cupones son' else 'La tarjeta de sellos es' end;
  end if;
  return n;
end $$;

-- ¿El negocio puede usar el módulo ahora? (prendido + su plan)
create or replace function public.cfx_fid_ok(p_negocio uuid, p_modulo text) returns boolean
language plpgsql stable security definer set search_path = '' as $$
begin
  if p_negocio is null or not public.cfx_modulo(p_modulo) then return false; end if;
  if public.cfx_venta_on() then return public.cfx_modulo_de(p_modulo, p_negocio); end if;
  return coalesce(public.cfx_fid_activo(p_negocio, p_modulo), false);
end $$;

-- ---------- Cupones ----------
create or replace function public.cfx_desc_guardar(p_codigo text, p_porcentaje int, p_hasta date) returns void
language plpgsql security definer set search_path = '' as $$
declare n uuid := public.cfx_fid_mio('cupones'); c text := public.cfx_desc_codigo(p_codigo);
begin
  if length(c) < 3 or length(c) > 20 then raise exception 'El código debe tener entre 3 y 20 letras o números'; end if;
  if p_porcentaje is null or p_porcentaje < 1 or p_porcentaje > 90 then raise exception 'El descuento debe ser entre 1 y 90 por ciento'; end if;
  if (select count(*) from public.cfx_descuentos where owner_id = n) >= 50
     and not exists (select 1 from public.cfx_descuentos where owner_id = n and codigo = c) then raise exception 'Máximo 50 cupones'; end if;
  insert into public.cfx_descuentos (owner_id, codigo, porcentaje, hasta) values (n, c, p_porcentaje, p_hasta)
  on conflict (owner_id, codigo) do update set porcentaje = excluded.porcentaje, hasta = excluded.hasta, activo = true;
end $$;

create or replace function public.cfx_desc_borrar(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.cfx_descuentos where id = p_id and owner_id = public.cfx_fid_dueno(auth.uid());
end $$;

-- Mis cupones: [{id, codigo, porcentaje, hasta, activo, usos}]
create or replace function public.cfx_desc_lista() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare n uuid := public.cfx_fid_mio('cupones');
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'codigo', c.codigo, 'porcentaje', c.porcentaje, 'hasta', c.hasta,
    'activo', c.activo, 'usos', c.usos) order by c.creado desc) from public.cfx_descuentos c where c.owner_id = n), '[]');
end $$;

-- Porcentaje de un cupón vigente (null = no sirve). Interna: la app la usa al armar el pedido.
create or replace function public.cfx_desc_pct(p_negocio uuid, p_codigo text) returns int
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.cfx_fid_ok(p_negocio, 'cupones') then return null; end if;
  return (select c.porcentaje from public.cfx_descuentos c
          where c.owner_id = p_negocio and c.codigo = public.cfx_desc_codigo(p_codigo) and c.activo and (c.hasta is null or c.hasta >= current_date));
end $$;

-- Suma un uso (la app la llama cuando el pedido ya quedó guardado).
create or replace function public.cfx_desc_usar(p_negocio uuid, p_codigo text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.cfx_descuentos set usos = usos + 1 where owner_id = p_negocio and codigo = public.cfx_desc_codigo(p_codigo);
end $$;

-- El cliente prueba un cupón: devuelve el porcentaje o avisa que no sirve.
create or replace function public.cfx_desc_validar(p_negocio uuid, p_codigo text) returns int
language plpgsql stable security definer set search_path = '' as $$
declare pct int;
begin
  if not public.cfx_modulo('cupones') then raise exception 'Cupón no válido o vencido'; end if;
  if not coalesce(public.cfx_fid_cliente(auth.uid(), p_negocio), false) then raise exception 'Sin permiso'; end if;
  pct := public.cfx_desc_pct(p_negocio, p_codigo);
  if pct is null then raise exception 'Cupón no válido o vencido'; end if;
  return pct;
end $$;

-- ---------- Tarjeta de sellos ----------
-- El negocio la arma (meta 2-30 y premio) o la apaga (meta null).
create or replace function public.cfx_sellos_guardar(p_meta int, p_premio text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n uuid;
begin
  if p_meta is null then
    n := public.cfx_fid_dueno(auth.uid());
    if n is null then raise exception 'Solo el negocio'; end if;
    delete from public.cfx_sellos_cfg where owner_id = n;
    return null;
  end if;
  n := public.cfx_fid_mio('sellos');
  if p_meta < 2 or p_meta > 30 then raise exception 'La tarjeta debe tener entre 2 y 30 sellos'; end if;
  insert into public.cfx_sellos_cfg (owner_id, meta, premio) values (n, p_meta, nullif(left(trim(coalesce(p_premio, '')), 80), ''))
  on conflict (owner_id) do update set meta = excluded.meta, premio = excluded.premio;
  return public.cfx_sellos_cfg_de(n);
end $$;

-- La tarjeta del negocio {meta, premio} (null = no tiene, módulo apagado o su plan no la incluye).
create or replace function public.cfx_sellos_cfg_de(p_negocio uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.cfx_fid_ok(p_negocio, 'sellos') then return null; end if;
  return (select jsonb_build_object('meta', c.meta, 'premio', c.premio) from public.cfx_sellos_cfg c where c.owner_id = p_negocio);
end $$;

-- Mis sellos en un negocio: {cantidad, premios, meta, premio} o null.
create or replace function public.cfx_sellos_mios(p_negocio uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare c jsonb := public.cfx_sellos_cfg_de(p_negocio);
begin
  if c is null then return null; end if;
  if not coalesce(public.cfx_fid_cliente(auth.uid(), p_negocio), false) then return null; end if;
  return c || coalesce((select jsonb_build_object('cantidad', s.cantidad, 'premios', s.premios) from public.cfx_sellos s
                        where s.negocio_id = p_negocio and s.cliente_id = auth.uid()), jsonb_build_object('cantidad', 0, 'premios', 0));
end $$;

-- Suma un sello (al entregar una compra). Al llegar a la meta: vuelve a 0, suma un premio y avisa. Devuelve {cantidad, premio} o null.
create or replace function public.cfx_sello_sumar(p_negocio uuid, p_cliente uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare c jsonb := public.cfx_sellos_cfg_de(p_negocio); s public.cfx_sellos;
begin
  if c is null or p_cliente is null then return null; end if;
  insert into public.cfx_sellos (negocio_id, cliente_id, cantidad) values (p_negocio, p_cliente, 1)
  on conflict (negocio_id, cliente_id) do update set cantidad = public.cfx_sellos.cantidad + 1, actualizado = now() returning * into s;
  if s.cantidad >= (c ->> 'meta')::int then
    update public.cfx_sellos set cantidad = 0, premios = premios + 1 where negocio_id = p_negocio and cliente_id = p_cliente;
    perform public.cfx_sellos_aviso(p_negocio, p_cliente, c ->> 'premio');
    return jsonb_build_object('cantidad', 0, 'premio', true);
  end if;
  return jsonb_build_object('cantidad', s.cantidad, 'premio', false);
end $$;

-- Al borrar un negocio (lo llama la app): sus cupones, su tarjeta y los sellos de sus clientes.
create or replace function public.cfx_fid_borrar(p_negocio uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.cfx_descuentos where owner_id = p_negocio;
  delete from public.cfx_sellos_cfg where owner_id = p_negocio;
  delete from public.cfx_sellos where negocio_id = p_negocio;
end $$;

revoke all on function public.cfx_desc_codigo(text), public.cfx_fid_mio(text), public.cfx_fid_ok(uuid, text), public.cfx_desc_pct(uuid, text),
  public.cfx_desc_usar(uuid, text), public.cfx_sellos_cfg_de(uuid), public.cfx_sello_sumar(uuid, uuid), public.cfx_fid_borrar(uuid)
  from public, anon, authenticated;
revoke all on function public.cfx_desc_guardar(text, int, date), public.cfx_desc_borrar(uuid), public.cfx_desc_lista(), public.cfx_desc_validar(uuid, text),
  public.cfx_sellos_guardar(int, text), public.cfx_sellos_mios(uuid) from public, anon;
grant execute on function public.cfx_desc_guardar(text, int, date), public.cfx_desc_borrar(uuid), public.cfx_desc_lista(), public.cfx_desc_validar(uuid, text),
  public.cfx_sellos_guardar(int, text), public.cfx_sellos_mios(uuid) to authenticated;
-- ---------- 🛒 Carrito y 🚚 despacho (C17) ----------
-- Carrito guardado en la nube (para recordarle al cliente lo que dejó) y el cálculo del despacho por comuna y al resto de Chile (2.58).
-- Ganchos que pone cada app que lo usa (y 'carrito' en cfx_modulos_app() para el recordatorio):
--   cfx_carrito_puede(u, negocio) bool           ¿u puede guardar carrito en ese negocio? (es su cliente, puede comprar)
--   cfx_carrito_aviso(cliente, negocio, n) bool  manda el recordatorio (push); false = no corresponde (plan, vacaciones…)
-- La app usa: cfx_carrito_vaciar (al crear el pedido), cfx_carritos_recordar (pg_cron, cada hora), cfx_carrito_borrar (al borrar una cuenta).
-- Despacho (sin tabla: cada app guarda su { retiro, gratis_desde, zonas: [{comuna, precio}] } donde quiera):
--   cfx_despacho_limpio(p) → la misma config revisada (o error claro) · cfx_despacho_costo(cfg, entrega, direccion, monto) → {costo, comuna} o {error}
create table if not exists public.cfx_carritos (
  cliente     uuid not null references auth.users (id) on delete cascade,
  negocio     uuid not null,
  items       jsonb not null default '[]'::jsonb,
  actualizado timestamptz not null default now(),
  avisado     timestamptz,
  primary key (cliente, negocio)
);
create index if not exists cfx_carritos_negocio_idx on public.cfx_carritos (negocio);
create index if not exists cfx_carritos_aviso_idx on public.cfx_carritos (actualizado) where avisado is null;
alter table public.cfx_carritos enable row level security;
revoke all on public.cfx_carritos from anon, authenticated;

-- El cliente guarda su carrito (hasta 50 productos). Vacío = se borra.
create or replace function public.cfx_carrito_guardar(p_negocio uuid, p_items jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare l jsonb := '[]'::jsonb; it jsonb; ok boolean := false;
begin
  if auth.uid() is null or p_negocio is null or to_regprocedure('public.cfx_carrito_puede(uuid,uuid)') is null then return; end if;
  execute 'select public.cfx_carrito_puede($1, $2)' into ok using auth.uid(), p_negocio;
  if not coalesce(ok, false) or jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array' then return; end if;
  for it in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) limit 50 loop
    continue when jsonb_typeof(it) <> 'object' or coalesce(it ->> 'clave', '') = '';
    l := l || jsonb_build_object('clave', left(it ->> 'clave', 60), 'cant', least(greatest(coalesce((it ->> 'cant')::int, 1), 1), 99), 'nombre', left(it ->> 'nombre', 80));
  end loop;
  if jsonb_array_length(l) = 0 then
    delete from public.cfx_carritos where cliente = auth.uid() and negocio = p_negocio;
  else
    insert into public.cfx_carritos (cliente, negocio, items) values (auth.uid(), p_negocio, l)
    on conflict (cliente, negocio) do update set items = excluded.items, actualizado = now(), avisado = null
      where public.cfx_carritos.items is distinct from excluded.items;
  end if;
end $$;

create or replace function public.cfx_carrito_vaciar(p_cliente uuid, p_negocio uuid) returns void
language sql security definer set search_path = '' as $$ delete from public.cfx_carritos where cliente = p_cliente and negocio = p_negocio $$;
create or replace function public.cfx_carrito_borrar(p_cuenta uuid) returns void
language sql security definer set search_path = '' as $$ delete from public.cfx_carritos where cliente = p_cuenta or negocio = p_cuenta $$;

-- Cada hora: carritos sin pedir de hace más de 20 horas (y menos de 4 días) reciben UN aviso, de 10 a 20 h de Chile.
create or replace function public.cfx_carritos_recordar() returns int
language plpgsql security definer set search_path = '' as $$
declare r record; n int := 0; ok boolean; h int := extract(hour from now() at time zone 'America/Santiago');
begin
  if h < 10 or h > 20 or not public.cfx_modulo('carrito') or to_regprocedure('public.cfx_carrito_aviso(uuid,uuid,integer)') is null then return 0; end if;
  for r in select * from public.cfx_carritos where avisado is null and actualizado < now() - interval '20 hours' and actualizado > now() - interval '4 days' limit 500 loop
    if not public.cfx_modulo_de('carrito', r.negocio) then  -- G19: la tienda no tiene el módulo (no se vuelve a revisar)
      update public.cfx_carritos set avisado = now() where cliente = r.cliente and negocio = r.negocio; continue;
    end if;
    execute 'select public.cfx_carrito_aviso($1, $2, $3)' into ok using r.cliente, r.negocio, jsonb_array_length(r.items);
    update public.cfx_carritos set avisado = now() where cliente = r.cliente and negocio = r.negocio;
    if coalesce(ok, false) then n := n + 1; end if;
  end loop;
  return n;
end $$;

-- ---------- Despacho por comuna ----------
create or replace function public.cfx_comuna_norm(t text) returns text
language sql immutable set search_path = '' as $$ select lower(trim(translate(coalesce(t, ''), 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun'))) $$;

create or replace function public.cfx_despacho_limpio(p jsonb) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare z jsonb; l jsonb := '[]'::jsonb; vistas text[] := '{}'; rm text;
begin
  if jsonb_typeof(p) is distinct from 'object' then raise exception 'Datos no válidos'; end if;
  for z in select * from jsonb_array_elements(case when jsonb_typeof(p -> 'zonas') = 'array' then p -> 'zonas' else '[]'::jsonb end) loop
    if coalesce(trim(z ->> 'comuna'), '') = '' then continue; end if;
    if length(z ->> 'comuna') > 40 then raise exception 'Nombre de comuna muy largo'; end if;
    if coalesce((z ->> 'precio')::numeric, -1) not between 0 and 200000 then raise exception 'El despacho a % debe costar entre $0 y $200.000', z ->> 'comuna'; end if;
    if public.cfx_comuna_norm(z ->> 'comuna') = any (vistas) then raise exception 'La comuna % está repetida', z ->> 'comuna'; end if;
    vistas := vistas || public.cfx_comuna_norm(z ->> 'comuna');
    l := l || jsonb_build_object('comuna', trim(z ->> 'comuna'), 'precio', round((z ->> 'precio')::numeric));
  end loop;
  if jsonb_array_length(l) > 80 then raise exception 'Máximo 80 comunas'; end if;
  -- Resto de Chile (regiones y comunas que no están en la lista): 'no' | 'fijo' (un precio) | 'por_pagar' (lo paga quien recibe al courier).
  -- G102 b 'courier' = la app cotiza con el courier (Despega: Chilexpress); precio = respaldo si el courier no responde (0 = por pagar).
  rm := coalesce(nullif(p #>> '{resto,modo}', ''), 'no');
  if rm not in ('no', 'fijo', 'por_pagar', 'courier') then raise exception 'Elige cómo despachas al resto de Chile'; end if;
  if rm = 'fijo' and coalesce((p #>> '{resto,precio}')::numeric, -1) not between 0 and 200000 then raise exception 'El despacho al resto de Chile debe costar entre $0 y $200.000'; end if;
  if rm = 'courier' and coalesce((p #>> '{resto,precio}')::numeric, 0) not between 0 and 200000 then raise exception 'El precio de respaldo debe ser entre $0 y $200.000'; end if;
  if not coalesce((p ->> 'retiro')::boolean, true) and jsonb_array_length(l) = 0 and rm = 'no' then raise exception 'Activa el retiro en tienda o agrega al menos una comuna de despacho'; end if;
  if coalesce((p ->> 'gratis_desde')::numeric, 0) not between 0 and 10000000 then raise exception 'Monto de despacho gratis no válido'; end if;
  return jsonb_build_object('retiro', coalesce((p ->> 'retiro')::boolean, true), 'gratis_desde', round(coalesce((p ->> 'gratis_desde')::numeric, 0)), 'zonas', l,
    'resto', jsonb_build_object('modo', rm, 'precio', case when rm in ('fijo', 'courier') then round(coalesce((p #>> '{resto,precio}')::numeric, 0)) else 0 end));
end $$;

-- La comuna va al final de la dirección ("…, Ñuñoa"). Sin zonas ni resto de Chile: se coordina con el negocio ($0 aquí).
-- Comuna fuera de la lista: con resto 'fijo' cobra ese precio; con 'por_pagar' $0 y por_pagar = true (lo paga quien recibe); con 'courier' la app cotiza (G102 b).
create or replace function public.cfx_despacho_costo(p_cfg jsonb, p_entrega text, p_direccion text, p_monto numeric) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare c jsonb := coalesce(p_cfg, '{}'::jsonb); com text; z jsonb; rm text := coalesce(nullif(p_cfg #>> '{resto,modo}', ''), 'no'); orig text;
  gratis boolean := coalesce((p_cfg ->> 'gratis_desde')::numeric, 0) > 0 and p_monto >= (p_cfg ->> 'gratis_desde')::numeric;
begin
  if p_entrega is distinct from 'despacho' or (jsonb_array_length(coalesce(c -> 'zonas', '[]'::jsonb)) = 0 and rm = 'no') then return jsonb_build_object('costo', 0, 'comuna', null); end if;
  orig := left(trim(regexp_replace(coalesce(p_direccion, ''), '^.*,', '')), 60);
  com := public.cfx_comuna_norm(orig);
  select e into z from jsonb_array_elements(coalesce(c -> 'zonas', '[]'::jsonb)) e where public.cfx_comuna_norm(e ->> 'comuna') = com limit 1;
  if z is null then
    if com = '' or position(',' in coalesce(p_direccion, '')) = 0 then return jsonb_build_object('error', 'Escribe la dirección y la comuna de despacho'); end if;
    if rm = 'fijo' then return jsonb_build_object('comuna', orig, 'costo', case when gratis then 0 else greatest(0, coalesce((c #>> '{resto,precio}')::numeric, 0)) end); end if;
    if rm = 'por_pagar' then return jsonb_build_object('comuna', orig, 'costo', 0, 'por_pagar', true); end if;
    -- 'courier': la app reemplaza el costo con la tarifa (cotizar = true). Si la app no cotiza, vale el respaldo (o por pagar si es $0).
    if rm = 'courier' then return jsonb_build_object('comuna', orig, 'cotizar', not gratis, 'respaldo', greatest(0, coalesce((c #>> '{resto,precio}')::numeric, 0)),
      'costo', case when gratis then 0 else greatest(0, coalesce((c #>> '{resto,precio}')::numeric, 0)) end,
      'por_pagar', not gratis and coalesce((c #>> '{resto,precio}')::numeric, 0) = 0); end if;
    return jsonb_build_object('error', 'Esta tienda no despacha a esa comuna. Elige otra comuna o retiro en tienda.');
  end if;
  return jsonb_build_object('comuna', z ->> 'comuna', 'costo', case when gratis then 0 else greatest(0, coalesce((z ->> 'precio')::numeric, 0)) end);
end $$;

-- G96 🛒 Carritos olvidados (módulo 'carrito'): el negocio ve quién dejó productos sin pedir y le escribe por WhatsApp con un toque.
-- Gancho de la app: cfx_carrito_contacto_app(cliente uuid, negocio uuid) → {"nombre", "tel"} (null = no mostrar a ese cliente).
alter table public.cfx_carritos add column if not exists wa_at timestamptz;
create or replace function public.cfx_carritos_mios() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare n uuid := public.cfx_negocio_cuenta(auth.uid()); r record; c jsonb; out jsonb := '[]'::jsonb;
begin
  if n is null then raise exception 'Solo para negocios'; end if;
  if not public.cfx_modulo_de('carrito', n) then raise exception '🛒 Recordar carrito es un módulo 🧩: actívalo en Más → Mi plan y módulos'; end if;
  if to_regprocedure('public.cfx_carrito_contacto_app(uuid,uuid)') is null then return out; end if;
  for r in select * from public.cfx_carritos where negocio = n and actualizado > now() - interval '14 days' order by actualizado desc limit 100 loop
    execute 'select public.cfx_carrito_contacto_app($1, $2)' into c using r.cliente, n;
    continue when c is null;
    out := out || jsonb_build_object('cliente', r.cliente, 'nombre', c ->> 'nombre', 'tel', c ->> 'tel', 'items', r.items,
      'actualizado', r.actualizado, 'avisado', r.avisado, 'wa_at', r.wa_at);
  end loop;
  return out;
end $$;
-- Al tocar 💬 WhatsApp queda anotado (para no escribirle dos veces).
create or replace function public.cfx_carrito_wa(p_cliente uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare n uuid := public.cfx_negocio_cuenta(auth.uid());
begin
  if n is null or not public.cfx_modulo_de('carrito', n) then raise exception 'Sin permiso'; end if;
  update public.cfx_carritos set wa_at = now() where negocio = n and cliente = p_cliente;
end $$;
revoke all on function public.cfx_carritos_mios(), public.cfx_carrito_wa(uuid) from public, anon;
grant execute on function public.cfx_carritos_mios(), public.cfx_carrito_wa(uuid) to authenticated;
revoke all on function public.cfx_carrito_vaciar(uuid, uuid), public.cfx_carrito_borrar(uuid), public.cfx_carritos_recordar(), public.cfx_comuna_norm(text),
  public.cfx_despacho_limpio(jsonb), public.cfx_despacho_costo(jsonb, text, text, numeric) from public, anon, authenticated;
revoke all on function public.cfx_carrito_guardar(uuid, jsonb) from public, anon;
grant execute on function public.cfx_carrito_guardar(uuid, jsonb) to authenticated;
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'cfx-carritos';
  perform cron.schedule('cfx-carritos', '23 * * * *', 'select public.cfx_carritos_recordar()');
exception when others then
  raise notice 'Recordatorio de carritos no programado (%).', sqlerrm;
end $$;
-- ---------- 🧹 Limpieza (C18): una sola lista para el Centro de Mando → Mis aplicaciones → ↻ → 🧹 Respaldo y limpieza ----------
-- Lo del núcleo (claves "n_…") se borra solo cada noche si la limpieza automática está prendida (por defecto sí).
-- Lo propio de cada app viene del gancho cfx_limpieza_app() → [{clave, titulo, detalle, filas}] y cfx_limpiar_app(clave) → int
-- (la app ya lo borra sola con su propio horario; aquí se puede borrar a mano).
create index if not exists cfx_registro_creado_idx on public.cfx_registro (creado);
create index if not exists cfx_errores_ultimo_idx on public.cfx_errores (ultimo);
insert into public.cfx_config (clave, valor) values ('limpieza_auto', 'true') on conflict (clave) do nothing;

create or replace function public.cfx_limpieza_nucleo() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  return jsonb_build_array(
    jsonb_build_object('clave', 'n_registro', 'titulo', 'Registro de cambios', 'detalle', 'Más de 180 días.', 'auto', true,
      'filas', (select count(*) from public.cfx_registro where creado < now() - interval '180 days')),
    jsonb_build_object('clave', 'n_errores', 'titulo', 'Errores de la app', 'detalle', 'Sin repetirse hace más de 30 días.', 'auto', true,
      'filas', (select count(*) from public.cfx_errores where ultimo < now() - interval '30 days')),
    jsonb_build_object('clave', 'n_reportes', 'titulo', 'Reportes del chat ya revisados', 'detalle', 'Más de 90 días.', 'auto', true,
      'filas', (select count(*) from public.cfx_reportes where resuelto and creado < now() - interval '90 days')),
    jsonb_build_object('clave', 'n_carritos', 'titulo', 'Carritos abandonados', 'detalle', 'Sin tocar hace más de 30 días.', 'auto', true,
      'filas', (select count(*) from public.cfx_carritos where actualizado < now() - interval '30 days')));
end $$;

create or replace function public.cfx_limpiar_nucleo(p_clave text) returns int
language plpgsql security definer set search_path = '' as $$
declare n int := 0;
begin
  if p_clave = 'n_registro' then delete from public.cfx_registro where creado < now() - interval '180 days';
  elsif p_clave = 'n_errores' then delete from public.cfx_errores where ultimo < now() - interval '30 days';
  elsif p_clave = 'n_reportes' then delete from public.cfx_reportes where resuelto and creado < now() - interval '90 days';
  elsif p_clave = 'n_carritos' then delete from public.cfx_carritos where actualizado < now() - interval '30 days';
  else return 0; end if;
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.cfx_limpieza() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare a jsonb := '[]';
begin
  perform privado.solo_admin();
  if to_regprocedure('public.cfx_limpieza_app()') is not null then
    execute 'select public.cfx_limpieza_app()' into a;
  end if;
  return public.cfx_limpieza_nucleo() || coalesce(a, '[]');
end $$;

create or replace function public.cfx_limpiar(p_clave text) returns int
language plpgsql security definer set search_path = '' as $$
declare n int := 0;
begin
  perform privado.solo_admin();
  if p_clave like 'n\_%' then
    if not exists (select 1 from jsonb_array_elements(public.cfx_limpieza_nucleo()) x where x ->> 'clave' = p_clave) then raise exception 'Opción no válida'; end if;
    n := public.cfx_limpiar_nucleo(p_clave);
  elsif to_regprocedure('public.cfx_limpiar_app(text)') is not null then
    execute 'select public.cfx_limpiar_app($1)' into n using p_clave;
  else raise exception 'Opción no válida'; end if;
  perform public.cfx_anotar('limpieza', p_clave || ': ' || coalesce(n, 0) || ' borrados');
  return coalesce(n, 0);
end $$;

-- Cada noche (pg_cron 'cfx-limpieza'): borra lo del núcleo marcado "auto" y anota cuánto.
create or replace function public.cfx_limpieza_auto() returns int
language plpgsql security definer set search_path = '' as $$
declare x jsonb; n int := 0;
begin
  if not coalesce(((select valor from public.cfx_config where clave = 'limpieza_auto') #>> '{}')::boolean, true) then return 0; end if;
  for x in select * from jsonb_array_elements(public.cfx_limpieza_nucleo()) loop
    if (x ->> 'auto')::boolean and (x ->> 'filas')::int > 0 then n := n + public.cfx_limpiar_nucleo(x ->> 'clave'); end if;
  end loop;
  insert into public.cfx_salud (clave, valor, cuando) values ('limpieza', jsonb_build_object('filas', n), now())
  on conflict (clave) do update set valor = excluded.valor, cuando = excluded.cuando;
  if n > 0 then perform public.cfx_anotar('limpieza automática', n || ' filas viejas borradas'); end if;
  return n;
end $$;

-- Interruptor del Centro de Mando: { activo, ultima, filas }.
create or replace function public.cfx_limpieza_auto_ver() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  return jsonb_build_object('activo', coalesce(((select valor from public.cfx_config where clave = 'limpieza_auto') #>> '{}')::boolean, true),
    'ultima', (select cuando from public.cfx_salud where clave = 'limpieza'), 'filas', (select (valor ->> 'filas')::int from public.cfx_salud where clave = 'limpieza'));
end $$;
create or replace function public.cfx_limpieza_auto_guardar(p_activo boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  insert into public.cfx_config (clave, valor) values ('limpieza_auto', to_jsonb(coalesce(p_activo, true)))
  on conflict (clave) do update set valor = excluded.valor;
  perform public.cfx_anotar('limpieza automática', case when coalesce(p_activo, true) then 'prendida' else 'apagada' end);
  return public.cfx_limpieza_auto_ver();
end $$;

revoke all on function public.cfx_limpieza_nucleo(), public.cfx_limpiar_nucleo(text), public.cfx_limpieza_auto() from public, anon, authenticated;
revoke all on function public.cfx_limpieza(), public.cfx_limpiar(text), public.cfx_limpieza_auto_ver(), public.cfx_limpieza_auto_guardar(boolean) from public, anon;
grant execute on function public.cfx_limpieza(), public.cfx_limpiar(text), public.cfx_limpieza_auto_ver(), public.cfx_limpieza_auto_guardar(boolean) to authenticated;
do $$
begin
  if to_regprocedure('public.cfx_limpieza_app()') is not null then revoke all on function public.cfx_limpieza_app() from public, anon, authenticated; end if;
  if to_regprocedure('public.cfx_limpiar_app(text)') is not null then revoke all on function public.cfx_limpiar_app(text) from public, anon, authenticated; end if;
end $$;
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'cfx-limpieza';
  perform cron.schedule('cfx-limpieza', '40 7 * * *', 'select public.cfx_limpieza_auto()');
exception when others then
  raise notice 'Limpieza automática no programada (%).', sqlerrm;
end $$;

-- ---------- Analítica (E24 · E25 · E27): el análisis nocturno lo hace Python en GitHub Actions (SaaS: analisis.yml + analisis/analisis.py) ----------
-- 1) Python lee cfx_analisis_datos() con la conexión del respaldo (solo la base: nadie con cuenta puede llamarla).
-- 2) Calcula tendencias de la app (CM → 📊 Analítica) y, por negocio, clientes que dejaron de comprar y productos quietos (E27).
-- 3) Lo devuelve con cfx_analisis_guardar(): una fila 'app' y una por negocio en cfx_analisis.
-- Ganchos de cada app (opcionales; sin ellos hay solo números generales):
--   cfx_analisis_datos_app() → {ventas: [{n, c, f, m, l: [[clave, cant]]}], clientes: {c: {nombre, tel}}, productos: [{n, k, nombre, stock, creado}],
--                               negocios: [{id, nombre, creado, ingreso}]}
--   cfx_analisis_negocio(u) → uuid del negocio que ve ese usuario (null: ninguno). Módulo 'analisis' (🧩 en el CM).
create table if not exists public.cfx_analisis (clave text primary key, datos jsonb not null default '{}', calculado timestamptz not null default now());
alter table public.cfx_analisis enable row level security;
revoke all on public.cfx_analisis from anon, authenticated;

create or replace function public.cfx_analisis_datos() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare a jsonb; d date := (now() at time zone 'America/Santiago')::date;
begin
  if to_regprocedure('public.cfx_analisis_datos_app()') is not null then execute 'select public.cfx_analisis_datos_app()' into a; end if;
  return jsonb_build_object('hoy', d, 'modulo', public.cfx_modulo('analisis'),
    'usuarios', (select jsonb_build_object('total', count(*),
        'activos7', count(*) filter (where last_sign_in_at > now() - interval '7 days'),
        'activos30', count(*) filter (where last_sign_in_at > now() - interval '30 days'),
        'dias', coalesce((select jsonb_object_agg(x.f, x.n) from (select (created_at at time zone 'America/Santiago')::date f, count(*) n from auth.users
          where created_at > now() - interval '61 days' and deleted_at is null group by 1) x), '{}'))
      from auth.users where deleted_at is null),
    'ingresos', coalesce((select jsonb_object_agg(x.f, x.m) from (select (coalesce(resuelto, creado) at time zone 'America/Santiago')::date f, sum(monto) m
      from public.cfx_pagos where estado = 'aprobado' and coalesce(resuelto, creado) > now() - interval '61 days' and coalesce(resuelto, creado) >= public.cfx_ingresos_desde() group by 1) x), '{}'),
    'premium', (select count(distinct cuenta) from public.cfx_pagos where estado = 'aprobado' and coalesce(resuelto, creado) > now() - interval '30 days'),
    'previo', coalesce((select jsonb_object_agg(clave, datos -> 'mov') from public.cfx_analisis where clave <> 'app' and datos ? 'mov'), '{}'),
    'app', a);
end $$;

create or replace function public.cfx_analisis_guardar(p jsonb) returns int
language plpgsql security definer set search_path = '' as $$
declare n int := 0; k text; v jsonb;
begin
  if jsonb_typeof(p -> 'app') = 'object' then
    insert into public.cfx_analisis (clave, datos, calculado) values ('app', p -> 'app', now())
    on conflict (clave) do update set datos = excluded.datos, calculado = now();
  end if;
  delete from public.cfx_analisis where clave <> 'app' and not (coalesce(p -> 'negocios', '{}') ? clave);
  for k, v in select * from jsonb_each(coalesce(p -> 'negocios', '{}')) loop
    insert into public.cfx_analisis (clave, datos, calculado) values (k, v, now())
    on conflict (clave) do update set datos = excluded.datos, calculado = now();
    n := n + 1;
  end loop;
  perform public.cfx_salud_marca('analisis', jsonb_build_object('negocios', n, 'run', coalesce(p ->> 'run', '')));
  return n;
end $$;
revoke all on function public.cfx_analisis_datos(), public.cfx_analisis_guardar(jsonb) from public, anon, authenticated;

-- Centro de Mando → 📊 Analítica.
create or replace function public.cfx_analisis_app() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  return (select datos || jsonb_build_object('calculado', calculado) from public.cfx_analisis where clave = 'app');
end $$;
revoke all on function public.cfx_analisis_app() from public, anon;
grant execute on function public.cfx_analisis_app() to authenticated;

-- Para el negocio (E27): sus clientes en riesgo y productos quietos (sin la foto interna del stock).
create or replace function public.cfx_analisis_mio() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare n uuid;
begin
  if auth.uid() is null or not public.cfx_modulo('analisis') or to_regprocedure('public.cfx_analisis_negocio(uuid)') is null then return null; end if;
  execute 'select public.cfx_analisis_negocio($1)' into n using auth.uid();
  if n is null or not public.cfx_modulo_de('analisis', n) then return null; end if;
  return (select (datos - 'mov') || jsonb_build_object('calculado', calculado) from public.cfx_analisis where clave = n::text);
end $$;
revoke all on function public.cfx_analisis_mio() from public, anon;
grant execute on function public.cfx_analisis_mio() to authenticated;

-- ---------- G32 d · 🔑 Entrar con QR (núcleo): el celular con sesión aprueba y el computador entra sin escribir la clave ----------
-- 1) El computador (sin cuenta) pide un código: cfx_qr_crear → { token (va en el QR), codigo (6 letras para escribir), secreto (solo el PC) }.
-- 2) El celular con sesión lo abre o lo escribe: cfx_qr_ver muestra qué computador es → "Sí, entrar" = cfx_qr_aprobar.
-- 3) El computador pregunta cada 2 s (cfx_qr_estado). Aprobado → la Edge Function (clave de servidor) canjea UNA vez (cfx_qr_canjear)
--    y devuelve un enlace mágico de un solo uso; el computador lo usa y queda con sesión. Vence a los 2 minutos.
create table if not exists public.cfx_login_qr (
  token       text primary key,
  codigo      text not null,
  secreto     text not null,              -- sha256 del secreto (el secreto real solo lo tiene el computador)
  equipo      text,
  user_id     uuid references auth.users(id) on delete cascade,
  aprobado_at timestamptz,
  usado_at    timestamptz,
  created_at  timestamptz not null default now()
);
create index if not exists cfx_login_qr_codigo on public.cfx_login_qr (codigo);
alter table public.cfx_login_qr enable row level security;
revoke all on public.cfx_login_qr from anon, authenticated;

create or replace function public.cfx_qr_crear(p_equipo text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare t text; c text; s text; L text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; b bytea; i int;
begin
  delete from public.cfx_login_qr where created_at < now() - interval '10 minutes';
  if (select count(*) from public.cfx_login_qr where created_at > now() - interval '2 minutes') > 300 then
    return jsonb_build_object('ok', false, 'error', 'Muchos intentos. Espera un minuto.');
  end if;
  t := encode(extensions.gen_random_bytes(18), 'hex');
  s := encode(extensions.gen_random_bytes(24), 'hex');
  loop
    b := extensions.gen_random_bytes(6); c := '';
    for i in 0..5 loop c := c || substr(L, 1 + get_byte(b, i) % length(L), 1); end loop;
    exit when not exists (select 1 from public.cfx_login_qr where codigo = c and usado_at is null);
  end loop;
  insert into public.cfx_login_qr (token, codigo, secreto, equipo)
  values (t, c, encode(extensions.digest(s, 'sha256'), 'hex'), left(nullif(regexp_replace(coalesce(p_equipo, ''), '[^[:alnum:] ·.()-]', '', 'g'), ''), 60));
  return jsonb_build_object('ok', true, 'token', t, 'codigo', c, 'secreto', s, 'vence', 120);
end $$;
grant execute on function public.cfx_qr_crear(text) to anon, authenticated;

-- p = token del QR o el código de 6 letras. Solo códigos de menos de 2 minutos, sin aprobar.
create or replace function public.cfx_qr_buscar(p text) returns public.cfx_login_qr
language sql stable security definer set search_path = '' as $$
  select * from public.cfx_login_qr
  where (token = lower(trim(p)) or codigo = upper(regexp_replace(coalesce(p, ''), '[^A-Za-z0-9]', '', 'g')))
    and created_at > now() - interval '2 minutes' and aprobado_at is null and usado_at is null
  order by created_at desc limit 1 $$;
revoke all on function public.cfx_qr_buscar(text) from public, anon, authenticated;

create or replace function public.cfx_qr_ver(p text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare q public.cfx_login_qr := public.cfx_qr_buscar(p);
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Primero inicia sesión en este celular'); end if;
  if q.token is null then return jsonb_build_object('ok', false, 'error', 'El código venció o no existe. En el computador toca "Otro código".'); end if;
  return jsonb_build_object('ok', true, 'equipo', coalesce(q.equipo, 'Computador'),
    'segundos', greatest(0, 120 - extract(epoch from now() - q.created_at)::int));
end $$;
revoke all on function public.cfx_qr_ver(text) from public, anon;
grant execute on function public.cfx_qr_ver(text) to authenticated;

-- El computador pregunta: esperando | aprobado | vencido (con su secreto: nadie más puede preguntar).
create or replace function public.cfx_qr_estado(p_token text, p_secreto text) returns text
language sql stable security definer set search_path = '' as $$
  select coalesce((select case when usado_at is not null then 'vencido'
                               when aprobado_at is not null and aprobado_at > now() - interval '2 minutes' then 'aprobado'
                               when aprobado_at is null and created_at > now() - interval '2 minutes' then 'esperando'
                               else 'vencido' end
    from public.cfx_login_qr where token = p_token and secreto = encode(extensions.digest(coalesce(p_secreto, ''), 'sha256'), 'hex')), 'vencido') $$;
grant execute on function public.cfx_qr_estado(text, text) to anon, authenticated;


-- ---------- G32 f · 🔒 3 claves malas: no se bloquea la cuenta, solo la clave y el QR; se entra con el enlace al correo (gratis) ----------
-- Se cuenta por correo (exista o no la cuenta: no revela nada). Al entrar con el enlace (amr otp/magiclink) se desbloquea.
create table if not exists public.cfx_login_fallos (
  email      text primary key,
  fallos     int not null default 0,
  updated_at timestamptz not null default now()
);
alter table public.cfx_login_fallos enable row level security;
revoke all on public.cfx_login_fallos from anon, authenticated;

create or replace function public.cfx_login_bloqueado(p_email text) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select fallos >= 3 from public.cfx_login_fallos where email = lower(trim(coalesce(p_email, '')))), false) $$;
grant execute on function public.cfx_login_bloqueado(text) to anon, authenticated;

-- Clave mala → suma 1 y responde si quedó bloqueada (y cuántos intentos quedan).
create or replace function public.cfx_login_fallo(p_email text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare e text := lower(trim(coalesce(p_email, ''))); n int;
begin
  if e !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return jsonb_build_object('ok', false); end if;
  delete from public.cfx_login_fallos where updated_at < now() - interval '30 days';
  insert into public.cfx_login_fallos (email, fallos) values (e, 1)
  on conflict (email) do update set fallos = least(public.cfx_login_fallos.fallos + 1, 99), updated_at = now()
  returning fallos into n;
  return jsonb_build_object('ok', true, 'bloqueado', n >= 3, 'quedan', greatest(0, 3 - n));
end $$;
grant execute on function public.cfx_login_fallo(text) to anon, authenticated;

-- Con sesión: clave correcta (sin bloqueo) o entró por el enlace del correo → contador a cero. 'estaba' = venía bloqueada (ofrecer cambiar la clave).
create or replace function public.cfx_login_desbloquear() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare e text := lower(coalesce(auth.jwt() ->> 'email', '')); f int; enlace boolean;
begin
  if auth.uid() is null or e = '' then return jsonb_build_object('ok', false); end if;
  enlace := exists (select 1 from jsonb_array_elements(coalesce(auth.jwt() -> 'amr', '[]'::jsonb)) a where a ->> 'method' in ('otp', 'magiclink', 'email/signup', 'recovery'));
  select fallos into f from public.cfx_login_fallos where email = e;
  if f is null then return jsonb_build_object('ok', true, 'estaba', false); end if;
  if f >= 3 and not enlace then return jsonb_build_object('ok', false, 'bloqueado', true); end if;
  delete from public.cfx_login_fallos where email = e;
  return jsonb_build_object('ok', true, 'estaba', f >= 3);
end $$;
revoke all on function public.cfx_login_desbloquear() from public, anon;
grant execute on function public.cfx_login_desbloquear() to authenticated;

-- Aprobar (celular) y canjear (solo la Edge Function, clave de servidor: marca el código usado UNA vez y entrega el correo).
-- El QR también queda cerrado mientras la cuenta esté protegida.
create or replace function public.cfx_qr_aprobar(p text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare q public.cfx_login_qr := public.cfx_qr_buscar(p);
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Primero inicia sesión en este celular'); end if;
  if public.cfx_login_bloqueado(auth.jwt() ->> 'email') then return jsonb_build_object('ok', false, 'error', '🔒 Tu cuenta está protegida por 3 claves malas. Entra en el computador con el enlace de tu correo.'); end if;
  if q.token is null then return jsonb_build_object('ok', false, 'error', 'El código venció o no existe. En el computador toca "Otro código".'); end if;
  update public.cfx_login_qr set user_id = auth.uid(), aprobado_at = now() where token = q.token and aprobado_at is null;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.cfx_qr_aprobar(text) from public, anon;
grant execute on function public.cfx_qr_aprobar(text) to authenticated;

create or replace function public.cfx_qr_canjear(p_token text, p_secreto text) returns text
language plpgsql security definer set search_path = '' as $$
declare u uuid; m text;
begin
  update public.cfx_login_qr set usado_at = now()
  where token = p_token and secreto = encode(extensions.digest(coalesce(p_secreto, ''), 'sha256'), 'hex')
    and aprobado_at is not null and aprobado_at > now() - interval '2 minutes' and usado_at is null
  returning user_id into u;
  if u is null then return null; end if;
  m := (select email from auth.users where id = u);
  if public.cfx_login_bloqueado(m) then return null; end if;
  return m;
end $$;
revoke all on function public.cfx_qr_canjear(text, text) from public, anon, authenticated;
grant execute on function public.cfx_qr_canjear(text, text) to service_role;

-- ---------- Seguridad (A7): lo que puede hacer alguien sin cuenta (anon) y los buckets de archivos ----------
-- Va al final del núcleo: así alcanza a todas las funciones de la app.
-- 1) En Supabase anon recibe permiso para TODA función nueva ("revoke ... from public" no se lo quita). Las que lo primero que hacen es
--    exigir ser admin igual fallarían: se les quita el permiso a anon (no cambia nada para quien tiene cuenta).
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as fn from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')
      and p.prolang = (select oid from pg_language where lanname = 'plpgsql')
      and substring(lower(p.prosrc) from '\mbegin\M(.*)$') ~ ('^\s*perform\s+' || regexp_replace(lower('privado.solo_admin()'), '([().])', '\\\1', 'g') || '\s*;')
  loop
    execute 'revoke execute on function ' || f.fn || ' from public, anon';
  end loop;
end $$;
revoke execute on function public.cfx_anotar(text, text) from public, anon;

-- 2) Buckets públicos (se ven con su dirección): solo fotos y de hasta 5 MB, si la app no puso otro límite.
update storage.buckets set file_size_limit = 5242880 where public and file_size_limit is null;
update storage.buckets set allowed_mime_types = array['image/webp', 'image/jpeg', 'image/png'] where public and allowed_mime_types is null;

-- 3) Revisión para el Centro de Mando → Control → 🛡️ Seguridad.
create or replace function public.cfx_seguridad() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  return jsonb_build_object(
    'sin_rls', coalesce((select jsonb_agg(c.relname order by c.relname) from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity
        and (has_table_privilege('anon', c.oid, 'select') or has_table_privilege('anon', c.oid, 'insert,update,delete'))), '[]'),
    'anon_escribe', coalesce((select jsonb_agg(p.tablename || ' · ' || lower(p.cmd) order by p.tablename) from pg_policies p
      where p.schemaname = 'public' and p.cmd <> 'SELECT' and (p.roles @> '{anon}' or p.roles @> '{public}')), '[]'),
    'anon_lee', coalesce((select jsonb_agg(distinct p.tablename) from pg_policies p
      where p.schemaname = 'public' and p.cmd in ('SELECT', 'ALL') and (p.roles @> '{anon}' or p.roles @> '{public}')), '[]'),
    'funciones_anon', coalesce((select jsonb_agg(p.proname order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.prokind = 'f' and p.prosecdef and has_function_privilege('anon', p.oid, 'execute')), '[]'),
    'buckets', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'publico', b.public, 'mb', round(b.file_size_limit / 1048576.0, 1),
        'tipos', b.allowed_mime_types,
        'anon_lista', exists (select 1 from pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects'
          and p.cmd in ('SELECT', 'ALL') and (p.roles @> '{anon}' or p.roles @> '{public}'))) order by b.id) from storage.buckets b), '[]'),
    'humano', public.cfx_humano() - 'site_key' || jsonb_build_object('activo', coalesce(public.cfx_humano() ->> 'site_key', '') <> ''));
end $$;
revoke all on function public.cfx_seguridad() from public, anon;
grant execute on function public.cfx_seguridad() to authenticated;

-- G87 C · 🔑 Clave temporal: la cuenta que crea el admin (o a la que le restablece la clave) debe crear su clave al entrar.
-- Solo guarda el correo (nunca la clave). El admin la marca; la persona la borra al guardar su clave nueva.
create table if not exists public.cfx_clave_temporal (email text primary key, creado timestamptz not null default now());
alter table public.cfx_clave_temporal enable row level security;
revoke all on public.cfx_clave_temporal from anon, authenticated;
create or replace function public.cfx_clave_temporal_marcar(p_email text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  if coalesce(p_email, '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Correo no válido'; end if;
  insert into public.cfx_clave_temporal (email) values (lower(trim(p_email))) on conflict (email) do update set creado = now();
  perform public.cfx_anotar('clave temporal', lower(trim(p_email)));
end $$;
create or replace function public.cfx_clave_debo() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.cfx_clave_temporal t join auth.users u on lower(u.email) = t.email where u.id = auth.uid())
$$;
create or replace function public.cfx_clave_cambiada() returns void
language sql security definer set search_path = '' as $$
  delete from public.cfx_clave_temporal where email = (select lower(email) from auth.users where id = auth.uid())
$$;
revoke all on function public.cfx_clave_temporal_marcar(text), public.cfx_clave_debo(), public.cfx_clave_cambiada() from public, anon;
grant execute on function public.cfx_clave_temporal_marcar(text), public.cfx_clave_debo(), public.cfx_clave_cambiada() to authenticated;
-- ---------- G33 🌐 Dominio de CodeFix (núcleo 2.69, se puede volver a correr) ----------
-- El CM (Control → 🌐 Dominio) arma los dominios en Cloudflare y le guarda a cada app su dirección: ej. https://despega.codefix.cl/
-- "activo" = Cloudflare ya lo sirve. Mientras no esté activo (o vacío) todo sigue en workers.dev como hoy.
-- Público (no es secreto): las apps lo usan para armar links, QR y correos.
insert into public.cfx_config (clave, valor) values ('sitio', '{"dominio": "", "url": "", "activo": false}') on conflict (clave) do nothing;
create or replace function public.cfx_sitio() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce((select valor from public.cfx_config where clave = 'sitio'), '{"dominio": "", "url": "", "activo": false}'::jsonb) $$;
revoke all on function public.cfx_sitio() from public;
grant execute on function public.cfx_sitio() to anon, authenticated;
-- Dirección de la app para correos y links del servidor: null si no hay dominio activo (se usa la de siempre).
create or replace function public.cfx_sitio_url() returns text
language sql stable security definer set search_path = '' as $$
  select case when (valor->>'activo')::boolean and coalesce(valor->>'url', '') <> '' then valor->>'url' end
  from public.cfx_config where clave = 'sitio' $$;
revoke all on function public.cfx_sitio_url() from public;
grant execute on function public.cfx_sitio_url() to anon, authenticated;
create or replace function public.cfx_sitio_guardar(p_dominio text, p_url text, p_activo boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare d text := nullif(lower(trim(regexp_replace(coalesce(p_dominio, ''), '^https?://|/.*$|\.$', '', 'gi'))), '');
        u text := nullif(lower(trim(coalesce(p_url, ''))), '');
begin
  perform privado.solo_admin();
  if d is not null and (d !~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,24}$' or length(d) > 80) then raise exception 'Escribe solo el dominio, ej: codefix.cl'; end if;
  if u is not null and (u !~ '^https://([a-z0-9-]+\.)+[a-z]{2,24}/$' or d is null or right(u, length(d) + 1) <> d || '/') then raise exception 'Dirección no válida'; end if;
  insert into public.cfx_config (clave, valor) values ('sitio', jsonb_build_object('dominio', coalesce(d, ''), 'url', coalesce(u, ''), 'activo', d is not null and u is not null and coalesce(p_activo, false)))
    on conflict (clave) do update set valor = excluded.valor;
  return public.cfx_sitio();
end $$;
revoke all on function public.cfx_sitio_guardar(text, text, boolean) from public, anon;
grant execute on function public.cfx_sitio_guardar(text, text, boolean) to authenticated;
-- ---------- G61 a · 📲 Push insistente (núcleo): cada aviso se reenvía hasta que el celular confirma que llegó ----------
-- La función de la app (enviar/servidor) anota cada envío por dispositivo (cfx_push_anotar) con un "grupo" (= el aviso).
-- El service worker, al recibirlo, confirma (cfx_push_recibido) → se cortan los reenvíos de ese aviso en TODOS los dispositivos.
-- Sin confirmación se reenvía a los 1, 2, 5, 10, 15 y 30 min y luego cada 1 h, hasta 48 h (más es spam: Google/Apple lo bloquean).
-- Abrir la app también corta lo pendiente de ese celular (cfx_push_abri). Suscripción muerta (404/410) → cfx_push_muerto.
create table if not exists public.cfx_push_entrega (
  id          bigserial primary key,
  grupo       uuid not null,
  endpoint    text not null,
  p256dh      text not null,
  auth        text not null,
  payload     text not null,
  intentos    int not null default 0,
  proximo     timestamptz not null default now() + interval '1 minute',
  recibido_at timestamptz,
  created_at  timestamptz not null default now(),
  unique (grupo, endpoint)
);
create index if not exists cfx_push_entrega_prox on public.cfx_push_entrega (proximo) where recibido_at is null;
create index if not exists cfx_push_entrega_end on public.cfx_push_entrega (endpoint);
alter table public.cfx_push_entrega enable row level security;
revoke all on public.cfx_push_entrega from anon, authenticated;

-- p_lista: [{ grupo, endpoint, p256dh, auth, payload }] (solo la función de la app, con la clave de servidor)
create or replace function public.cfx_push_anotar(p_lista jsonb) returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  insert into public.cfx_push_entrega (grupo, endpoint, p256dh, auth, payload)
  select (x->>'grupo')::uuid, x->>'endpoint', x->>'p256dh', x->>'auth', x->>'payload'
  from jsonb_array_elements(coalesce(p_lista, '[]'::jsonb)) x
  where x->>'grupo' ~ '^[0-9a-f-]{36}$' and coalesce(x->>'endpoint', '') like 'https://%'
  on conflict (grupo, endpoint) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.cfx_push_anotar(jsonb) from public, anon, authenticated;
grant execute on function public.cfx_push_anotar(jsonb) to service_role;

-- Lo que toca reenviar ahora (y deja agendado el siguiente intento). Limpia lo viejo.
create or replace function public.cfx_push_tomar(p_max int default 200) returns setof public.cfx_push_entrega
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.cfx_push_entrega where created_at < now() - interval '50 hours' or recibido_at < now() - interval '1 day';
  return query
  update public.cfx_push_entrega e set intentos = e.intentos + 1,
    proximo = now() + case e.intentos when 0 then interval '1 minute' when 1 then interval '3 minutes' when 2 then interval '5 minutes'
      when 3 then interval '5 minutes' when 4 then interval '15 minutes' else interval '1 hour' end
  where e.id in (select x.id from public.cfx_push_entrega x where x.recibido_at is null and x.proximo <= now() and x.created_at > now() - interval '48 hours'
                 order by x.proximo limit greatest(1, least(coalesce(p_max, 200), 500)) for update skip locked)
  returning e.*;
end $$;
revoke all on function public.cfx_push_tomar(int) from public, anon, authenticated;
grant execute on function public.cfx_push_tomar(int) to service_role;

-- El service worker confirma que llegó (el grupo es un uuid al azar que solo viaja cifrado en el aviso).
create or replace function public.cfx_push_recibido(p_grupo uuid) returns boolean
language sql security definer set search_path = '' as $$
  with u as (update public.cfx_push_entrega set recibido_at = now() where grupo = p_grupo and recibido_at is null returning 1)
  select count(*) > 0 from u;
$$;
grant execute on function public.cfx_push_recibido(uuid) to anon, authenticated;

-- Abrir la app en un celular = ya vio sus avisos: se corta lo pendiente de ese celular (y de esos avisos en los otros).
create or replace function public.cfx_push_abri(p_endpoint text) returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  update public.cfx_push_entrega set recibido_at = now()
  where recibido_at is null and grupo in (select grupo from public.cfx_push_entrega where endpoint = p_endpoint and recibido_at is null);
  get diagnostics n = row_count;
  return n;
end $$;
grant execute on function public.cfx_push_abri(text) to anon, authenticated;

-- Suscripción dada de baja (404/410): no se reintenta más a ese celular.
create or replace function public.cfx_push_muerto(p_endpoint text) returns void
language sql security definer set search_path = '' as $$ delete from public.cfx_push_entrega where endpoint = p_endpoint; $$;
revoke all on function public.cfx_push_muerto(text) from public, anon, authenticated;
grant execute on function public.cfx_push_muerto(text) to service_role;

-- ---------------------------------------------------------------------
-- 🧾 Boleta SII del núcleo (G92, desde Despega): el negocio guarda sus datos de emisor y emite la boleta de una venta.
--   Manual: la emite gratis en el SII y anota el N° (folio). Automática: con su API key de OpenFactura (Haulmer) la boleta
--   electrónica (tipo 39, precios con IVA) sale sola. La API key queda solo en la base (al dueño se le muestran 4 caracteres).
--   Gancho por app: cfx_boleta_negocio_app(p_dueno) → negocio de quien llama (null = sin permiso). Cada app lo redefine DESPUÉS
--   de este bloque; el de aquí no da permiso a nadie. Los montos SIEMPRE salen de la base (la app manda solo la venta: ref).
--   Despega mantiene su boleta_* propia (pedidos de la tienda online).
-- ---------------------------------------------------------------------
create table if not exists public.cfx_boleta_cuentas (
  negocio_id uuid primary key,
  modo       text not null default 'manual' check (modo in ('manual', 'openfactura')),
  apikey     text,
  rut        text not null,
  razon      text not null,
  giro       text not null,
  direccion  text not null,
  comuna     text not null,
  auto       boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.cfx_boleta_cuentas enable row level security;
revoke all on public.cfx_boleta_cuentas from anon, authenticated;
create table if not exists public.cfx_boletas (
  negocio_id uuid not null,
  ref        text not null check (ref ~ '^[A-Za-z0-9_:-]{4,80}$'),
  total      numeric not null default 0,
  folio      text,
  url        text,
  error      text,
  intentos   int not null default 0,
  created_at timestamptz not null default now(),
  primary key (negocio_id, ref)
);
alter table public.cfx_boletas enable row level security;
revoke all on public.cfx_boletas from anon, authenticated;

do $$ begin
  if not exists (select 1 from pg_proc where proname = 'cfx_boleta_negocio_app' and pronamespace = 'public'::regnamespace) then
    execute 'create function public.cfx_boleta_negocio_app(p_dueno boolean) returns uuid language sql stable as $f$ select null::uuid $f$';
  end if;
end $$;

-- RUT normal '12345678-5' o null (dígito verificador con cfx_rut_ok).
create or replace function public.cfx_rut_normal(p text) returns text
language sql immutable set search_path = '' as $$
  select case when public.cfx_rut_ok(r) and r ~ '^[0-9]{7,8}[0-9K]$' then ltrim(left(r, -1), '0') || '-' || right(r, 1) end
  from (select upper(regexp_replace(coalesce(p, ''), '[^0-9kK]', '', 'g')) r) x
$$;

create or replace function public.cfx_boleta_estado() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare n uuid := public.cfx_boleta_negocio_app(false); d boolean := public.cfx_boleta_negocio_app(true) is not null; b public.cfx_boleta_cuentas;
begin
  if n is null then return jsonb_build_object('puede', false); end if;
  select * into b from public.cfx_boleta_cuentas where negocio_id = n;
  return jsonb_build_object('puede', true, 'dueno', d, 'conectado', b.negocio_id is not null, 'modo', coalesce(b.modo, 'manual'), 'rut', b.rut, 'razon', b.razon,
    'giro', b.giro, 'direccion', b.direccion, 'comuna', b.comuna, 'auto', coalesce(b.auto, true), 'fin', case when d then right(b.apikey, 4) end);
end $$;

-- El dueño guarda sus datos (p null = quitar). apikey vacía mantiene la anterior.
create or replace function public.cfx_boleta_guardar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  n uuid := public.cfx_boleta_negocio_app(true); md text := coalesce(p ->> 'modo', 'manual'); rt text := public.cfx_rut_normal(p ->> 'rut');
  k text := nullif(regexp_replace(coalesce(p ->> 'apikey', ''), '\s', '', 'g'), ''); t text;
begin
  if n is null then raise exception 'Solo el dueño del negocio'; end if;
  if p is null then delete from public.cfx_boleta_cuentas where negocio_id = n; return public.cfx_boleta_estado(); end if;
  if md not in ('manual', 'openfactura') then raise exception 'Modo no válido'; end if;
  if rt is null then raise exception 'RUT no válido: revisa el número y el dígito verificador'; end if;
  foreach t in array array['razon', 'giro', 'direccion', 'comuna'] loop
    if length(trim(coalesce(p ->> t, ''))) < 2 then
      raise exception 'Falta %', case t when 'razon' then 'la razón social' when 'giro' then 'el giro' when 'direccion' then 'la dirección' else 'la comuna' end;
    end if;
  end loop;
  if k is not null and k !~ '^[A-Za-z0-9_-]{16,120}$' then raise exception 'Esa no parece una API key de OpenFactura'; end if;
  if md = 'openfactura' and k is null and not exists (select 1 from public.cfx_boleta_cuentas where negocio_id = n and apikey is not null) then
    raise exception 'Pega tu API key de OpenFactura';
  end if;
  insert into public.cfx_boleta_cuentas (negocio_id, modo, apikey, rut, razon, giro, direccion, comuna, auto)
  values (n, md, k, rt, left(trim(p ->> 'razon'), 100), left(trim(p ->> 'giro'), 80), left(trim(p ->> 'direccion'), 70), left(trim(p ->> 'comuna'), 20), coalesce((p ->> 'auto')::boolean, true))
  on conflict (negocio_id) do update set modo = excluded.modo, apikey = coalesce(excluded.apikey, public.cfx_boleta_cuentas.apikey), rut = excluded.rut, razon = excluded.razon,
    giro = excluded.giro, direccion = excluded.direccion, comuna = excluded.comuna, auto = excluded.auto, updated_at = now();
  return public.cfx_boleta_estado();
end $$;

-- Boleta tipo 39 en el formato de OpenFactura. items = [{ nombre, cant, subtotal }]; si suman más que el total, la diferencia va como descuento.
create or replace function public.cfx_boleta_dte(p_items jsonb, p_total numeric, c public.cfx_boleta_cuentas) returns jsonb
language plpgsql stable set search_path = '' as $$
declare det jsonb := '[]'::jsonb; l jsonb; n int := 0; suma numeric := 0; m numeric; q numeric; tot numeric := round(p_total); neto numeric; d numeric;
begin
  for l in select * from jsonb_array_elements(coalesce(p_items, '[]')) loop
    exit when n >= 59;
    q := greatest(coalesce((l ->> 'cant')::numeric, 1), 1); m := round(coalesce((l ->> 'subtotal')::numeric, 0));
    if m <= 0 then continue; end if;
    n := n + 1; suma := suma + m;
    det := det || jsonb_build_object('NroLinDet', n, 'NmbItem', left(coalesce(nullif(trim(l ->> 'nombre'), ''), 'Producto'), 80), 'QtyItem', q, 'PrcItem', round(m / q, 2), 'MontoItem', m);
  end loop;
  if suma < tot then n := n + 1; det := det || jsonb_build_object('NroLinDet', n, 'NmbItem', 'Otros', 'QtyItem', 1, 'PrcItem', tot - suma, 'MontoItem', tot - suma); suma := tot; end if;
  d := suma - tot; neto := round(tot / 1.19);
  return jsonb_build_object('response', jsonb_build_array('FOLIO', 'SELF_SERVICE'), 'dte', jsonb_build_object(
    'Encabezado', jsonb_build_object(
      'IdDoc', jsonb_build_object('TipoDTE', 39, 'Folio', 0, 'FchEmis', to_char(now() at time zone 'America/Santiago', 'YYYY-MM-DD'), 'IndServicio', 3),
      'Emisor', jsonb_build_object('RUTEmisor', c.rut, 'RznSocEmisor', c.razon, 'GiroEmisor', c.giro, 'DirOrigen', c.direccion, 'CmnaOrigen', c.comuna),
      'Receptor', jsonb_build_object('RUTRecep', '66666666-6'),
      'Totales', jsonb_build_object('MntNeto', neto, 'IVA', tot - neto, 'MntTotal', tot)),
    'Detalle', det) || case when d > 0 then jsonb_build_object('DscRcgGlobal', jsonb_build_array(
      jsonb_build_object('NroLinDR', 1, 'TpoMov', 'D', 'GlosaDR', 'Descuento', 'TpoValor', '$', 'ValorDR', d))) else '{}'::jsonb end);
end $$;

create or replace function public.cfx_of_api(p_key text, p_cuerpo jsonb, p_idem text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare st int; c text;
begin
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '15');
  execute 'select status, content from extensions.http(row($1, $2, $3, $4, $5)::extensions.http_request)' into st, c
    using 'POST', 'https://api.haulmer.com/v2/dte/document',
          array[row('apikey', p_key)::extensions.http_header, row('Idempotency-Key', p_idem)::extensions.http_header], 'application/json', p_cuerpo::text;
  return jsonb_build_object('status', st, 'body', case when c ~ '^\s*[\{\[]' then c::jsonb end);
exception when others then
  return jsonb_build_object('status', 0, 'error', sqlerrm);
end $$;

-- Interna (la llama la función de cada app, que ya revisó el permiso y armó los ítems DESDE LA BASE).
-- p_folio = N° anotado a mano (modo manual); null = OpenFactura. Una boleta por venta: si ya tiene folio, la devuelve.
create or replace function public.cfx_boleta_crear(p_negocio uuid, p_ref text, p_items jsonb, p_total numeric, p_folio text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare c public.cfx_boleta_cuentas; b public.cfx_boletas; r jsonb; f text; e text; fm text := nullif(regexp_replace(coalesce(p_folio, ''), '\D', '', 'g'), '');
begin
  if p_negocio is null or p_ref !~ '^[A-Za-z0-9_:-]{4,80}$' then raise exception 'Venta no válida'; end if;
  select * into b from public.cfx_boletas where negocio_id = p_negocio and ref = p_ref;
  if b.folio is not null and (b.url is not null or fm is null) then return jsonb_build_object('ok', true, 'folio', b.folio, 'url', b.url); end if;
  if round(coalesce(p_total, 0)) < 1 then raise exception 'La venta no tiene monto'; end if;
  select * into c from public.cfx_boleta_cuentas where negocio_id = p_negocio;
  if fm is not null or c.negocio_id is null or c.modo <> 'openfactura' then
    if fm is null then return jsonb_build_object('ok', false, 'manual', true, 'error', 'Escribe el N° (folio) de la boleta del SII'); end if;
    if length(fm) > 10 then raise exception 'El N° de boleta tiene hasta 10 dígitos'; end if;
    insert into public.cfx_boletas (negocio_id, ref, total, folio) values (p_negocio, p_ref, round(p_total), fm)
    on conflict (negocio_id, ref) do update set folio = excluded.folio, total = excluded.total, error = null;
    return jsonb_build_object('ok', true, 'folio', fm);
  end if;
  if c.apikey is null then raise exception 'Pega tu API key de OpenFactura en 🧾 Boleta SII'; end if;
  r := public.cfx_of_api(c.apikey, public.cfx_boleta_dte(p_items, p_total, c), 'cfx-' || p_negocio::text || '-' || p_ref);
  f := nullif(coalesce(r #>> '{body,FOLIO}', r #>> '{body,folio}'), '');
  if coalesce((r ->> 'status')::int, 0) in (200, 201) and f is not null then
    insert into public.cfx_boletas (negocio_id, ref, total, folio, url) values (p_negocio, p_ref, round(p_total), left(f, 20),
      case when r #>> '{body,SELF_SERVICE,url}' ~ '^https://[^\s"<>]+$' then left(r #>> '{body,SELF_SERVICE,url}', 500) end)
    on conflict (negocio_id, ref) do update set folio = excluded.folio, url = excluded.url, total = excluded.total, error = null
    returning * into b;
    return jsonb_build_object('ok', true, 'folio', b.folio, 'url', b.url);
  end if;
  e := left(coalesce(case when (r ->> 'status')::int = 0 then 'No se pudo conectar con OpenFactura' end,
                     r #>> '{body,error,message}', r #>> '{body,message}', 'OpenFactura respondió ' || coalesce(r ->> 'status', '?')), 200);
  if (r ->> 'status')::int in (401, 403) then e := 'OpenFactura no aceptó la API key'; end if;
  insert into public.cfx_boletas (negocio_id, ref, total, error, intentos) values (p_negocio, p_ref, round(p_total), e, 1)
  on conflict (negocio_id, ref) do update set error = excluded.error, intentos = public.cfx_boletas.intentos + 1;
  return jsonb_build_object('ok', false, 'error', e);
end $$;
revoke all on function public.cfx_boleta_crear(uuid, text, jsonb, numeric, text), public.cfx_of_api(text, jsonb, text) from public, anon, authenticated;
revoke all on function public.cfx_boleta_estado(), public.cfx_boleta_guardar(jsonb) from public, anon;
grant execute on function public.cfx_boleta_estado(), public.cfx_boleta_guardar(jsonb) to authenticated;

-- ---------------------------------------------------------------------
-- CodeFix · 📣 Anuncios (G93 · G87 D). Solo promos PROPIAS (de CodeFix a quienes usan las apps), nunca publicidad de terceros.
--   CM → Control → 📣 Anuncios: Campaña → Conjuntos (a quién) → Anuncios (título, texto, imagen, botón). Se publican en cada app elegida.
--   En la app: tarjeta con ✕ (no vuelve a salir a esa persona) · cuenta vistas, clics y cierres (1 vez por persona).
-- ---------------------------------------------------------------------
create table if not exists public.cfx_anuncios (
  id uuid primary key, campana uuid not null, campana_nombre text not null default '' check (length(campana_nombre) <= 60),
  conjunto text not null default '' check (length(conjunto) <= 60),
  publico text not null default 'todos' check (publico in ('todos', 'negocios', 'clientes', 'premium', 'gratis')),
  titulo text not null check (length(titulo) between 1 and 80), texto text not null default '' check (length(texto) <= 240),
  imagen text not null default '' check (length(imagen) <= 90000 and (imagen = '' or imagen ~ '^https://' or imagen ~ '^data:image/(png|jpeg|webp);base64,')),
  boton text not null default '' check (length(boton) <= 30),
  link text not null default '' check (length(link) <= 500 and (link = '' or link ~ '^(https://|/|#)')),
  desde date, hasta date, activo boolean not null default true, orden int not null default 0, creado timestamptz not null default now());
create index if not exists cfx_anuncios_campana_idx on public.cfx_anuncios (campana);
create table if not exists public.cfx_anuncio_vistos (
  anuncio uuid not null references public.cfx_anuncios (id) on delete cascade, cuenta uuid not null,
  visto timestamptz not null default now(), clic timestamptz, cerrado timestamptz, primary key (anuncio, cuenta));
-- G96 b 📣 Promos del negocio a SUS clientes: misma tabla, con negocio (null = de CodeFix). Solo las ven sus clientes (gancho de la app).
alter table public.cfx_anuncios add column if not exists negocio uuid;
create index if not exists cfx_anuncios_negocio_idx on public.cfx_anuncios (negocio) where negocio is not null;
alter table public.cfx_anuncios enable row level security;
alter table public.cfx_anuncio_vistos enable row level security;
revoke all on public.cfx_anuncios, public.cfx_anuncio_vistos from anon, authenticated;

-- Publicar una campaña completa en ESTA app: reemplaza sus anuncios (los que ya no vienen se borran). Solo admin.
create or replace function public.cfx_anuncios_publicar(p_campana uuid, p_nombre text, p_lista jsonb) returns int
language plpgsql security definer set search_path = '' as $$
declare a jsonb; n int := 0; ids uuid[] := '{}';
begin
  perform privado.solo_admin();
  if p_campana is null or jsonb_typeof(coalesce(p_lista, 'null')) <> 'array' or jsonb_array_length(p_lista) > 30 then raise exception 'Datos no válidos'; end if;
  for a in select * from jsonb_array_elements(p_lista) loop
    ids := ids || (a ->> 'id')::uuid;
    insert into public.cfx_anuncios as x (id, campana, campana_nombre, conjunto, publico, titulo, texto, imagen, boton, link, desde, hasta, activo, orden)
    values ((a ->> 'id')::uuid, p_campana, left(trim(coalesce(p_nombre, '')), 60), left(trim(coalesce(a ->> 'conjunto', '')), 60), coalesce(nullif(a ->> 'publico', ''), 'todos'),
            left(trim(coalesce(a ->> 'titulo', '')), 80), left(trim(coalesce(a ->> 'texto', '')), 240), trim(coalesce(a ->> 'imagen', '')), left(trim(coalesce(a ->> 'boton', '')), 30),
            trim(coalesce(a ->> 'link', '')), nullif(a ->> 'desde', '')::date, nullif(a ->> 'hasta', '')::date, coalesce((a ->> 'activo')::boolean, true), n)
    on conflict (id) do update set campana = excluded.campana, campana_nombre = excluded.campana_nombre, conjunto = excluded.conjunto, publico = excluded.publico,
      titulo = excluded.titulo, texto = excluded.texto, imagen = excluded.imagen, boton = excluded.boton, link = excluded.link, desde = excluded.desde,
      hasta = excluded.hasta, activo = excluded.activo, orden = excluded.orden
    where x.campana = p_campana;
    n := n + 1;
  end loop;
  delete from public.cfx_anuncios where campana = p_campana and not (id = any (ids));
  perform public.cfx_anotar('anuncios', 'Campaña "' || left(coalesce(p_nombre, ''), 60) || '": ' || n || ' anuncio(s)');
  return n;
end $$;

-- Quitar una campaña de ESTA app (se borran sus anuncios y contadores). Solo admin.
create or replace function public.cfx_anuncios_quitar(p_campana uuid) returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  perform privado.solo_admin();
  delete from public.cfx_anuncios where campana = p_campana; get diagnostics n = row_count;
  perform public.cfx_anotar('anuncios', 'Campaña quitada (' || n || ')');
  return n;
end $$;

-- Resultados por anuncio en ESTA app (vistas, clics, cierres = personas distintas). Solo admin.
create or replace function public.cfx_anuncios_admin() returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform privado.solo_admin();
  return coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'campana', a.campana, 'titulo', a.titulo, 'activo', a.activo,
    'vistas', (select count(*) from public.cfx_anuncio_vistos v where v.anuncio = a.id),
    'clics', (select count(*) from public.cfx_anuncio_vistos v where v.anuncio = a.id and v.clic is not null),
    'cierres', (select count(*) from public.cfx_anuncio_vistos v where v.anuncio = a.id and v.cerrado is not null)) order by a.creado) from public.cfx_anuncios a where a.negocio is null), '[]');
end $$;

-- G96 b 📣 PROMOS DEL NEGOCIO. Gancho de cada app que tiene clientes con cuenta (y 'promos' en cfx_modulos_app()):
--   cfx_promo_negocios_app(u) jsonb   [{"n": negocio, "nombre": "Barbería Juan"}] de los que u es cliente (sin gancho: ninguno).
-- Módulo 'promos' (con la venta de módulos apagada: Premium). Máx. 3 activas y 10 guardadas por negocio. Validado aquí.
create or replace function public.cfx_promo_negocios(u uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r jsonb;
begin
  if u is null or to_regprocedure('public.cfx_promo_negocios_app(uuid)') is null then return '[]'; end if;
  execute 'select public.cfx_promo_negocios_app($1)' into r using u;
  return case when jsonb_typeof(r) = 'array' then r else '[]' end;
end $$;
create or replace function public.cfx_promos_puede(n uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select n is not null and case when public.cfx_venta_on() and 'promos' = any (public.cfx_modulos_de_app()) then public.cfx_modulo_de('promos', n)
    else public.cfx_negocio_premium(n) end
$$;
-- El negocio de quien llama, solo si es el dueño (null si no).
create or replace function public.cfx_promo_mi_negocio() returns uuid
language sql stable security definer set search_path = '' as $$
  select n from (select public.cfx_negocio_cuenta(auth.uid()) n) x where n is not null and public.cfx_negocio_dueno(n) = auth.uid()
$$;
create or replace function public.cfx_promos_mias() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare n uuid := public.cfx_promo_mi_negocio();
begin
  if n is null then raise exception 'Solo el dueño del negocio'; end if;
  return jsonb_build_object('puede', public.cfx_promos_puede(n), 'lista', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'titulo', a.titulo, 'texto', a.texto,
    'imagen', a.imagen, 'boton', a.boton, 'link', a.link, 'desde', a.desde, 'hasta', a.hasta, 'activo', a.activo,
    'vistas', (select count(*) from public.cfx_anuncio_vistos v where v.anuncio = a.id),
    'clics', (select count(*) from public.cfx_anuncio_vistos v where v.anuncio = a.id and v.clic is not null),
    'cierres', (select count(*) from public.cfx_anuncio_vistos v where v.anuncio = a.id and v.cerrado is not null)) order by a.creado desc)
    from public.cfx_anuncios a where a.negocio = n), '[]'));
end $$;
create or replace function public.cfx_promo_guardar(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare n uuid := public.cfx_promo_mi_negocio(); i uuid := nullif(p ->> 'id', '')::uuid; r uuid; act boolean := coalesce((p ->> 'activo')::boolean, true);
  lk text := trim(coalesce(p ->> 'link', '')); de date := nullif(p ->> 'desde', '')::date; ha date := nullif(p ->> 'hasta', '')::date;
begin
  if n is null then raise exception 'Solo el dueño del negocio'; end if;
  if not public.cfx_promos_puede(n) then raise exception '📣 Promo destacada es un módulo 🧩: actívalo en Mi plan y módulos'; end if;
  if length(trim(coalesce(p ->> 'titulo', ''))) = 0 then raise exception 'Escribe el título de la promo'; end if;
  if lk <> '' and lk !~ '^https://' then raise exception 'El link debe partir con https://'; end if;
  if ha is not null and de is not null and ha < de then raise exception 'La fecha de término es antes del inicio'; end if;
  if i is null and (select count(*) from public.cfx_anuncios where negocio = n) >= 10 then raise exception 'Máximo 10 promos guardadas: borra alguna'; end if;
  if act and (select count(*) from public.cfx_anuncios where negocio = n and activo and id is distinct from i) >= 3 then raise exception 'Máximo 3 promos activas a la vez: pausa alguna'; end if;
  if i is null then
    insert into public.cfx_anuncios (id, campana, negocio, publico, titulo, texto, imagen, boton, link, desde, hasta, activo)
    values (gen_random_uuid(), gen_random_uuid(), n, 'clientes', left(trim(p ->> 'titulo'), 80), left(trim(coalesce(p ->> 'texto', '')), 240), trim(coalesce(p ->> 'imagen', '')),
            case when lk = '' then '' else left(trim(coalesce(nullif(p ->> 'boton', ''), 'Ver')), 30) end, lk, de, ha, act) returning id into r;
  else
    update public.cfx_anuncios set titulo = left(trim(p ->> 'titulo'), 80), texto = left(trim(coalesce(p ->> 'texto', '')), 240), imagen = trim(coalesce(p ->> 'imagen', '')),
      boton = case when lk = '' then '' else left(trim(coalesce(nullif(p ->> 'boton', ''), 'Ver')), 30) end, link = lk, desde = de, hasta = ha, activo = act
    where id = i and negocio = n returning id into r;
    if r is null then raise exception 'Promo no encontrada'; end if;
  end if;
  return r;
end $$;
create or replace function public.cfx_promo_borrar(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare n uuid := public.cfx_promo_mi_negocio();
begin
  if n is null then raise exception 'Solo el dueño del negocio'; end if;
  delete from public.cfx_anuncios where id = p_id and negocio = n;
end $$;
revoke all on function public.cfx_promo_negocios(uuid), public.cfx_promos_puede(uuid), public.cfx_promo_mi_negocio() from public, anon, authenticated;
revoke all on function public.cfx_promos_mias(), public.cfx_promo_guardar(jsonb), public.cfx_promo_borrar(uuid) from public, anon;
grant execute on function public.cfx_promos_mias(), public.cfx_promo_guardar(jsonb), public.cfx_promo_borrar(uuid) to authenticated;

-- Lo que ve la persona: anuncios activos, vigentes, de su público y que no cerró (máx. 3). La app no los pide para admin/socio.
create or replace function public.cfx_anuncios_ver() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid := auth.uid(); hoy date := (now() at time zone 'America/Santiago')::date;
begin
  if u is null then return '[]'; end if;
  -- G96 b: + 📣 promos de los negocios de los que es cliente (con el nombre del negocio en 'de'), después de las de CodeFix.
  return coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'titulo', a.titulo, 'texto', a.texto, 'imagen', a.imagen, 'boton', a.boton, 'link', a.link, 'de', a.de) order by a.k, a.orden, a.creado)
    from (select a.*, case when a.negocio is null then 0 else 1 end k, (select x ->> 'nombre' from jsonb_array_elements(ng) x where x ->> 'n' = a.negocio::text limit 1) de
          from public.cfx_anuncios a, (select public.cfx_promo_negocios(u) ng) g
          where a.activo and (a.desde is null or a.desde <= hoy) and (a.hasta is null or a.hasta >= hoy)
            and not exists (select 1 from public.cfx_anuncio_vistos v where v.anuncio = a.id and v.cuenta = u and v.cerrado is not null)
            and (case when a.negocio is null then a.publico = 'todos' or u in (select d from public.cfx_destinatarios(a.publico) d)
                      else exists (select 1 from jsonb_array_elements(ng) x where x ->> 'n' = a.negocio::text) and public.cfx_promos_puede(a.negocio) end)
          order by case when a.negocio is null then 0 else 1 end, a.orden, a.creado limit 3) a), '[]');
end $$;

-- Marca vista / clic / cierre (una fila por persona y anuncio: no se infla contando de nuevo).
create or replace function public.cfx_anuncio_marcar(p_id uuid, p_que text) returns void
language plpgsql security definer set search_path = '' as $$
declare u uuid := auth.uid();
begin
  if u is null or p_que not in ('vista', 'clic', 'cierre') or not exists (select 1 from public.cfx_anuncios where id = p_id) then return; end if;
  insert into public.cfx_anuncio_vistos (anuncio, cuenta) values (p_id, u) on conflict do nothing;
  if p_que = 'clic' then update public.cfx_anuncio_vistos set clic = coalesce(clic, now()) where anuncio = p_id and cuenta = u;
  elsif p_que = 'cierre' then update public.cfx_anuncio_vistos set cerrado = coalesce(cerrado, now()) where anuncio = p_id and cuenta = u; end if;
end $$;
revoke all on function public.cfx_anuncios_publicar(uuid, text, jsonb), public.cfx_anuncios_quitar(uuid), public.cfx_anuncios_admin(), public.cfx_anuncios_ver(), public.cfx_anuncio_marcar(uuid, text) from public, anon;
grant execute on function public.cfx_anuncios_publicar(uuid, text, jsonb), public.cfx_anuncios_quitar(uuid), public.cfx_anuncios_admin(), public.cfx_anuncios_ver(), public.cfx_anuncio_marcar(uuid, text) to authenticated;

-- ---------------------------------------------------------------------
-- G98 ⚡ MERCADO PAGO PROPIO DE CADA NEGOCIO (cobrar a SUS clientes: abonos, arriendos, órdenes…). La plata llega directo al negocio.
--   El dueño pega su Access Token una vez (cfx_mp_neg_guardar; nadie lo puede leer después, ni el equipo ni la app).
--   La app crea un cobro con cfx_mp_neg_cobro(negocio, ref, título, monto, volver, vence) → url de Mercado Pago.
--   Al volver (cfx_mp_neg_revisar(ref)) o cada 1 min (cron 'cfx-mp-neg') la BASE consulta a Mercado Pago: aprobado + CLP + monto
--   completo + n° de pago usado 1 sola vez → marca el cobro pagado y llama al gancho de la app cfx_mp_neg_pagado_app(ref, pago, monto).
--   ref = '<tipo>:<id>' (ej. 'reserva:uuid'); la app decide qué hacer al pagarse (agendar, extender, etc.).
--   Despega tiene su propio mp_cuentas (pedidos) desde antes: no se toca.
-- ---------------------------------------------------------------------
create table if not exists public.cfx_mp_negocio (
  negocio    uuid primary key,
  token      text not null,
  nick       text,
  activo     boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.cfx_mp_negocio enable row level security;
alter table public.cfx_mp_negocio add column if not exists llave_desde timestamptz not null default now(); -- G112 c2
revoke all on public.cfx_mp_negocio from anon, authenticated;

create table if not exists public.cfx_mp_neg_cobros (
  id         uuid primary key default gen_random_uuid(),
  negocio    uuid not null,
  ref        text not null,
  titulo     text,
  monto      int not null check (monto > 0),
  vence      timestamptz,
  pago       text unique,
  pagado_at  timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists cfx_mp_neg_cobros_ref on public.cfx_mp_neg_cobros (ref, created_at desc);
create index if not exists cfx_mp_neg_cobros_pend on public.cfx_mp_neg_cobros (created_at) where pago is null;
alter table public.cfx_mp_neg_cobros enable row level security;
revoke all on public.cfx_mp_neg_cobros from anon, authenticated;

-- El negocio de quien llama, solo si es el dueño (null si no).
create or replace function public.cfx_mp_neg_mio() returns uuid
language sql stable security definer set search_path = '' as $$
  select n from (select public.cfx_negocio_cuenta(auth.uid()) n) x where n is not null and public.cfx_negocio_dueno(n) = auth.uid()
$$;

-- G107: "cobro automático" = su ⚡ Mercado Pago O su 💳 Flow (Webpay). cfx_mp_neg_mp = solo Mercado Pago (suscripciones G106).
create table if not exists public.cfx_flow_negocio (
  negocio    uuid primary key,
  apikey     text not null,
  secret     text not null,
  sandbox    boolean not null default false,
  activo     boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.cfx_flow_negocio enable row level security;
alter table public.cfx_flow_negocio add column if not exists llave_desde timestamptz not null default now(); -- G112 c2
revoke all on public.cfx_flow_negocio from anon, authenticated;
alter table public.cfx_mp_neg_cobros add column if not exists medio text not null default 'mp';
alter table public.cfx_mp_neg_cobros add column if not exists volver text;

create or replace function public.cfx_mp_neg_mp(p_negocio uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.cfx_mp_negocio where negocio = p_negocio and activo)
$$;
create or replace function public.cfx_flow_neg_on(p_negocio uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.cfx_flow_negocio where negocio = p_negocio and activo)
$$;
create or replace function public.cfx_mp_neg_activo(p_negocio uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.cfx_mp_neg_mp(p_negocio) or public.cfx_flow_neg_on(p_negocio)
$$;
-- Para la pantalla del cliente: qué botones mostrar.
create or replace function public.cfx_mp_neg_medios(p_negocio uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('mp', public.cfx_mp_neg_mp(p_negocio), 'flow', public.cfx_flow_neg_on(p_negocio))
$$;

create or replace function public.cfx_mp_neg_estado() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('dueno', n is not null, 'conectado', m.negocio is not null, 'activo', coalesce(m.activo, false), 'nick', m.nick, 'fin', right(public.cfx_secreto(m.token), 4),
    'desde', m.llave_desde, 'rotar', coalesce(m.llave_desde < now() - interval '365 days', false))
  from (select public.cfx_mp_neg_mio() n) x left join public.cfx_mp_negocio m on m.negocio = x.n
$$;

-- El dueño conecta (token), activa/pausa (p_activo) o desconecta (sin token y p_activo null).
create or replace function public.cfx_mp_neg_guardar(p_token text, p_activo boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n uuid := public.cfx_mp_neg_mio(); tk text := nullif(regexp_replace(coalesce(p_token, ''), '\s', '', 'g'), ''); r jsonb;
begin
  if n is null then raise exception 'Solo el dueño del negocio'; end if;
  if tk is null then
    if p_activo is null then delete from public.cfx_mp_negocio where negocio = n;
    else
      update public.cfx_mp_negocio set activo = p_activo, updated_at = now() where negocio = n;
      if not found and p_activo then raise exception 'Pega tu Access Token de Mercado Pago'; end if;
    end if;
    return public.cfx_mp_neg_estado();
  end if;
  if tk !~ '^(APP_USR|TEST)-[A-Za-z0-9-]{20,}$' or length(tk) > 300 then raise exception 'Ese no es un Access Token: empieza con APP_USR-'; end if;
  r := public.cfx_mp_api(tk, 'GET', '/users/me');
  if coalesce((r ->> 'status')::int, 0) = 0 then raise exception 'No se pudo conectar con Mercado Pago. Intenta de nuevo.'; end if;
  if (r ->> 'status')::int <> 200 then raise exception 'Mercado Pago no aceptó el token: copia el Access Token de producción'; end if;
  insert into public.cfx_mp_negocio (negocio, token, nick, activo)
  values (n, tk, left(coalesce(r #>> '{body,nickname}', r #>> '{body,email}', ''), 80), coalesce(p_activo, true))
  on conflict (negocio) do update set token = excluded.token, nick = excluded.nick, activo = excluded.activo, updated_at = now();
  return public.cfx_mp_neg_estado();
end $$;

-- La app pide el cobro (solo desde sus funciones; no se llama directo). Devuelve { ok, url } o { ok: false, error }.
-- G107: p_medio 'mp' | 'flow' (null = Mercado Pago si está, si no Flow).
drop function if exists public.cfx_mp_neg_cobro(uuid, text, text, int, text, timestamptz);
create or replace function public.cfx_mp_neg_cobro(p_negocio uuid, p_ref text, p_titulo text, p_monto int, p_volver text, p_vence timestamptz default null, p_medio text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare tk text; c public.cfx_mp_neg_cobros; r jsonb; v text := left(coalesce(p_volver, ''), 500);
        md text := coalesce(p_medio, case when public.cfx_mp_neg_mp(p_negocio) then 'mp' else 'flow' end);
begin
  if md = 'flow' then return public.cfx_flow_neg_cobro(p_negocio, p_ref, p_titulo, p_monto, p_volver, p_vence); end if;
  select public.cfx_secreto(token) into tk from public.cfx_mp_negocio where negocio = p_negocio and activo;
  if tk is null then return jsonb_build_object('ok', false, 'error', 'Este negocio no tiene Mercado Pago activo'); end if;
  if coalesce(p_monto, 0) < 1 then return jsonb_build_object('ok', false, 'error', 'Monto no válido'); end if;
  if p_vence is not null and p_vence < now() + interval '1 minute' then return jsonb_build_object('ok', false, 'error', 'Se pasó el tiempo para pagar'); end if;
  if exists (select 1 from public.cfx_mp_neg_cobros where ref = p_ref and pago is not null) then return jsonb_build_object('ok', false, 'error', 'Esto ya está pagado'); end if;
  if v !~ '^https://[^\s"<>]+$' then v := null; end if;
  insert into public.cfx_mp_neg_cobros (negocio, ref, titulo, monto, vence) values (p_negocio, left(p_ref, 120), left(coalesce(p_titulo, 'Pago'), 120), p_monto, p_vence)
  returning * into c;
  r := public.cfx_mp_api(tk, 'POST', '/checkout/preferences', jsonb_build_object(
    'items', jsonb_build_array(jsonb_build_object('id', c.id, 'title', c.titulo, 'quantity', 1, 'currency_id', 'CLP', 'unit_price', c.monto)),
    'external_reference', c.id::text,
    'payment_methods', jsonb_build_object('excluded_payment_types', jsonb_build_array(jsonb_build_object('id', 'ticket'))))
    || public.cfx_mp_notif('n:' || c.id::text)
    || case when p_vence is null then '{}'::jsonb else jsonb_build_object('expires', true,
         'expiration_date_to', to_char(p_vence at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS".000+00:00"')) end
    || case when v is null then '{}'::jsonb else jsonb_build_object('back_urls', jsonb_build_object('success', v, 'pending', v, 'failure', v), 'auto_return', 'approved') end);
  if coalesce((r ->> 'status')::int, 0) not in (200, 201) or r #>> '{body,init_point}' is null then
    delete from public.cfx_mp_neg_cobros where id = c.id;
    return jsonb_build_object('ok', false, 'error', 'Mercado Pago no respondió. Intenta de nuevo o usa otro medio de pago.');
  end if;
  return jsonb_build_object('ok', true, 'url', r #>> '{body,init_point}');
end $$;

-- Pregunta a Mercado Pago por UN cobro; si está aprobado (CLP, monto completo, n° no usado) lo marca y llama al gancho de la app.
create or replace function public.cfx_mp_neg_confirmar(p_id uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare c public.cfx_mp_neg_cobros; tk text; r jsonb; pg jsonb;
begin
  select * into c from public.cfx_mp_neg_cobros where id = p_id for update skip locked;
  if c.id is null then return false; end if;
  if c.pago is not null then return true; end if;
  if c.medio = 'flow' then return public.cfx_flow_neg_confirmar(c); end if;  -- G107
  select public.cfx_secreto(token) into tk from public.cfx_mp_negocio where negocio = c.negocio;
  if tk is null then return false; end if;
  r := public.cfx_mp_api(tk, 'GET', '/v1/payments/search?sort=date_created&criteria=desc&external_reference=' || c.id::text);
  select e into pg from jsonb_array_elements(coalesce(r #> '{body,results}', '[]'::jsonb)) e
  where e ->> 'status' = 'approved' and e ->> 'external_reference' = c.id::text
    and coalesce(e ->> 'currency_id', 'CLP') = 'CLP' and (e ->> 'transaction_amount')::numeric >= c.monto
    and not exists (select 1 from public.cfx_mp_neg_cobros u where u.pago = left(e ->> 'id', 40)) limit 1;
  if pg is null then return false; end if;
  update public.cfx_mp_neg_cobros set pago = left(pg ->> 'id', 40), pagado_at = now() where id = c.id;
  if to_regprocedure('public.cfx_mp_neg_pagado_app(text, text, integer)') is not null then
    execute 'select public.cfx_mp_neg_pagado_app($1, $2, $3)' using c.ref, left(pg ->> 'id', 40), c.monto;
  end if;
  return true;
end $$;

-- Al volver de Mercado Pago: revisa los cobros de esa referencia (la app lo llama dentro de su propia función, con su control de acceso).
create or replace function public.cfx_mp_neg_revisar(p_ref text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare i uuid;
begin
  if exists (select 1 from public.cfx_mp_neg_cobros where ref = p_ref and pago is not null) then return true; end if;
  for i in select id from public.cfx_mp_neg_cobros where ref = p_ref and pago is null and created_at > now() - interval '3 days' order by created_at desc limit 5 loop
    if public.cfx_mp_neg_confirmar(i) then return true; end if;
  end loop;
  return false;
end $$;

create or replace function public.cfx_mp_neg_pagado(p_ref text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.cfx_mp_neg_cobros where ref = p_ref and pago is not null)
$$;

-- Cada 1 min: cobros abiertos de los últimos 2 días (por si la persona no volvió a la página).
create or replace function public.cfx_mp_neg_revisar_pendientes() returns int
language plpgsql security definer set search_path = '' as $$
declare i uuid; n int := 0;
begin
  for i in select id from public.cfx_mp_neg_cobros c where pago is null and created_at > now() - interval '2 days'
             and (vence is null or vence > now() - interval '30 minutes')
             and not exists (select 1 from public.cfx_mp_neg_cobros p where p.ref = c.ref and p.pago is not null)
           order by created_at desc limit 40 loop
    if public.cfx_mp_neg_confirmar(i) then n := n + 1; end if;
  end loop;
  delete from public.cfx_mp_neg_cobros where pago is null and created_at < now() - interval '30 days';
  return n;
end $$;

-- ---------------------------------------------------------------------
-- G107 💳 FLOW PROPIO DE CADA NEGOCIO (Webpay débito/crédito, transferencia y MACH; la plata llega a SU cuenta Flow).
--   Mismo molde que su Mercado Pago: el dueño pega API Key + Secret Key 1 vez (nadie las lee después). El cobro va en
--   cfx_mp_neg_cobros (medio 'flow'), se confirma con getStatusByCommerceId (pagado + CLP + monto completo + n° de Flow 1 vez)
--   al volver, con el aviso de Flow (función ?cfx_mp=n:<id>) y con el cron 'cfx-mp-neg' → mismo gancho cfx_mp_neg_pagado_app.
--   Flow exige el correo de quien paga: el de la persona con sesión; si no hay (invitado), el del dueño (le llega el recibo).
-- ---------------------------------------------------------------------
create or replace function public.cfx_flow_neg_cfg(p_negocio uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('apikey', public.cfx_secreto(apikey), 'secret', public.cfx_secreto(secret), 'sandbox', sandbox) from public.cfx_flow_negocio where negocio = p_negocio
$$;

create or replace function public.cfx_flow_neg_cobro(p_negocio uuid, p_ref text, p_titulo text, p_monto int, p_volver text, p_vence timestamptz default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare f jsonb; c public.cfx_mp_neg_cobros; r jsonb; v text := left(coalesce(p_volver, ''), 500); n text; em text;
begin
  if not public.cfx_flow_neg_on(p_negocio) then return jsonb_build_object('ok', false, 'error', 'Este negocio no tiene Webpay (Flow) activo'); end if;
  f := public.cfx_flow_neg_cfg(p_negocio);
  if coalesce(p_monto, 0) < 350 then return jsonb_build_object('ok', false, 'error', 'Webpay cobra desde $350. Usa otro medio de pago.'); end if;
  if p_vence is not null and p_vence < now() + interval '1 minute' then return jsonb_build_object('ok', false, 'error', 'Se pasó el tiempo para pagar'); end if;
  if exists (select 1 from public.cfx_mp_neg_cobros where ref = p_ref and pago is not null) then return jsonb_build_object('ok', false, 'error', 'Esto ya está pagado'); end if;
  if v !~ '^https://[^\s"<>]+$' then v := null; end if;
  select email into em from auth.users where id = auth.uid();
  if coalesce(em, '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then select email into em from auth.users where id = public.cfx_negocio_dueno(p_negocio); end if;
  if coalesce(em, '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return jsonb_build_object('ok', false, 'error', 'Falta un correo para Webpay. Usa otro medio de pago.'); end if;
  insert into public.cfx_mp_neg_cobros (negocio, ref, titulo, monto, vence, medio, volver)
  values (p_negocio, left(p_ref, 120), left(coalesce(p_titulo, 'Pago'), 120), p_monto, p_vence, 'flow', v) returning * into c;
  n := public.cfx_mp_notif('n:' || c.id::text) ->> 'notification_url';
  if n is null and v is null then
    delete from public.cfx_mp_neg_cobros where id = c.id;
    return jsonb_build_object('ok', false, 'error', 'Webpay no está listo en esta app. Usa otro medio de pago.');
  end if;
  r := public.cfx_flow_api('POST', '/payment/create', jsonb_build_object('commerceOrder', c.id::text, 'subject', c.titulo,
    'currency', 'CLP', 'amount', c.monto::text, 'email', lower(em), 'paymentMethod', '9',
    'urlConfirmation', coalesce(n, v), 'urlReturn', coalesce(n || '&cfx_volver=1', v))
    || case when p_vence is null then '{}'::jsonb else jsonb_build_object('timeout', greatest(120, least(86400, extract(epoch from p_vence - now())::int))::text) end, f);
  if coalesce((r ->> 'status')::int, 0) <> 200 or coalesce(r #>> '{body,url}', '') !~ '^https://' or coalesce(r #>> '{body,token}', '') = '' then
    delete from public.cfx_mp_neg_cobros where id = c.id;
    return jsonb_build_object('ok', false, 'error', 'Webpay (Flow) no respondió. Intenta de nuevo o usa otro medio de pago.');
  end if;
  return jsonb_build_object('ok', true, 'url', (r #>> '{body,url}') || '?token=' || public.cfx_url_cod(r #>> '{body,token}'));
end $$;

create or replace function public.cfx_flow_neg_confirmar(c public.cfx_mp_neg_cobros) returns boolean
language plpgsql security definer set search_path = '' as $$
declare f jsonb := public.cfx_flow_neg_cfg(c.negocio); r jsonb; b jsonb; nro text;
begin
  if f is null then return false; end if;
  r := public.cfx_flow_api('GET', '/payment/getStatusByCommerceId', jsonb_build_object('commerceId', c.id::text), f);
  b := r -> 'body';
  if coalesce((r ->> 'status')::int, 0) <> 200 or b is null or coalesce((b ->> 'status')::int, 0) <> 2 or b ->> 'commerceOrder' is distinct from c.id::text
     or coalesce(b ->> 'currency', 'CLP') <> 'CLP' or coalesce((b ->> 'amount')::numeric, 0) < c.monto or coalesce(b ->> 'flowOrder', '') = '' then return false; end if;
  nro := 'flow:' || left(b ->> 'flowOrder', 34);
  if exists (select 1 from public.cfx_mp_neg_cobros u where u.pago = nro) then return false; end if;
  update public.cfx_mp_neg_cobros set pago = nro, pagado_at = now() where id = c.id;
  if to_regprocedure('public.cfx_mp_neg_pagado_app(text, text, integer)') is not null then
    execute 'select public.cfx_mp_neg_pagado_app($1, $2, $3)' using c.ref, nro, c.monto;
  end if;
  return true;
end $$;

create or replace function public.cfx_flow_neg_estado() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('dueno', n is not null, 'conectado', f.negocio is not null, 'activo', coalesce(f.activo, false), 'sandbox', coalesce(f.sandbox, false), 'fin', right(public.cfx_secreto(f.apikey), 4),
    'desde', f.llave_desde, 'rotar', coalesce(f.llave_desde < now() - interval '365 days', false))
  from (select public.cfx_mp_neg_mio() n) x left join public.cfx_flow_negocio f on f.negocio = x.n
$$;

-- El dueño conecta (llaves), activa/pausa (p_activo) o desconecta (sin llaves y p_activo null).
create or replace function public.cfx_flow_neg_guardar(p_apikey text, p_secret text, p_activo boolean, p_sandbox boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n uuid := public.cfx_mp_neg_mio(); k text := nullif(regexp_replace(coalesce(p_apikey, ''), '\s', '', 'g'), '');
        sc text := nullif(regexp_replace(coalesce(p_secret, ''), '\s', '', 'g'), ''); r jsonb;
begin
  if n is null then raise exception 'Solo el dueño del negocio'; end if;
  if k is null and sc is null then
    if p_activo is null then delete from public.cfx_flow_negocio where negocio = n;
    else
      update public.cfx_flow_negocio set activo = p_activo, updated_at = now() where negocio = n;
      if not found and p_activo then raise exception 'Pega tu API Key y tu Secret Key de Flow'; end if;
    end if;
    return public.cfx_flow_neg_estado();
  end if;
  if k is null or sc is null then raise exception 'Pega las 2 llaves: API Key y Secret Key'; end if;
  if k !~ '^[A-Za-z0-9-]{20,80}$' then raise exception 'Esa no parece una API Key de Flow (Integración → API Keys)'; end if;
  if sc !~ '^[A-Za-z0-9]{20,100}$' then raise exception 'Esa no parece una Secret Key de Flow'; end if;
  r := public.cfx_flow_api('GET', '/payment/getStatusByCommerceId', jsonb_build_object('commerceId', 'cfx-prueba'),
    jsonb_build_object('apikey', k, 'secret', sc, 'sandbox', coalesce(p_sandbox, false)));
  if coalesce((r ->> 'status')::int, 0) = 0 then raise exception 'No se pudo conectar con Flow. Intenta de nuevo.'; end if;
  if (r ->> 'status')::int in (401, 403) then raise exception 'Flow no aceptó las llaves: cópialas de nuevo (¿son de producción o de pruebas?)'; end if;
  insert into public.cfx_flow_negocio (negocio, apikey, secret, sandbox, activo) values (n, k, sc, coalesce(p_sandbox, false), coalesce(p_activo, true))
  on conflict (negocio) do update set apikey = excluded.apikey, secret = excluded.secret, sandbox = excluded.sandbox, activo = excluded.activo, updated_at = now();
  return public.cfx_flow_neg_estado();
end $$;

revoke all on function public.cfx_flow_neg_cfg(uuid), public.cfx_flow_neg_cobro(uuid, text, text, int, text, timestamptz), public.cfx_flow_neg_confirmar(public.cfx_mp_neg_cobros) from public, anon, authenticated;
revoke all on function public.cfx_flow_neg_estado(), public.cfx_flow_neg_guardar(text, text, boolean, boolean) from public, anon;
grant execute on function public.cfx_flow_neg_estado(), public.cfx_flow_neg_guardar(text, text, boolean, boolean) to authenticated;

revoke all on function public.cfx_mp_neg_mio(), public.cfx_mp_neg_activo(uuid), public.cfx_mp_neg_cobro(uuid, text, text, int, text, timestamptz, text),
  public.cfx_mp_neg_mp(uuid), public.cfx_flow_neg_on(uuid), public.cfx_mp_neg_medios(uuid),
  public.cfx_mp_neg_confirmar(uuid), public.cfx_mp_neg_revisar(text), public.cfx_mp_neg_pagado(text), public.cfx_mp_neg_revisar_pendientes() from public, anon, authenticated;
revoke all on function public.cfx_mp_neg_estado(), public.cfx_mp_neg_guardar(text, boolean) from public, anon;
grant execute on function public.cfx_mp_neg_estado(), public.cfx_mp_neg_guardar(text, boolean) to authenticated;
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'cfx-mp-neg';
  perform cron.schedule('cfx-mp-neg', '* * * * *', 'select public.cfx_mp_neg_revisar_pendientes()');
exception when others then
  raise notice 'Revisión de Mercado Pago de los negocios no programada (%).', sqlerrm;
end $$;

-- ---------------------------------------------------------------------
-- G106 ⚡ PAGO AUTOMÁTICO CON TARJETA (suscripción "preapproval" de Mercado Pago, con el MP PROPIO del negocio).
--   La persona autoriza su tarjeta 1 vez en Mercado Pago; MP la cobra sola cada mes, sin que nadie toque nada.
--   La app crea la suscripción con cfx_mp_neg_suscribir(negocio, ref, título, monto, correo, volver, inicio) → url de MP.
--   La BASE pregunta a MP (al volver y con el cron 'cfx-mp-neg'): estado de la suscripción + cobros aprobados (CLP, monto
--   completo, cada cobro 1 sola vez) → gancho de la app cfx_mp_neg_sub_app(ref, evento, pago, monto); evento = 'activa' | 'cobro' | 'cancelada'.
--   cfx_mp_neg_sub_cancelar(ref) la apaga EN Mercado Pago (si MP no responde, no se marca: se reintenta).
-- ---------------------------------------------------------------------
create table if not exists public.cfx_mp_neg_subs (
  id          uuid primary key default gen_random_uuid(),
  negocio     uuid not null,
  ref         text not null,
  titulo      text,
  monto       int not null check (monto > 0),
  preapproval text unique,
  estado      text not null default 'pendiente' check (estado in ('pendiente', 'activa', 'pausada', 'cancelada')),
  cobros      int not null default 0,
  ultimo_at   timestamptz,
  revisado_at timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists cfx_mp_neg_subs_ref on public.cfx_mp_neg_subs (ref, created_at desc);
create index if not exists cfx_mp_neg_subs_viva on public.cfx_mp_neg_subs (revisado_at) where estado <> 'cancelada';
alter table public.cfx_mp_neg_subs enable row level security;
revoke all on public.cfx_mp_neg_subs from anon, authenticated;

create table if not exists public.cfx_mp_neg_sub_pagos (
  id    text primary key,          -- n° del cobro autorizado de MP (1 sola vez)
  sub   uuid not null,
  pago  text,
  monto int not null,
  at    timestamptz not null default now()
);
alter table public.cfx_mp_neg_sub_pagos enable row level security;
revoke all on public.cfx_mp_neg_sub_pagos from anon, authenticated;

create or replace function public._cfx_mp_neg_sub_gancho(p_ref text, p_evento text, p_pago text, p_monto int) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if to_regprocedure('public.cfx_mp_neg_sub_app(text, text, text, integer)') is not null then
    execute 'select public.cfx_mp_neg_sub_app($1, $2, $3, $4)' using p_ref, p_evento, p_pago, p_monto;
  end if;
end $$;

-- La app pide la suscripción (solo desde sus funciones). Devuelve { ok, url } o { ok: false, error }.
create or replace function public.cfx_mp_neg_suscribir(p_negocio uuid, p_ref text, p_titulo text, p_monto int, p_email text, p_volver text, p_inicio timestamptz default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare tk text; s public.cfx_mp_neg_subs; r jsonb; v text := left(coalesce(p_volver, ''), 500); m text := lower(trim(coalesce(p_email, '')));
  ini timestamptz := greatest(coalesce(p_inicio, now()), now() + interval '5 minutes');
begin
  select public.cfx_secreto(token) into tk from public.cfx_mp_negocio where negocio = p_negocio and activo;
  if tk is null then return jsonb_build_object('ok', false, 'error', 'Este negocio no tiene Mercado Pago activo'); end if;
  if coalesce(p_monto, 0) < 1 then return jsonb_build_object('ok', false, 'error', 'Monto no válido'); end if;
  if m !~ '^[^@\s"<>]+@[^@\s"<>]+\.[a-z]{2,}$' or length(m) > 120 then return jsonb_build_object('ok', false, 'error', 'Escribe el correo de tu cuenta de Mercado Pago'); end if;
  if v !~ '^https://[^\s"<>]+$' then return jsonb_build_object('ok', false, 'error', 'Falta la dirección de regreso'); end if;
  if exists (select 1 from public.cfx_mp_neg_subs where ref = p_ref and estado in ('activa', 'pausada')) then
    return jsonb_build_object('ok', false, 'error', 'Ya tienes el pago automático');
  end if;
  update public.cfx_mp_neg_subs set estado = 'cancelada', updated_at = now() where ref = p_ref and estado = 'pendiente';  -- intento anterior sin autorizar
  insert into public.cfx_mp_neg_subs (negocio, ref, titulo, monto) values (p_negocio, left(p_ref, 120), left(coalesce(p_titulo, 'Pago mensual'), 120), p_monto)
  returning * into s;
  r := public.cfx_mp_api(tk, 'POST', '/preapproval', jsonb_build_object(
    'reason', s.titulo, 'external_reference', s.id::text, 'payer_email', m, 'back_url', v, 'status', 'pending',
    'auto_recurring', jsonb_build_object('frequency', 1, 'frequency_type', 'months', 'currency_id', 'CLP', 'transaction_amount', s.monto,
      'start_date', to_char(ini at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS".000+00:00"'))));
  if coalesce((r ->> 'status')::int, 0) not in (200, 201) or r #>> '{body,init_point}' is null or r #>> '{body,id}' is null then
    delete from public.cfx_mp_neg_subs where id = s.id;
    return jsonb_build_object('ok', false, 'error', coalesce('Mercado Pago: ' || left(r #>> '{body,message}', 160), 'Mercado Pago no respondió. Intenta de nuevo.'));
  end if;
  update public.cfx_mp_neg_subs set preapproval = left(r #>> '{body,id}', 60), revisado_at = now() where id = s.id;
  return jsonb_build_object('ok', true, 'url', r #>> '{body,init_point}');
end $$;

-- Pregunta a MP por UNA suscripción: estado + cobros nuevos. Devuelve cuántos cobros nuevos encontró.
create or replace function public.cfx_mp_neg_sub_revisar(p_id uuid) returns int
language plpgsql security definer set search_path = '' as $$
declare s public.cfx_mp_neg_subs; tk text; r jsonb; e jsonb; nuevo text; n int := 0;
begin
  select * into s from public.cfx_mp_neg_subs where id = p_id for update skip locked;
  if s.id is null or s.preapproval is null or s.estado = 'cancelada' then return 0; end if;
  select public.cfx_secreto(token) into tk from public.cfx_mp_negocio where negocio = s.negocio;
  if tk is null then return 0; end if;
  update public.cfx_mp_neg_subs set revisado_at = now() where id = s.id;
  r := public.cfx_mp_api(tk, 'GET', '/preapproval/' || s.preapproval);
  if coalesce((r ->> 'status')::int, 0) = 200 then
    nuevo := case r #>> '{body,status}' when 'authorized' then 'activa' when 'paused' then 'pausada' when 'cancelled' then 'cancelada' else s.estado end;
    if nuevo <> s.estado then
      update public.cfx_mp_neg_subs set estado = nuevo, updated_at = now() where id = s.id;
      if nuevo in ('activa', 'cancelada') then perform public._cfx_mp_neg_sub_gancho(s.ref, nuevo, null, s.monto); end if;
    end if;
  end if;
  r := public.cfx_mp_api(tk, 'GET', '/authorized_payments/search?preapproval_id=' || s.preapproval);
  for e in select x from jsonb_array_elements(coalesce(r #> '{body,results}', '[]'::jsonb)) x
           where coalesce(x #>> '{payment,status}', '') = 'approved' and coalesce(x ->> 'preapproval_id', s.preapproval) = s.preapproval
             and coalesce(x ->> 'currency_id', 'CLP') = 'CLP' and coalesce((x ->> 'transaction_amount')::numeric, 0) >= s.monto
             and x ->> 'id' is not null loop
    insert into public.cfx_mp_neg_sub_pagos (id, sub, pago, monto) values (left(e ->> 'id', 40), s.id, left(e #>> '{payment,id}', 40), s.monto)
    on conflict do nothing;
    if found then
      n := n + 1;
      update public.cfx_mp_neg_subs set cobros = cobros + 1, ultimo_at = now(), estado = case when estado = 'pendiente' then 'activa' else estado end, updated_at = now() where id = s.id;
      perform public._cfx_mp_neg_sub_gancho(s.ref, 'cobro', left(coalesce(e #>> '{payment,id}', e ->> 'id'), 40), s.monto);
    end if;
  end loop;
  return n;
end $$;

-- La app revisa las suscripciones de una referencia (al volver de MP), dentro de su propia función con su control de acceso.
create or replace function public.cfx_mp_neg_sub_revisar_ref(p_ref text) returns int
language plpgsql security definer set search_path = '' as $$
declare i uuid; n int := 0;
begin
  for i in select id from public.cfx_mp_neg_subs where ref = p_ref and estado <> 'cancelada' order by created_at desc limit 3 loop
    n := n + public.cfx_mp_neg_sub_revisar(i);
  end loop;
  return n;
end $$;

-- Lo que la app muestra: la suscripción viva más nueva de esa referencia (o null).
create or replace function public.cfx_mp_neg_sub_ver(p_ref text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('estado', estado, 'monto', monto, 'cobros', cobros, 'ultimo', ultimo_at, 'desde', created_at)
  from public.cfx_mp_neg_subs where ref = p_ref and estado <> 'cancelada' order by created_at desc limit 1
$$;

-- Apaga en Mercado Pago todas las suscripciones vivas de esa referencia. false = MP no respondió (no se marca; se reintenta).
create or replace function public.cfx_mp_neg_sub_cancelar(p_ref text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare s public.cfx_mp_neg_subs; tk text; r jsonb; todo boolean := true;
begin
  for s in select * from public.cfx_mp_neg_subs where ref = p_ref and estado <> 'cancelada' for update loop
    select public.cfx_secreto(token) into tk from public.cfx_mp_negocio where negocio = s.negocio;
    if s.preapproval is not null and tk is not null then
      r := public.cfx_mp_api(tk, 'PUT', '/preapproval/' || s.preapproval, jsonb_build_object('status', 'cancelled'));
      if coalesce((r ->> 'status')::int, 0) not in (200, 201) and coalesce(r #>> '{body,status}', '') <> 'cancelled' then todo := false; continue; end if;
    end if;
    update public.cfx_mp_neg_subs set estado = 'cancelada', updated_at = now() where id = s.id;
  end loop;
  return todo;
end $$;

-- Cron: pendientes (cada 1 min, 2 días; después se dan por abandonadas) · vivas (cada 30 min).
create or replace function public.cfx_mp_neg_subs_revisar() returns int
language plpgsql security definer set search_path = '' as $$
declare i uuid; n int := 0;
begin
  update public.cfx_mp_neg_subs set estado = 'cancelada', updated_at = now() where estado = 'pendiente' and created_at < now() - interval '2 days' and cobros = 0;
  for i in select id from public.cfx_mp_neg_subs where estado <> 'cancelada' and preapproval is not null
             and (revisado_at is null or revisado_at < now() - case when estado = 'pendiente' then interval '1 minute' else interval '30 minutes' end)
           order by revisado_at nulls first limit 30 loop
    n := n + public.cfx_mp_neg_sub_revisar(i);
  end loop;
  return n;
end $$;

revoke all on function public._cfx_mp_neg_sub_gancho(text, text, text, int), public.cfx_mp_neg_suscribir(uuid, text, text, int, text, text, timestamptz),
  public.cfx_mp_neg_sub_revisar(uuid), public.cfx_mp_neg_sub_revisar_ref(text), public.cfx_mp_neg_sub_ver(text), public.cfx_mp_neg_sub_cancelar(text),
  public.cfx_mp_neg_subs_revisar() from public, anon, authenticated;
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'cfx-mp-neg-subs';
  perform cron.schedule('cfx-mp-neg-subs', '* * * * *', 'select public.cfx_mp_neg_subs_revisar()');
exception when others then
  raise notice 'Revisión de pagos automáticos no programada (%).', sqlerrm;
end $$;

-- ---------- G112 c1 · 🔒 Llaves de pago y secretos a Supabase Vault (se puede volver a correr) ----------
-- G112 c2 · 🔄 Fecha de cada llave (llave_desde / 'desde'): las pantallas avisan a los 12 meses "Cámbiala".
-- Al guardar una llave (CM → Pagos, el dueño en su app, Turnstile, GitHub, Cloudflare) un trigger la pasa a Vault y en la tabla queda
-- solo 'vault:<nombre>'. Al desconectar se borra también de Vault. Sin Vault: queda como antes (la base vieja no se rompe).
create or replace function public._cfx_vault_cfg() returns trigger
language plpgsql security definer set search_path = '' as $$
declare k text; nueva boolean := false;
begin
  if tg_op = 'DELETE' then perform public.cfx_secreto_quitar('cfx_cfg_' || old.clave || '_'); return old; end if;
  if new.clave not in ('mp', 'flow') then return new; end if;
  foreach k in array array['token', 'apikey', 'secret'] loop
    if coalesce(new.valor ->> k, '') <> '' and new.valor ->> k not like 'vault:%' then
      -- G112 c2: ¿es una llave nueva? (no la misma que ya estaba) → se anota la fecha para avisar a los 12 meses.
      nueva := nueva or tg_op = 'INSERT' or new.valor ->> k is distinct from public.cfx_secreto(old.valor ->> k);
      new.valor := jsonb_set(new.valor, array[k], to_jsonb(public.cfx_secreto_poner('cfx_cfg_' || new.clave || '_' || k, new.valor ->> k)));
    end if;
  end loop;
  if nueva or (not new.valor ? 'desde' and coalesce(new.valor ->> 'token', new.valor ->> 'apikey', '') <> '') then
    new.valor := new.valor || jsonb_build_object('desde', now());
  end if;
  return new;
end $$;
create or replace function public._cfx_vault_mp_neg() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'DELETE' then perform public.cfx_secreto_quitar('cfx_mpneg_' || old.negocio); return old; end if;
  if tg_op = 'INSERT' or (new.token not like 'vault:%' and new.token is distinct from public.cfx_secreto(old.token)) then new.llave_desde := now(); end if;
  new.token := public.cfx_secreto_poner('cfx_mpneg_' || new.negocio, new.token);
  return new;
end $$;
create or replace function public._cfx_vault_flow_neg() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'DELETE' then perform public.cfx_secreto_quitar('cfx_flowneg_' || old.negocio || '_'); return old; end if;
  if tg_op = 'INSERT' or (new.apikey not like 'vault:%' and new.apikey is distinct from public.cfx_secreto(old.apikey))
     or (new.secret not like 'vault:%' and new.secret is distinct from public.cfx_secreto(old.secret)) then new.llave_desde := now(); end if;
  new.apikey := public.cfx_secreto_poner('cfx_flowneg_' || new.negocio || '_apikey', new.apikey);
  new.secret := public.cfx_secreto_poner('cfx_flowneg_' || new.negocio || '_secret', new.secret);
  return new;
end $$;
create or replace function public._cfx_vault_secretos() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'DELETE' then perform public.cfx_secreto_quitar('cfx_sec_' || old.clave || '_'); return old; end if;
  new.valor := public.cfx_secreto_poner('cfx_sec_' || new.clave || '_', new.valor);
  return new;
end $$;
revoke all on function public._cfx_vault_cfg(), public._cfx_vault_mp_neg(), public._cfx_vault_flow_neg(), public._cfx_vault_secretos() from public, anon, authenticated;
drop trigger if exists cfx_vault on public.cfx_config;
create trigger cfx_vault before insert or update on public.cfx_config for each row execute function public._cfx_vault_cfg();
drop trigger if exists cfx_vault_borrar on public.cfx_config;
create trigger cfx_vault_borrar after delete on public.cfx_config for each row when (old.clave in ('mp', 'flow')) execute function public._cfx_vault_cfg();
drop trigger if exists cfx_vault on public.cfx_mp_negocio;
create trigger cfx_vault before insert or update on public.cfx_mp_negocio for each row execute function public._cfx_vault_mp_neg();
drop trigger if exists cfx_vault_borrar on public.cfx_mp_negocio;
create trigger cfx_vault_borrar after delete on public.cfx_mp_negocio for each row execute function public._cfx_vault_mp_neg();
drop trigger if exists cfx_vault on public.cfx_flow_negocio;
create trigger cfx_vault before insert or update on public.cfx_flow_negocio for each row execute function public._cfx_vault_flow_neg();
drop trigger if exists cfx_vault_borrar on public.cfx_flow_negocio;
create trigger cfx_vault_borrar after delete on public.cfx_flow_negocio for each row execute function public._cfx_vault_flow_neg();
drop trigger if exists cfx_vault on public.cfx_secretos;
create trigger cfx_vault before insert or update on public.cfx_secretos for each row execute function public._cfx_vault_secretos();
drop trigger if exists cfx_vault_borrar on public.cfx_secretos;
create trigger cfx_vault_borrar after delete on public.cfx_secretos for each row execute function public._cfx_vault_secretos();
-- Las llaves que ya estaban (en texto) pasan a Vault al correr este archivo (el trigger hace el trabajo; si no hay Vault, no cambia nada).
do $$
begin
  if public.cfx_vault_hay() then
    update public.cfx_config set valor = valor where clave in ('mp', 'flow') and valor::text !~ '"(token|apikey|secret)": "vault:';
    update public.cfx_mp_negocio set token = token where token not like 'vault:%';
    update public.cfx_flow_negocio set apikey = apikey where apikey not like 'vault:%' or secret not like 'vault:%';
    update public.cfx_secretos set valor = valor where valor not like 'vault:%';
  end if;
end $$;
-- La función de servidor (Cloudflare) abre su token con esto: solo la llave de servicio puede llamarla.
create or replace function public.cfx_secreto_srv(p_clave text) returns text
language sql stable security definer set search_path = '' as $$
  select public.cfx_secreto(valor) from public.cfx_secretos where clave = p_clave $$;
revoke all on function public.cfx_secreto_srv(text) from public, anon, authenticated;
do $$ begin grant execute on function public.cfx_secreto_srv(text) to service_role; exception when others then null; end $$;
-- ---------- G112 d · 🎬 Estudio de contenido (módulo 'estudio' de las 5 apps con negocios) ----------
-- Mismo motor que el 🎬 Estudio del Centro de Mando (est-motor.js, SIN API de IA): el negocio arma su base de temas, genera ideas
-- (gancho, guión, copy, hashtags, CTA, hora) y anota sus métricas para que el motor aprenda. Datos PRIVADOS de cada negocio:
-- la tabla no tiene políticas (nadie la lee directo); solo el dueño, por estas funciones. Leer y borrar: siempre (🛡️ sus datos
-- nunca se ocultan). Crear o cambiar: con el módulo (o Premium si la venta de módulos está apagada), igual que 📣 promos.
create table if not exists public.cfx_estudio (
  id      uuid primary key default gen_random_uuid(),
  negocio uuid not null,
  tipo    text not null check (tipo in ('conf', 'base', 'idea')),
  titulo  text not null default '' check (length(titulo) <= 300),
  fecha   date,
  estado  text not null default 'pendiente' check (estado in ('pendiente', 'grabada', 'publicada', 'abierto')),
  datos   jsonb not null default '{}' check (jsonb_typeof(datos) = 'object' and pg_column_size(datos) <= 6000),
  creado  timestamptz not null default now()
);
create index if not exists cfx_estudio_negocio_idx on public.cfx_estudio (negocio, tipo);
alter table public.cfx_estudio enable row level security;
revoke all on public.cfx_estudio from anon, authenticated;

-- El negocio de quien llama, solo si es el dueño (null si no).
create or replace function public.cfx_estudio_negocio() returns uuid
language sql stable security definer set search_path = '' as $$
  select n from (select public.cfx_negocio_cuenta(auth.uid()) n) x where n is not null and public.cfx_negocio_dueno(n) = auth.uid()
$$;
create or replace function public.cfx_estudio_puede(n uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select n is not null and case when public.cfx_venta_on() and 'estudio' = any (public.cfx_modulos_de_app()) then public.cfx_modulo_de('estudio', n)
    else public.cfx_negocio_premium(n) end
$$;
create or replace function public.cfx_estudio_fila(e public.cfx_estudio) returns jsonb
language sql immutable as $$
  select jsonb_build_object('id', e.id, 'tipo', e.tipo, 'titulo', e.titulo, 'fecha', e.fecha, 'estado', e.estado, 'datos', e.datos, 'created_at', e.creado)
$$;
create or replace function public.cfx_estudio_mio() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare n uuid := public.cfx_estudio_negocio();
begin
  if n is null then raise exception 'Solo el dueño del negocio'; end if;
  return jsonb_build_object('puede', public.cfx_estudio_puede(n),
    'lista', coalesce((select jsonb_agg(public.cfx_estudio_fila(e) order by e.creado) from public.cfx_estudio e where e.negocio = n), '[]'));
end $$;
-- Guarda una fila o una lista (máx. 500 por vez). Con id = cambia esa fila (solo la del mismo negocio); sin id = nueva.
-- Topes por negocio: 3000 filas de base, 3000 ideas, 1 configuración. Devuelve las filas guardadas.
create or replace function public.cfx_estudio_guardar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n uuid := public.cfx_estudio_negocio(); x jsonb; r public.cfx_estudio; out jsonb := '[]'; i uuid; t text; es text; f date; d jsonb;
begin
  if n is null then raise exception 'Solo el dueño del negocio'; end if;
  if not public.cfx_estudio_puede(n) then raise exception '🎬 Estudio de contenido es un módulo 🧩: pruébalo gratis o actívalo en Mi plan y módulos'; end if;
  if jsonb_typeof(p) = 'object' then p := jsonb_build_array(p); end if;
  if jsonb_typeof(p) is distinct from 'array' or jsonb_array_length(p) = 0 then raise exception 'Nada que guardar'; end if;
  if jsonb_array_length(p) > 500 then raise exception 'Máximo 500 filas por vez'; end if;
  for x in select * from jsonb_array_elements(p) loop
    i := nullif(x ->> 'id', '')::uuid;
    d := coalesce(x -> 'datos', '{}'); if jsonb_typeof(d) <> 'object' then d := '{}'; end if;
    if pg_column_size(d) > 6000 then raise exception 'Idea muy larga'; end if;
    f := case when coalesce(x ->> 'fecha', '') ~ '^\d{4}-\d{2}-\d{2}' then left(x ->> 'fecha', 10)::date end;
    if i is not null then
      update public.cfx_estudio set titulo = left(trim(coalesce(x ->> 'titulo', titulo)), 300),
        fecha = case when x ? 'fecha' then f else fecha end,
        estado = case when x ->> 'estado' in ('pendiente', 'grabada', 'publicada', 'abierto') then x ->> 'estado' else estado end,
        datos = case when x ? 'datos' then d else datos end
      where id = i and negocio = n returning * into r;
      if r.id is null then raise exception 'No encontrada'; end if;
    else
      t := x ->> 'tipo';
      if t is null or t not in ('conf', 'base', 'idea') then raise exception 'Tipo inválido'; end if;
      if t = 'conf' and exists (select 1 from public.cfx_estudio where negocio = n and tipo = 'conf') then
        update public.cfx_estudio set datos = d where negocio = n and tipo = 'conf' returning * into r;
      else
        if (select count(*) from public.cfx_estudio where negocio = n and tipo = t) >= 3000 then
          raise exception 'Llegaste al máximo de 3000 %: borra algunas', case when t = 'base' then 'filas de base' else 'ideas' end; end if;
        es := case when x ->> 'estado' in ('pendiente', 'grabada', 'publicada', 'abierto') then x ->> 'estado' when t = 'idea' then 'pendiente' else 'abierto' end;
        insert into public.cfx_estudio (negocio, tipo, titulo, fecha, estado, datos)
        values (n, t, left(trim(coalesce(x ->> 'titulo', '')), 300), f, es, d) returning * into r;
      end if;
    end if;
    out := out || jsonb_build_array(public.cfx_estudio_fila(r)); r := null;
  end loop;
  return out;
end $$;
-- Borrar es siempre posible (son sus datos), con o sin el módulo.
create or replace function public.cfx_estudio_borrar(p_ids uuid[]) returns int
language plpgsql security definer set search_path = '' as $$
declare n uuid := public.cfx_estudio_negocio(); k int;
begin
  if n is null then raise exception 'Solo el dueño del negocio'; end if;
  delete from public.cfx_estudio where negocio = n and id = any (coalesce(p_ids, '{}'));
  get diagnostics k = row_count;
  return k;
end $$;
revoke all on function public.cfx_estudio_negocio(), public.cfx_estudio_puede(uuid), public.cfx_estudio_fila(public.cfx_estudio) from public, anon, authenticated;
revoke all on function public.cfx_estudio_mio(), public.cfx_estudio_guardar(jsonb), public.cfx_estudio_borrar(uuid[]) from public, anon;
grant execute on function public.cfx_estudio_mio(), public.cfx_estudio_guardar(jsonb), public.cfx_estudio_borrar(uuid[]) to authenticated;
-- ===================== G122 🖼️ Fotos a Storage (núcleo) =====================
-- Bucket público 'vitrina': cada uno sube SOLO a su carpeta (<su id>/<uuid>.webp), hasta 700 KB, solo imágenes. Nadie lista lo ajeno.
-- Las apps aceptan en sus fotos de vitrina el texto base64 de siempre O una URL de este bucket (cfx_foto_ok). Lo viejo sigue igual.
do $$ begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('vitrina', 'vitrina', true, 716800, array['image/webp', 'image/jpeg', 'image/png'])
    on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
    drop policy if exists cfx_vitrina_subir on storage.objects;
    drop policy if exists cfx_vitrina_ver on storage.objects;
    drop policy if exists cfx_vitrina_borrar on storage.objects;
    create policy cfx_vitrina_subir on storage.objects for insert to authenticated
      with check (bucket_id = 'vitrina' and (storage.foldername(name))[1] = (select auth.uid())::text);
    create policy cfx_vitrina_ver on storage.objects for select to authenticated
      using (bucket_id = 'vitrina' and (storage.foldername(name))[1] = (select auth.uid())::text);
    create policy cfx_vitrina_borrar on storage.objects for delete to authenticated
      using (bucket_id = 'vitrina' and (storage.foldername(name))[1] = (select auth.uid())::text);
  end if;
end $$;

-- ¿Es una foto de la nube (bucket vitrina de Supabase)? Con p_uid: además, ¿la subió esa persona?
create or replace function public.cfx_foto_nube(t text, p_uid uuid default null) returns boolean
language sql immutable set search_path = '' as $$
  select coalesce(t, '') ~ '^https://[a-z0-9-]+\.supabase\.co/storage/v1/object/public/vitrina/[0-9a-f-]{36}/[0-9a-f-]{36}\.(webp|jpg|png)$'
    and (p_uid is null or split_part(split_part(t, '/vitrina/', 2), '/', 1) = p_uid::text)
$$;
-- Foto de vitrina válida: vacía, base64 liviano (≤ maxlen) o de la nube.
create or replace function public.cfx_foto_ok(t text, maxlen int) returns boolean
language sql immutable set search_path = '' as $$
  select coalesce(t, '') = '' or (t ~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$' and length(t) <= maxlen) or public.cfx_foto_nube(t)
$$;
grant execute on function public.cfx_foto_nube(text, uuid), public.cfx_foto_ok(text, int) to authenticated, anon;

-- G122 b 🧹 Fotos huérfanas: de una lista de MIS archivos (<uuid>.webp de mi carpeta), ¿cuáles NO aparecen en ninguna tabla?
-- Busca en TODAS las columnas de texto/json/arreglo de la app (también respaldos), así nunca se borra una foto en uso.
-- Ante cualquier duda (nombre raro, error al leer una tabla) devuelve vacío: no se borra nada.
create or replace function public.cfx_fotos_libres(p_nombres text[]) returns text[]
language plpgsql security definer set search_path = '' as $$
declare u uuid := auth.uid(); pat text; r record; txt text; n text; usados text[] := '{}'; libres text[] := '{}';
begin
  if u is null or coalesce(array_length(p_nombres, 1), 0) = 0 or array_length(p_nombres, 1) > 1000 then return '{}'; end if;
  foreach n in array p_nombres loop
    if n is null or n !~ '^[0-9a-f-]{36}\.(webp|jpg|png)$' then return '{}'; end if;
  end loop;
  pat := '%/vitrina/' || u::text || '/%';
  for r in select c.table_schema s, c.table_name t, c.column_name col
      from information_schema.columns c join information_schema.tables tb on tb.table_schema = c.table_schema and tb.table_name = c.table_name
      where tb.table_type = 'BASE TABLE' and c.data_type in ('text', 'character varying', 'jsonb', 'json', 'ARRAY')
        and c.table_schema not in ('storage', 'auth', 'information_schema', 'vault', 'pgsodium', 'pgsodium_masks', 'realtime', '_realtime',
          'supabase_functions', 'supabase_migrations', 'extensions', 'graphql', 'graphql_public', 'net', 'cron', 'pgbouncer', '_analytics')
        and c.table_schema !~ '^pg_' loop
    begin
      execute format('select string_agg(%I::text, '' '') from %I.%I where %I::text like $1', r.col, r.s, r.t, r.col) into txt using pat;
    exception when others then return '{}';
    end;
    if txt is not null then
      foreach n in array p_nombres loop
        if position(u::text || '/' || n in txt) > 0 then usados := usados || n; end if;
      end loop;
    end if;
  end loop;
  foreach n in array p_nombres loop
    if not (n = any(usados)) then libres := libres || n; end if;
  end loop;
  return libres;
end $$;
revoke all on function public.cfx_fotos_libres(text[]) from public, anon;
grant execute on function public.cfx_fotos_libres(text[]) to authenticated;
-- <<< CFX núcleo

-- G95 🎁 Prueba Pro por botón (núcleo cfx_pro_probar): en Billetera la prueba es prueba_hasta (estado 'prueba'), no un pago.
-- Los correos que ya probaron (privado.pruebas_usadas, mismo hash sha256 del correo) pasan a la lista del núcleo.
insert into public.cfx_pruebas_usadas (hash, item) select email_hash, 'pro' from privado.pruebas_usadas on conflict do nothing;
create or replace function public.cfx_pro_prueba_app(p_cuenta uuid, p_rol text, p_dias int) returns timestamptz
language plpgsql security definer set search_path = public, pg_temp as $$
declare n record;
begin
  update public.negocios set prueba_hasta = greatest(coalesce(prueba_hasta, now()), now()) + make_interval(days => p_dias)
  where dueno = p_cuenta and estado <> 'eliminado' returning id, prueba_hasta into n;
  if n.id is null then raise exception 'La cuenta no tiene billetera'; end if;
  insert into privado.pruebas_usadas (email_hash) select privado.sha(lower(u.email)) from auth.users u where u.id = p_cuenta and u.email is not null on conflict do nothing;
  perform privado.aplicar_plan(n.id);
  return n.prueba_hasta;
end $$;
revoke all on function public.cfx_pro_prueba_app(uuid, text, int) from public, anon, authenticated;
-- G95 🐞 el negocio es la billetera (no la cuenta): sin esto el dueño no podía probar ni comprar módulos ("Solo el dueño del negocio").
create or replace function public.cfx_negocio_dueno_app(n uuid) returns uuid
language sql stable security definer set search_path = public, pg_temp as $$ select dueno from public.negocios where id = n $$;
revoke all on function public.cfx_negocio_dueno_app(uuid) from public, anon, authenticated;

-- =====================================================================
-- G94 · 🧩 Billetera modular (va después del núcleo: usa cfx_modulo_mio). Lo Free/Pro que ya existía no cambia.
-- Ganchos del núcleo: el negocio es la billetera (dueño o ayudante); Premium = Pro de la billetera.
create or replace function public.cfx_negocio_de_cuenta(u uuid) returns uuid
language sql stable security definer set search_path = public, pg_temp as $$
  select m.negocio from public.miembros m join public.negocios n on n.id = m.negocio where m.usuario = u and m.activo and n.estado <> 'eliminado' limit 1
$$;
create or replace function public.cfx_es_premium(n uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$ select privado.es_premium(n) $$;
create or replace function public.cfx_modulos_app() returns text[]
language sql immutable as $$ select array['acuerdo', 'contador', 'escalonado', 'gastos_fijos', 'cuentas_pagar', 'cierre_caja', 'aviso_vence', 'estudio'] $$;  -- G112 d: + 🎬
revoke all on function public.cfx_negocio_de_cuenta(uuid), public.cfx_es_premium(uuid), public.cfx_modulos_app() from public, anon, authenticated;
-- Packs propios de Billetera (solo si siguen los de fábrica del núcleo).
update public.cfx_config set valor = jsonb_set(valor, '{packs}', jsonb_build_object(
    'basico',   jsonb_build_object('nombre', '🌱 Cobrar mejor', 'detalle', 'Acuerdos firmados y cobranza que sube de tono sola', 'precio', 1490, 'modulos', jsonb_build_array('acuerdo', 'escalonado')),
    'completo', jsonb_build_object('nombre', '💎 Completo', 'detalle', 'Todos los módulos, también los nuevos', 'precio', 2490, 'destacado', true, 'modulos', '*')))
where clave = 'modulos_venta' and valor #>> '{packs,crecer,modulos,4}' = 'carrito';
-- G112 b: 3 packs iguales en todas las apps (🌱 Básico · ⭐ Normal · 💎 Completo). Solo si siguen los de fábrica.
update public.cfx_config set valor = jsonb_set(jsonb_set(jsonb_set(valor, '{packs,basico,nombre}', '"🌱 Básico"'), '{packs,completo,destacado}', 'false'), '{packs,crecer}',
    jsonb_build_object('nombre', '⭐ Normal', 'detalle', 'Cobra a tiempo y ordena tu caja', 'precio', 1990, 'destacado', true,
                       'modulos', jsonb_build_array('acuerdo', 'escalonado', 'aviso_vence', 'gastos_fijos', 'cierre_caja')))
where clave = 'modulos_venta' and valor #> '{packs,crecer}' is null and valor #>> '{packs,basico,nombre}' = '🌱 Cobrar mejor';
-- G112 d: 🎬 Estudio de contenido entra al ⭐ Normal (el 💎 Completo ya trae todos). Solo si sigue el de fábrica.
update public.cfx_config set valor = jsonb_set(valor, '{packs,crecer,modulos}', (valor #> '{packs,crecer,modulos}') || '["estudio"]')
where clave = 'modulos_venta' and valor #> '{packs,crecer,modulos}' = '["acuerdo", "escalonado", "aviso_vence", "gastos_fijos", "cierre_caja"]'::jsonb;

-- Lo que puede usar mi billetera: {"acuerdo": true, …}
create or replace function public.mis_modulos() returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_object_agg(k, public.cfx_modulo_mio(k)), '{}') from unnest(public.cfx_modulos_app()) k
$$;
create or replace function privado.modulo_o_error(p text) returns void language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if privado.mi_negocio() is null then raise exception 'Sin billetera'; end if;
  if not public.cfx_modulo_mio(p) then raise exception 'Este módulo no está activo: actívalo en Más → 🧩 Módulos'; end if;
end $$;

-- 📝 Acuerdo de pago firmado por link
create table if not exists public.acuerdos (
  id uuid primary key default gen_random_uuid(),
  negocio uuid not null references public.negocios (id) on delete cascade,
  cliente uuid not null references public.clientes (id) on delete cascade,
  monto int not null check (monto between 1 and 99999999),
  cuotas int not null check (cuotas between 1 and 24),
  primera date not null,
  cada text not null default 'mes' check (cada in ('semana', 'quincena', 'mes')),
  nota text not null default '' check (char_length(nota) <= 300),
  estado text not null default 'pendiente' check (estado in ('pendiente', 'firmado', 'rechazado', 'anulado')),
  firma_nombre text check (firma_nombre is null or char_length(firma_nombre) <= 80),
  firmado_at timestamptz,
  creado timestamptz not null default now()
);
create index if not exists acuerdos_cli on public.acuerdos (cliente, creado desc);
alter table public.acuerdos enable row level security;
revoke all on public.acuerdos from anon, authenticated;
create or replace function public.acuerdo_crear(p_cliente uuid, p_monto int, p_cuotas int, p_primera date, p_cada text, p_nota text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare n uuid := privado.mi_negocio(); r public.acuerdos;
begin
  perform privado.modulo_o_error('acuerdo');
  if not exists (select 1 from public.clientes c where c.id = p_cliente and c.negocio = n) then raise exception 'Cliente no encontrado'; end if;
  if coalesce(p_monto, 0) < 1 or p_monto > 99999999 then raise exception 'Monto no válido'; end if;
  if coalesce(p_cuotas, 0) not between 1 and 24 then raise exception 'Entre 1 y 24 cuotas'; end if;
  if p_primera is null or p_primera < current_date - 1 or p_primera > current_date + 366 then raise exception 'Fecha de la primera cuota no válida'; end if;
  update public.acuerdos set estado = 'anulado' where cliente = p_cliente and estado = 'pendiente';
  insert into public.acuerdos (negocio, cliente, monto, cuotas, primera, cada, nota)
  values (n, p_cliente, p_monto, p_cuotas, p_primera, case when p_cada in ('semana', 'quincena') then p_cada else 'mes' end, left(coalesce(p_nota, ''), 300)) returning * into r;
  return to_jsonb(r);
end $$;
create or replace function public.acuerdos_de(p_cliente uuid) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(to_jsonb(a) order by a.creado desc), '[]') from public.acuerdos a
  where a.cliente = p_cliente and a.negocio = privado.mi_negocio()
$$;
create or replace function public.acuerdo_anular(p_id uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.acuerdos set estado = 'anulado' where id = p_id and negocio = privado.mi_negocio() and estado in ('pendiente', 'firmado');
  if not found then raise exception 'Acuerdo no encontrado'; end if;
end $$;
-- Portal del cliente (link + PIN): ve su acuerdo y lo acepta escribiendo su nombre (o lo rechaza).
create or replace function public.portal_acuerdo(p_sesion text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_cli uuid := privado.sesion(p_sesion);
begin
  return (select to_jsonb(x) from (select id, monto, cuotas, primera, cada, nota, estado, firma_nombre, firmado_at from public.acuerdos
          where cliente = v_cli and estado in ('pendiente', 'firmado') order by creado desc limit 1) x);
end $$;
create or replace function public.portal_acuerdo_firmar(p_sesion text, p_id uuid, p_nombre text, p_acepta boolean) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_cli uuid := privado.sesion(p_sesion); a public.acuerdos; nm text := btrim(coalesce(p_nombre, ''));
begin
  select * into a from public.acuerdos where id = p_id and cliente = v_cli and estado = 'pendiente' for update;
  if a.id is null then raise exception 'El acuerdo ya no está pendiente'; end if;
  if p_acepta and char_length(nm) < 3 then raise exception 'Escribe tu nombre completo para firmar'; end if;
  update public.acuerdos set estado = case when p_acepta then 'firmado' else 'rechazado' end,
    firma_nombre = case when p_acepta then left(nm, 80) end, firmado_at = now() where id = a.id returning * into a;
  perform privado.avisar_usuario((select dueno from public.negocios where id = a.negocio),
    case when p_acepta then '📝 Acuerdo firmado' else '📝 Acuerdo rechazado' end,
    (select nombre from public.clientes where id = v_cli) || case when p_acepta then ' aceptó el acuerdo de pago' else ' no aceptó el acuerdo de pago' end, 'app/#cliente/' || v_cli, true);
  return jsonb_build_object('estado', a.estado, 'firmado_at', a.firmado_at);
end $$;

-- 🧮 Link para el contador (solo lectura, sin nombres de clientes)
alter table public.negocios add column if not exists contador_token text;
create unique index if not exists negocios_contador on public.negocios (contador_token) where contador_token is not null;
create or replace function public.contador_link(p_on boolean) returns text
language plpgsql security definer set search_path = public, pg_temp as $$
declare n uuid := privado.mi_negocio(); t text;
begin
  perform privado.modulo_o_error('contador');
  if privado.mi_rol() <> 'dueno' then raise exception 'Solo el dueño'; end if;
  if not p_on then update public.negocios set contador_token = null where id = n; return null; end if;
  select contador_token into t from public.negocios where id = n;
  if t is null then t := replace(replace(encode(extensions.gen_random_bytes(18), 'base64'), '/', '_'), '+', '-'); update public.negocios set contador_token = t where id = n; end if;
  return t;
end $$;
create or replace function public.contador_ver(p_token text, p_mes text) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare n public.negocios; d date; h date;
begin
  if coalesce(p_token, '') !~ '^[A-Za-z0-9_=-]{20,40}$' then raise exception 'Link no válido'; end if;
  select * into n from public.negocios where contador_token = p_token and estado = 'activo';
  if n.id is null or not public.cfx_modulo_de('contador', n.id) then raise exception 'Este link ya no está activo'; end if;
  d := case when coalesce(p_mes, '') ~ '^\d{4}-\d{2}$' then (p_mes || '-01')::date else date_trunc('month', now() at time zone 'America/Santiago')::date end;
  h := (d + interval '1 month')::date;
  return jsonb_build_object('negocio', n.nombre, 'mes', to_char(d, 'YYYY-MM'),
    'caja', coalesce((select jsonb_agg(jsonb_build_object('tipo', tipo, 'categoria', categoria, 'total', t, 'n', k) order by tipo, t desc) from (
        select tipo, categoria, sum(monto)::bigint t, count(*) k from public.caja where negocio = n.id and anulado_at is null
          and (fecha at time zone 'America/Santiago')::date >= d and (fecha at time zone 'America/Santiago')::date < h group by tipo, categoria) x), '[]'),
    'fiado', (select coalesce(sum(monto), 0) from public.movimientos where negocio = n.id and signo > 0 and anulado_at is null and (fecha at time zone 'America/Santiago')::date >= d and (fecha at time zone 'America/Santiago')::date < h),
    'abonos', (select coalesce(sum(monto), 0) from public.movimientos where negocio = n.id and signo < 0 and anulado_at is null and (fecha at time zone 'America/Santiago')::date >= d and (fecha at time zone 'America/Santiago')::date < h),
    'por_cobrar', (select coalesce(sum(saldo), 0) from public.clientes where negocio = n.id and saldo > 0 and estado <> 'archivado'),
    'filas', coalesce((select jsonb_agg(jsonb_build_object('fecha', to_char(fecha at time zone 'America/Santiago', 'YYYY-MM-DD'), 'tipo', tipo, 'categoria', categoria, 'descripcion', coalesce(descripcion, ''), 'medio', medio, 'monto', monto) order by fecha)
        from (select * from public.caja where negocio = n.id and anulado_at is null and (fecha at time zone 'America/Santiago')::date >= d and (fecha at time zone 'America/Santiago')::date < h order by fecha limit 3000) c), '[]'));
end $$;

-- 🔁 Gastos fijos automáticos (se anotan en la caja al abrir la app desde su día del mes)
create table if not exists public.gastos_fijos (
  id uuid primary key default gen_random_uuid(),
  negocio uuid not null references public.negocios (id) on delete cascade,
  categoria text not null check (char_length(categoria) between 2 and 24),
  descripcion text not null default '' check (char_length(descripcion) <= 120),
  monto int not null check (monto between 1 and 99999999),
  dia int not null check (dia between 1 and 28),
  activo boolean not null default true,
  ultimo_mes text,
  creado timestamptz not null default now()
);
alter table public.gastos_fijos enable row level security;
revoke all on public.gastos_fijos from anon, authenticated;
create or replace function public.gastos_fijos_lista() returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(to_jsonb(g) order by g.dia), '[]') from public.gastos_fijos g where g.negocio = privado.mi_negocio() and privado.mi_rol() = 'dueno'
$$;
create or replace function public.gasto_fijo_guardar(p_id uuid, p_categoria text, p_descripcion text, p_monto int, p_dia int, p_activo boolean) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare n uuid := privado.mi_negocio(); r uuid;
begin
  perform privado.modulo_o_error('gastos_fijos');
  if privado.mi_rol() <> 'dueno' then raise exception 'Solo el dueño'; end if;
  if char_length(btrim(coalesce(p_categoria, ''))) not between 2 and 24 then raise exception 'Categoría de 2 a 24 letras'; end if;
  if coalesce(p_monto, 0) not between 1 and 99999999 then raise exception 'Monto no válido'; end if;
  if coalesce(p_dia, 0) not between 1 and 28 then raise exception 'Día entre 1 y 28'; end if;
  if p_id is null then
    if (select count(*) from public.gastos_fijos where negocio = n) >= 30 then raise exception 'Máximo 30 gastos fijos'; end if;
    insert into public.gastos_fijos (negocio, categoria, descripcion, monto, dia, activo) values (n, btrim(p_categoria), left(coalesce(p_descripcion, ''), 120), p_monto, p_dia, coalesce(p_activo, true)) returning id into r;
  else
    update public.gastos_fijos set categoria = btrim(p_categoria), descripcion = left(coalesce(p_descripcion, ''), 120), monto = p_monto, dia = p_dia, activo = coalesce(p_activo, true)
    where id = p_id and negocio = n returning id into r;
    if r is null then raise exception 'No encontrado'; end if;
  end if;
  return r;
end $$;
create or replace function public.gasto_fijo_borrar(p_id uuid) returns void
language sql security definer set search_path = public, pg_temp as $$
  delete from public.gastos_fijos where id = p_id and negocio = privado.mi_negocio() and privado.mi_rol() = 'dueno'
$$;
-- Anota los que ya llegaron a su día este mes (1 vez por mes cada uno). Devuelve cuántos anotó.
create or replace function public.gastos_fijos_aplicar() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare n uuid := privado.mi_negocio(); g record; k int := 0; hoy date := (now() at time zone 'America/Santiago')::date; mes text := to_char(hoy, 'YYYY-MM');
begin
  if n is null or not public.cfx_modulo_mio('gastos_fijos') then return 0; end if;
  for g in select * from public.gastos_fijos where negocio = n and activo and coalesce(ultimo_mes, '') <> mes and dia <= extract(day from hoy) for update loop
    insert into public.caja (id, negocio, tipo, monto, categoria, descripcion, medio, fecha, creado_por)
    values (gen_random_uuid(), n, 'gasto', g.monto, g.categoria, left('🔁 ' || coalesce(nullif(g.descripcion, ''), g.categoria), 120), 'transferencia',
            ((mes || '-' || lpad(g.dia::text, 2, '0'))::date + time '12:00') at time zone 'America/Santiago', auth.uid());
    update public.gastos_fijos set ultimo_mes = mes where id = g.id; k := k + 1;
  end loop;
  return k;
end $$;
revoke all on function public.mis_modulos(), privado.modulo_o_error(text), public.acuerdo_crear(uuid, int, int, date, text, text), public.acuerdos_de(uuid), public.acuerdo_anular(uuid),
  public.portal_acuerdo(text), public.portal_acuerdo_firmar(text, uuid, text, boolean), public.contador_link(boolean), public.contador_ver(text, text),
  public.gastos_fijos_lista(), public.gasto_fijo_guardar(uuid, text, text, int, int, boolean), public.gasto_fijo_borrar(uuid), public.gastos_fijos_aplicar() from public, anon, authenticated;
grant execute on function public.mis_modulos(), privado.modulo_o_error(text), public.acuerdo_crear(uuid, int, int, date, text, text), public.acuerdos_de(uuid), public.acuerdo_anular(uuid),
  public.contador_link(boolean), public.gastos_fijos_lista(), public.gasto_fijo_guardar(uuid, text, text, int, int, boolean), public.gasto_fijo_borrar(uuid), public.gastos_fijos_aplicar() to authenticated;
grant execute on function public.portal_acuerdo(text), public.portal_acuerdo_firmar(text, uuid, text, boolean), public.contador_ver(text, text) to anon, authenticated;

-- =====================================================================
-- G104 · 🧩 3 módulos más: 📤 cuentas_pagar · 🧮 cierre_caja · 🔔 aviso_vence (todo se valida aquí).
-- 📤 Lo que debo a proveedores: vencimiento, aviso y "Pagar" → queda como gasto en la caja.
create table if not exists public.cuentas_pagar (
  id uuid primary key default gen_random_uuid(),
  negocio uuid not null references public.negocios (id) on delete cascade,
  proveedor text not null check (char_length(proveedor) between 2 and 60),
  detalle text not null default '' check (char_length(detalle) <= 120),
  monto int not null check (monto between 1 and 99999999),
  vence date not null,
  estado text not null default 'pendiente' check (estado in ('pendiente', 'pagada')),
  pagada_at timestamptz,
  caja uuid,
  avisada date,
  creado timestamptz not null default now()
);
create index if not exists cuentas_pagar_neg on public.cuentas_pagar (negocio, estado, vence);
alter table public.cuentas_pagar enable row level security;
revoke all on public.cuentas_pagar from anon, authenticated;
create or replace function public.cpp_lista() returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(to_jsonb(c) order by c.estado, case when c.estado = 'pendiente' then c.vence end, c.pagada_at desc), '[]') from (
    select * from public.cuentas_pagar where negocio = privado.mi_negocio() and privado.mi_rol() = 'dueno'
      and (estado = 'pendiente' or pagada_at > now() - interval '60 days') order by estado, vence limit 300) c
$$;
create or replace function public.cpp_guardar(p_id uuid, p_proveedor text, p_detalle text, p_monto int, p_vence date) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare n uuid := privado.exigir(true); r uuid; pv text := btrim(coalesce(p_proveedor, ''));
begin
  perform privado.modulo_o_error('cuentas_pagar');
  if char_length(pv) not between 2 and 60 then raise exception 'Escribe el proveedor (2 a 60 letras)'; end if;
  if coalesce(p_monto, 0) not between 1 and 99999999 then raise exception 'Monto no válido'; end if;
  if p_vence is null or p_vence < current_date - 365 or p_vence > current_date + 730 then raise exception 'Fecha de vencimiento no válida'; end if;
  if p_id is null then
    if (select count(*) from public.cuentas_pagar where negocio = n and estado = 'pendiente') >= 200 then raise exception 'Máximo 200 cuentas por pagar pendientes'; end if;
    insert into public.cuentas_pagar (negocio, proveedor, detalle, monto, vence) values (n, pv, left(coalesce(p_detalle, ''), 120), p_monto, p_vence) returning id into r;
  else
    update public.cuentas_pagar set proveedor = pv, detalle = left(coalesce(p_detalle, ''), 120), monto = p_monto, vence = p_vence, avisada = null
    where id = p_id and negocio = n and estado = 'pendiente' returning id into r;
    if r is null then raise exception 'No encontrada o ya pagada'; end if;
  end if;
  return r;
end $$;
create or replace function public.cpp_borrar(p_id uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  delete from public.cuentas_pagar where id = p_id and negocio = privado.exigir(true) and estado = 'pendiente';
  if not found then raise exception 'No encontrada o ya pagada'; end if;
end $$;
-- Pagar: queda pagada y se anota como gasto en la caja (categoría "Proveedores"), con el monto de la base.
create or replace function public.cpp_pagar(p_id uuid, p_medio text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare n uuid := privado.exigir(true); c public.cuentas_pagar; k uuid := gen_random_uuid();
begin
  perform privado.modulo_o_error('cuentas_pagar');
  select * into c from public.cuentas_pagar where id = p_id and negocio = n for update;
  if c.id is null then raise exception 'No encontrada'; end if;
  if c.estado <> 'pendiente' then raise exception 'Esta cuenta ya está pagada'; end if;
  insert into public.caja (id, negocio, tipo, monto, categoria, descripcion, medio, fecha, creado_por)
  values (k, n, 'gasto', c.monto, 'Proveedores', left('📤 ' || c.proveedor || coalesce(nullif(' · ' || c.detalle, ' · '), ''), 120),
          case when p_medio in ('efectivo', 'transferencia', 'tarjeta', 'otro') then p_medio else 'transferencia' end, now(), auth.uid());
  update public.cuentas_pagar set estado = 'pagada', pagada_at = now(), caja = k where id = c.id;
  return jsonb_build_object('ok', true, 'caja', k);
end $$;
-- Resumen para el inicio: vencidas y las que vencen en 3 días.
create or replace function public.cpp_pronto() returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object('n', count(*), 'total', coalesce(sum(monto), 0), 'vencidas', count(*) filter (where vence < privado.hoy()))
  from public.cuentas_pagar where negocio = privado.mi_negocio() and privado.mi_rol() = 'dueno' and estado = 'pendiente'
    and vence <= privado.hoy() + 3 and public.cfx_modulo_mio('cuentas_pagar')
$$;

-- 🧮 Cierre de caja del día: efectivo esperado (inicial + entradas − salidas en efectivo) vs lo contado.
create table if not exists public.cierres_caja (
  id uuid primary key default gen_random_uuid(),
  negocio uuid not null references public.negocios (id) on delete cascade,
  dia date not null,
  inicial int not null default 0 check (inicial between 0 and 99999999),
  esperado int not null,
  contado int not null check (contado between 0 and 99999999),
  diferencia int not null,
  nota text not null default '' check (char_length(nota) <= 200),
  creado_por uuid,
  creado timestamptz not null default now(),
  unique (negocio, dia)
);
alter table public.cierres_caja enable row level security;
revoke all on public.cierres_caja from anon, authenticated;
-- Lo que entró y salió en efectivo ese día (los montos salen de la base, no de la pantalla).
create or replace function privado.efectivo_dia(p_neg uuid, p_dia date) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'ventas', (select coalesce(sum(monto), 0) from public.caja where negocio = p_neg and tipo = 'ingreso' and medio = 'efectivo' and anulado_at is null and (fecha at time zone 'America/Santiago')::date = p_dia),
    'abonos', (select coalesce(sum(monto), 0) from public.movimientos where negocio = p_neg and tipo = 'abono' and medio = 'efectivo' and anulado_at is null and (fecha at time zone 'America/Santiago')::date = p_dia),
    'gastos', (select coalesce(sum(monto), 0) from public.caja where negocio = p_neg and tipo = 'gasto' and medio = 'efectivo' and anulado_at is null and (fecha at time zone 'America/Santiago')::date = p_dia),
    'otros', (select coalesce(sum(monto), 0) from public.caja where negocio = p_neg and tipo = 'ingreso' and medio <> 'efectivo' and anulado_at is null and (fecha at time zone 'America/Santiago')::date = p_dia))
$$;
create or replace function public.cierre_ver(p_dia date) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare n uuid := privado.exigir(); d date := coalesce(p_dia, privado.hoy()); e jsonb; ant int;
begin
  perform privado.modulo_o_error('cierre_caja');
  if d > privado.hoy() or d < privado.hoy() - 62 then raise exception 'Elige un día de los últimos 2 meses'; end if;
  e := privado.efectivo_dia(n, d);
  select contado into ant from public.cierres_caja where negocio = n and dia < d order by dia desc limit 1;
  return e || jsonb_build_object('dia', d, 'inicial_sugerido', coalesce(ant, 0),
    'cierre', (select to_jsonb(c) from public.cierres_caja c where c.negocio = n and c.dia = d),
    'historial', coalesce((select jsonb_agg(jsonb_build_object('dia', dia, 'esperado', esperado, 'contado', contado, 'diferencia', diferencia, 'nota', nota) order by dia desc)
      from (select * from public.cierres_caja where negocio = n order by dia desc limit 30) h), '[]'));
end $$;
create or replace function public.cierre_guardar(p_dia date, p_inicial int, p_contado int, p_nota text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare n uuid := privado.exigir(); d date := coalesce(p_dia, privado.hoy()); e jsonb; esp int; r public.cierres_caja;
begin
  perform privado.modulo_o_error('cierre_caja');
  if d > privado.hoy() or d < privado.hoy() - 62 then raise exception 'Elige un día de los últimos 2 meses'; end if;
  if coalesce(p_inicial, -1) not between 0 and 99999999 then raise exception 'Efectivo inicial no válido'; end if;
  if coalesce(p_contado, -1) not between 0 and 99999999 then raise exception 'Escribe cuánto efectivo contaste'; end if;
  e := privado.efectivo_dia(n, d);
  esp := p_inicial + (e ->> 'ventas')::int + (e ->> 'abonos')::int - (e ->> 'gastos')::int;
  insert into public.cierres_caja (negocio, dia, inicial, esperado, contado, diferencia, nota, creado_por)
  values (n, d, p_inicial, esp, p_contado, p_contado - esp, left(coalesce(p_nota, ''), 200), auth.uid())
  on conflict (negocio, dia) do update set inicial = excluded.inicial, esperado = excluded.esperado, contado = excluded.contado,
    diferencia = excluded.diferencia, nota = excluded.nota, creado_por = excluded.creado_por, creado = now()
  returning * into r;
  if r.diferencia <> 0 and privado.mi_rol() <> 'dueno' then
    perform privado.avisar_usuario((select dueno from public.negocios where id = n), '🧮 Cierre de caja con diferencia',
      to_char(d, 'DD/MM') || ': ' || case when r.diferencia > 0 then 'sobran ' else 'faltan ' end || privado.pesos(abs(r.diferencia)), 'app/#cierre', true);
  end if;
  return to_jsonb(r);
end $$;

-- 🔔 Aviso de vencimiento automático: 1 día antes y el día que vence, aviso al celular del cliente (si activó avisos en su link)
-- respetando la ley de cobranza (cuenta como recordatorio: máx. 2 por semana, lunes a sábado 08–20). Al dueño: resumen del día.
alter table public.clientes add column if not exists aviso_auto date;
create or replace function privado.avisar_vencimientos() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare c record; r record; k int := 0; hoy date := privado.hoy(); ng record;
begin
  for c in select cl.*, n.nombre neg_nombre from public.clientes cl join public.negocios n on n.id = cl.negocio
    where n.estado = 'activo' and cl.estado not in ('borrado', 'archivado') and cl.saldo > 0 and cl.prox_venc between hoy and hoy + 1
      and coalesce(cl.aviso_auto, date '2000-01-01') < hoy and public.cfx_modulo_de('aviso_vence', cl.negocio)
      and exists (select 1 from public.push_subs s where s.cliente = cl.id) limit 2000 loop
    select * into r from privado.cobro_permitido(c.id);
    if not r.ok then continue; end if;
    insert into public.recordatorios (negocio, cliente, canal, tono, enviado_por) values (c.negocio, c.id, 'push', 'auto', null);
    update public.clientes set aviso_auto = hoy where id = c.id;
    perform privado.push(null, null, c.id, '🔔 ' || c.neg_nombre || ': ' || case when c.prox_venc = hoy then 'tu pago vence hoy' else 'tu pago vence mañana' end,
      'Tu saldo es ' || privado.pesos(c.saldo) || '. Puedes pagar o subir tu comprobante desde tu link.', 'c/');
    k := k + 1;
  end loop;
  -- Resumen al dueño (1 vez al día): quiénes vencen hoy, para cobrarles con un toque.
  for ng in select n.id, n.dueno, count(*) q, sum(cl.saldo) t from public.negocios n join public.clientes cl on cl.negocio = n.id
    where n.estado = 'activo' and cl.estado not in ('borrado', 'archivado') and cl.saldo > 0 and cl.prox_venc = hoy and public.cfx_modulo_de('aviso_vence', n.id)
      and coalesce(n.aviso_vence_at, date '2000-01-01') < hoy group by n.id, n.dueno loop
    update public.negocios set aviso_vence_at = hoy where id = ng.id;
    perform privado.avisar_usuario(ng.dueno, '🔔 Hoy vencen ' || ng.q || case when ng.q = 1 then ' cuenta' else ' cuentas' end,
      'Total ' || privado.pesos(ng.t::int) || ': cóbrales con un toque', 'app/#cobranza', true);
  end loop;
  return k;
exception when others then return k;   -- un aviso nunca debe romper el cron
end $$;
alter table public.negocios add column if not exists aviso_vence_at date;
-- Lo que la pantalla muestra: cuántos tienen avisos activos y cuántos avisos salieron en 30 días.
create or replace function public.aviso_vence_estado() returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'con_avisos', (select count(distinct s.cliente) from public.push_subs s join public.clientes c on c.id = s.cliente where c.negocio = privado.mi_negocio() and c.estado <> 'borrado'),
    'clientes', (select count(*) from public.clientes where negocio = privado.mi_negocio() and estado not in ('borrado', 'archivado')),
    'enviados', (select count(*) from public.recordatorios where negocio = privado.mi_negocio() and tono = 'auto' and at > now() - interval '30 days'),
    'proximos', (select count(*) from public.clientes where negocio = privado.mi_negocio() and saldo > 0 and estado not in ('borrado', 'archivado') and prox_venc between privado.hoy() and privado.hoy() + 7))
$$;
do $$ begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'lc-vence';
  perform cron.schedule('lc-vence', '7 13,17,21 * * *', 'select privado.avisar_vencimientos()');
exception when others then raise notice 'cron: %', sqlerrm;
end $$;

revoke all on function public.cpp_lista(), public.cpp_guardar(uuid, text, text, int, date), public.cpp_borrar(uuid), public.cpp_pagar(uuid, text), public.cpp_pronto(),
  privado.efectivo_dia(uuid, date), public.cierre_ver(date), public.cierre_guardar(date, int, int, text), privado.avisar_vencimientos(), public.aviso_vence_estado() from public, anon, authenticated;
grant execute on function public.cpp_lista(), public.cpp_guardar(uuid, text, text, int, date), public.cpp_borrar(uuid), public.cpp_pagar(uuid, text), public.cpp_pronto(),
  public.cierre_ver(date), public.cierre_guardar(date, int, int, text), public.aviso_vence_estado() to authenticated;

-- Al correr este SQL la versión de la app queda liberada al tiro: todos ven "Actualizar" (al publicar una versión nueva, sube este número).
update public.ajustes set version_liberada = '1.10.0' where id = 1 and case when version_liberada ~ '^\d+(\.\d+)*$'
  then string_to_array(version_liberada, '.')::int[] < string_to_array('1.10.0', '.')::int[] else true end;
-- =====================================================================
-- Actualización automática (núcleo CodeFix): cada 10 minutos la base revisa GitHub (rama main).
--   · Si hay una base nueva (version.json), descarga y ejecuta este mismo instalar.sql (no borra datos).
--   · La app la liberas tú cuando la pruebes (panel de la app o Centro de Mando → Liberar).
--   Si algo falla no cambia nada y lo reintenta en la siguiente vuelta. Hay que correr este archivo UNA vez.
-- =====================================================================
create or replace function public.auto_actualizar() returns text
language plpgsql security definer set search_path = '' as $f$
declare
  base constant text := 'https://raw.githubusercontent.com/CodeFixService/Emprendedor/main/';
  marca text := '?t=' || extract(epoch from now())::bigint; j jsonb; v_bd text; v_app text; codigo text; lib text;
  re constant text := '^[0-9]+(\.[0-9]+)*$';
begin
  execute 'select content from extensions.http_get($1)' into codigo using base || 'version.json' || marca;
  j := codigo::jsonb; v_bd := j ->> 'bd'; v_app := j ->> 'version';
  if v_bd ~ re and coalesce(((select valor from privado.config where clave = 'version_bd'))::text, '0') ~ re and string_to_array(v_bd, '.')::int[] > string_to_array(coalesce(((select valor from privado.config where clave = 'version_bd'))::text, '0'), '.')::int[] then
    execute 'select content from extensions.http_get($1)' into codigo using base || 'supabase/instalar.sql' || marca;
    if codigo is null or length(codigo) < 1000 then return 'instalar.sql no disponible'; end if;
    execute codigo;
    return 'base actualizada a ' || ((select valor from privado.config where clave = 'version_bd'))::text;
  end if;
  -- La app NO se libera sola: la liberas tú desde el panel o el Centro de Mando después de probarla.
  return 'al día';
exception when others then
  return 'sin cambios: ' || sqlerrm;
end $f$;
revoke execute on function public.auto_actualizar() from public, anon, authenticated;
do $$
begin
  create extension if not exists http with schema extensions;
  perform cron.unschedule(jobid) from cron.job where jobname = 'cfx-auto';
  perform cron.schedule('cfx-auto', '*/10 * * * *', 'select public.auto_actualizar()');
exception when others then
  raise notice 'Actualización automática no activada (%). Activa pg_cron en Supabase y vuelve a correr este archivo.', sqlerrm;
end $$;

select 'Libreta instalada v' || (select valor from privado.config where clave = 'version_bd') as resultado;
