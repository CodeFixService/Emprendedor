/* Panel del superadministrador: billeteras, planes, pagos, cupones, keys, avisos y ajustes. No ve clientes ni deudas de los negocios. */
(function () {
  'use strict';
  const { el, $, vaciar, rpc, sb, V, error, toast, conCarga, dialogo, confirmar, pedirTexto, pesos, fechaCorta, fechaLarga, fechaHora, copiar, wa, abrir, local } = LC;
  const vista = $('#vista');
  $('#ver').textContent = LC.VERSION;
  LC.registrarSW();
  const pintar = (...n) => { vaciar(vista).append(...n.flat().filter((x) => x != null && x !== false)); LC.centrarActivos(vista); };
  const kpi = (t, v, cls) => el('div', { class: 'kpi' }, el('div', { class: 't' }, t), el('div', { class: 'v ' + (cls || '') }, v));
  const PLAN = { pro: 'Pro', prueba: 'Prueba Pro', free: 'Free' };
  const L = (x) => (Array.isArray(x) ? x : []); // listas que pueden faltar si la base de datos es antigua
  const bdVieja = (cfg) => Number((cfg && cfg.version_bd) || 0) < LC.BD;
  const salir = async () => { await sb.auth.signOut().catch(() => {}); location.replace('../#ingresar'); };
  $('#salir').onclick = salir;

  async function arrancar() {
    const { data } = await sb.auth.getSession();
    if (!data.session) { location.replace('../#ingresar'); return; }
    const st = await rpc('mi_estado');
    if (!st.es_admin) { pintar(el('div', { class: 'vacio' }, el('span', { class: 'ico' }, '🔒'), 'Solo el administrador puede entrar aquí.', el('br'), el('a', { href: '../app/' }, 'Volver a la app'))); return; }
    if (bdVieja(st.config)) document.querySelector('.app').insertBefore(el('a', { class: 'banda error', href: '#ajustes/versiones', style: 'text-decoration:none' },
      el('span', null, '⚠️ La base de datos está en v' + (st.config.version_bd || '4 o menos') + ' y esta versión de la app necesita v' + LC.BD + '. Corre la consulta de actualización.'), el('span', { class: 'btn chico' }, 'Ver cómo')), document.getElementById('vista'));
    LC.revisarVersion(st.config, (txt, fn) => {
      const v = document.getElementById('admUpd'); if (v) v.remove();
      if (txt) document.querySelector('.app').insertBefore(el('div', { id: 'admUpd', class: 'banda info' }, el('span', null, txt + ' Tu celular aún no la tiene.'), el('button', { class: 'btn chico', type: 'button', onclick: fn }, 'Actualizar')), document.getElementById('vista'));
    });
    window.addEventListener('hashchange', router);
    router();
  }
  function router() {
    const [v, a] = (location.hash.slice(1) || 'resumen').split('/');
    document.querySelectorAll('#nav a').forEach((x) => x.classList.toggle('activo', x.dataset.v === v));
    if (v !== 'soporte' && canal) { sb.removeChannel(canal); canal = null; }
    ({ resumen: vResumen, negocios: vNegocios, pagos: vPagos, ajustes: vAjustes, keys: vKeys, avisos: vAvisos, soporte: vSoporte, cupones: vCupones }[v] || vResumen)(a).catch(error);
  }

  // ---------- Resumen ----------
  async function vResumen() {
    const [r, op] = await conCarga(() => Promise.all([rpc('admin_resumen'), rpc('admin_oportunidades')]));
    $('#badgePagos').textContent = r.pagos_pendientes; $('#badgePagos').classList.toggle('oculto', !r.pagos_pendientes);
    $('#badgeSoporte').textContent = r.soporte_sin_leer; $('#badgeSoporte').classList.toggle('oculto', !r.soporte_sin_leer);
    const pct = Math.round(r.bd_mb * 100 / 500);
    const conv = r.negocios ? Math.round(r.convertidos * 100 / r.negocios) : 0;
    const dias = []; for (let i = 29; i >= 0; i--) dias.push(LC.sumarDias(LC.hoyISO(), -i));
    const porDia = Object.fromEntries(L(r.registros_dia).map((x) => [x.dia, x.n]));
    const maxD = Math.max(1, ...dias.map((d) => porDia[d] || 0));
    const etapa = (t, n, cls) => el('div', { class: 'kpi' }, el('div', { class: 't' }, t), el('div', { class: 'v ' + (cls || '') }, n));
    const op1 = (titulo, lista, sub, plantilla) => (lista = L(lista)).length ? el('div', { class: 'tarjeta' }, el('h2', null, titulo + ' (' + lista.length + ')'),
      el('div', { class: 'lista' }, lista.map((n) => el('div', { class: 'item', style: 'cursor:default' },
        el('div', { class: 'avatar', style: 'background:' + LC.colorDe(n.nombre) }, LC.iniciales(n.nombre)),
        el('a', { class: 'crece', href: '#negocios/' + n.id, style: 'color:inherit;text-decoration:none' }, el('div', { class: 'nom' }, n.nombre), el('div', { class: 'sub' }, sub(n))),
        n.whatsapp ? el('button', { class: 'btn-icono', type: 'button', 'aria-label': 'WhatsApp', onclick: () => abrir(wa(n.whatsapp, plantilla(n))) }, '💬') : null,
        el('a', { class: 'btn-icono', href: '#soporte/' + n.id, style: 'text-decoration:none', 'aria-label': 'Chat' }, '✉️'))))) : null;
    const cfgP = r.mrr;
    const avisoVersion = el('div');
    Promise.all([leerPublicada(), rpc('config_publica')]).then(([pub, c]) => {
      const bd = Number(c.version_bd || 0);
      if (LC.versionMenor(c.version_liberada, pub.version) || bd < pub.bd) avisoVersion.append(el('a', { class: 'banda info', href: '#ajustes/versiones', style: 'text-decoration:none' },
        '🚀 Hay una versión nueva lista (v' + pub.version + '). Actualízala en 4 pasos: base de datos, función, probar y liberar.', el('span', { class: 'btn chico' }, 'Empezar')));
    }).catch(() => {});
    pintarUso();
    pintar(el('h2', null, 'Resumen'),
      avisoVersion,
      !r.cron_ok ? el('div', { class: 'banda error' }, '⚠️ Las tareas automáticas no están activas: en Supabase → Database → Extensions enciende pg_cron y pg_net, y vuelve a correr el SQL de actualización.') : null,
      !r.push_ok ? el('div', { class: 'banda aviso' }, '⚠️ Falta generar las claves push.', el('a', { class: 'btn chico', href: '#ajustes/push' }, 'Ir')) : null,
      r.pagos_pendientes ? el('a', { class: 'banda info', href: '#pagos', style: 'text-decoration:none' }, '💳 ' + r.pagos_pendientes + ' pago(s) por revisar', el('span', { class: 'btn chico' }, 'Revisar')) : null,
      r.soporte_sin_leer ? el('a', { class: 'banda info', href: '#soporte', style: 'text-decoration:none' }, '💬 ' + r.soporte_sin_leer + ' chat(s) de soporte sin leer', el('span', { class: 'btn chico' }, 'Ver')) : null,
      el('div', { class: 'kpi hero mb' }, el('div', { class: 't' }, 'Ingreso mensual recurrente (Pro activos × mensualidad)'), el('div', { class: 'grande' }, pesos(cfgP)),
        el('div', { class: 't' }, 'Cobrado este mes: ' + pesos(r.ingresos_mes) + ' · ' + r.convertidos + ' clientes han pagado (' + conv + '% de las billeteras)')),
      el('h3', null, 'Embudo de ventas'),
      el('div', { class: 'grid2 mb' }, etapa('Billeteras creadas', r.negocios), etapa('En prueba Pro', r.en_prueba), etapa('Quieren Pro ⭐', r.quieren_pro, r.quieren_pro ? 'naranjo' : ''),
        etapa('Pro pagando', r.premium, 'verde'), etapa('En Free', r.free != null ? r.free : '—'), etapa('Activas 7 días', r.activos_7d, 'verde'),
        etapa('🤝 Conexiones activas', r.conexiones != null ? r.conexiones : '—'), etapa('🎁 Llegaron invitados (30 días)', r.referidos_30d != null ? r.referidos_30d : '—'),
        etapa('📅 Planes anuales vigentes', r.anuales != null ? r.anuales : '—')),
      L(r.vencen).length ? el('div', { class: 'tarjeta', style: 'border-color:var(--aviso)' }, el('h2', null, '⏰ Vencen hoy o mañana (' + r.vencen.length + ')'),
        el('div', { class: 'lista' }, r.vencen.map((n) => el('div', { class: 'item', style: 'cursor:default' },
          el('div', { class: 'avatar', style: 'background:' + LC.colorDe(n.nombre) }, LC.iniciales(n.nombre)),
          el('a', { class: 'crece', href: '#negocios/' + n.id, style: 'color:inherit;text-decoration:none' }, el('div', { class: 'nom' }, n.nombre),
            el('div', { class: 'sub' }, (n.tipo === 'pro' ? 'Mensualidad Pro' : 'Prueba Pro') + ' · vence ' + LC.relativo(LC.fechaISO(n.fecha)))),
          n.whatsapp ? el('button', { class: 'btn-icono', type: 'button', 'aria-label': 'WhatsApp', onclick: () => abrir(wa(n.whatsapp, n.tipo === 'pro'
            ? 'Hola ' + n.nombre + ', tu mensualidad de Pro en Libreta de Cobros vence ' + LC.relativo(LC.fechaISO(n.fecha)) + '. ¿Te paso los datos para pagar?'
            : 'Hola ' + n.nombre + ', tu prueba Pro de Libreta de Cobros termina ' + LC.relativo(LC.fechaISO(n.fecha)) + '. Si activas Pro sigues con todo sin límites. ¿Te ayudo?')) }, '💬') : null)))) : null,
      el('div', { class: 'tarjeta' }, el('h2', null, 'Registros: ' + r.nuevos_7d + ' esta semana · ' + r.nuevos_30d + ' en 30 días'),
        el('div', { class: 'grafico', role: 'img', 'aria-label': 'Registros por día en los últimos 30 días' }, dias.map((d) => el('div', { title: LC.fechaCorta(d) + ': ' + (porDia[d] || 0) },
          el('i', { class: 'c', style: 'height:' + Math.round((porDia[d] || 0) * 100 / maxD) + 'px' }))))),
      el('h3', null, 'Oportunidades'),
      op1('⭐ Quieren Pro', op.quieren_pro, (n) => 'Lo pidió ' + LC.relativo(n.fecha.slice(0, 10)) + ' · ' + n.email, (n) => 'Hola ' + n.nombre + ', vi que quieres activar Pro en tu billetera 🙌 Te cuento cómo pagar:'),
      op1('⏳ Su prueba Pro termina pronto', op.prueba_termina, (n) => 'Termina ' + LC.relativo(n.fecha.slice(0, 10)) + ' · usó la app ' + (n.ultimo_uso ? LC.relativo(n.ultimo_uso.slice(0, 10)) : 'nunca'), (n) => 'Hola ' + n.nombre + ', tu prueba Pro de Libreta de Cobros termina pronto. Después sigues gratis, pero sin las funciones Pro. ¿Te ayudo a activarlo?'),
      op1('💳 Pro por vencer', op.pro_vence, (n) => 'Vence ' + LC.relativo(n.fecha.slice(0, 10)), (n) => 'Hola ' + n.nombre + ', te recuerdo que tu mensualidad de Pro vence pronto. ¿Te paso los datos para pagar?'),
      op1('🙂 En Free y usando la app', op.free, (n) => (n.activado ? 'Venció su Pro' : 'Terminó su prueba') + ' · entró ' + (n.ultimo_uso ? LC.relativo(n.ultimo_uso.slice(0, 10)) : '—'), (n) => 'Hola ' + n.nombre + ', vi que sigues usando tu billetera 🙌 Si activas Pro tienes cobro a todos de una, recibos, reportes y todo sin límites. ¿Te cuento?'),
      !L(op.quieren_pro).length && !L(op.prueba_termina).length && !L(op.pro_vence).length && !L(op.free).length ? el('div', { class: 'lista' }, el('div', { class: 'vacio' }, 'Sin oportunidades por ahora.')) : null,
      el('button', { class: 'btn primario ancho mb mt', type: 'button', onclick: crearCuenta }, '＋ Crear cuenta para un cliente'),
      el('div', { class: 'tarjeta' }, el('h2', null, 'Uso del servidor'),
        el('div', { class: 'fila entre' }, el('span', null, 'Base de datos'), el('strong', null, r.bd_mb + ' MB de 500 MB')),
        el('div', { class: 'barra ' + (pct >= 85 ? 'lleno' : pct >= 70 ? 'alerta' : '') }, el('i', { style: 'width:' + Math.min(pct, 100) + '%' })),
        el('div', { class: 'fila entre mt' }, el('span', null, 'Archivos (fotos)'), el('strong', null, r.archivos_mb + ' MB de 1.024 MB')),
        pct >= 70 ? el('p', { class: 'naranjo mt' }, 'Pasaste el 70%: es momento de pasar a Supabase Pro.') : null,
        el('p', { class: 'sutil mt' }, 'Avisos en cola: ' + r.cola_push),
        el('details', { class: 'mt' }, el('summary', { class: 'sutil', style: 'cursor:pointer' }, 'Ver cada tabla y limpiar'), usoDetalle)),
      el('div', { class: 'grid3' }, el('a', { class: 'btn', href: '#avisos' }, '📣 Mensajes'), el('a', { class: 'btn', href: '#cupones' }, '🏷️ Cupones'), el('a', { class: 'btn', href: '#keys' }, '🔑 Keys')),
      el('button', { class: 'btn ancho mt', type: 'button', onclick: probar }, '🩺 Probar servidor de avisos'),
      el('button', { class: 'btn texto ancho mt', type: 'button', onclick: salir }, '🚪 Cerrar sesión'));
  }
  const usoDetalle = el('div', { class: 'mt' });
  async function pintarUso() {
    const u = await rpc('admin_uso').catch(() => null); if (!u) return;
    const limpiar = async (que, tx) => { if (!await confirmar('Limpiar', tx, 'Limpiar', 'rojo')) return; try { const n = await conCarga(() => rpc('admin_limpiar', { p_que: que })); toast('Listo ✓ (' + n + ')'); pintarUso(); } catch (e) { error(e); } };
    vaciar(usoDetalle).append(el('table', { class: 'uso' }, (u.tablas || []).slice(0, 25).map((x) => el('tr', null, el('td', null, x.tabla), el('td', { class: 'r sutil' }, Math.max(0, x.filas) + ' filas'), el('td', { class: 'r' }, (x.bytes / 1024 / 1024).toFixed(2) + ' MB')))),
      (u.archivos || []).length ? el('p', { class: 'sutil mt' }, 'Archivos: ' + u.archivos.map((x) => x.bucket + ' ' + x.n + ' (' + x.mb + ' MB)').join(' · ')) : null,
      el('div', { class: 'grid2 mt' }, el('button', { class: 'btn chico', type: 'button', onclick: () => limpiar('comprobantes', 'Borra las fotos de comprobantes revisados más antiguas que los días de Ajustes → Reglas.') }, '🧾 Comprobantes viejos'),
        el('button', { class: 'btn chico', type: 'button', onclick: () => limpiar('avisos', 'Borra los avisos leídos de más de 30 días.') }, '🔔 Avisos leídos'),
        el('button', { class: 'btn chico', type: 'button', onclick: () => limpiar('cola', 'Borra la cola de push ya enviada.') }, '📤 Cola de push'),
        el('button', { class: 'btn chico', type: 'button', onclick: () => limpiar('sesiones', 'Borra sesiones vencidas de los links de clientes.') }, '🔗 Sesiones vencidas'),
        el('button', { class: 'btn chico', type: 'button', onclick: () => limpiar('auditoria', 'Borra el registro de cambios de más de 180 días.') }, '📜 Registro antiguo'),
        el('button', { class: 'btn chico', type: 'button', onclick: () => limpiar('soporte', 'Borra los mensajes de soporte de más de 30 días (también se borran solos).') }, '💬 Soporte antiguo')),
      el('button', { class: 'btn ancho mt', type: 'button', onclick: async () => { try { CFX_RESPALDO.excel('billetera-admin', await conCarga(() => rpc('cfx_respaldo'))); toast('Respaldo descargado ✓'); } catch (e) { error(e); } } }, '📗 Descargar respaldo (Excel)'),
      el('p', { class: 'sutil' }, 'Billeteras, pagos de Pro, keys, cupones y registro de cambios. Descárgalo antes de limpiar.'));
  }
  async function probar() {
    try { const r = await conCarga(() => LC.funcion({ accion: 'ping' })); toast(r.ok ? '✅ Función "enviar" v' + r.version + (r.servicio ? '' : ' · falta clave de servicio') : '❌ ' + (r.error || 'Sin respuesta')); }
    catch (e) { toast('❌ ' + e.message, { error: true, ms: 9000 }); }
  }

  // ---------- Negocios ----------
  let filtro = 'todos', busca = '';
  let ultimaLista = [];
  async function vNegocios(id) {
    if (id) { const d = await rpc('admin_negocios', { p_buscar: '', p_filtro: 'todos' }); const n = d.find((x) => x.id === id); history.replaceState(null, '', '#negocios'); if (n) { vNegocios(); return fichaNegocio(n); } }
    const lista = el('div', { class: 'lista' });
    const inp = el('input', { type: 'search', placeholder: '🔎 Nombre o correo', value: busca });
    let t;
    const cargar = async () => {
      const d = await rpc('admin_negocios', { p_buscar: busca, p_filtro: filtro });
      ultimaLista = d;
      vaciar(lista);
      if (!d.length) lista.append(el('div', { class: 'vacio' }, 'Sin resultados.'));
      d.forEach((n) => lista.append(el('button', { class: 'item', type: 'button', onclick: () => fichaNegocio(n) },
        el('div', { class: 'avatar', style: 'background:' + LC.colorDe(n.nombre) }, LC.iniciales(n.nombre)),
        el('div', { class: 'crece' }, el('div', { class: 'nom' }, n.nombre, n.soporte ? ' 💬' : ''), el('div', { class: 'sub' }, n.email + ' · ' + n.clientes + ' clientes · ' + (n.movimientos_mes || 0) + ' mov/mes')),
        el('span', { class: 'tag ' + (n.estado !== 'activo' ? 'rojo' : { pro: 'premium', prueba: 'marca', free: '' }[n.plan]) }, n.estado !== 'activo' ? n.estado : PLAN[n.plan]))));
    };
    inp.oninput = () => { busca = inp.value; clearTimeout(t); t = setTimeout(() => cargar().catch(error), 300); };
    pintar(el('div', { class: 'fila entre mb' }, el('h2', { style: 'margin:0' }, 'Billeteras'), el('button', { class: 'btn chico primario', type: 'button', onclick: crearCuenta }, '＋ Crear cuenta')), inp,
      el('div', { class: 'chips mt' }, [['todos', 'Todas'], ['pro', '⭐ Pro'], ['prueba', 'En prueba'], ['free', 'Free'], ['vence', '⏳ Por vencer'], ['inactivos', '💤 Sin actividad 7 días'], ['suspendido', '⛔ Suspendidas'], ['eliminado', 'Por borrar']].map(([v, tx]) =>
        el('button', { class: 'chip' + (filtro === v ? ' activo' : ''), type: 'button', onclick: () => { filtro = v; vNegocios(); } }, tx))),
      lista,
      el('button', { class: 'btn ancho mt', type: 'button', onclick: () => {
        LC.descargar('billeteras-' + LC.hoyISO() + '.csv', LC.csv(ultimaLista, [{ t: 'Negocio', v: (n) => n.nombre }, { t: 'Correo', v: (n) => n.email }, { t: 'WhatsApp', v: (n) => n.whatsapp || '' },
          { t: 'Rubro', v: (n) => n.rubro }, { t: 'Plan', v: (n) => PLAN[n.plan] }, { t: 'Activación pagada', v: (n) => n.activado ? 'Sí' : 'No' }, { t: 'Prueba hasta', v: (n) => n.prueba_hasta || '' },
          { t: 'Pro hasta', v: (n) => n.premium_hasta || '' }, { t: 'Clientes', v: (n) => n.clientes }, { t: 'Movimientos del mes', v: (n) => n.movimientos_mes || 0 }, { t: 'Último uso', v: (n) => n.ultimo_uso || '' }, { t: 'Creada', v: (n) => n.creado }]));
      } }, '📄 Exportar lista (CSV)'));
    await cargar();
  }
  async function fichaNegocio(n) {
    const det = await rpc('admin_negocio_detalle', { p_negocio: n.id }).catch(() => null);
    const plantillas = [['Recordar pago', 'Hola ' + n.nombre + ', te recuerdo que tu mensualidad de Libreta de Cobros vence pronto. ¿Te paso los datos para pagar?'],
      ['Ofrecer Pro', 'Hola ' + n.nombre + ', ¿cómo te ha ido con tu billetera? Si activas Pro tienes todo sin límites, cobro a todos de una, recibos con imagen y reportes avanzados. ¿Te ayudo?'],
      ['Ayuda para empezar', 'Hola ' + n.nombre + ', te escribe el equipo de Libreta de Cobros. ¿Te ayudo a configurar tu billetera? Toma 5 minutos.']];
    const r = await dialogo(n.nombre, el('div', null,
      det ? el('div', { class: 'grid3 mb' },
        el('div', { class: 'kpi' }, el('div', { class: 't' }, 'Clientes'), el('div', { class: 'v' }, det.clientes)),
        el('div', { class: 'kpi' }, el('div', { class: 't' }, 'Mov. del mes'), el('div', { class: 'v' }, (det.movimientos_mes || 0) + (det.caja_mes || 0))),
        el('div', { class: 'kpi' }, el('div', { class: 't' }, 'Días con uso'), el('div', { class: 'v' }, det.dias_activo))) : null,
      det && det.quiere_pro_at ? el('p', { class: 'naranjo' }, '⭐ Pidió Pro ' + LC.relativo(det.quiere_pro_at.slice(0, 10))) : null,
      det && det.pagos.length ? el('details', { class: 'mb' }, el('summary', { class: 'sutil', style: 'cursor:pointer' }, 'Pagos (' + det.pagos.length + ')'),
        el('div', { class: 'lista mt' }, det.pagos.map((x) => el('div', { class: 'item', style: 'cursor:default' }, el('span', { class: 'crece' }, pesos(x.monto) + ' · ' + fechaCorta(x.creado)), el('span', { class: 'tag ' + (x.estado === 'aprobada' ? 'verde' : x.estado === 'rechazada' ? 'rojo' : 'naranjo') }, x.estado))))) : null,
      n.whatsapp ? el('div', { class: 'chips' }, plantillas.map(([t, m]) => el('button', { class: 'chip', type: 'button', onclick: () => abrir(wa(n.whatsapp, m)) }, '💬 ' + t))) : null,
      el('p', null, n.email, n.whatsapp ? ' · ' + n.whatsapp : ''),
      el('p', { class: 'sutil' }, 'Rubro: ' + n.rubro + ' · Desde ' + fechaCorta(n.creado) + ' · Último uso: ' + (n.ultimo_uso ? fechaHora(n.ultimo_uso) : '—')),
      el('p', null, 'Plan: ', el('strong', null, PLAN[n.plan]),
        n.plan === 'pro' ? ' · pagado hasta ' + fechaLarga(n.premium_hasta) : n.plan === 'prueba' ? ' · hasta ' + fechaLarga(n.prueba_hasta) : '',
        n.activado ? ' · ✅ activación pagada' : ' · sin activación'),
      el('p', { class: 'sutil' }, '🤝 ' + (n.conexiones || 0) + ' conexiones activas · ' + (n.conexiones_extra || 0) + ' paquete(s) extra'),
      det && (det.invitados || det.invitado_por) ? el('p', { class: 'sutil' }, det.invitados ? '🎁 Invitó a ' + det.invitados + ' negocio(s), ' + det.premiados + ' con premio. ' : '', det.invitado_por ? 'Llegó invitado por ' + det.invitado_por + '.' : '') : null,
      n.estado === 'suspendido' ? el('p', { class: 'rojo' }, 'Suspendido: ' + (n.motivo_suspension || '')) : null,
      n.nota_admin ? el('p', { class: 'sutil' }, '📝 ' + n.nota_admin) : null,
      el('div', { class: 'col' },
        el('div', { class: 'grid2' }, el('button', { class: 'btn primario', type: 'button', onclick: () => cerrarCon('dias') }, '⭐ Dar Pro'),
          n.plan !== 'pro' ? el('button', { class: 'btn', type: 'button', onclick: () => cerrarCon('prueba') }, n.plan === 'prueba' ? '🎁 Extender prueba' : '🎁 Dar prueba Pro')
            : el('button', { class: 'btn', type: 'button', onclick: () => cerrarCon('quitar') }, '⬇️ Quitar Pro')),
        n.plan === 'prueba' ? el('button', { class: 'btn', type: 'button', onclick: () => cerrarCon('quitar') }, '⬇️ Terminar prueba (pasa a Free)') : null,
        el('a', { class: 'btn', href: '#soporte/' + n.id }, '💬 Chat de soporte' + (n.soporte ? ' (' + n.soporte + ')' : '')),
        el('button', { class: 'btn', type: 'button', onclick: () => cerrarCon('conexiones') }, '🤝 Paquetes de conexiones'),
        el('button', { class: 'btn', type: 'button', onclick: () => cerrarCon('nota') }, '📝 Nota interna'),
        el('button', { class: 'btn', type: 'button', onclick: () => cerrarCon('aviso') }, '📣 Enviar aviso'),
        n.whatsapp ? el('button', { class: 'btn wsp', type: 'button', onclick: () => abrir(wa(n.whatsapp, 'Hola ' + n.nombre + ', te escribo de Libreta de Cobros.')) }, '💬 WhatsApp') : null,
        n.estado === 'activo' ? el('button', { class: 'btn peligro', type: 'button', onclick: () => cerrarCon('suspender') }, '⛔ Desactivar cuenta')
          : n.estado === 'suspendido' ? el('button', { class: 'btn verde', type: 'button', onclick: () => cerrarCon('reactivar') }, '✅ Reactivar cuenta') : null)));
    function cerrarCon(v) { document.querySelector('.velo').remove(); accion(v); }
    async function accion(v) {
      try {
        if (v === 'dias') {
          const d = await pedirTexto('Dar Pro', 'Días de Pro', { valor: '30', inputmode: 'numeric', tipo: 'number', validar: (x) => Number(x) >= 1 && Number(x) <= 3660 ? null : 'Entre 1 y 3660' });
          if (d) { await conCarga(() => rpc('admin_plan', { p_negocio: n.id, p_accion: 'sumar', p_dias: Number(d) })); toast('Pro activado ✓'); }
        } else if (v === 'prueba') {
          const d = await pedirTexto('Prueba Pro', 'Días de prueba Pro', { valor: '7', inputmode: 'numeric', tipo: 'number', validar: (x) => Number(x) >= 1 && Number(x) <= 90 ? null : 'Entre 1 y 90' });
          if (d) { await conCarga(() => rpc('admin_plan', { p_negocio: n.id, p_accion: 'prueba', p_dias: Number(d) })); toast('Prueba extendida ✓'); }
        } else if (v === 'quitar') {
          if (await confirmar(n.plan === 'prueba' ? 'Terminar prueba' : 'Quitar Pro', '¿Pasar a ' + n.nombre + ' a Free ahora? Su billetera sigue funcionando gratis y las funciones Pro quedan en pausa. No se borra nada.', 'Pasar a Free', 'rojo')) { await conCarga(() => rpc('admin_plan', { p_negocio: n.id, p_accion: 'quitar', p_dias: null })); toast('Ahora está en Free'); }
        } else if (v === 'conexiones') {
          const d = await pedirTexto('Paquetes de conexiones', 'Paquetes extra (cada uno suma conexiones según Ajustes)', { valor: String(n.conexiones_extra || 0), inputmode: 'numeric', tipo: 'number', validar: (x) => Number(x) >= 0 && Number(x) <= 200 ? null : 'Entre 0 y 200' });
          if (d != null && d !== '') { await conCarga(() => rpc('admin_plan', { p_negocio: n.id, p_accion: 'conexiones', p_dias: Number(d) })); toast('Paquetes actualizados ✓'); }
        } else if (v === 'nota') {
          const t = await pedirTexto('Nota interna', 'Solo la ves tú', { valor: n.nota_admin || '', multilinea: true, max: 500 });
          if (t != null) { await rpc('admin_estado', { p_negocio: n.id, p_suspender: null, p_motivo: null, p_nota: t }); toast('Nota guardada'); }
        } else if (v === 'aviso') {
          await enviarAviso('negocio', n.id);
        } else if (v === 'suspender') {
          const m = await pedirTexto('Desactivar cuenta', 'Motivo (lo verá el negocio)', { min: 3, max: 150, boton: 'Desactivar', clase: 'rojo', ayuda: 'No podrá anotar ni sus clientes ver su link hasta que la reactives. Podrá exportar sus datos.' });
          if (m) { await conCarga(() => rpc('admin_estado', { p_negocio: n.id, p_suspender: true, p_motivo: m, p_nota: null })); toast('Cuenta desactivada'); }
        } else if (v === 'reactivar') {
          await conCarga(() => rpc('admin_estado', { p_negocio: n.id, p_suspender: false, p_motivo: null, p_nota: null })); toast('Reactivado ✓');
        }
        vNegocios();
      } catch (e) { error(e); }
    }
    return r;
  }

  // ---------- Pagos ----------
  let filtroPago = 'pendiente';
  async function vPagos() {
    const todos = await conCarga(() => rpc('admin_pagos'));
    const d = filtroPago ? todos.filter((x) => x.estado === filtroPago) : todos;
    const lista = el('div', { class: 'col' });
    if (!d.length) lista.append(el('div', { class: 'lista' }, el('div', { class: 'vacio' }, 'Sin pagos aquí.')));
    for (const s of d) {
      const foto = el('div');
      if (s.comprobante_path) sb.storage.from('pagos').createSignedUrl(s.comprobante_path, 600).then(({ data: u }) => { if (u) foto.append(el('img', { class: 'foto-comp mt', src: u.signedUrl, alt: 'Comprobante', onclick: () => abrir(u.signedUrl) }),
        el('button', { class: 'btn chico mt', type: 'button', onclick: async () => { try { LC.descargar('pago-' + LC.norm(s.negocio_nombre).replace(/[^a-z0-9]+/g, '-') + '-' + String(s.creado).slice(0, 10) + '.jpg', await (await fetch(u.signedUrl)).blob()); } catch (e) { abrir(u.signedUrl); } } }, '⬇️ Descargar')); });
      lista.append(el('div', { class: 'tarjeta' },
        el('div', { class: 'fila entre' }, el('strong', null, s.negocio_nombre), el('span', { class: 'tag ' + (s.estado === 'aprobada' ? 'verde' : s.estado === 'rechazada' ? 'rojo' : 'naranjo') }, s.estado)),
        el('div', null, (s.tipo === 'conexiones' ? '🤝 ' + s.paquetes + ' paquete' + (s.paquetes > 1 ? 's' : '') + ' de conexiones' : s.meses === 12 ? '📅 Pro anual (12 meses)' : 'Pro 1 mes') + ' · ' + pesos(s.monto) + ' · ' + fechaHora(s.creado)), s.cupon ? el('div', { class: 'verde' }, '🏷️ Usó el cupón ' + s.cupon) : null,
        s.nota ? el('p', { class: 'sutil' }, '“' + s.nota + '”') : null, s.motivo ? el('p', { class: 'rojo' }, s.motivo) : null, foto,
        s.estado === 'pendiente' ? el('div', { class: 'grid2 mt' },
          el('button', { class: 'btn peligro', type: 'button', onclick: async () => { const m = await pedirTexto('Rechazar pago', 'Motivo (lo verá el negocio)', { min: 3, max: 150, boton: 'Rechazar', clase: 'rojo' }); if (m) { try { await conCarga(() => rpc('admin_resolver_pago', { p_id: s.id, p_aprobar: false, p_motivo: m })); vPagos(); } catch (e) { error(e); } } } }, 'Rechazar'),
          el('button', { class: 'btn verde', type: 'button', onclick: async () => { if (await confirmar('Aprobar pago', 'Revisa que el dinero (' + pesos(s.monto) + ') haya llegado. ¿Aprobar ' + (s.tipo === 'conexiones' ? s.paquetes + ' paquete(s) de conexiones' : s.meses === 12 ? '12 meses de Pro (plan anual)' : '1 mes de Pro') + '?', 'Aprobar')) { try { await conCarga(() => rpc('admin_resolver_pago', { p_id: s.id, p_aprobar: true, p_motivo: null })); toast('Aprobado ✓'); vPagos(); } catch (e) { error(e); } } } }, 'Aprobar')) : null));
    }
    const cuenta = (e) => todos.filter((x) => !e || x.estado === e).length;
    pintar(el('h2', null, 'Pagos'), el('div', { class: 'subtabs' }, [['pendiente', '🧾 Por revisar'], ['aprobada', '✅ Aprobados'], ['rechazada', '❌ Rechazados'], ['', 'Todos']].map(([k, tx]) =>
      el('button', { class: 'chip' + (filtroPago === k ? ' activo' : ''), type: 'button', onclick: () => { filtroPago = k; vPagos(); } }, tx + ' (' + cuenta(k) + ')'))),
      el('p', { class: 'sutil' }, 'Aquí llegan los "Ya pagué" de las billeteras (Pro y conexiones extra). Revisa que la plata llegó y aprueba.'), lista);
  }

  // ---------- Keys ----------
  async function vKeys() {
    const d = await conCarga(() => rpc('admin_keys'));
    pintar(el('div', { class: 'fila entre mb' }, el('h2', { style: 'margin:0' }, 'Keys Pro'), el('a', { class: 'btn chico', href: '#resumen' }, '← Volver')),
      el('button', { class: 'btn primario ancho mb', type: 'button', onclick: crearKeys }, '＋ Generar keys'),
      el('div', { class: 'lista' }, d.length ? d.map((k) => el('div', { class: 'item', style: 'cursor:default' },
        el('div', { class: 'crece' }, el('div', { class: 'nom', style: 'font-family:monospace' }, k.codigo), el('div', { class: 'sub' }, k.meses + ' mes(es) · ' + pesos(k.precio) + (k.usada_por ? ' · usada por ' + (k.negocio_nombre || '—') + ' el ' + fechaCorta(k.usada_at) : k.revocada ? ' · revocada' : ' · libre'))),
        !k.usada_por && !k.revocada ? el('button', { class: 'btn chico', type: 'button', onclick: () => copiar(k.codigo) }, 'Copiar') : null,
        !k.usada_por && !k.revocada ? el('button', { class: 'btn-icono', type: 'button', 'aria-label': 'Revocar', onclick: async () => { if (await confirmar('Revocar key', '¿Revocar ' + k.codigo + '?', 'Revocar', 'rojo')) { await rpc('admin_revocar_key', { p_codigo: k.codigo }).catch(error); vKeys(); } } }, '🚫') : null))
        : el('div', { class: 'vacio' }, 'Aún no generas keys.')));
  }
  async function crearKeys() {
    const meses = el('select', null, [1, 3, 6, 12].map((m) => el('option', { value: m }, m + (m === 1 ? ' mes' : ' meses'))));
    const cant = el('input', { type: 'number', min: 1, max: 50, value: 1, inputmode: 'numeric' }), precio = el('input', { type: 'number', min: 0, inputmode: 'numeric', placeholder: 'Para tus reportes' });
    const ok = await dialogo('Generar keys', el('div', null, el('div', { class: 'campo' }, el('label', null, 'Duración'), meses), el('div', { class: 'campo' }, el('label', null, 'Cantidad'), cant), el('div', { class: 'campo' }, el('label', null, 'Precio de venta (cada una)'), precio)),
      [{ texto: 'Cancelar', valor: null }, { texto: 'Generar', clase: 'primario', valor: true }]);
    if (!ok) return;
    try {
      const k = await conCarga(() => rpc('admin_crear_keys', { p_meses: Number(meses.value), p_cantidad: Number(cant.value), p_precio: Number(precio.value || 0) }));
      await dialogo('Keys listas', el('div', null, el('div', { class: 'tarjeta plana', style: 'font-family:monospace;white-space:pre' }, k.join('\n')), el('button', { class: 'btn ancho', type: 'button', onclick: () => copiar(k.join('\n')) }, 'Copiar todas')));
      vKeys();
    } catch (e) { error(e); }
  }

  // ---------- Cupones de descuento en la activación ----------
  async function vCupones() {
    const d = await conCarga(() => rpc('admin_cupones'));
    pintar(el('div', { class: 'fila entre mb' }, el('h2', { style: 'margin:0' }, '🏷️ Cupones'), el('a', { class: 'btn chico', href: '#resumen' }, '← Volver')),
      el('p', { class: 'sutil' }, 'Descuento en la activación de Pro. Tus clientes lo escriben en Mi plan → "Tengo un cupón". El uso se cuenta cuando apruebas su pago.'),
      el('button', { class: 'btn primario ancho mb', type: 'button', onclick: () => editarCupon() }, '＋ Nuevo cupón'),
      el('div', { class: 'lista' }, d.length ? d.map((c) => el('div', { class: 'item', style: 'cursor:default' + (c.valido ? '' : ';opacity:.55') },
        el('div', { class: 'crece' }, el('div', { class: 'nom', style: 'font-family:monospace' }, c.codigo + ' · ' + c.descuento + '%'),
          el('div', { class: 'sub' }, c.usos + (c.usos_max ? ' de ' + c.usos_max : '') + ' usos · ' + c.aplicados + ' esperando pago' + (c.vence ? ' · vence ' + fechaCorta(c.vence) : '') + (c.valido ? '' : ' · no vigente'))),
        el('button', { class: 'btn chico', type: 'button', onclick: () => copiar(c.codigo) }, 'Copiar'),
        el('button', { class: 'btn-icono', type: 'button', 'aria-label': c.activo ? 'Desactivar' : 'Activar', onclick: async () => { await rpc('admin_cupon_activo', { p_codigo: c.codigo, p_activo: !c.activo }).catch(error); vCupones(); } }, c.activo ? '⏸️' : '▶️')))
        : el('div', { class: 'vacio' }, 'Aún no creas cupones.')));
  }
  async function editarCupon() {
    const cod = el('input', { maxlength: 20, placeholder: 'FERIA50', style: 'text-transform:uppercase' }), desc = el('input', { type: 'number', min: 1, max: 100, value: 50, inputmode: 'numeric' });
    const usos = el('input', { type: 'number', min: 1, inputmode: 'numeric', placeholder: 'Sin límite' }), vence = el('input', { type: 'date', min: LC.hoyISO() });
    const campo = (t, i, a) => el('div', { class: 'campo' }, el('label', null, t), i, a ? el('div', { class: 'ayuda' }, a) : null);
    const err = el('div', { class: 'error' });
    await dialogo('Nuevo cupón', el('div', null, campo('Código', cod, 'Letras, números o guiones (3 a 20).'), el('div', { class: 'grid2' }, campo('Descuento %', desc), campo('Máximo de usos', usos)), campo('Vence (opcional)', vence), err),
      [{ texto: 'Cancelar', valor: null }, { texto: 'Crear', clase: 'primario', valor: true, antes: async () => {
        try { await conCarga(() => rpc('admin_guardar_cupon', { p_codigo: cod.value, p_descuento: Number(desc.value), p_usos_max: usos.value ? Number(usos.value) : null, p_vence: vence.value || null })); return true; }
        catch (e) { err.textContent = LC.traducir(e).message; return false; }
      } }]);
    vCupones();
  }

  // ---------- Avisos ----------
  async function vAvisos() {
    const n = await conCarga(() => rpc('admin_segmentos'));
    const grupos = [['todos', '📣 A todas las billeteras', n.todos], ['free', '🙂 Solo Free (para ofrecer Pro)', n.free], ['prueba', '🎁 Solo en prueba Pro', n.prueba],
      ['pro', '⭐ Solo Pro (novedades, gracias)', n.pro], ['vencen', '⏰ Les vence el Pro o la prueba esta semana', n.vencen]];
    pintar(el('div', { class: 'fila entre mb' }, el('h2', { style: 'margin:0' }, 'Mensajes masivos'), el('a', { class: 'btn chico', href: '#resumen' }, '← Volver')),
      el('p', { class: 'sutil' }, 'Llegan a la bandeja de avisos de cada billetera y como notificación al celular.'),
      el('div', { class: 'lista' }, grupos.map(([v, t, c]) => el('button', { class: 'item', type: 'button', disabled: !c, onclick: () => enviarAviso(v) },
        el('span', { class: 'crece' }, t), el('span', { class: 'tag' }, c + ' billetera' + (c === 1 ? '' : 's'))))));
  }
  async function enviarAviso(destino, negocio) {
    const tit = el('input', { maxlength: 80 }), cue = el('textarea', { maxlength: 300 });
    const ok = await dialogo('Nuevo aviso', el('div', null, el('div', { class: 'campo' }, el('label', null, 'Título'), tit), el('div', { class: 'campo' }, el('label', null, 'Mensaje'), cue)),
      [{ texto: 'Cancelar', valor: null }, { texto: 'Enviar', clase: 'primario', valor: true }]);
    if (!ok) return;
    try { const n = await conCarga(() => rpc('admin_aviso', { p_destino: destino, p_negocio: negocio || null, p_titulo: tit.value, p_cuerpo: cue.value })); toast('Enviado a ' + n + ' libreta(s) ✓'); } catch (e) { error(e); }
  }

  // ---------- Ajustes ----------
  // ---------- Ajustes (sub-pestañas, todo editable desde aquí) ----------
  let secAj = 'precios';
  const SECCIONES = [['precios', '💳 Precios y links'], ['planes', '⭐ Planes'], ['reglas', '⚖️ Reglas'], ['textos', '✏️ Textos'], ['ventas', '🏷️ Cupones y keys'],
    ['avisos', '📣 Avisos'], ['push', '🔔 Notificaciones'], ['registro', '📜 Registro'], ['versiones', '🔄 Versiones'], ['cuenta', '👤 Mi cuenta']];
  async function vAjustes(sec) {
    if (sec && SECCIONES.some((x) => x[0] === sec)) secAj = sec;
    const { data: a, error: e } = await sb.from('ajustes').select('*').single();
    if (e) throw LC.traducir(e);
    const cfg = await rpc('config_publica');
    const inp = (v, attrs) => { const i = el('input', attrs || {}); i.value = v == null ? '' : v; return i; };
    const num = (i) => Math.round(Number(i.value));
    const campo = (tx, i, ay) => el('div', { class: 'campo' }, el('label', null, tx), i, ay ? el('div', { class: 'ayuda' }, ay) : null);
    const guardar = (fn) => el('button', { class: 'btn primario ancho', type: 'button', onclick: async () => {
      try { await conCarga(() => rpc('admin_guardar_ajustes', { p: fn() })); toast('Guardado ✓'); vAjustes(); } catch (er) { error(er); } } }, 'Guardar');
    const cuerpo = el('div');
    const t = a.transferencia || {}, ln = a.lim_normal || {};
    if (secAj === 'precios') {
      const f = { act: inp(a.precio_activacion, { type: 'number', inputmode: 'numeric' }), mes: inp(a.precio_mensual, { type: 'number', inputmode: 'numeric' }), anual: inp(a.precio_anual, { type: 'number', inputmode: 'numeric' }),
        wsp: inp(a.contacto_whatsapp, { type: 'tel', placeholder: '+56 9 …' }), conInc: inp(a.conexiones_incluidas, { type: 'number' }), conPaq: inp(a.conexiones_paquete, { type: 'number' }),
        linkAnual: inp(a.link_pago_anual, { type: 'url', placeholder: 'https://link.mercadopago.cl/…' }),
        conPrecio: inp(a.precio_paquete, { type: 'number', inputmode: 'numeric' }), tb: inp(t.banco), tt: inp(t.tipo), tn: inp(t.numero, { inputmode: 'numeric' }), tr: inp(t.rut), ttit: inp(t.titular), te: inp(t.email, { type: 'email' }) };
      const ls = espacios(a.links_pro && a.links_pro.length ? a.links_pro : (a.link_pago ? [{ texto: 'Mercado Pago', url: a.link_pago, activo: true }] : []));
      cuerpo.append(el('div', { class: 'tarjeta' }, el('h2', null, 'Precio Pro'), el('div', { class: 'grid3' }, campo('Activación (una vez)', f.act), campo('Mensualidad', f.mes), campo('Plan anual', f.anual, '0 = sin plan anual')),
          el('p', { class: 'sutil' }, 'El primer pago es activación + mensualidad (o + año); después solo la mensualidad o el año. El anual da 12 meses al aprobarlo.')),
        el('div', { class: 'tarjeta' }, el('h2', null, 'Link de pago mensual (2 espacios)'), ls.caja, el('p', { class: 'sutil' }, 'El activo es el que ven las billeteras al pagar la mensualidad, conexiones extra y cupones.')),
        el('div', { class: 'tarjeta' }, el('h2', null, 'Link de pago anual'), campo('Link para pagar el año completo', f.linkAnual, 'Debe empezar con https://. Si lo dejas vacío, el plan anual usa el link mensual.')),
        el('div', { class: 'tarjeta' }, el('h2', null, '🤝 Conexiones extra'), el('div', { class: 'grid3' }, campo('Incluidas', f.conInc), campo('Por paquete', f.conPaq), campo('Precio/mes', f.conPrecio))),
        el('div', { class: 'tarjeta' }, el('h2', null, 'Tus datos de transferencia'), campo('Banco', f.tb), campo('Tipo de cuenta', f.tt), campo('Número', f.tn), campo('RUT', f.tr), campo('Titular', f.ttit), campo('Correo', f.te), campo('Tu WhatsApp de soporte', f.wsp)),
        guardar(() => ({ precio_activacion: num(f.act), precio_mensual: num(f.mes), precio_anual: num(f.anual), link_pago_anual: f.linkAnual.value.trim(), links_pro: ls.valor(), contacto_whatsapp: f.wsp.value.trim() ? V.telefono(f.wsp.value) : '',
          conexiones_incluidas: num(f.conInc), conexiones_paquete: num(f.conPaq), precio_paquete: num(f.conPrecio),
          transferencia: { banco: f.tb.value.trim(), tipo: f.tt.value.trim(), numero: f.tn.value.replace(/\D/g, ''), rut: f.tr.value ? V.rutBonito(V.rut(f.tr.value)) : '', titular: f.ttit.value.trim(), email: f.te.value.trim() } })));
    } else if (secAj === 'planes') {
      const pf = LC.plan(cfg, 'free'), pp = LC.plan(cfg, 'pro');
      const bloque = (p) => ({ nombre: inp(p.nombre, { maxlength: 30 }), desc: inp(p.descripcion, { maxlength: 160 }), ben: (() => { const x = el('textarea', { rows: 6, maxlength: 3000 }); x.value = (p.beneficios || []).join('\n'); return x; })() });
      const bf = bloque(pf), bp = bloque(pp);
      const l = { lc: inp(ln.clientes, { type: 'number' }), lm: inp(ln.movimientos, { type: 'number' }), lcaja: inp(ln.caja, { type: 'number' }), lq: inp(ln.cuotas, { type: 'number' }),
        lp: inp(ln.productos, { type: 'number' }), lk: inp(ln.comprobantes, { type: 'number' }), lcat: inp(ln.categorias, { type: 'number' }), lh: inp(ln.historial_meses, { type: 'number' }) };
      const tarjeta = (tit, b) => el('div', { class: 'tarjeta' }, el('h2', null, tit), campo('Nombre', b.nombre), campo('Descripción', b.desc), campo('Beneficios (uno por línea)', b.ben, 'Salen en la portada, en "Mi plan" y en el aviso de Pro.'));
      const pl = (b) => ({ nombre: b.nombre.value.trim(), descripcion: b.desc.value.trim(), beneficios: b.ben.value.split('\n').map((x) => x.trim()).filter(Boolean).slice(0, 20) });
      cuerpo.append(tarjeta('Plan gratis', bf), el('div', { class: 'tarjeta' }, el('h2', null, 'Límites del plan gratis'), el('p', { class: 'sutil' }, 'Pro y la prueba no tienen límites.'),
          el('div', { class: 'grid2' }, campo('Clientes activos', l.lc), campo('Fiados y abonos/mes', l.lm), campo('Ingresos y gastos/mes', l.lcaja), campo('Cuotas activas', l.lq), campo('Productos', l.lp), campo('Comprobantes/mes', l.lk), campo('Categorías propias', l.lcat), campo('Historial (meses)', l.lh))),
        tarjeta('Plan Pro', bp),
        guardar(() => ({ planes: { free: pl(bf), pro: pl(bp) }, lim_normal: { clientes: num(l.lc), movimientos: num(l.lm), cuotas: num(l.lq), productos: num(l.lp), comprobantes: num(l.lk), historial_meses: num(l.lh), caja: num(l.lcaja), categorias: num(l.lcat) } })));
    } else if (secAj === 'reglas') {
      const f = { prueba: inp(a.dias_prueba, { type: 'number' }), gracia: inp(a.dias_gracia, { type: 'number' }), comp: inp(a.dias_comprobantes, { type: 'number' }), aviso: inp(a.dias_aviso, { type: 'number' }),
        vlegal: inp(a.version_legal, { type: 'number' }), vmin: inp(a.version_min),
        refDias: inp(a.dias_referido, { type: 'number' }), refMin: inp(a.ref_min_registros, { type: 'number' }), refMax: inp(a.ref_max_premios, { type: 'number' }) };
      cuerpo.append(el('div', { class: 'tarjeta' }, el('h2', null, 'Reglas'),
          el('div', { class: 'grid2' }, campo('Días de prueba Pro', f.prueba, 'Al crear una billetera.'), campo('Días de gracia', f.gracia, 'Después de vencer la mensualidad.'),
            campo('Días que se guardan los comprobantes', f.comp, 'Después la foto se borra sola.'), campo('Aviso antes de vencer (días)', f.aviso, 'Además avisa 3 y 1 día antes y el mismo día.'))),
        el('div', { class: 'tarjeta' }, el('h2', null, '🎁 Invita y gana'), el('p', { class: 'sutil' }, 'Cada billetera tiene su link para invitar. Cuando el invitado se usa de verdad, quien invitó gana días de Pro.'),
          el('div', { class: 'grid3' }, campo('Días de Pro por invitado', f.refDias, '0 = apagado'), campo('Registros mínimos', f.refMin, 'Ventas, gastos o fiados del invitado'), campo('Máximo de premios', f.refMax, 'Por billetera'))),
        el('div', { class: 'tarjeta' }, el('h2', null, 'Avanzado'), campo('Versión de los textos legales', f.vlegal, 'Súbela si cambias los Términos: todos deberán aceptarlos de nuevo.'),
          campo('Versión mínima obligatoria', f.vmin, 'Quien tenga una versión menor ve un aviso rojo para actualizar.')),
        el('div', { class: 'tarjeta' }, el('h2', null, 'Feriados'), el('p', { class: 'sutil' }, 'En feriados no se puede cobrar.'), el('button', { class: 'btn', type: 'button', onclick: feriados }, 'Ver y editar feriados')),
        guardar(() => ({ dias_prueba: num(f.prueba), dias_gracia: num(f.gracia), dias_comprobantes: num(f.comp), dias_aviso: num(f.aviso), version_legal: num(f.vlegal), version_min: f.vmin.value.trim(),
          dias_referido: num(f.refDias), ref_min_registros: num(f.refMin), ref_max_premios: num(f.refMax) })));
    } else if (secAj === 'textos') {
      const nombres = { landing_titulo: 'Título de la portada', landing_bajada: 'Texto bajo el título', pro_titulo: 'Título del aviso de Pro', pago_instrucciones: 'Instrucciones de pago en el link del cliente ({negocio} = nombre)' };
      const campos = Object.keys(LC.TEXTOS_DEF).map((k) => { const x = el('textarea', { rows: 3, maxlength: 1000 }); x.value = LC.texto(cfg, k); return [k, x]; });
      cuerpo.append(el('div', { class: 'tarjeta' }, el('h2', null, 'Textos de la app'), ...campos.map(([k, x]) => campo(nombres[k] || k, x))),
        guardar(() => ({ textos: Object.fromEntries(campos.map(([k, x]) => [k, x.value.trim()]).filter(([k, v]) => v && v !== LC.TEXTOS_DEF[k])) })));
    } else if (secAj === 'ventas') {
      cuerpo.append(el('div', { class: 'col' }, el('a', { class: 'btn', href: '#cupones' }, '🏷️ Cupones de descuento'), el('a', { class: 'btn', href: '#keys' }, '🔑 Keys Pro')));
    } else if (secAj === 'avisos') {
      return vAvisos();
    } else if (secAj === 'push') {
      cuerpo.append(el('div', { class: 'tarjeta' }, el('h2', null, 'Notificaciones push'), el('p', null, cfg.vapid_public ? '✅ Claves push configuradas' : '⚠️ Falta generar las claves push'),
        el('div', { class: 'col' }, el('button', { class: 'btn', type: 'button', onclick: generarVapid }, cfg.vapid_public ? 'Regenerar claves push' : 'Generar claves push'),
          el('button', { class: 'btn', type: 'button', onclick: probar }, '🩺 Probar servidor'))));
    } else if (secAj === 'registro') {
      const d = await rpc('admin_auditoria').catch(() => []);
      cuerpo.append(el('div', { class: 'lista' }, d.length ? d.map((x) => el('div', { class: 'item', style: 'cursor:default' }, el('div', { class: 'crece' },
        el('div', { class: 'nom' }, x.accion + (x.negocio ? ' · ' + x.negocio : '')), el('div', { class: 'sub', style: 'white-space:normal' }, JSON.stringify(x.detalle || {}).slice(0, 160))),
        el('span', { class: 'sutil' }, fechaHora(x.at)))) : el('div', { class: 'vacio' }, 'Sin registros.')));
    } else if (secAj === 'versiones') {
      cuerpo.append(tarjetaVersiones(a, cfg));
    } else if (secAj === 'cuenta') {
      const { data: u } = await sb.auth.getSession();
      cuerpo.append(el('div', { class: 'tarjeta' }, el('h2', null, 'Mi cuenta'), el('p', null, (u.session && u.session.user.email) || ''),
        el('div', { class: 'col' }, el('button', { class: 'btn', type: 'button', onclick: async () => {
          const c1 = await pedirTexto('Cambiar contraseña', 'Nueva contraseña', { tipo: 'password', min: 8, max: 72 }); if (!c1) return;
          const { error: er } = await sb.auth.updateUser({ password: c1 }); if (er) error(er); else toast('Contraseña cambiada ✓');
        } }, '🔑 Cambiar contraseña'), el('button', { class: 'btn texto', type: 'button', style: 'color:var(--deuda)', onclick: salir }, '🚪 Cerrar sesión'))));
    }
    pintar(el('h2', null, 'Ajustes'), el('div', { class: 'subtabs' }, SECCIONES.map(([k, tx]) => el('button', { class: 'chip' + (secAj === k ? ' activo' : ''), type: 'button', onclick: () => { secAj = k; vAjustes(); } }, tx))), cuerpo);
  }
  // 2 espacios de link (texto + link) con interruptor: solo uno activo.
  function espacios(lista) {
    const ls = [0, 1].map((i) => ({ texto: (lista[i] && lista[i].texto) || '', url: (lista[i] && lista[i].url) || '', activo: !!(lista[i] && lista[i].activo) }));
    if (!ls.some((x) => x.activo)) ls[0].activo = true;
    const caja = el('div');
    const pintarS = () => vaciar(caja).append(...ls.map((x, i) => el('div', { class: 'slotpago' + (x.activo ? ' on' : '') },
      el('label', { class: 'check' }, el('input', { type: 'radio', name: 'slotPro', checked: x.activo, onchange: () => { ls.forEach((y, j) => { y.activo = j === i; }); pintarS(); } }), el('strong', null, 'Espacio ' + (i + 1) + (x.activo ? ' · activo' : ''))),
      el('input', { maxlength: 60, placeholder: 'Nombre (ej: Mercado Pago)', value: x.texto, oninput: (ev) => { x.texto = ev.target.value; } }),
      el('input', { type: 'url', inputmode: 'url', maxlength: 300, placeholder: 'https://mpago.la/…', value: x.url, style: 'margin-top:6px', oninput: (ev) => { x.url = ev.target.value; } }))));
    pintarS();
    return { caja, valor: () => ls.map((x) => ({ texto: x.texto.trim(), url: x.url.trim(), activo: x.activo })) };
  }
  // Asistente de actualización en 4 pasos: 1) base de datos, 2) función del servidor, 3) probar en tu celular, 4) liberar para todos.
  // Nadie recibe cambios hasta el paso 4, y no se puede liberar si la base de datos o la función quedaron atrás.
  async function leerPublicada() {
    const j = await (await fetch('../version.json?t=' + Date.now(), { cache: 'no-store' })).json();
    return { version: String(j.version || ''), bd: Number(j.bd || 0), funcion: String(j.funcion || '') };
  }
  function tarjetaVersiones(a, cfg) {
    const caja = el('div', null, el('p', { class: 'sutil' }, 'Revisando…'));
    const paso = (n, ok, titulo, ...cuerpo) => el('div', { class: 'paso-act ' + (ok === true ? 'ok' : ok === false ? 'pend' : '') },
      el('b', null, ok === true ? '✓' : n), el('div', { class: 'crece' }, el('strong', null, titulo), ...cuerpo));
    (async () => {
      let pub;
      try { pub = await leerPublicada(); } catch (e) { vaciar(caja).append(el('p', { class: 'rojo' }, 'No se pudo leer la versión publicada en GitHub. Revisa tu internet.')); return; }
      const bd = Number((cfg && cfg.version_bd) || 0);
      let fn = null; try { const r = await LC.funcion({ accion: 'ping' }); fn = r && r.ok ? String(r.version) : null; } catch (e) { fn = null; }
      const okBd = bd >= pub.bd, okFn = !pub.funcion || (fn && !LC.versionMenor(fn, pub.funcion)), okCel = !LC.versionMenor(LC.VERSION, pub.version);
      const liberada = !LC.versionMenor(a.version_liberada, pub.version);
      const bLib = el('button', { class: 'btn primario ancho', type: 'button', disabled: liberada || !okBd || !okFn }, liberada ? '✓ La v' + pub.version + ' ya está liberada para todos' : '🚀 Liberar v' + pub.version + ' para todos');
      bLib.onclick = async () => {
        if (!await confirmar('Liberar actualización', '¿Liberar la v' + pub.version + '? A todos les aparecerá "✨ Hay una versión nueva" con el botón Actualizar.', 'Liberar')) return;
        try { await conCarga(() => rpc('admin_guardar_ajustes', { p: { version_liberada: pub.version } })); toast('✅ v' + pub.version + ' liberada para todos'); if (!okCel) LC.actualizarAhora(); else vAjustes('versiones'); } catch (e) { error(e); }
      };
      vaciar(caja).append(...[
        el('div', { class: 'grid2 mb' }, kpi('Publicada en GitHub', 'v' + pub.version), kpi('Liberada para todos', 'v' + a.version_liberada, liberada ? 'verde' : 'naranjo'),
          kpi('Tu celular', 'v' + LC.VERSION, okCel ? 'verde' : 'naranjo'), kpi('Base de datos', bd ? 'v' + bd : '—', okBd ? 'verde' : 'rojo')),
        liberada && okBd && okFn ? el('div', { class: 'banda info' }, '✅ Todo al día. Cuando publique una versión nueva, aquí verás los pasos.') : null,
        // La base se actualiza sola cada 10 minutos (desde GitHub): aquí solo se ve su estado.
        paso(1, okBd, 'Base de datos' + (okBd ? ' al día (v' + bd + ')' : ': actualizándose sola a la v' + pub.bd),
          okBd ? null : el('p', { class: 'sutil' }, 'Se actualiza sola en máximo 10 minutos, sin borrar datos.'),
          okBd ? null : el('button', { class: 'btn chico', type: 'button', onclick: () => vAjustes('versiones') }, '🔄 Revisar de nuevo')),
        okFn ? null : paso(2, pub.funcion ? !!okFn : null, 'Función del servidor "enviar"' + (okFn ? ' al día' + (fn ? ' (v' + fn + ')' : '') : fn ? ': tienes v' + fn + ', falta v' + pub.funcion : ': no responde'),
          okFn ? null : el('p', { class: 'sutil' }, 'Copia el código y en Supabase → Edge Functions → enviar → Code: borra todo, pega y toca Deploy. Si no existe, créala con el nombre "enviar" y apaga "Verify JWT".'),
          el('div', { class: 'fila envolver' }, el('button', { class: 'btn chico' + (okFn ? '' : ' primario'), type: 'button', onclick: copiarFuncion }, '📋 Copiar código'),
            el('a', { class: 'btn chico', href: 'https://supabase.com/dashboard/project/' + new URL(LC.C.SUPABASE_URL).hostname.split('.')[0] + '/functions', target: '_blank', rel: 'noopener' }, '↗ Abrir Edge Functions'),
            el('button', { class: 'btn chico', type: 'button', onclick: () => vAjustes('versiones') }, '🩺 Probar de nuevo'))),
        paso(3, okCel, okCel ? 'Tu celular ya tiene la v' + LC.VERSION : 'Pruébala en tu celular',
          okCel ? el('p', { class: 'sutil' }, 'Revisa que todo funcione antes de liberarla.') : el('p', { class: 'sutil' }, 'Solo tu celular se actualiza. Revisa que todo funcione antes de liberarla.'),
          okCel ? null : el('button', { class: 'btn chico primario', type: 'button', onclick: LC.actualizarAhora }, '⬇️ Actualizar mi celular a la v' + pub.version)),
        paso(4, liberada, 'Liberar para todos', el('p', { class: 'sutil' }, !okBd || !okFn ? '🔒 Espera que la base termine de actualizarse: si liberas antes, la app de tus clientes fallaría.' : 'A cada billetera le aparece el botón Actualizar. Nadie recibe cambios hasta que tú lo apruebas.'), bLib),
        el('button', { class: 'btn texto ancho', type: 'button', onclick: async () => { if (await confirmar('Reparar la app', 'Vuelve a descargar la app en este celular. No borra datos.', 'Reparar')) LC.repararApp(); } }, '🛠️ Reparar la app en este celular')].filter(Boolean));
    })();
    return el('div', { class: 'tarjeta', id: 'actualizaciones' }, el('h2', null, '🔄 Actualizar la app'), caja);
  }
  async function copiarArchivo(ruta, prueba, aviso) {
    try {
      const t = await (await fetch(ruta + '?t=' + Date.now(), { cache: 'no-store' })).text();
      if (!prueba.test(t)) throw new Error('No se pudo leer ' + ruta.split('/').pop());
      copiar(t.split('\n').filter((x) => !x.startsWith('--') && !x.startsWith('//')).join('\n').trim(), aviso);
    } catch (e) { toast('No se pudo copiar: ' + e.message, { error: true }); }
  }
  const copiarFuncion = () => copiarArchivo('../supabase/functions/enviar/corto.ts', /^import /m, 'Código copiado ✓ Pégalo en Edge Functions → enviar → Deploy');
  const b64u = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  async function generarVapid() {
    const cfg = await rpc('config_publica');
    if (cfg.vapid_public && !await confirmar('Regenerar claves', 'Todos tendrán que volver a activar las notificaciones. ¿Seguir?', 'Regenerar', 'rojo')) return;
    try {
      const kp = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
      const pub = b64u(await crypto.subtle.exportKey('raw', kp.publicKey));
      const priv = (await crypto.subtle.exportKey('jwk', kp.privateKey)).d;
      await rpc('admin_set_secret', { p_nombre: 'vapid_private', p_valor: priv });
      await rpc('admin_set_secret', { p_nombre: 'vapid_public', p_valor: pub });
      toast('Claves push listas ✓'); vAjustes();
    } catch (e) { error(e); }
  }
  async function feriados() {
    const { data } = await sb.from('feriados').select('*').gte('fecha', LC.hoyISO()).order('fecha');
    const fecha = el('input', { type: 'date' }), nombre = el('input', { maxlength: 60, placeholder: 'Nombre' });
    const r = await dialogo('Feriados', el('div', null, el('div', { class: 'lista' }, (data || []).map((x) => el('div', { class: 'item', style: 'cursor:default' }, el('span', { class: 'crece' }, fechaLarga(x.fecha) + ' · ' + x.nombre),
      el('button', { class: 'btn-icono', type: 'button', 'aria-label': 'Borrar', onclick: async () => { await rpc('admin_feriado', { p_fecha: x.fecha, p_nombre: null, p_borrar: true }).catch(error); document.querySelector('.velo').remove(); feriados(); } }, '🗑️')))),
      el('h3', null, 'Agregar'), el('div', { class: 'grid2' }, fecha, nombre)),
    [{ texto: 'Cerrar', valor: null }, { texto: 'Agregar', clase: 'primario', valor: true }]);
    if (r && fecha.value) { await rpc('admin_feriado', { p_fecha: fecha.value, p_nombre: nombre.value, p_borrar: false }).catch(error); feriados(); }
  }

  // ---------- Soporte ----------
  let canal = null;
  async function vSoporte(neg) {
    if (neg) return chatSoporte(neg);
    const d = await conCarga(() => rpc('admin_soporte_lista'));
    pintar(el('h2', null, 'Soporte'), el('p', { class: 'sutil' }, 'Chats privados con cada billetera. Te llega un aviso cuando alguien escribe.'),
      el('div', { class: 'lista' }, d.length ? d.map((c) => el('a', { class: 'item', href: '#soporte/' + c.negocio },
        el('div', { class: 'avatar', style: 'background:' + LC.colorDe(c.nombre) }, LC.iniciales(c.nombre)),
        el('div', { class: 'crece' }, el('div', { class: 'nom' }, c.nombre), el('div', { class: 'sub' }, c.ultimo_texto || '')),
        c.sin_leer ? el('span', { class: 'tag rojo' }, c.sin_leer) : el('span', { class: 'sutil' }, fechaCorta(c.ultimo))))
        : el('div', { class: 'vacio' }, 'Aún no hay mensajes de soporte.')));
  }
  async function chatSoporte(neg) {
    const cont = el('div', { class: 'chat-soporte' }), titulo = el('h2', { style: 'margin:0' }, 'Soporte');
    const txt = el('textarea', { maxlength: 1000, placeholder: 'Escribe tu respuesta…', 'aria-label': 'Mensaje' });
    const cargar = async () => {
      const d = await rpc('admin_soporte_ver', { p_negocio: neg });
      titulo.textContent = '💬 ' + (d.negocio || 'Soporte');
      vaciar(cont);
      if (!d.mensajes.length) cont.append(el('div', { class: 'vacio' }, 'Sin mensajes. Escríbele primero si quieres.'));
      d.mensajes.forEach((m) => cont.append(el('div', { class: 'msg' + (m.de === 'admin' ? ' mio' : '') }, m.texto, el('div', { class: 'meta' }, fechaHora(m.creado) + (m.de === 'admin' && m.leido ? ' · ✓✓ visto' : '')))));
      window.scrollTo(0, document.body.scrollHeight);
    };
    const enviar = async () => {
      const t = txt.value.trim(); if (!t) return;
      try { await rpc('admin_soporte_enviar', { p_negocio: neg, p_texto: t }); txt.value = ''; await cargar(); } catch (e) { error(e); }
    };
    txt.addEventListener('keydown', (e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); enviar(); } });
    const borrar = async () => {
      if (!await confirmar('Borrar chat', 'Se borra la conversación completa con esta billetera (para ambos). Los mensajes se borran solos a los 30 días.', 'Borrar', 'rojo')) return;
      try { await rpc('admin_soporte_borrar', { p_negocio: neg }); toast('Chat borrado ✓'); location.hash = '#soporte'; } catch (e) { error(e); }
    };
    pintar(el('div', { class: 'fila mb' }, el('a', { class: 'btn-icono', href: '#soporte', style: 'text-decoration:none', 'aria-label': 'Volver' }, '←'), titulo,
      el('button', { class: 'btn-icono', type: 'button', 'aria-label': 'Borrar chat', style: 'margin-left:auto', onclick: borrar }, '🗑️')),
      cont, el('div', { class: 'escribir' }, txt, el('button', { class: 'btn primario', type: 'button', onclick: enviar }, 'Enviar')));
    await cargar();
    if (canal) sb.removeChannel(canal);
    canal = sb.channel('adm-sop-' + neg).on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'soporte', filter: 'negocio=eq.' + neg },
      (p) => { if (p.new.de === 'negocio') cargar(); }).subscribe();
  }

  // ---------- Crear cuenta para un cliente ----------
  function claveAzar() {
    const abc = 'abcdefghjkmnpqrstuvwxyz', num = '23456789', b = crypto.getRandomValues(new Uint8Array(10));
    let s = ''; for (let i = 0; i < 6; i++) s += abc[b[i] % abc.length]; for (let i = 6; i < 9; i++) s += num[b[i] % num.length];
    return s.charAt(0).toUpperCase() + s.slice(1);
  }
  async function crearCuenta() {
    const RUB = [['almacen', 'Almacén'], ['feria', 'Feria'], ['catalogo', 'Catálogo'], ['emprendimiento', 'Emprendimiento'], ['servicios', 'Servicios'], ['educacion', 'Educación'], ['club', 'Club'], ['personal', 'Personal'], ['otro', 'Otro']];
    const nombre = el('input', { maxlength: 50, placeholder: 'Ej: Almacén Don Pedro' }), rubro = el('select', null, RUB.map(([v, t]) => el('option', { value: v }, t)));
    const email = el('input', { type: 'email', inputmode: 'email', placeholder: 'correo@cliente.cl' }), clave = el('input', { value: claveAzar() });
    const tel = el('input', { type: 'tel', inputmode: 'tel', placeholder: '+56 9 … (para enviarle los datos)' });
    const plan = el('select', null, el('option', { value: '0' }, 'Prueba Pro (según Ajustes)'), el('option', { value: '30' }, 'Pro 1 mes (ya pagó)'), el('option', { value: '90' }, 'Pro 3 meses'));
    const err = el('div', { class: 'error' });
    const campo = (t, i, a) => el('div', { class: 'campo' }, el('label', null, t), i, a ? el('div', { class: 'ayuda' }, a) : null);
    let creado = null;
    await dialogo('Crear cuenta', el('div', null, campo('Nombre del negocio', nombre), campo('Rubro', rubro), campo('Correo del cliente', email),
      campo('Contraseña', clave, 'Se la envías tú. Puede cambiarla en Mi cuenta.'), campo('WhatsApp del cliente', tel), campo('Plan inicial', plan), err),
    [{ texto: 'Cancelar', valor: null }, { texto: 'Crear', clase: 'primario', valor: true, antes: async () => {
      err.textContent = '';
      if (nombre.value.trim().length < 2) { err.textContent = 'Escribe el nombre del negocio'; return false; }
      if (!V.email(email.value)) { err.textContent = 'Correo inválido'; return false; }
      const m = V.clave(clave.value, email.value); if (m) { err.textContent = m; return false; }
      try { if (tel.value.trim()) V.telefono(tel.value); } catch (e) { err.textContent = e.message; return false; }
      const { data } = await sb.auth.getSession();
      const r = await conCarga(() => LC.funcion({ accion: 'crear_usuario', email: email.value.trim(), clave: clave.value, nombre: nombre.value, rubro: rubro.value, dias_pro: Number(plan.value) }, data.session && data.session.access_token)).catch((e) => ({ ok: false, error: e.message }));
      if (!r.ok) { err.textContent = r.error || 'No se pudo crear la cuenta'; return false; }
      creado = { email: email.value.trim().toLowerCase(), clave: clave.value, nombre: nombre.value.trim(), tel: tel.value.trim() };
      return true;
    } }]);
    if (!creado) return;
    const msg = 'Hola, tu billetera de ' + creado.nombre + ' en Libreta de Cobros está lista 🎉\n\nEntra aquí: ' + LC.RAIZ + '#ingresar\nCorreo: ' + creado.email + '\nContraseña: ' + creado.clave +
      '\n\nTe recomiendo instalarla en tu celular (botón Instalar) y cambiar la contraseña en Más → Mi cuenta.';
    await dialogo('Cuenta creada ✓', el('div', null, el('p', null, 'Envíale estos datos a tu cliente:'), el('div', { class: 'tarjeta plana', style: 'white-space:pre-wrap' }, msg),
      el('div', { class: 'col' }, creado.tel ? el('button', { class: 'btn wsp', type: 'button', onclick: () => abrir(wa(V.telefono(creado.tel), msg)) }, '💬 Enviar por WhatsApp') : null,
        el('button', { class: 'btn', type: 'button', onclick: () => copiar(msg) }, '📋 Copiar mensaje'))));
    if (location.hash.startsWith('#negocios')) vNegocios();
  }

  arrancar().catch(error);
})();
