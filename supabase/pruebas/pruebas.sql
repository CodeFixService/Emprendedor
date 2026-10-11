-- Pruebas de reglas y abusos (se corren en un Postgres local con simular-supabase.sql + instalar.sql).
-- Cada bloque termina en error si algo no se cumple.
\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists pruebas;
grant usage on schema pruebas to authenticated, anon, service_role;
create or replace function pruebas.falla(p_sql text, p_contiene text) returns void language plpgsql as $$
begin
  execute p_sql;
  raise exception 'DEBIÓ FALLAR: %', p_sql;
exception when others then
  if sqlerrm like 'DEBIÓ FALLAR%' then raise; end if;
  if position(lower(p_contiene) in lower(sqlerrm)) = 0 then raise exception 'Error distinto en %: % (esperaba "%")', p_sql, sqlerrm, p_contiene; end if;
end $$;
create or replace function pruebas.ok(c boolean, msg text) returns void language plpgsql as $$
begin if not coalesce(c, false) then raise exception 'FALLÓ: %', msg; end if; end $$;
grant execute on all functions in schema pruebas to authenticated, anon, service_role;

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-0000-0000-0000000000a1', 'juanjosuecastilloloyola@gmail.com', now()),
  ('00000000-0000-0000-0000-0000000000d1', 'dueno1@prueba.cl', now()),
  ('00000000-0000-0000-0000-0000000000d2', 'dueno2@prueba.cl', now()),
  ('00000000-0000-0000-0000-0000000000e1', 'ayudante@prueba.cl', now())
on conflict do nothing;
select pruebas.ok(not exists (select 1 from privado.config where clave = 'admin_id' and valor <> ''), 'sin admin fijado al instalar');
select pruebas.ok(privado.fijar_admin() like 'Administrador fijado%', 'fijar admin');
insert into auth.users (id, email, email_confirmed_at) values ('00000000-0000-0000-0000-0000000000f1', 'juanjosuecastilloloyola@gmail.com', now());
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f1', false);
select pruebas.ok(not (public.mi_estado() ->> 'es_admin')::boolean, 'impostor con el mismo correo no es admin');
select pruebas.falla($$select public.admin_resumen()$$, 'administrador');
reset role;

-- ===== Dueño 1 crea su billetera (prueba gratis de 7 días) =====
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
select pruebas.falla($$select public.crear_negocio('Almacén Rosita', 'almacen', false)$$, 'Términos');
select pruebas.ok((public.crear_negocio('Almacén Rosita', 'almacen', true) ->> 'prueba')::boolean, 'prueba gratis');
select pruebas.falla($$select public.crear_negocio('Otro', 'almacen', true)$$, 'ya tiene una billetera');
select pruebas.ok(public.mi_estado() -> 'plan' ->> 'estado' = 'prueba', 'parte en prueba gratis');
select pruebas.ok((select prueba_hasta between now() + interval '6 days' and now() + interval '8 days' from public.negocios where dueno = '00000000-0000-0000-0000-0000000000d1'), 'prueba de 7 días');
select pruebas.falla($$select public.guardar_negocio('{"nombre":"Almacén Rosita","banco":{"rut":"12.345.678-0"}}')$$, 'RUT inválido');
select public.guardar_negocio('{"nombre":"Almacén Rosita","whatsapp":"9 8765 4321","banco":{"banco":"BancoEstado","tipo":"Cuenta RUT","numero":"12345678","rut":"12.345.678-5","titular":"Rosa Pérez"}}');
select pruebas.ok((select whatsapp = '+56987654321' and banco ->> 'rut' = '12345678-5' from public.negocios), 'normaliza teléfono y RUT');
select pruebas.falla($$select public.guardar_negocio('{"nombre":"X"}')$$, 'entre 2 y 50');

-- Clientes
select pruebas.falla($$select public.crear_cliente('Juan Pérez', null, '+56 9 1111 2222', null, null, null, null, 0, false, false)$$, 'autorizó');
select pruebas.falla($$select public.crear_cliente('Juan Pérez', null, '12', null, null, null, null, 0, false, true)$$, 'Teléfono inválido');
select set_config('t.c1', public.crear_cliente('Juan Pérez', 'vecino', '+56 9 1111 2222', null, null, null, null, 0, false, true) ->> 'id', false);
select pruebas.ok(public.crear_cliente('juan perez', null, null, null, null, null, null, 0, false, true) ? 'duplicado', 'detecta duplicado');
select set_config('t.c2', public.crear_cliente('María Soto', null, '987654321', null, null, null, '1234', 5000, false, true) ->> 'id', false);
select pruebas.ok((select saldo = 5000 from public.clientes where id = current_setting('t.c2')::uuid), 'saldo inicial');

-- Movimientos
select pruebas.ok((public.registrar_movimiento('10000000-0000-0000-0000-000000000001', current_setting('t.c1')::uuid, 'cargo', 3500, 'Pan y leche', null, null, null, null, false, false) ->> 'saldo')::int = 3500, 'fiado');
select pruebas.ok((public.registrar_movimiento('10000000-0000-0000-0000-000000000001', current_setting('t.c1')::uuid, 'cargo', 3500, 'Pan y leche', null, null, null, null, false, false) ->> 'repetido')::boolean, 'id repetido no duplica');
select pruebas.ok((public.registrar_movimiento('10000000-0000-0000-0000-000000000002', current_setting('t.c1')::uuid, 'cargo', 3500, null, null, null, null, null, false, false) ->> 'duplicado')::boolean, 'doble toque avisa');
select pruebas.falla($$select public.registrar_movimiento(gen_random_uuid(), current_setting('t.c1')::uuid, 'abono', 9000, null, 'efectivo', null, null, null, false, false)$$, 'debe $3.500');
select pruebas.falla($$select public.registrar_movimiento(gen_random_uuid(), current_setting('t.c1')::uuid, 'cargo', 0, null, null, null, null, null, false, false)$$, 'entre $1');
select pruebas.falla($$select public.registrar_movimiento(gen_random_uuid(), current_setting('t.c1')::uuid, 'cargo', 100, null, null, now() + interval '1 day', null, null, false, false)$$, 'futura');
select pruebas.ok((public.registrar_movimiento('10000000-0000-0000-0000-000000000003', current_setting('t.c1')::uuid, 'abono', 1000, null, 'efectivo', null, null, null, false, false) ->> 'saldo')::int = 2500, 'abono');
select pruebas.falla($$select public.anular_movimiento('10000000-0000-0000-0000-000000000003', 'no')$$, 'motivo');
select pruebas.ok((public.anular_movimiento('10000000-0000-0000-0000-000000000003', 'Me equivoqué de cliente') ->> 'saldo')::int = 3500, 'anular recalcula');
select pruebas.falla($$select public.estado_cliente(current_setting('t.c1')::uuid, 'archivar')$$, 'saldo $0');

-- Límite de fiado por cliente (Pro)
reset role;
update public.negocios set premium_hasta = now() + interval '30 days' where dueno = '00000000-0000-0000-0000-0000000000d1';
set role authenticated;
select pruebas.ok(public.mi_estado() -> 'plan' ->> 'estado' = 'pro', 'pasa a Pro');
select public.editar_cliente(current_setting('t.c1')::uuid, 'Juan Pérez', 'vecino', '+56911112222', null, null, 5000);
select pruebas.ok((public.registrar_movimiento(gen_random_uuid(), current_setting('t.c1')::uuid, 'cargo', 2000, null, null, null, null, null, false, false) ->> 'limite')::int = 5000, 'avisa límite');
select pruebas.ok((public.registrar_movimiento(gen_random_uuid(), current_setting('t.c1')::uuid, 'cargo', 2000, null, null, null, null, null, true, false) ->> 'ok')::boolean, 'dueño fuerza límite');

-- Cuotas: 100.000 en 3 = 33.333 + 33.333 + 33.334; mensual desde el 31
select pruebas.ok((public.crear_venta_cuotas('20000000-0000-0000-0000-000000000001', current_setting('t.c2')::uuid, 'Zapatillas', 100000, 0, 3, 'mensual', (now() at time zone 'America/Santiago')::date + 1, false) ->> 'ok')::boolean, 'venta en cuotas');
select pruebas.ok((select array_agg(monto order by numero) = array[33333,33333,33334] from public.cuotas where venta = '20000000-0000-0000-0000-000000000001'), 'redondeo en la última cuota');
select pruebas.ok((select saldo = 105000 from public.clientes where id = current_setting('t.c2')::uuid), 'saldo con cuotas');
-- abono FIFO: paga primero el saldo anterior (5.000, vence hoy) y luego la cuota 1
select public.registrar_movimiento(gen_random_uuid(), current_setting('t.c2')::uuid, 'abono', 10000, null, 'transferencia', null, null, null, false, false);
select pruebas.ok((select pagado = 5000 from public.cuotas where venta = '20000000-0000-0000-0000-000000000001' and numero = 1), 'abono a la deuda más antigua');
select pruebas.falla($$select public.anular_movimiento('20000000-0000-0000-0000-000000000001', 'Prueba de anulación')$$, 'pestaña Cuotas');

-- Cobro legal: dos recordatorios seguidos no
select pruebas.falla($$select public.registrar_recordatorio(current_setting('t.c1')::uuid, 'whatsapp', 'amable', 'Te vamos a demandar')$$, 'demanda');
reset role;
-- forzar hora hábil para la prueba: se simula un recordatorio de ayer
insert into public.recordatorios (negocio, cliente, canal, tono, at) select negocio, id, 'whatsapp', 'amable', now() - interval '1 day' from public.clientes where id = current_setting('t.c1')::uuid;
set role authenticated;
select pruebas.ok(not (public.registrar_recordatorio(current_setting('t.c1')::uuid, 'whatsapp', 'amable', 'Hola') ->> 'ok')::boolean, 'menos de 2 días entre recordatorios');
select pruebas.ok((public.puede_cobrar(current_setting('t.c1')::uuid) ->> 'proxima') is not null, 'informa próxima fecha');

-- ===== Dueño 2 no ve ni toca nada del dueño 1 =====
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d2', false);
select public.crear_negocio('Feria Don Lucho', 'feria', true);
select pruebas.ok((select count(*) = 0 from public.clientes where id = current_setting('t.c1')::uuid), 'aislamiento clientes');
select pruebas.ok((select count(*) = 0 from public.movimientos where cliente = current_setting('t.c1')::uuid), 'aislamiento movimientos');
select pruebas.falla($$select public.registrar_movimiento(gen_random_uuid(), current_setting('t.c1')::uuid, 'cargo', 100, null, null, null, null, null, false, false)$$, 'Cliente no encontrado');
select pruebas.falla($$select public.anular_movimiento('10000000-0000-0000-0000-000000000001', 'Ataque de otro negocio')$$, 'no encontrado');
select pruebas.falla($$insert into public.movimientos (id, negocio, cliente, tipo, signo, monto) values (gen_random_uuid(), (select id from public.negocios limit 1), current_setting('t.c1')::uuid, 'abono', -1, 1)$$, 'permission denied');
select pruebas.falla($$update public.negocios set premium_hasta = now() + interval '10 years'$$, 'permission denied');
select pruebas.falla($$select pin_hash from public.clientes$$, 'permission denied');
select pruebas.falla($$select nota_admin from public.negocios$$, 'permission denied');
select pruebas.falla($$select public.admin_resumen()$$, 'administrador');
select pruebas.falla($$select * from privado.secretos$$, 'permission denied');
select pruebas.falla($$select privado.fijar_admin()$$, 'permission denied');

-- ===== Prueba gratis (límites del plan gratis): 20 clientes y 250 movimientos =====
select pruebas.ok(public.mi_estado() -> 'plan' ->> 'estado' = 'prueba', 'dueño 2 en prueba');
do $$ begin for i in 1..20 loop perform public.crear_cliente('Cliente ' || i, null, null, null, null, null, '1111', 0, false, true); end loop; end $$;
select pruebas.falla($$select public.crear_cliente('Cliente 21', null, null, null, null, null, '1111', 0, false, true)$$, '20 clientes');
select set_config('t.f1', (select id::text from public.clientes where nombre = 'Cliente 1'), false);
reset role;
update public.uso_mensual set movimientos = 250 where negocio = (select id from public.negocios where dueno = '00000000-0000-0000-0000-0000000000d2');
set role authenticated;
select pruebas.falla($$select public.registrar_movimiento(gen_random_uuid(), current_setting('t.f1')::uuid, 'cargo', 100, null, null, null, null, null, false, false)$$, 'movimientos de este mes');
reset role;
update public.uso_mensual set movimientos = 0 where negocio = (select id from public.negocios where dueno = '00000000-0000-0000-0000-0000000000d2');
set role authenticated;
select public.registrar_movimiento(gen_random_uuid(), current_setting('t.f1')::uuid, 'cargo', 100, null, null, null, null, null, false, false);
select pruebas.falla($$select public.registrar_recordatorio(current_setting('t.f1')::uuid, 'whatsapp', 'firme', '')$$, 'Premium');
select pruebas.falla($$select public.invitar_ayudante()$$, 'personal');
select pruebas.falla($$select public.solicitar_pago(12, null, null)$$, 'mes a mes');
reset role;
update public.uso_mensual set caja = 300 where negocio = (select id from public.negocios where dueno = '00000000-0000-0000-0000-0000000000d2');
set role authenticated;
select pruebas.falla($$select public.registrar_caja(gen_random_uuid(), 'gasto', 1000, 'Arriendo', null, 'efectivo', null, false)$$, 'ingresos y gastos de este mes');

-- ===== Fin de la prueba: billetera bloqueada (ver y exportar sí; anotar no) =====
reset role;
update public.negocios set prueba_hasta = now() - interval '1 minute' where dueno = '00000000-0000-0000-0000-0000000000d2';
select set_config('t.codf', (select link_codigo from public.clientes where id = current_setting('t.f1')::uuid), false);
set role authenticated;
select pruebas.ok(public.mi_estado() -> 'plan' ->> 'estado' = 'bloqueado', 'se bloquea al terminar la prueba');
select pruebas.ok((select count(*) >= 1 from public.notificaciones where titulo = 'Terminó tu prueba gratis'), 'avisa el bloqueo');
select pruebas.falla($$select public.crear_cliente('Nuevo', null, null, null, null, null, '1111', 0, false, true)$$, 'Terminó tu prueba gratis');
select pruebas.falla($$select public.registrar_movimiento(gen_random_uuid(), current_setting('t.f1')::uuid, 'abono', 50, null, 'efectivo', null, null, null, false, false)$$, 'Terminó tu prueba gratis');
select pruebas.ok((public.tablero() ->> 'por_cobrar')::int >= 0, 'bloqueado puede ver el tablero');
select pruebas.ok(public.exportar_datos() ? 'clientes', 'bloqueado puede exportar');
select public.soporte_enviar('Hola, quiero activar Pro');
select public.solicitar_pago(1, null, 'transferí');
select pruebas.ok((select monto = 14990 from public.solicitudes_pago where negocio = (select id from public.negocios where dueno = '00000000-0000-0000-0000-0000000000d2')), 'primer pago = activación + mes');
reset role;
set role anon;
select pruebas.falla($$select public.portal_entrar(current_setting('t.codf'), '1111')$$, 'en pausa');
reset role;
set role authenticated;

-- ===== Admin: aprueba el pago, soporte y keys =====
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select pruebas.ok((public.admin_resumen() ->> 'negocios')::int = 2, 'admin ve resumen');
select pruebas.ok((public.admin_resumen() ->> 'bloqueados')::int = 1, 'admin ve bloqueados');
select pruebas.ok((public.admin_resumen() ->> 'soporte_sin_leer')::int = 1, 'admin ve soporte sin leer');
select pruebas.ok((select count(*) = 0 from public.clientes), 'admin no ve clientes');
select pruebas.ok((select count(*) = 0 from public.caja), 'admin no ve la caja');
select public.admin_resolver_pago((select id from public.solicitudes_pago where estado = 'pendiente' limit 1), true, null);
select public.admin_soporte_enviar((select id from public.negocios where dueno = '00000000-0000-0000-0000-0000000000d2'), '¡Listo, activado!');
select set_config('t.key', (public.admin_crear_keys(1, 1, 4990) ->> 0), false);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d2', false);
select pruebas.ok(public.mi_estado() -> 'plan' ->> 'estado' = 'pro', 'pago aprobado: Pro');
select pruebas.ok((public.mi_estado() -> 'plan' ->> 'activado')::boolean, 'queda activado');
select pruebas.ok((public.mi_estado() -> 'pendientes' ->> 'soporte')::int = 1, 've respuesta de soporte');
select pruebas.ok(jsonb_array_length(public.soporte_leer()) = 2, 'conversación de soporte');
select pruebas.ok((public.mi_estado() -> 'pendientes' ->> 'soporte')::int = 0, 'soporte leído');
select public.solicitar_pago(1, null, null);
select pruebas.ok((select monto = 4990 from public.solicitudes_pago where estado = 'pendiente'), 'mensualidad sin activación');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
select pruebas.ok((select count(*) = 0 from public.soporte), 'no ve el soporte de otro');
select pruebas.ok((public.usar_key(current_setting('t.key')) ->> 'ok')::boolean, 'usar key');
select pruebas.falla($$select public.usar_key(current_setting('t.key'))$$, 'ya usada');

-- ===== Caja: ingresos y gastos =====
select pruebas.ok((public.registrar_caja('30000000-0000-0000-0000-000000000001', 'ingreso', 10000, 'Ventas', 'Ventas del día', 'efectivo', null, false) ->> 'ok')::boolean, 'ingreso');
select pruebas.ok((public.registrar_caja('30000000-0000-0000-0000-000000000001', 'ingreso', 10000, 'Ventas', null, 'efectivo', null, false) ->> 'repetido')::boolean, 'ingreso repetido no duplica');
select pruebas.ok((public.registrar_caja(gen_random_uuid(), 'ingreso', 10000, 'Ventas', null, 'efectivo', null, false) ->> 'duplicado')::boolean, 'doble toque en caja');
select public.registrar_caja('30000000-0000-0000-0000-000000000002', 'gasto', 3000, 'Arriendo', null, 'transferencia', null, false);
select pruebas.falla($$select public.registrar_caja(gen_random_uuid(), 'gasto', 0, 'Arriendo', null, null, null, false)$$, 'entre $1');
select pruebas.falla($$select public.registrar_caja(gen_random_uuid(), 'gasto', 10, 'X', null, null, null, false)$$, 'categoría');
select pruebas.falla($$select public.registrar_caja(gen_random_uuid(), 'gasto', 10, 'Arriendo', null, null, now() + interval '1 day', false)$$, 'futura');
select pruebas.ok((public.resumen_caja(null) ->> 'ingresos')::int = 10000 and (public.resumen_caja(null) ->> 'gastos')::int = 3000, 'resumen de caja');
select pruebas.ok((public.resumen_caja(null) ->> 'cobros')::int > 0, 'los abonos cuentan como cobros');
select public.anular_caja('30000000-0000-0000-0000-000000000002', 'Me equivoqué de monto');
select pruebas.ok((public.resumen_caja(null) ->> 'gastos')::int = 0, 'anular gasto');
select public.guardar_categoria('gasto', 'Bencina camioneta');
select pruebas.ok((select count(*) = 1 from public.categorias), 'categoría propia');
select pruebas.ok(jsonb_array_length(public.exportar_datos() -> 'caja') = 2, 'exportar incluye caja');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d2', false);
select pruebas.ok((select count(*) = 0 from public.caja), 'aislamiento de caja');
select pruebas.falla($$select public.anular_caja('30000000-0000-0000-0000-000000000001', 'Ataque de otro negocio')$$, 'no encontrado');
select pruebas.falla($$select public.srv_crear_negocio(auth.uid(), 'x', 'otro', 999)$$, 'permission denied');

-- ===== Link del cliente =====
reset role;
select set_config('t.cod', (select link_codigo from public.clientes where id = current_setting('t.c2')::uuid), false);
set role anon;
select pruebas.falla($$select * from public.clientes$$, 'permission denied');
select pruebas.falla($$select public.mi_estado()$$, 'permission denied');
select pruebas.ok(not (public.portal_entrar(current_setting('t.cod'), '0000') ->> 'ok')::boolean, 'PIN malo');
select pruebas.falla($$select public.portal_entrar('codigo-falso', '1234')$$, 'no es válido');
select pruebas.falla($$select public.portal_ver('token-falso')$$, 'sesión terminó');
select set_config('t.ses', public.portal_entrar(current_setting('t.cod'), '1234') ->> 'sesion', false);
select pruebas.ok((public.portal_ver(current_setting('t.ses')) -> 'cliente' ->> 'saldo')::int = 95000, 'cliente ve su saldo');
select pruebas.ok(position('nota' in (public.portal_ver(current_setting('t.ses')))::text) = 0, 'no ve notas internas');
select pruebas.ok((public.portal_comprobante(current_setting('t.ses'), 20000, (now() at time zone 'America/Santiago')::date, 'transferí', true) ->> 'foto_token') is not null, 'sube comprobante');
select pruebas.falla($$select public.portal_comprobante(current_setting('t.ses'), 999999999, (now() at time zone 'America/Santiago')::date, null, false)$$, 'Revisa el monto');
select pruebas.falla($$select public.portal_comprobante(current_setting('t.ses'), 100, (now() at time zone 'America/Santiago')::date + 1, null, false)$$, '30 días');
do $$ begin for i in 1..5 loop perform public.portal_entrar(current_setting('t.cod'), '9999'); end loop; end $$;
select pruebas.falla($$select public.portal_entrar(current_setting('t.cod'), '1234')$$, 'Demasiados intentos');
reset role;

-- Aprobar el comprobante (dueño)
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
select pruebas.ok((public.revisar_comprobante((select id from public.comprobantes limit 1), true, null, null) ->> 'saldo')::int = 75000, 'aprobar comprobante crea abono');
select pruebas.falla($$select public.revisar_comprobante((select id from public.comprobantes limit 1), true, null, null)$$, 'ya fue revisado');
select pruebas.ok((public.tablero() ->> 'por_cobrar')::int > 0, 'tablero');
select pruebas.ok((public.reporte(current_date - 30, current_date) ->> 'cobrado')::int >= 20000, 'reporte');
select pruebas.ok(jsonb_array_length(public.exportar_datos() -> 'movimientos') > 0, 'exportar');
reset role;

-- ===== El admin crea una cuenta desde su panel (función del servidor) =====
reset role;
insert into auth.users (id, email, email_confirmed_at) values ('00000000-0000-0000-0000-0000000000c1', 'creada@prueba.cl', now());
set role service_role;
select pruebas.ok(public.srv_es_admin('00000000-0000-0000-0000-0000000000a1') and not public.srv_es_admin('00000000-0000-0000-0000-0000000000c1'), 'srv_es_admin');
select public.srv_crear_negocio('00000000-0000-0000-0000-0000000000c1', 'Creado por Josué', 'feria', 30);
reset role;
select pruebas.ok((select privado.estado_plan(id) = 'pro' and activado from public.negocios where dueno = '00000000-0000-0000-0000-0000000000c1'), 'cuenta creada con Pro');

-- Tareas automáticas no fallan
select privado.tarea_horaria();
select privado.tarea_cola();
select pruebas.ok((select count(*) > 0 from public.cola_push), 'cola de avisos con datos');
select pruebas.ok(jsonb_typeof(public.srv_cola_tomar(50)) = 'array', 'cola se puede tomar');
select 'TODAS LAS PRUEBAS PASARON' as resultado;
