/* Panel del superadministrador: negocios, planes, pagos, keys, avisos y ajustes. No ve clientes ni deudas de los negocios. */
(function () {
  'use strict';
  const { el, $, vaciar, rpc, sb, V, error, toast, conCarga, dialogo, confirmar, pedirTexto, pesos, fechaCorta, fechaLarga, fechaHora, copiar, wa, abrir, local } = LC;
  const vista = $('#vista');
  $('#ver').textContent = LC.VERSION;
  LC.registrarSW();
  const pintar = (...n) => { vaciar(vista).append(...n.flat().filter((x) => x != null && x !== false)); };
  const kpi = (t, v, cls) => el('div', { class: 'kpi' }, el('div', { class: 't' }, t), el('div', { class: 'v ' + (cls || '') }, v));

  async function arrancar() {
    const { data } = await sb.auth.getSession();
    if (!data.session) { location.replace('../#ingresar'); return; }
    const st = await rpc('mi_estado');
    if (!st.es_admin) { pintar(el('div', { class: 'vacio' }, el('span', { class: 'ico' }, '🔒'), 'Solo el administrador puede entrar aquí.', el('br'), el('a', { href: '../app/' }, 'Volver a la app'))); return; }
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
    ({ resumen: vResumen, negocios: vNegocios, pagos: vPagos, ajustes: vAjustes, keys: vKeys, avisos: vAvisos, soporte: vSoporte }[v] || vResumen)(a).catch(error);
  }

  // ---------- Resumen ----------
  async function vResumen() {
    const [r, op] = await conCarga(() => Promise.all([rpc('admin_resumen'), rpc('admin_oportunidades')]));
    $('#badgePagos').textContent = r.pagos_pendientes; $('#badgePagos').classList.toggle('oculto', !r.pagos_pendientes);
    $('#badgeSoporte').textContent = r.soporte_sin_leer; $('#badgeSoporte').classList.toggle('oculto', !r.soporte_sin_leer);
    const pct = Math.round(r.bd_mb * 100 / 500);
    const conv = r.negocios ? Math.round(r.convertidos * 100 / r.negocios) : 0;
    const dias = []; for (let i = 29; i >= 0; i--) dias.push(LC.sumarDias(LC.hoyISO(), -i));
    const porDia = Object.fromEntries((r.registros_dia || []).map((x) => [x.dia, x.n]));
    const maxD = Math.max(1, ...dias.map((d) => porDia[d] || 0));
    const etapa = (t, n, cls) => el('div', { class: 'kpi' }, el('div', { class: 't' }, t), el('div', { class: 'v ' + (cls || '') }, n));
    const op1 = (titulo, lista, sub, plantilla) => lista.length ? el('div', { class: 'tarjeta' }, el('h2', null, titulo + ' (' + lista.length + ')'),
      el('div', { class: 'lista' }, lista.map((n) => el('div', { class: 'item', style: 'cursor:default' },
        el('div', { class: 'avatar', style: 'background:' + LC.colorDe(n.nombre) }, LC.iniciales(n.nombre)),
        el('a', { class: 'crece', href: '#negocios/' + n.id, style: 'color:inherit;text-decoration:none' }, el('div', { class: 'nom' }, n.nombre), el('div', { class: 'sub' }, sub(n))),
        n.whatsapp ? el('button', { class: 'btn-icono', type: 'button', 'aria-label': 'WhatsApp', onclick: () => abrir(wa(n.whatsapp, plantilla(n))) }, '💬') : null,
        el('a', { class: 'btn-icono', href: '#soporte/' + n.id, style: 'text-decoration:none', 'aria-label': 'Chat' }, '✉️'))))) : null;
    const cfgP = r.mrr;
    pintar(el('h2', null, 'Resumen'),
      !r.cron_ok ? el('div', { class: 'banda error' }, '⚠️ Las tareas automáticas no están activas: en Supabase → Database → Extensions enciende pg_cron y pg_net, y vuelve a correr el SQL de actualización.') : null,
      !r.push_ok ? el('div', { class: 'banda aviso' }, '⚠️ Falta generar las claves push.', el('a', { class: 'btn chico', href: '#ajustes' }, 'Ir')) : null,
      r.pagos_pendientes ? el('a', { class: 'banda info', href: '#pagos', style: 'text-decoration:none' }, '💳 ' + r.pagos_pendientes + ' pago(s) por revisar', el('span', { class: 'btn chico' }, 'Revisar')) : null,
      r.soporte_sin_leer ? el('a', { class: 'banda info', href: '#soporte', style: 'text-decoration:none' }, '💬 ' + r.soporte_sin_leer + ' chat(s) de soporte sin leer', el('span', { class: 'btn chico' }, 'Ver')) : null,
      el('div', { class: 'kpi hero mb' }, el('div', { class: 't' }, 'Ingreso mensual recurrente (Pro activos × mensualidad)'), el('div', { class: 'grande' }, pesos(cfgP)),
        el('div', { class: 't' }, 'Cobrado este mes: ' + pesos(r.ingresos_mes) + ' · ' + r.convertidos + ' clientes han pagado (' + conv + '% de las billeteras)')),
      el('h3', null, 'Embudo de ventas'),
      el('div', { class: 'grid2 mb' }, etapa('Billeteras creadas', r.negocios), etapa('En prueba gratis', r.en_prueba), etapa('Quieren Pro ⭐', r.quieren_pro, r.quieren_pro ? 'naranjo' : ''),
        etapa('Pro pagando', r.premium, 'verde'), etapa('Bloqueadas', r.bloqueados, r.bloqueados ? 'rojo' : ''), etapa('Activas 7 días', r.activos_7d, 'verde')),
      el('div', { class: 'tarjeta' }, el('h2', null, 'Registros: ' + r.nuevos_7d + ' esta semana · ' + r.nuevos_30d + ' en 30 días'),
        el('div', { class: 'grafico', role: 'img', 'aria-label': 'Registros por día en los últimos 30 días' }, dias.map((d) => el('div', { title: LC.fechaCorta(d) + ': ' + (porDia[d] || 0) },
          el('i', { class: 'c', style: 'height:' + Math.round((porDia[d] || 0) * 100 / maxD) + 'px' }))))),
      el('h3', null, 'Oportunidades'),
      op1('⭐ Quieren Pro', op.quieren_pro, (n) => 'Lo pidió ' + LC.relativo(n.fecha.slice(0, 10)) + ' · ' + n.email, (n) => 'Hola ' + n.nombre + ', vi que quieres activar Pro en tu billetera 🙌 Te cuento cómo pagar:'),
      op1('⏳ Su prueba termina pronto', op.prueba_termina, (n) => 'Termina ' + LC.relativo(n.fecha.slice(0, 10)) + ' · usó la app ' + (n.ultimo_uso ? LC.relativo(n.ultimo_uso.slice(0, 10)) : 'nunca'), (n) => 'Hola ' + n.nombre + ', tu prueba gratis de Libreta de Cobros termina pronto. ¿Te ayudo a activar Pro para que no se bloquee?'),
      op1('💳 Pro por vencer', op.pro_vence, (n) => 'Vence ' + LC.relativo(n.fecha.slice(0, 10)), (n) => 'Hola ' + n.nombre + ', te recuerdo que tu mensualidad de Pro vence pronto. ¿Te paso los datos para pagar?'),
      op1('🔒 Bloqueadas que siguen entrando', op.bloqueados, (n) => (n.activado ? 'Venció su Pro' : 'Terminó su prueba') + ' · entró ' + (n.ultimo_uso ? LC.relativo(n.ultimo_uso.slice(0, 10)) : '—'), (n) => 'Hola ' + n.nombre + ', vi que tu billetera quedó bloqueada. Si quieres la activamos hoy y sigues donde quedaste.'),
      !op.quieren_pro.length && !op.prueba_termina.length && !op.pro_vence.length && !op.bloqueados.length ? el('div', { class: 'lista' }, el('div', { class: 'vacio' }, 'Sin oportunidades por ahora.')) : null,
      el('button', { class: 'btn primario ancho mb mt', type: 'button', onclick: crearCuenta }, '＋ Crear cuenta para un cliente'),
      el('div', { class: 'tarjeta' }, el('h2', null, 'Capacidad del plan gratis de Supabase'),
        el('div', { class: 'fila entre' }, el('span', null, 'Base de datos'), el('strong', null, r.bd_mb + ' MB de 500 MB')),
        el('div', { class: 'barra ' + (pct >= 85 ? 'lleno' : pct >= 70 ? 'alerta' : '') }, el('i', { style: 'width:' + Math.min(pct, 100) + '%' })),
        el('div', { class: 'fila entre mt' }, el('span', null, 'Archivos (fotos)'), el('strong', null, r.archivos_mb + ' MB de 1.024 MB')),
        pct >= 70 ? el('p', { class: 'naranjo mt' }, 'Pasaste el 70%: es momento de pasar a Supabase Pro.') : null,
        el('p', { class: 'sutil mt' }, 'Avisos en cola: ' + r.cola_push)),
      el('div', { class: 'grid2' }, el('a', { class: 'btn', href: '#keys' }, '🔑 Keys'), el('a', { class: 'btn', href: '#avisos' }, '📣 Avisos a todos')),
      el('button', { class: 'btn ancho mt', type: 'button', onclick: probar }, '🩺 Probar servidor de avisos'),
      el('button', { class: 'btn texto ancho mt', type: 'button', onclick: async () => { await sb.auth.signOut().catch(() => {}); location.replace('../#ingresar'); } }, '🚪 Cerrar sesión'));
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
        el('span', { class: 'tag ' + (n.estado !== 'activo' ? 'rojo' : { pro: 'premium', prueba: 'marca', bloqueado: 'rojo' }[n.plan]) }, n.estado !== 'activo' ? n.estado : { pro: 'Pro', prueba: 'Prueba', bloqueado: 'Bloqueada' }[n.plan]))));
    };
    inp.oninput = () => { busca = inp.value; clearTimeout(t); t = setTimeout(() => cargar().catch(error), 300); };
    pintar(el('div', { class: 'fila entre mb' }, el('h2', { style: 'margin:0' }, 'Billeteras'), el('button', { class: 'btn chico primario', type: 'button', onclick: crearCuenta }, '＋ Crear cuenta')), inp,
      el('div', { class: 'chips mt' }, [['todos', 'Todas'], ['pro', 'Pro'], ['prueba', 'En prueba'], ['bloqueado', 'Bloqueadas'], ['suspendido', 'Suspendidas'], ['eliminado', 'Por borrar']].map(([v, tx]) =>
        el('button', { class: 'chip' + (filtro === v ? ' activo' : ''), type: 'button', onclick: () => { filtro = v; vNegocios(); } }, tx))),
      lista,
      el('button', { class: 'btn ancho mt', type: 'button', onclick: () => {
        const plan = { pro: 'Pro', prueba: 'Prueba', bloqueado: 'Bloqueada' };
        LC.descargar('billeteras-' + LC.hoyISO() + '.csv', LC.csv(ultimaLista, [{ t: 'Negocio', v: (n) => n.nombre }, { t: 'Correo', v: (n) => n.email }, { t: 'WhatsApp', v: (n) => n.whatsapp || '' },
          { t: 'Rubro', v: (n) => n.rubro }, { t: 'Plan', v: (n) => plan[n.plan] }, { t: 'Activación pagada', v: (n) => n.activado ? 'Sí' : 'No' }, { t: 'Prueba hasta', v: (n) => n.prueba_hasta || '' },
          { t: 'Pro hasta', v: (n) => n.premium_hasta || '' }, { t: 'Clientes', v: (n) => n.clientes }, { t: 'Movimientos del mes', v: (n) => n.movimientos_mes || 0 }, { t: 'Último uso', v: (n) => n.ultimo_uso || '' }, { t: 'Creada', v: (n) => n.creado }]));
      } }, '📄 Exportar lista (CSV)'));
    await cargar();
  }
  async function fichaNegocio(n) {
    const det = await rpc('admin_negocio_detalle', { p_negocio: n.id }).catch(() => null);
    const plantillas = [['Recordar pago', 'Hola ' + n.nombre + ', te recuerdo que tu mensualidad de Libreta de Cobros vence pronto. ¿Te paso los datos para pagar?'],
      ['Ofrecer Pro', 'Hola ' + n.nombre + ', ¿cómo te ha ido con tu billetera? Si activas Pro tienes todo sin límites, avisos automáticos a tus clientes y reportes. ¿Te ayudo?'],
      ['Ayuda para empezar', 'Hola ' + n.nombre + ', soy Josué de Libreta de Cobros. ¿Te ayudo a configurar tu billetera? Toma 5 minutos.']];
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
      el('p', null, 'Plan: ', el('strong', null, { pro: 'Pro', prueba: 'Prueba gratis', bloqueado: 'Bloqueada' }[n.plan]),
        n.plan === 'pro' ? ' · pagado hasta ' + fechaLarga(n.premium_hasta) : n.plan === 'prueba' ? ' · hasta ' + fechaLarga(n.prueba_hasta) : '',
        n.activado ? ' · ✅ activación pagada' : ' · sin activación'),
      n.estado === 'suspendido' ? el('p', { class: 'rojo' }, 'Suspendido: ' + (n.motivo_suspension || '')) : null,
      n.nota_admin ? el('p', { class: 'sutil' }, '📝 ' + n.nota_admin) : null,
      el('div', { class: 'col' },
        el('button', { class: 'btn primario', type: 'button', onclick: () => cerrarCon('dias') }, '⭐ Dar Pro (días)'),
        n.plan !== 'pro' ? el('button', { class: 'btn', type: 'button', onclick: () => cerrarCon('prueba') }, '🎁 Extender prueba gratis') : null,
        el('a', { class: 'btn', href: '#soporte/' + n.id }, '💬 Chat de soporte' + (n.soporte ? ' (' + n.soporte + ')' : '')),
        n.plan === 'pro' ? el('button', { class: 'btn', type: 'button', onclick: () => cerrarCon('quitar') }, 'Quitar Pro') : null,
        el('button', { class: 'btn', type: 'button', onclick: () => cerrarCon('nota') }, '📝 Nota interna'),
        el('button', { class: 'btn', type: 'button', onclick: () => cerrarCon('aviso') }, '📣 Enviar aviso'),
        n.whatsapp ? el('button', { class: 'btn wsp', type: 'button', onclick: () => abrir(wa(n.whatsapp, 'Hola ' + n.nombre + ', te escribo de Libreta de Cobros.')) }, '💬 WhatsApp') : null,
        n.estado === 'activo' ? el('button', { class: 'btn peligro', type: 'button', onclick: () => cerrarCon('suspender') }, '⛔ Suspender')
          : n.estado === 'suspendido' ? el('button', { class: 'btn', type: 'button', onclick: () => cerrarCon('reactivar') }, '✅ Reactivar') : null)));
    function cerrarCon(v) { document.querySelector('.velo').remove(); accion(v); }
    async function accion(v) {
      try {
        if (v === 'dias') {
          const d = await pedirTexto('Dar Pro', 'Días de Pro', { valor: '30', inputmode: 'numeric', tipo: 'number', validar: (x) => Number(x) >= 1 && Number(x) <= 3660 ? null : 'Entre 1 y 3660' });
          if (d) { await conCarga(() => rpc('admin_plan', { p_negocio: n.id, p_accion: 'sumar', p_dias: Number(d) })); toast('Pro activado ✓'); }
        } else if (v === 'prueba') {
          const d = await pedirTexto('Extender prueba', 'Días más de prueba gratis', { valor: '7', inputmode: 'numeric', tipo: 'number', validar: (x) => Number(x) >= 1 && Number(x) <= 90 ? null : 'Entre 1 y 90' });
          if (d) { await conCarga(() => rpc('admin_plan', { p_negocio: n.id, p_accion: 'prueba', p_dias: Number(d) })); toast('Prueba extendida ✓'); }
        } else if (v === 'quitar') {
          if (await confirmar('Quitar Pro', '¿Quitar el Pro de ' + n.nombre + ' ahora? Su billetera quedará bloqueada.', 'Quitar', 'rojo')) { await conCarga(() => rpc('admin_plan', { p_negocio: n.id, p_accion: 'quitar', p_dias: null })); toast('Listo'); }
        } else if (v === 'nota') {
          const t = await pedirTexto('Nota interna', 'Solo la ves tú', { valor: n.nota_admin || '', multilinea: true, max: 500 });
          if (t != null) { await rpc('admin_estado', { p_negocio: n.id, p_suspender: null, p_motivo: null, p_nota: t }); toast('Nota guardada'); }
        } else if (v === 'aviso') {
          await enviarAviso('negocio', n.id);
        } else if (v === 'suspender') {
          const m = await pedirTexto('Suspender', 'Motivo (lo verá el negocio)', { min: 3, max: 150, boton: 'Suspender', clase: 'rojo' });
          if (m) { await conCarga(() => rpc('admin_estado', { p_negocio: n.id, p_suspender: true, p_motivo: m, p_nota: null })); toast('Suspendido'); }
        } else if (v === 'reactivar') {
          await conCarga(() => rpc('admin_estado', { p_negocio: n.id, p_suspender: false, p_motivo: null, p_nota: null })); toast('Reactivado ✓');
        }
        vNegocios();
      } catch (e) { error(e); }
    }
    return r;
  }

  // ---------- Pagos ----------
  async function vPagos() {
    const d = await conCarga(() => rpc('admin_pagos'));
    const lista = el('div', { class: 'col' });
    if (!d.length) lista.append(el('div', { class: 'lista' }, el('div', { class: 'vacio' }, 'Sin solicitudes de pago.')));
    for (const s of d) {
      const foto = el('div');
      if (s.comprobante_path) sb.storage.from('pagos').createSignedUrl(s.comprobante_path, 600).then(({ data: u }) => { if (u) foto.append(el('img', { class: 'foto-comp mt', src: u.signedUrl, alt: 'Comprobante', onclick: () => abrir(u.signedUrl) })); });
      lista.append(el('div', { class: 'tarjeta' },
        el('div', { class: 'fila entre' }, el('strong', null, s.negocio_nombre), el('span', { class: 'tag ' + (s.estado === 'aprobada' ? 'verde' : s.estado === 'rechazada' ? 'rojo' : 'naranjo') }, s.estado)),
        el('div', null, 'Pro 1 mes · ' + pesos(s.monto) + ' · ' + fechaHora(s.creado)),
        s.nota ? el('p', { class: 'sutil' }, '“' + s.nota + '”') : null, s.motivo ? el('p', { class: 'rojo' }, s.motivo) : null, foto,
        s.estado === 'pendiente' ? el('div', { class: 'grid2 mt' },
          el('button', { class: 'btn peligro', type: 'button', onclick: async () => { const m = await pedirTexto('Rechazar pago', 'Motivo (lo verá el negocio)', { min: 3, max: 150, boton: 'Rechazar', clase: 'rojo' }); if (m) { try { await conCarga(() => rpc('admin_resolver_pago', { p_id: s.id, p_aprobar: false, p_motivo: m })); vPagos(); } catch (e) { error(e); } } } }, 'Rechazar'),
          el('button', { class: 'btn verde', type: 'button', onclick: async () => { if (await confirmar('Aprobar pago', 'Revisa que el dinero (' + pesos(s.monto) + ') haya llegado. ¿Aprobar 1 mes de Pro?', 'Aprobar')) { try { await conCarga(() => rpc('admin_resolver_pago', { p_id: s.id, p_aprobar: true, p_motivo: null })); toast('Aprobado ✓'); vPagos(); } catch (e) { error(e); } } } }, 'Aprobar')) : null));
    }
    pintar(el('h2', null, 'Pagos'), el('p', { class: 'sutil' }, 'Aquí llegan los avisos de "Ya pagué" de tus clientes (con comprobante si lo subieron). Revisa que la plata llegó a tu cuenta y aprueba: se le suma 1 mes de Pro al instante.'), lista);
  }

  // ---------- Keys ----------
  async function vKeys() {
    const d = await conCarga(() => rpc('admin_keys'));
    pintar(el('div', { class: 'fila entre mb' }, el('h2', { style: 'margin:0' }, 'Keys Premium'), el('a', { class: 'btn chico', href: '#resumen' }, '← Volver')),
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

  // ---------- Avisos ----------
  async function vAvisos() {
    pintar(el('div', { class: 'fila entre mb' }, el('h2', { style: 'margin:0' }, 'Avisos a negocios'), el('a', { class: 'btn chico', href: '#resumen' }, '← Volver')),
      el('p', { class: 'sutil' }, 'Llegan a la bandeja de cada libreta y como notificación push.'),
      el('div', { class: 'col' }, [['todos', 'A todas las libretas'], ['premium', 'Solo Premium'], ['normal', 'Solo Normal']].map(([v, t]) => el('button', { class: 'btn', type: 'button', onclick: () => enviarAviso(v) }, '📣 ' + t))));
  }
  async function enviarAviso(destino, negocio) {
    const tit = el('input', { maxlength: 80 }), cue = el('textarea', { maxlength: 300 });
    const ok = await dialogo('Nuevo aviso', el('div', null, el('div', { class: 'campo' }, el('label', null, 'Título'), tit), el('div', { class: 'campo' }, el('label', null, 'Mensaje'), cue)),
      [{ texto: 'Cancelar', valor: null }, { texto: 'Enviar', clase: 'primario', valor: true }]);
    if (!ok) return;
    try { const n = await conCarga(() => rpc('admin_aviso', { p_destino: destino, p_negocio: negocio || null, p_titulo: tit.value, p_cuerpo: cue.value })); toast('Enviado a ' + n + ' libreta(s) ✓'); } catch (e) { error(e); }
  }

  // ---------- Ajustes ----------
  async function vAjustes() {
    const { data: a, error: e } = await sb.from('ajustes').select('*').single();
    if (e) throw LC.traducir(e);
    const cfg = await rpc('config_publica');
    const t = a.transferencia || {}, ln = a.lim_normal || {};
    const inp = (v, attrs) => { const i = el('input', attrs || {}); i.value = v == null ? '' : v; return i; };
    const f = {
      mensual: inp(a.precio_mensual, { type: 'number', inputmode: 'numeric' }), activacion: inp(a.precio_activacion, { type: 'number', inputmode: 'numeric' }), anual: inp(a.precio_anual, { type: 'number', inputmode: 'numeric' }),
      link: inp(a.link_pago, { type: 'url', placeholder: 'https://mpago.la/…' }), wsp: inp(a.contacto_whatsapp, { type: 'tel', placeholder: '+56 9 …' }),
      prueba: inp(a.dias_prueba, { type: 'number' }), gracia: inp(a.dias_gracia, { type: 'number' }),
      tb: inp(t.banco), tt: inp(t.tipo), tn: inp(t.numero, { inputmode: 'numeric' }), tr: inp(t.rut), ttit: inp(t.titular), te: inp(t.email, { type: 'email' }),
      lc: inp(ln.clientes, { type: 'number' }), lm: inp(ln.movimientos, { type: 'number' }), lq: inp(ln.cuotas, { type: 'number' }), lp: inp(ln.productos, { type: 'number' }), lk: inp(ln.comprobantes, { type: 'number' }), lh: inp(ln.historial_meses, { type: 'number' }), lcaja: inp(ln.caja, { type: 'number' }), lcat: inp(ln.categorias, { type: 'number' }),
      vlegal: inp(a.version_legal, { type: 'number' }), vmin: inp(a.version_min),
    };
    const campo = (tx, i, ay) => el('div', { class: 'campo' }, el('label', null, tx), i, ay ? el('div', { class: 'ayuda' }, ay) : null);
    pintar(el('h2', null, 'Ajustes'),
      el('div', { class: 'dos-col' },
        el('div', null,
          el('div', { class: 'tarjeta' }, el('h2', null, 'Venta de Premium'), el('div', { class: 'grid2' }, campo('Activación (una vez)', f.activacion), campo('Mensualidad Pro', f.mensual)),
            el('p', { class: 'sutil' }, 'El primer pago es activación + mensualidad; después solo la mensualidad.'),
            campo('Link de pago (Mercado Pago u otro)', f.link), campo('Tu WhatsApp de soporte', f.wsp), el('div', { class: 'grid2' }, campo('Días de prueba', f.prueba), campo('Días de gracia', f.gracia))),
          el('div', { class: 'tarjeta' }, el('h2', null, 'Tus datos para transferencias de Premium'), campo('Banco', f.tb), campo('Tipo de cuenta', f.tt), campo('Número', f.tn), campo('RUT', f.tr), campo('Titular', f.ttit), campo('Correo', f.te))),
        el('div', null,
          el('div', { class: 'tarjeta' }, el('h2', null, 'Límites de la prueba gratis'),
            el('div', { class: 'grid2' }, campo('Clientes activos', f.lc), campo('Fiados y abonos/mes', f.lm), campo('Ingresos y gastos/mes', f.lcaja), campo('Cuotas activas', f.lq), campo('Productos', f.lp), campo('Comprobantes/mes', f.lk), campo('Categorías propias', f.lcat), campo('Historial (meses)', f.lh))),
          tarjetaVersiones(a),
          el('div', { class: 'tarjeta' }, el('h2', null, 'Avanzado'), campo('Versión de los textos legales', f.vlegal, 'Súbela si cambias los Términos: todos deberán aceptarlos de nuevo.'),
            campo('Versión mínima obligatoria', f.vmin, 'Quien tenga una versión menor ve un aviso rojo para actualizar. Úsalo solo si una versión vieja deja de funcionar.')),
          el('div', { class: 'tarjeta' }, el('h2', null, 'Notificaciones push'), el('p', null, cfg.vapid_public ? '✅ Claves push configuradas' : '⚠️ Falta generar las claves push'),
            el('button', { class: 'btn', type: 'button', onclick: generarVapid }, cfg.vapid_public ? 'Regenerar claves push' : 'Generar claves push'),
            el('button', { class: 'btn texto', type: 'button', onclick: probar }, 'Probar servidor')),
          el('div', { class: 'tarjeta' }, el('h2', null, 'Feriados'), el('p', { class: 'sutil' }, 'Vienen cargados 2026 y 2027. En feriados no se puede cobrar.'),
            el('button', { class: 'btn', type: 'button', onclick: feriados }, 'Ver y editar feriados')))),
      el('button', { class: 'btn primario ancho', type: 'button', onclick: async () => {
        try {
          const num = (i) => Math.round(Number(i.value));
          const datos = { precio_mensual: num(f.mensual), precio_activacion: num(f.activacion), link_pago: f.link.value.trim(), contacto_whatsapp: f.wsp.value.trim() ? V.telefono(f.wsp.value) : '',
            dias_prueba: num(f.prueba), dias_gracia: num(f.gracia),
            transferencia: { banco: f.tb.value.trim(), tipo: f.tt.value.trim(), numero: f.tn.value.replace(/\D/g, ''), rut: f.tr.value ? V.rutBonito(V.rut(f.tr.value)) : '', titular: f.ttit.value.trim(), email: f.te.value.trim() },
            lim_normal: { clientes: num(f.lc), movimientos: num(f.lm), cuotas: num(f.lq), productos: num(f.lp), comprobantes: num(f.lk), historial_meses: num(f.lh), caja: num(f.lcaja), categorias: num(f.lcat) },
            version_legal: num(f.vlegal), version_min: f.vmin.value.trim() };
          await conCarga(() => rpc('admin_guardar_ajustes', { p: datos })); toast('Ajustes guardados ✓');
        } catch (er) { error(er); }
      } }, 'Guardar ajustes'));
  }
  function tarjetaVersiones(a) {
    const estado = el('p', null, 'Revisando…'), btn = el('button', { class: 'btn primario', type: 'button', disabled: true }, 'Liberar actualización');
    const tuyo = el('div');
    let pub = '';
    fetch('../version.json', { cache: 'no-store' }).then((r) => r.json()).then((j) => {
      pub = String(j.version || '');
      vaciar(estado).append('Tu celular: ', el('strong', null, 'v' + LC.VERSION), ' · Publicada en GitHub: ', el('strong', null, 'v' + (pub || '?')),
        ' · Liberada para todos: ', el('strong', null, 'v' + a.version_liberada));
      btn.textContent = 'Liberar v' + pub + ' para todos';
      btn.disabled = !pub || !LC.versionMenor(a.version_liberada, pub);
      if (pub && !LC.versionMenor(a.version_liberada, pub)) btn.textContent = '✓ La última versión ya está liberada';
    }).catch(() => { estado.textContent = 'No se pudo leer la versión publicada.'; });
    LC.revisarVersion({ version_liberada: a.version_liberada }, (txt, fn) => { vaciar(tuyo); if (txt) tuyo.append(el('button', { class: 'btn primario ancho mt', type: 'button', onclick: fn }, '⬇️ Actualizar mi celular a la v' + a.version_liberada)); });
    tuyo.append(el('button', { class: 'btn texto ancho', type: 'button', onclick: async () => { if (await confirmar('Reparar la app', 'Vuelve a descargar la app en este celular. No borra datos.', 'Reparar')) LC.repararApp(); } }, '🛠️ Reparar la app en este celular'));
    btn.onclick = async () => {
      if (!await confirmar('Liberar actualización', '¿Liberar la v' + pub + '? A todos les aparecerá el botón "Actualizar" y la tendrán al tocarlo.', 'Liberar')) return;
      try {
        await conCarga(() => rpc('admin_guardar_ajustes', { p: { version_liberada: pub } }));
        toast('✅ v' + pub + ' liberada para todos. Actualizando tu celular…');
        if (LC.versionMenor(LC.VERSION, pub)) LC.actualizarAhora(); else vAjustes();
      } catch (e) { error(e); }
    };
    return el('div', { class: 'tarjeta' }, el('h2', null, 'Actualizaciones'),
      el('p', { class: 'sutil' }, 'Cuando se publique una versión nueva en GitHub, pruébala en tu celular y después libérala. Nadie recibe cambios hasta que tú los apruebas.'),
      estado, btn, tuyo);
  }
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
    pintar(el('div', { class: 'fila mb' }, el('a', { class: 'btn-icono', href: '#soporte', style: 'text-decoration:none', 'aria-label': 'Volver' }, '←'), titulo),
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
    const plan = el('select', null, el('option', { value: '0' }, 'Prueba gratis (según Ajustes)'), el('option', { value: '30' }, 'Pro 1 mes (ya pagó)'), el('option', { value: '90' }, 'Pro 3 meses'));
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
