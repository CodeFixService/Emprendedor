/* Panel del superadministrador: billeteras y ajustes propios (los pagos de conexiones extra se revisan en CM → Pagos) de la Libreta. No ve clientes ni deudas de los negocios.
   Precios, planes, textos, keys, cupones, avisos a todos, soporte y versiones se manejan en el Centro de Mando (Pagos, Control, Mensajes y Apps). */
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
    if (bdVieja(st.config)) document.querySelector('.app').insertBefore(el('a', { class: 'banda error', href: '#ajustes', style: 'text-decoration:none' },
      el('span', null, '⚠️ La base de datos está en v' + (st.config.version_bd || '4 o menos') + ' y esta versión de la app necesita v' + LC.BD + '. Corre la consulta de actualización.'), el('span', { class: 'btn chico' }, 'Ver cómo')), document.getElementById('vista'));
    LC.revisarVersion(st.config, (txt, fn) => {
      const v = document.getElementById('admUpd'); if (v) v.remove();
      if (txt) document.querySelector('.app').insertBefore(el('div', { id: 'admUpd', class: 'banda info' }, el('span', null, txt + ' Tu celular aún no la tiene.'), el('button', { class: 'btn chico', type: 'button', onclick: fn }, 'Actualizar')), document.getElementById('vista'));
    });
    // Núcleo (ayuda.js): cabecera común con el plan y el menú de la cuenta.
    window.CFX_PERFIL_APP = { __proto__: LC.perfil, nombre: 'Administración', nombreFijo: 'Cuenta de administración.' };
    window.CFX_AYUDA_PEND = { rpc, app: 'billetera', admin: true, email: data.session.user.email, nombre: 'Administración', cuenta: '#ajustes/cuenta', salir, quitar: '#salir' };
    if (window.CFX_AYUDA) window.CFX_AYUDA.iniciar(window.CFX_AYUDA_PEND);
    window.addEventListener('hashchange', router);
    router();
  }
  function router() {
    const [v, a] = (location.hash.slice(1) || 'resumen').split('/');
    document.querySelectorAll('#nav a').forEach((x) => x.classList.toggle('activo', x.dataset.v === v));
    ({ resumen: vResumen, negocios: vNegocios, registro: () => vAjustes('registro'), ajustes: vAjustes }[v] || vResumen)(a).catch(error);
  }

  // ---------- Resumen ----------
  async function vResumen() {
    const [r, op] = await conCarga(() => Promise.all([rpc('admin_resumen'), rpc('admin_oportunidades')]));


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
        null)))) : null;
    const cfgP = r.mrr;
    pintarUso();
    pintar(el('h2', null, 'Resumen'),
      !r.cron_ok ? el('div', { class: 'banda error' }, '⚠️ Las tareas automáticas no están activas: en Supabase → Database → Extensions enciende pg_cron y pg_net, y vuelve a correr el SQL de actualización.') : null,
      !r.push_ok ? el('div', { class: 'banda aviso' }, '⚠️ Falta generar las claves push.', el('a', { class: 'btn chico', href: '#ajustes/push' }, 'Ir')) : null,
      r.pagos_pendientes ? el('a', { class: 'banda info', href: window.CFX_AYUDA ? CFX_AYUDA.panelCM() + '#pagos' : '#', style: 'text-decoration:none' }, '💳 ' + r.pagos_pendientes + ' pago(s) de conexiones por revisar en el Centro de Mando', el('span', { class: 'btn chico' }, 'Revisar')) : null,
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
      // El uso del servidor (base, archivos, cola) se ve en el Centro de Mando → Resumen (carrusel de servidores). Aquí solo limpiar y respaldar.
      el('div', { class: 'tarjeta' }, el('h2', null, '🧹 Limpieza y respaldo'), usoDetalle),
      el('button', { class: 'btn ancho mt', type: 'button', onclick: probar }, '🩺 Probar servidor de avisos'),
      null);
  }
  const usoDetalle = el('div', { class: 'mt' });
  async function pintarUso() {
    const u = await rpc('admin_uso').catch(() => null); if (!u) return;
    const limpiar = async (que, tx) => { if (!await confirmar('Limpiar', tx, 'Limpiar', 'rojo')) return; try { const n = await conCarga(() => rpc('admin_limpiar', { p_que: que })); toast('Listo ✓ (' + n + ')'); pintarUso(); } catch (e) { error(e); } };
    vaciar(usoDetalle).append(
      el('div', { class: 'grid2' }, el('button', { class: 'btn chico', type: 'button', onclick: () => limpiar('comprobantes', 'Borra las fotos de comprobantes revisados más antiguas que los días de Ajustes → Reglas.') }, '🧾 Comprobantes viejos'),
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
    pintar(el('div', { class: 'fila entre mb' }, el('h2', { style: 'margin:0' }, 'Billeteras'), el('button', { class: 'btn chico primario', type: 'button', id: 'bCrearCta', onclick: crearCuenta }, '＋ Crear cuenta')), inp,
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

  // ---------- Avisos ----------
  async function enviarAviso(destino, negocio) {
    const tit = el('input', { maxlength: 80 }), cue = el('textarea', { maxlength: 300 });
    const ok = await dialogo('Nuevo aviso', el('div', null, el('div', { class: 'campo' }, el('label', null, 'Título'), tit), el('div', { class: 'campo' }, el('label', null, 'Mensaje'), cue)),
      [{ texto: 'Cancelar', valor: null }, { texto: 'Enviar', clase: 'primario', valor: true }]);
    if (!ok) return;
    try { const n = await conCarga(() => rpc('admin_aviso', { p_destino: destino, p_negocio: negocio || null, p_titulo: tit.value, p_cuerpo: cue.value })); toast('Enviado a ' + n + ' libreta(s) ✓'); } catch (e) { error(e); }
  }

  // ---------- Ajustes (cuadrícula del núcleo: solo lo propio de la Libreta) ----------
  async function vAjustes(sec) {
    const { data: a, error: e } = await sb.from('ajustes').select('*').single();
    if (e) throw LC.traducir(e);
    const cfg = await rpc('config_publica');
    const inp = (v, attrs) => { const i = el('input', attrs || {}); i.value = v == null ? '' : v; return i; };
    const num = (i) => Math.round(Number(i.value));
    const campo = (tx, i, ay) => el('div', { class: 'campo' }, el('label', null, tx), i, ay ? el('div', { class: 'ayuda' }, ay) : null);
    const guardar = (fn, k) => el('button', { class: 'btn primario ancho', type: 'button', onclick: async () => {
      try { await conCarga(() => rpc('admin_guardar_ajustes', { p: fn() })); toast('Guardado ✓'); vAjustes(k); } catch (er) { error(er); } } }, 'Guardar');
    const SECC = [
      { k: 'conexiones', ico: '🤝', t: 'Conexiones extra', d: 'Incluidas, paquetes y precio', abrir: (z) => {
        const f = { inc: inp(a.conexiones_incluidas, { type: 'number' }), paq: inp(a.conexiones_paquete, { type: 'number' }), pre: inp(a.precio_paquete, { type: 'number', inputmode: 'numeric' }) };
        z.append(el('div', { class: 'tarjeta' }, el('p', { class: 'sutil' }, 'Conexiones entre billeteras: cuántas trae cada una y cuánto cuesta cada paquete extra (se paga en Pagos de este panel).'),
          el('div', { class: 'grid3' }, campo('Incluidas', f.inc), campo('Por paquete', f.paq), campo('Precio/mes', f.pre))),
        guardar(() => ({ conexiones_incluidas: num(f.inc), conexiones_paquete: num(f.paq), precio_paquete: num(f.pre) }), 'conexiones'));
      } },
      { k: 'reglas', ico: '⚖️', t: 'Reglas', d: 'Prueba, gracia, invitados y feriados', abrir: (z) => {
        const f = { prueba: inp(a.dias_prueba, { type: 'number' }), gracia: inp(a.dias_gracia, { type: 'number' }), comp: inp(a.dias_comprobantes, { type: 'number' }), aviso: inp(a.dias_aviso, { type: 'number' }),
          vlegal: inp(a.version_legal, { type: 'number' }), refDias: inp(a.dias_referido, { type: 'number' }), refMin: inp(a.ref_min_registros, { type: 'number' }), refMax: inp(a.ref_max_premios, { type: 'number' }) };
        z.append(el('div', { class: 'tarjeta' }, el('div', { class: 'grid2' }, campo('Días de prueba Pro', f.prueba, 'Al crear una billetera.'), campo('Días de gracia', f.gracia, 'Después de vencer la mensualidad.'),
            campo('Días que se guardan los comprobantes', f.comp, 'Después la foto se borra sola.'), campo('Aviso antes de vencer (días)', f.aviso, 'Además avisa 3 y 1 día antes y el mismo día.'))),
          el('div', { class: 'tarjeta' }, el('h2', null, '🎁 Invita y gana'), el('p', { class: 'sutil' }, 'Cada billetera tiene su link para invitar. Cuando el invitado se usa de verdad, quien invitó gana días de Pro.'),
            el('div', { class: 'grid3' }, campo('Días de Pro por invitado', f.refDias, '0 = apagado'), campo('Registros mínimos', f.refMin, 'Ventas, gastos o fiados del invitado'), campo('Máximo de premios', f.refMax, 'Por billetera'))),
          el('div', { class: 'tarjeta' }, campo('Versión de los textos legales', f.vlegal, 'Súbela si cambias los Términos: todos deberán aceptarlos de nuevo.'),
            el('p', { class: 'sutil' }, 'En feriados no se puede cobrar.'), el('button', { class: 'btn', type: 'button', onclick: feriados }, '📅 Ver y editar feriados')),
          guardar(() => ({ dias_prueba: num(f.prueba), dias_gracia: num(f.gracia), dias_comprobantes: num(f.comp), dias_aviso: num(f.aviso), version_legal: num(f.vlegal),
            dias_referido: num(f.refDias), ref_min_registros: num(f.refMin), ref_max_premios: num(f.refMax) }), 'reglas'));
      } },
      { k: 'push', ico: '🔔', t: 'Notificaciones', d: 'Claves push y servidor', abrir: (z) => {
        z.append(el('div', { class: 'tarjeta' }, el('p', null, cfg.vapid_public ? '✅ Claves push configuradas' : '⚠️ Falta generar las claves push'),
          el('div', { class: 'col' }, el('button', { class: 'btn', type: 'button', onclick: generarVapid }, cfg.vapid_public ? 'Regenerar claves push' : 'Generar claves push'),
            el('button', { class: 'btn', type: 'button', onclick: probar }, '🩺 Probar servidor'),
            el('button', { class: 'btn texto', type: 'button', onclick: copiarFuncion }, '📋 Copiar código de la función "enviar"'))));
      } },
      { k: 'registro', ico: '📜', t: 'Registro de cambios', d: 'Lo que se hizo en el panel', abrir: async (z) => {
        const d = await rpc('admin_auditoria').catch(() => []);
        z.append(el('div', { class: 'lista' }, d.length ? d.map((x) => el('div', { class: 'item', style: 'cursor:default' }, el('div', { class: 'crece' },
          el('div', { class: 'nom' }, x.accion + (x.negocio ? ' · ' + x.negocio : '')), el('div', { class: 'sub', style: 'white-space:normal' }, JSON.stringify(x.detalle || {}).slice(0, 160))),
          el('span', { class: 'sutil' }, fechaHora(x.at)))) : el('div', { class: 'vacio' }, 'Sin registros.')));
        window.CFX_AJUSTES.registro(z, (f, x) => rpc(f, x), { recargar: () => vAjustes('registro') });
      } },
      // Perfil común del núcleo (CFX_PERFIL): foto, modo, notificaciones y contraseña.
      { k: 'cuenta', ico: '👤', t: 'Mi perfil', d: 'Foto, modo y contraseña', abrir: (z) => { const c = el('div', { class: 'tarjeta' }); z.append(c); window.CFX_PERFIL.montar(c); } }
    ];
    const caja = el('div');
    pintar(caja);
    const aj = window.CFX_AJUSTES.montar(caja, SECC, { arriba: '<h2>Ajustes</h2><p class="sutil">Precios, planes, textos, keys, cupones, avisos, soporte y versiones se manejan en el Centro de Mando.</p>' });
    if (sec && SECC.some((x) => x.k === sec)) aj.abrir(sec);
  }
  const copiarFuncion = async () => {
    try {
      const t = await (await fetch('../supabase/functions/enviar/corto.ts?t=' + Date.now(), { cache: 'no-store' })).text();
      if (!/^import /m.test(t)) throw new Error('No se pudo leer corto.ts');
      copiar(t.split('\n').filter((x) => !x.startsWith('--') && !x.startsWith('//')).join('\n').trim(), 'Código copiado ✓ Pégalo en Edge Functions → enviar → Deploy');
    } catch (e) { toast('No se pudo copiar: ' + e.message, { error: true }); }
  };
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
      toast('Claves push listas ✓'); vAjustes('push');
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
