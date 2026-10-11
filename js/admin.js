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
    window.addEventListener('hashchange', router);
    router();
  }
  function router() {
    const [v, a] = (location.hash.slice(1) || 'resumen').split('/');
    document.querySelectorAll('#nav a').forEach((x) => x.classList.toggle('activo', x.dataset.v === v));
    ({ resumen: vResumen, negocios: vNegocios, pagos: vPagos, ajustes: vAjustes, keys: vKeys, avisos: vAvisos }[v] || vResumen)(a).catch(error);
  }

  // ---------- Resumen ----------
  async function vResumen() {
    const r = await conCarga(() => rpc('admin_resumen'));
    $('#badgePagos').textContent = r.pagos_pendientes; $('#badgePagos').classList.toggle('oculto', !r.pagos_pendientes);
    const pct = Math.round(r.bd_mb * 100 / 500);
    pintar(el('h2', null, 'Resumen'),
      !r.cron_ok ? el('div', { class: 'banda error' }, '⚠️ Las tareas automáticas no están activas. Revisa que pg_cron y pg_net estén activados y vuelve a correr el SQL.') : null,
      !r.push_ok ? el('div', { class: 'banda aviso' }, '⚠️ Falta generar las claves push.', el('a', { class: 'btn chico', href: '#ajustes' }, 'Ir')) : null,
      r.pagos_pendientes ? el('a', { class: 'banda info', href: '#pagos', style: 'text-decoration:none' }, '💳 ' + r.pagos_pendientes + ' pago(s) por revisar', el('span', { class: 'btn chico' }, 'Revisar')) : null,
      el('div', { class: 'grid2 mb' }, kpi('Libretas', r.negocios), kpi('Activas 7 días', r.activos_7d, 'verde'), kpi('Premium pagando', r.premium, 'verde'), kpi('En prueba', r.en_prueba),
        kpi('Ingresos del mes', pesos(r.ingresos_mes), 'verde'), kpi('Suspendidas', r.suspendidos, r.suspendidos ? 'rojo' : ''), kpi('Clientes registrados', r.clientes_total), kpi('Movimientos del mes', r.movimientos_mes)),
      el('div', { class: 'tarjeta' }, el('h2', null, 'Capacidad del plan gratis de Supabase'),
        el('div', { class: 'fila entre' }, el('span', null, 'Base de datos'), el('strong', null, r.bd_mb + ' MB de 500 MB')),
        el('div', { class: 'barra ' + (pct >= 85 ? 'lleno' : pct >= 70 ? 'alerta' : '') }, el('i', { style: 'width:' + Math.min(pct, 100) + '%' })),
        el('div', { class: 'fila entre mt' }, el('span', null, 'Archivos (fotos)'), el('strong', null, r.archivos_mb + ' MB de 1.024 MB')),
        pct >= 70 ? el('p', { class: 'naranjo mt' }, 'Pasaste el 70%: es momento de pasar a Supabase Pro.') : null,
        el('p', { class: 'sutil mt' }, 'Avisos en cola: ' + r.cola_push)),
      el('div', { class: 'grid2' }, el('a', { class: 'btn', href: '#keys' }, '🔑 Keys'), el('a', { class: 'btn', href: '#avisos' }, '📣 Avisos a negocios')),
      el('button', { class: 'btn ancho mt', type: 'button', onclick: probar }, '🩺 Probar servidor de avisos'),
      el('button', { class: 'btn texto ancho mt', type: 'button', onclick: async () => { await sb.auth.signOut().catch(() => {}); location.replace('../#ingresar'); } }, '🚪 Cerrar sesión'));
  }
  async function probar() {
    try { const r = await conCarga(() => LC.funcion({ accion: 'ping' })); toast(r.ok ? '✅ Función "enviar" v' + r.version + (r.servicio ? '' : ' · falta clave de servicio') : '❌ ' + (r.error || 'Sin respuesta')); }
    catch (e) { toast('❌ ' + e.message, { error: true, ms: 9000 }); }
  }

  // ---------- Negocios ----------
  let filtro = 'todos', busca = '';
  async function vNegocios() {
    const lista = el('div', { class: 'lista' });
    const inp = el('input', { type: 'search', placeholder: '🔎 Nombre o correo', value: busca });
    let t;
    const cargar = async () => {
      const d = await rpc('admin_negocios', { p_buscar: busca, p_filtro: filtro });
      vaciar(lista);
      if (!d.length) lista.append(el('div', { class: 'vacio' }, 'Sin resultados.'));
      d.forEach((n) => lista.append(el('button', { class: 'item', type: 'button', onclick: () => fichaNegocio(n) },
        el('div', { class: 'avatar', style: 'background:' + LC.colorDe(n.nombre) }, LC.iniciales(n.nombre)),
        el('div', { class: 'crece' }, el('div', { class: 'nom' }, n.nombre), el('div', { class: 'sub' }, n.email + ' · ' + n.clientes + ' clientes · ' + (n.movimientos_mes || 0) + ' mov/mes')),
        el('span', { class: 'tag ' + (n.estado !== 'activo' ? 'rojo' : n.premium ? (n.en_prueba ? 'marca' : 'premium') : '') }, n.estado !== 'activo' ? n.estado : n.premium ? (n.en_prueba ? 'Prueba' : 'Premium') : 'Normal'))));
    };
    inp.oninput = () => { busca = inp.value; clearTimeout(t); t = setTimeout(() => cargar().catch(error), 300); };
    pintar(el('h2', null, 'Negocios'), inp,
      el('div', { class: 'chips mt' }, [['todos', 'Todos'], ['premium', 'Premium'], ['prueba', 'En prueba'], ['normal', 'Normal'], ['suspendido', 'Suspendidos'], ['eliminado', 'Por borrar']].map(([v, tx]) =>
        el('button', { class: 'chip' + (filtro === v ? ' activo' : ''), type: 'button', onclick: () => { filtro = v; vNegocios(); } }, tx))),
      lista);
    await cargar();
  }
  async function fichaNegocio(n) {
    const r = await dialogo(n.nombre, el('div', null,
      el('p', null, n.email, n.whatsapp ? ' · ' + n.whatsapp : ''),
      el('p', { class: 'sutil' }, 'Rubro: ' + n.rubro + ' · Desde ' + fechaCorta(n.creado) + ' · Último uso: ' + (n.ultimo_uso ? fechaHora(n.ultimo_uso) : '—')),
      el('p', null, 'Plan: ', el('strong', null, n.premium ? (n.en_prueba ? 'Prueba Premium' : 'Premium') : 'Normal'), n.premium_hasta ? ' · hasta ' + fechaLarga(n.premium_hasta) : ''),
      n.estado === 'suspendido' ? el('p', { class: 'rojo' }, 'Suspendido: ' + (n.motivo_suspension || '')) : null,
      n.nota_admin ? el('p', { class: 'sutil' }, '📝 ' + n.nota_admin) : null,
      el('div', { class: 'col' },
        el('button', { class: 'btn primario', type: 'button', onclick: () => cerrarCon('dias') }, '⭐ Sumar días de Premium'),
        n.premium ? el('button', { class: 'btn', type: 'button', onclick: () => cerrarCon('quitar') }, 'Quitar Premium') : null,
        el('button', { class: 'btn', type: 'button', onclick: () => cerrarCon('nota') }, '📝 Nota interna'),
        el('button', { class: 'btn', type: 'button', onclick: () => cerrarCon('aviso') }, '📣 Enviar aviso'),
        n.whatsapp ? el('button', { class: 'btn wsp', type: 'button', onclick: () => abrir(wa(n.whatsapp, 'Hola ' + n.nombre + ', te escribo de Libreta de Cobros.')) }, '💬 WhatsApp') : null,
        n.estado === 'activo' ? el('button', { class: 'btn peligro', type: 'button', onclick: () => cerrarCon('suspender') }, '⛔ Suspender')
          : n.estado === 'suspendido' ? el('button', { class: 'btn', type: 'button', onclick: () => cerrarCon('reactivar') }, '✅ Reactivar') : null)));
    function cerrarCon(v) { document.querySelector('.velo').remove(); accion(v); }
    async function accion(v) {
      try {
        if (v === 'dias') {
          const d = await pedirTexto('Sumar Premium', 'Días', { valor: '30', inputmode: 'numeric', tipo: 'number', validar: (x) => Number(x) >= 1 && Number(x) <= 3660 ? null : 'Entre 1 y 3660' });
          if (d) { await conCarga(() => rpc('admin_plan', { p_negocio: n.id, p_accion: 'sumar', p_dias: Number(d) })); toast('Premium sumado ✓'); }
        } else if (v === 'quitar') {
          if (await confirmar('Quitar Premium', '¿Pasar ' + n.nombre + ' a Normal ahora?', 'Quitar', 'rojo')) { await conCarga(() => rpc('admin_plan', { p_negocio: n.id, p_accion: 'quitar', p_dias: null })); toast('Listo'); }
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
        el('div', null, (s.meses === 12 ? 'Anual' : 'Mensual') + ' · ' + pesos(s.monto) + ' · ' + fechaHora(s.creado)),
        s.nota ? el('p', { class: 'sutil' }, '“' + s.nota + '”') : null, s.motivo ? el('p', { class: 'rojo' }, s.motivo) : null, foto,
        s.estado === 'pendiente' ? el('div', { class: 'grid2 mt' },
          el('button', { class: 'btn peligro', type: 'button', onclick: async () => { const m = await pedirTexto('Rechazar pago', 'Motivo (lo verá el negocio)', { min: 3, max: 150, boton: 'Rechazar', clase: 'rojo' }); if (m) { try { await conCarga(() => rpc('admin_resolver_pago', { p_id: s.id, p_aprobar: false, p_motivo: m })); vPagos(); } catch (e) { error(e); } } } }, 'Rechazar'),
          el('button', { class: 'btn verde', type: 'button', onclick: async () => { if (await confirmar('Aprobar pago', 'Revisa que el dinero haya llegado. ¿Aprobar ' + (s.meses === 12 ? '1 año' : '1 mes') + ' de Premium?', 'Aprobar')) { try { await conCarga(() => rpc('admin_resolver_pago', { p_id: s.id, p_aprobar: true, p_motivo: null })); toast('Aprobado ✓'); vPagos(); } catch (e) { error(e); } } } }, 'Aprobar')) : null));
    }
    pintar(el('h2', null, 'Pagos'), lista);
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
      mensual: inp(a.precio_mensual, { type: 'number', inputmode: 'numeric' }), anual: inp(a.precio_anual, { type: 'number', inputmode: 'numeric' }),
      link: inp(a.link_pago, { type: 'url', placeholder: 'https://mpago.la/…' }), wsp: inp(a.contacto_whatsapp, { type: 'tel', placeholder: '+56 9 …' }),
      prueba: inp(a.dias_prueba, { type: 'number' }), gracia: inp(a.dias_gracia, { type: 'number' }),
      tb: inp(t.banco), tt: inp(t.tipo), tn: inp(t.numero, { inputmode: 'numeric' }), tr: inp(t.rut), ttit: inp(t.titular), te: inp(t.email, { type: 'email' }),
      lc: inp(ln.clientes, { type: 'number' }), lm: inp(ln.movimientos, { type: 'number' }), lq: inp(ln.cuotas, { type: 'number' }), lp: inp(ln.productos, { type: 'number' }), lk: inp(ln.comprobantes, { type: 'number' }), lh: inp(ln.historial_meses, { type: 'number' }),
      vlegal: inp(a.version_legal, { type: 'number' }), vmin: inp(a.version_min),
    };
    const campo = (tx, i, ay) => el('div', { class: 'campo' }, el('label', null, tx), i, ay ? el('div', { class: 'ayuda' }, ay) : null);
    pintar(el('h2', null, 'Ajustes'),
      el('div', { class: 'dos-col' },
        el('div', null,
          el('div', { class: 'tarjeta' }, el('h2', null, 'Venta de Premium'), campo('Precio mensual de Premium', f.mensual, 'Premium se paga solo mes a mes.'),
            campo('Link de pago (Mercado Pago u otro)', f.link), campo('Tu WhatsApp de soporte', f.wsp), el('div', { class: 'grid2' }, campo('Días de prueba', f.prueba), campo('Días de gracia', f.gracia))),
          el('div', { class: 'tarjeta' }, el('h2', null, 'Tus datos para transferencias de Premium'), campo('Banco', f.tb), campo('Tipo de cuenta', f.tt), campo('Número', f.tn), campo('RUT', f.tr), campo('Titular', f.ttit), campo('Correo', f.te))),
        el('div', null,
          el('div', { class: 'tarjeta' }, el('h2', null, 'Límites del plan Normal'),
            el('div', { class: 'grid2' }, campo('Clientes activos', f.lc), campo('Movimientos/mes', f.lm), campo('Cuotas activas', f.lq), campo('Productos', f.lp), campo('Comprobantes/mes', f.lk), campo('Historial (meses)', f.lh))),
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
          const datos = { precio_mensual: num(f.mensual), link_pago: f.link.value.trim(), contacto_whatsapp: f.wsp.value.trim() ? V.telefono(f.wsp.value) : '',
            dias_prueba: num(f.prueba), dias_gracia: num(f.gracia),
            transferencia: { banco: f.tb.value.trim(), tipo: f.tt.value.trim(), numero: f.tn.value.replace(/\D/g, ''), rut: f.tr.value ? V.rutBonito(V.rut(f.tr.value)) : '', titular: f.ttit.value.trim(), email: f.te.value.trim() },
            lim_normal: { clientes: num(f.lc), movimientos: num(f.lm), cuotas: num(f.lq), productos: num(f.lp), comprobantes: num(f.lk), historial_meses: num(f.lh) },
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
    LC.revisarVersion({ version_liberada: a.version_liberada }, (txt, fn) => { vaciar(tuyo); if (txt) tuyo.append(el('button', { class: 'btn ancho mt', type: 'button', onclick: fn }, 'Actualizar mi celular a la versión liberada')); });
    btn.onclick = async () => {
      if (!await confirmar('Liberar actualización', '¿Liberar la v' + pub + '? A todos les aparecerá el botón "Actualizar" y la tendrán al tocarlo.', 'Liberar')) return;
      try { await conCarga(() => rpc('admin_guardar_ajustes', { p: { version_liberada: pub } })); toast('✅ v' + pub + ' liberada para todos'); vAjustes(); } catch (e) { error(e); }
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

  arrancar().catch(error);
})();
