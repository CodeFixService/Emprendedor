/* App del negocio: inicio, clientes, anotar, cuotas, cobrar, comprobantes, reportes, ajustes, plan, ayudantes. */
(function () {
  'use strict';
  const { el, $, vaciar, rpc, sb, V, error, toast, conCarga, dialogo, confirmar, pedirTexto, pesos, fechaCorta, fechaLarga, fechaHora,
    hora, hoyISO, sumarDias, relativo, iniciales, colorDe, norm, local, RAIZ, copiar, wa, abrir, uuid } = LC;

  const S = { st: null, neg: null, uid: null, email: '', clientes: [], productos: [], cargado: false, vista: '' };
  const esDueno = () => S.st && S.st.rol === 'dueno';
  const prem = () => !!(S.st && S.st.plan.premium);
  const vista = $('#vista');
  $('#ver').textContent = LC.VERSION;

  // ================= Arranque =================
  async function arrancar() {
    const { data } = await sb.auth.getSession();
    if (!data.session) { location.replace('../#ingresar'); return; }
    S.uid = data.session.user.id; S.email = data.session.user.email;
    await bloqueoLocal();
    LC.registrarSW((activar) => banda('actualizar', 'info', '✨ Hay una versión nueva de la app.', 'Actualizar', activar));
    LC.alPlan = alPlan;
    LC.alSesion = () => { toast('Tu sesión terminó. Ingresa de nuevo.', { error: true }); setTimeout(() => location.replace('../#ingresar'), 1200); };
    S.clientes = local.get('lc-clientes-' + S.uid, []);
    S.st = local.get('lc-estado-' + S.uid, null);
    if (S.st) aplicarEstado();
    try { await refrescarEstado(); } catch (e) { if (!S.st) { error(e); return; } }
    if (!S.st.negocio) { location.replace('../#app'); return; }
    if (!S.st.terminos_ok) await pedirTerminos();
    window.addEventListener('online', () => { red(); sincronizar(); });
    window.addEventListener('offline', red);
    red();
    await Promise.all([cargarClientes().catch(() => {}), cargarProductos().catch(() => {})]);
    tiempoReal();
    sincronizar();
    window.addEventListener('hashchange', router);
    router();
    const msg = local.get('lc-msg', null); if (msg) { local.del('lc-msg'); toast(msg, { ms: 5000 }); }
    document.addEventListener('visibilitychange', () => { if (!document.hidden) { refrescarEstado().catch(() => {}); cargarClientes().then(refrescarVista).catch(() => {}); } });
  }

  async function refrescarEstado() {
    S.st = await rpc('mi_estado');
    local.set('lc-estado-' + S.uid, S.st);
    aplicarEstado();
  }

  function aplicarEstado() {
    const st = S.st; if (!st || !st.negocio) return;
    S.neg = st.negocio;
    $('#titulo').textContent = S.neg.nombre;
    const logo = vaciar($('#logoNeg'));
    if (prem() && S.neg.logo_url) logo.append(el('img', { src: S.neg.logo_url, alt: '' })); else logo.append(iniciales(S.neg.nombre));
    if (prem() && S.neg.color) { document.documentElement.style.setProperty('--marca', S.neg.color); document.documentElement.style.setProperty('--marca-2', S.neg.color); }
    else { document.documentElement.style.removeProperty('--marca'); document.documentElement.style.removeProperty('--marca-2'); }
    const p = st.pendientes || {};
    const nAv = p.avisos || 0; $('#badgeAvisos').textContent = nAv > 9 ? '9+' : nAv; $('#badgeAvisos').classList.toggle('oculto', !nAv);
    const nMas = (p.comprobantes || 0) + (esDueno() ? p.reclamos || 0 : 0); $('#badgeMas').textContent = nMas; $('#badgeMas').classList.toggle('oculto', !nMas);
    // Bandas de estado
    const pl = st.plan;
    banda('suspendido', 'error', S.neg.estado === 'suspendido' ? '⛔ Cuenta suspendida' + (S.neg.motivo_suspension ? ': ' + S.neg.motivo_suspension : '') + '. Puedes exportar tus datos en Más → Ajustes.' : null);
    const dias = pl.hasta ? Math.ceil((new Date(pl.hasta) - Date.now()) / 86400000) : null;
    banda('prueba', 'info', pl.en_prueba && dias != null ? '🎁 Premium de prueba: te quedan ' + Math.max(dias, 0) + ' días.' : null, 'Ver planes', () => { location.hash = 'plan'; });
    banda('gracia', 'error', pl.en_gracia ? '⚠️ Tu Premium venció. Renueva antes de ' + (pl.dias_gracia) + ' días para no pasar a Normal.' : null, 'Renovar', () => { location.hash = 'plan'; });
    banda('fuera', 'aviso', st.uso && st.uso.fuera_de_plan ? '🔒 ' + st.uso.fuera_de_plan + ' clientes quedaron en "solo cobro" por el plan Normal.' : null, 'Ver', () => { location.hash = 'clientes/fuera'; });
    const minV = st.config && st.config.version_min;
    banda('vieja', 'error', minV && LC.versionMenor(LC.VERSION, minV) ? 'Esta versión de la app es antigua. Actualízala para seguir.' : null, 'Actualizar', () => location.reload());
  }

  function banda(id, tipo, texto, boton, fn) {
    let b = $('#banda-' + id);
    if (!texto) { if (b) b.remove(); return; }
    const nueva = el('div', { class: 'banda ' + tipo, id: 'banda-' + id }, el('span', null, texto), boton ? el('button', { class: 'btn chico', type: 'button', onclick: fn }, boton) : null);
    if (b) b.replaceWith(nueva); else $('#bandas').append(nueva);
  }

  function red() {
    const off = !navigator.onLine;
    $('#estadoRed').classList.toggle('oculto', !off);
    const n = cola().length;
    banda('cola', 'aviso', n ? '⏳ ' + n + ' movimiento' + (n > 1 ? 's' : '') + ' por subir' + (off ? ' (sin internet)' : '') : null, off ? null : 'Subir ahora', sincronizar);
  }

  async function pedirTerminos() {
    const chk = el('input', { type: 'checkbox', id: 'terms' });
    await dialogo('Términos actualizados', el('div', null,
      el('p', null, 'Actualizamos los Términos y la Política de privacidad. Revísalos para seguir usando la app.'),
      el('p', null, el('a', { href: '../legal/#terminos', target: '_blank' }, 'Ver Términos'), ' · ', el('a', { href: '../legal/#privacidad', target: '_blank' }, 'Ver Privacidad')),
      el('label', { class: 'check', for: 'terms' }, chk, 'Acepto los Términos y la Política de privacidad')),
    [{ texto: 'Aceptar', clase: 'primario', valor: true, antes: async () => {
      if (!chk.checked) { toast('Marca la casilla para aceptar', { error: true }); return false; }
      await rpc('aceptar_terminos'); return true;
    } }], { fijo: true });
  }

  async function bloqueoLocal() {
    const h = local.get('lc-bloqueo-' + S.uid, null);
    if (!h) return;
    let pin = '';
    const puntos = el('div', { class: 'pin' }, [0, 1, 2, 3].map(() => el('span')));
    const msg = el('p', { class: 'centro sutil' }, 'Ingresa tu PIN para abrir la libreta');
    return new Promise((ok) => {
      const pintar = () => [...puntos.children].forEach((s, i) => s.classList.toggle('lleno', i < pin.length));
      const tecla = async (k) => {
        if (k === '⌫') pin = pin.slice(0, -1); else if (pin.length < 4) pin += k;
        pintar();
        if (pin.length === 4) {
          if (await sha(pin) === h) { velo.remove(); ok(); } else { msg.textContent = 'PIN incorrecto'; pin = ''; setTimeout(pintar, 150); }
        }
      };
      const velo = el('div', { class: 'velo', style: 'align-items:center' }, el('div', { class: 'dialogo', style: 'max-width:340px' },
        el('h2', { class: 'centro' }, '🔒 Libreta bloqueada'), msg, puntos,
        el('div', { class: 'teclado' }, ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '⌫'].map((k) => k ? el('button', { type: 'button', onclick: () => tecla(k) }, k) : el('span'))),
        el('button', { class: 'btn texto ancho mt', type: 'button', onclick: async () => { local.del('lc-bloqueo-' + S.uid); await sb.auth.signOut(); location.replace('../#ingresar'); } }, 'Olvidé mi PIN (cerrar sesión)')));
      document.body.append(velo);
    });
  }
  async function sha(t) { const b = await crypto.subtle.digest('SHA-256', new TextEncoder().encode('lc:' + S.uid + ':' + t)); return [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, '0')).join(''); }

  // ================= Datos =================
  const COLS_CLI = 'id,nombre,apodo,telefono,rut,nota,limite,estado,bloqueado,fuera_de_plan,saldo,prox_venc,atrasado,puntaje,ultimo_mov,link_codigo,link_bloqueado,creado';
  async function cargarClientes() {
    const { data, error: e } = await sb.from('clientes').select(COLS_CLI).neq('estado', 'borrado').order('nombre').limit(5000);
    if (e) throw LC.traducir(e);
    S.clientes = data; S.cargado = true;
    local.set('lc-clientes-' + S.uid, data);
  }
  async function cargarProductos() {
    const { data } = await sb.from('productos').select('id,nombre,precio,orden').order('orden');
    S.productos = data || [];
  }
  const cliente = (id) => S.clientes.find((c) => c.id === id);
  let refrescoPendiente = null;
  function refrescarVista() { clearTimeout(refrescoPendiente); refrescoPendiente = setTimeout(() => { if (!document.querySelector('.velo')) router(true); }, 400); }

  function tiempoReal() {
    const id = S.neg.id;
    sb.channel('lc-' + id)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'movimientos', filter: 'negocio=eq.' + id }, () => { cargarClientes().then(refrescarVista).catch(() => {}); })
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'notificaciones', filter: 'negocio=eq.' + id }, (p) => {
        toast('🔔 ' + p.new.titulo); refrescarEstado().catch(() => {}); refrescarVista();
      })
      .subscribe();
  }

  // ================= Cola sin internet =================
  const cola = () => local.get('lc-cola-' + S.uid, []);
  const guardarCola = (c) => { local.set('lc-cola-' + S.uid, c); red(); };
  let sincronizando = false;
  async function sincronizar() {
    if (sincronizando || !navigator.onLine) return;
    const c = cola(); if (!c.length) return;
    sincronizando = true;
    let subidos = 0;
    try {
      for (const m of c) {
        if (m.error) continue;
        try {
          const r = await rpc('registrar_movimiento', { p_id: m.id, p_cliente: m.cliente, p_tipo: m.tipo, p_monto: m.monto, p_descripcion: m.descripcion,
            p_medio: m.medio, p_fecha: m.fecha, p_vence: m.vence, p_signo: null, p_forzar_limite: !!m.forzar, p_confirmar_dup: true });
          if (r.ok) { guardarCola(cola().filter((x) => x.id !== m.id)); subidos++; }
          else if (r.limite) guardarCola(cola().map((x) => x.id === m.id ? { ...x, error: 'Supera el límite de fiado (' + pesos(r.limite) + ')', limite: true } : x));
        } catch (e) {
          if (e.pista === 'RED') break;
          guardarCola(cola().map((x) => x.id === m.id ? { ...x, error: e.message } : x));
        }
      }
    } finally { sincronizando = false; }
    if (subidos) { toast('✓ Se subieron ' + subidos + ' movimientos'); await cargarClientes().catch(() => {}); refrescarVista(); }
    red();
    if (cola().some((x) => x.error)) banda('colaerr', 'error', 'Hay movimientos que no se pudieron subir.', 'Revisar', () => { location.hash = 'pendientes'; });
    else banda('colaerr');
  }

  // ================= Router =================
  function router(silencioso) {
    const h = location.hash.slice(1) || 'inicio';
    const [v, a, b] = h.split('/');
    S.vista = v;
    document.querySelectorAll('#nav a').forEach((x) => x.classList.toggle('activo', x.dataset.v === v || (v === 'cliente' && x.dataset.v === 'clientes') ||
      (['comprobantes', 'reportes', 'productos', 'ayudantes', 'ajustes', 'plan', 'cuenta', 'ayuda', 'pendientes'].includes(v) && x.dataset.v === 'mas')));
    const vistas = { inicio: vInicio, clientes: vClientes, cliente: vCliente, anotar: vAnotar, mas: vMas, comprobantes: vComprobantes, reportes: vReportes,
      productos: vProductos, ayudantes: vAyudantes, ajustes: vAjustes, plan: vPlan, avisos: vAvisos, cuenta: vCuenta, ayuda: vAyuda, pendientes: vPendientes };
    const fn = vistas[v] || vInicio;
    if (!silencioso) window.scrollTo(0, 0);
    Promise.resolve(fn(a, b)).catch(error);
  }
  function pintar(...nodos) { vaciar(vista).append(...nodos.flat().filter((x) => x != null && x !== false)); }
  const soloDueno = () => { if (!esDueno()) { pintar(el('div', { class: 'vacio' }, el('span', { class: 'ico' }, '🔒'), 'Solo el dueño de la libreta puede ver esto.')); return true; } return false; };

  // ================= Plan: aviso de límite =================
  function alPlan(msg) {
    dialogo('Límite del plan Normal', el('div', null, el('p', null, msg),
      el('div', { class: 'tarjeta plana' }, el('strong', null, '⭐ Con Premium'), el('ul', { class: 'sutil' },
        el('li', null, 'Clientes, movimientos y cuotas ilimitados'), el('li', null, 'Avisos automáticos a tus clientes'),
        el('li', null, 'Puntaje de buen pagador, reportes y PDF'), el('li', null, 'Ayudantes, tu logo y tus colores')),
        el('p', { class: 'mt' }, el('strong', null, pesos(S.st.config.precio_mensual) + ' al mes'), ' · o ' + pesos(S.st.config.precio_anual) + ' al año'))),
    [{ texto: 'Ahora no', valor: null }, { texto: 'Hazte Premium', clase: 'primario', valor: 1 }]).then((v) => { if (v) location.hash = 'plan'; });
  }

  // ================= INICIO =================
  async function vInicio() {
    if (!S.cargado) pintar(el('div', { class: 'vacio' }, el('div', { class: 'spinner', style: 'margin:30px auto' })));
    let t;
    try { t = await rpc('tablero'); local.set('lc-tablero-' + S.uid, t); } catch (e) { t = local.get('lc-tablero-' + S.uid, null); if (!t) throw e; }
    const dif = t.recuperado_mes - t.recuperado_mes_pasado;
    const nodos = [];
    if (local.get('lc-bienvenida', false) || (!S.clientes.length && esDueno())) nodos.push(bienvenida());
    nodos.push(
      el('div', { class: 'kpi hero mb' }, el('div', { class: 't' }, 'Te deben en total'), el('div', { class: 'grande' }, pesos(t.por_cobrar)),
        el('div', { class: 't' }, t.deudores + ' cliente' + (t.deudores === 1 ? '' : 's') + ' con deuda')),
      el('div', { class: 'grid3 mb' },
        el('a', { class: 'kpi', href: '#clientes/vence', style: 'text-decoration:none;color:inherit' }, el('div', { class: 't' }, 'Vence hoy'), el('div', { class: 'v naranjo' }, pesos(t.vence_hoy.monto)), el('div', { class: 't' }, t.vence_hoy.n + ' clientes')),
        el('a', { class: 'kpi', href: '#clientes/atrasados', style: 'text-decoration:none;color:inherit' }, el('div', { class: 't' }, 'Atrasados'), el('div', { class: 'v rojo' }, pesos(t.atrasados.monto)), el('div', { class: 't' }, t.atrasados.n + ' clientes')),
        el('div', { class: 'kpi' }, el('div', { class: 't' }, 'Recuperado este mes'), el('div', { class: 'v verde' }, pesos(t.recuperado_mes)),
          el('div', { class: 't' }, t.recuperado_mes_pasado || dif ? (dif >= 0 ? '▲ ' : '▼ ') + pesos(Math.abs(dif)) + ' vs mes pasado' : 'Este mes'))));
    const p = S.st.pendientes || {};
    if (p.comprobantes) nodos.push(el('a', { class: 'banda info', href: '#comprobantes', style: 'text-decoration:none' }, '🧾 ' + p.comprobantes + ' comprobante' + (p.comprobantes > 1 ? 's' : '') + ' por revisar', el('span', { class: 'btn chico' }, 'Revisar')));
    if (p.reclamos && esDueno()) nodos.push(el('a', { class: 'banda error', href: '#clientes/reclamos', style: 'text-decoration:none' }, '⚠️ ' + p.reclamos + ' cargo' + (p.reclamos > 1 ? 's' : '') + ' reclamado' + (p.reclamos > 1 ? 's' : ''), el('span', { class: 'btn chico' }, 'Ver')));
    nodos.push(el('h2', { class: 'mt' }, 'Para cobrar hoy'));
    if (!t.cobrar_hoy.length) nodos.push(el('div', { class: 'lista' }, el('div', { class: 'vacio' }, el('span', { class: 'ico' }, '🎉'), 'Nadie vence hoy ni está atrasado.')));
    else nodos.push(el('div', { class: 'lista' }, t.cobrar_hoy.map((c) => el('div', { class: 'item' },
      avatar(c.nombre), el('a', { class: 'crece', href: '#cliente/' + c.id, style: 'color:inherit;text-decoration:none' }, el('div', { class: 'nom' }, c.nombre),
        el('div', { class: 'sub ' + (c.atrasado ? 'rojo' : 'naranjo') }, c.atrasado ? 'Atrasado desde ' + fechaCorta(c.prox_venc) : 'Vence hoy')),
      el('div', { class: 'monto rojo' }, pesos(c.saldo)),
      el('button', { class: 'btn-icono', type: 'button', 'aria-label': 'Cobrar', onclick: () => cobrar(c.id) }, '💬')))));
    pintar(...nodos);
  }

  function bienvenida() {
    const b = S.neg.banco || {};
    const pasos = [
      ['Tu WhatsApp', !!S.neg.whatsapp, '#ajustes'], ['Datos para que te transfieran', !!(b.numero && b.rut), '#ajustes'],
      ['Tu primer cliente', S.clientes.length > 0, '#clientes/nuevo'],
    ];
    const listos = pasos.filter((x) => x[1]).length;
    if (listos === pasos.length) local.del('lc-bienvenida');
    return el('div', { class: 'tarjeta' }, el('div', { class: 'fila entre' }, el('h2', null, '👋 Empecemos'), el('span', { class: 'tag marca' }, listos + '/' + pasos.length)),
      el('div', { class: 'col' }, pasos.map(([t, ok, h]) => el('a', { class: 'fila', href: h, style: 'color:inherit;text-decoration:none' }, el('span', null, ok ? '✅' : '⬜'), el('span', { class: 'crece' }, t), ok ? null : el('span', { class: 'sutil' }, '→')))),
      esDueno() ? el('button', { class: 'btn ancho mt', type: 'button', onclick: pasarCuaderno }, '📒 Pasar mi cuaderno (varios clientes de una vez)') : null,
      el('button', { class: 'btn texto ancho', type: 'button', onclick: () => { local.del('lc-bienvenida'); router(); } }, 'Ocultar'));
  }

  const avatar = (n) => el('div', { class: 'avatar', style: 'background:' + colorDe(n) }, iniciales(n));

  // ================= CLIENTES =================
  const FILTROS = [['todos', 'Todos'], ['deben', 'Deben'], ['atrasados', 'Atrasados'], ['vence', 'Vencen pronto'], ['aldia', 'Al día'], ['solocobro', 'Solo cobro'], ['fuera', 'Fuera del plan'], ['reclamos', 'Con reclamo'], ['archivados', 'Archivados']];
  let filtroCli = 'todos', ordenCli = 'deuda', buscaCli = '';
  async function vClientes(arg) {
    if (arg === 'nuevo') { history.replaceState(null, '', '#clientes'); setTimeout(() => formCliente(), 50); }
    else if (arg && FILTROS.some((f) => f[0] === arg)) filtroCli = arg;
    let reclamados = new Set();
    if (filtroCli === 'reclamos') {
      const { data } = await sb.from('movimientos').select('cliente').eq('confirmacion', 'reclamado').is('respuesta', null).is('anulado_at', null);
      reclamados = new Set((data || []).map((x) => x.cliente));
    }
    const lim = S.st.limites.clientes;
    const activos = S.clientes.filter((c) => c.estado === 'activo' && !c.fuera_de_plan).length;
    const busc = el('input', { type: 'search', placeholder: '🔎 Buscar por nombre, apodo o teléfono', value: buscaCli, 'aria-label': 'Buscar' });
    const lista = el('div', { class: 'lista' });
    const orden = el('select', { 'aria-label': 'Ordenar', style: 'width:auto;min-height:38px' },
      [['deuda', 'Mayor deuda'], ['atraso', 'Más atrasado'], ['nombre', 'Nombre'], ['reciente', 'Último movimiento']].map(([v, t]) => el('option', { value: v, selected: v === ordenCli }, t)));
    const hoy = hoyISO(), en3 = sumarDias(hoy, 3);
    const pasa = (c) => {
      switch (filtroCli) {
        case 'deben': return c.saldo > 0 && c.estado !== 'archivado';
        case 'atrasados': return c.saldo > 0 && c.atrasado;
        case 'vence': return c.saldo > 0 && c.prox_venc && c.prox_venc >= hoy && c.prox_venc <= en3;
        case 'aldia': return c.saldo <= 0 && c.estado === 'activo';
        case 'solocobro': return c.bloqueado || c.fuera_de_plan;
        case 'fuera': return c.fuera_de_plan;
        case 'reclamos': return reclamados.has(c.id);
        case 'archivados': return c.estado === 'archivado';
        default: return c.estado !== 'archivado';
      }
    };
    const pintarLista = () => {
      const q = norm(buscaCli), qd = buscaCli.replace(/\D/g, '');
      let l = S.clientes.filter(pasa).filter((c) => !q || norm(c.nombre).includes(q) || norm(c.apodo).includes(q) || (qd.length >= 3 && (c.telefono || '').includes(qd)));
      const cmp = { deuda: (a, b) => b.saldo - a.saldo, atraso: (a, b) => (a.prox_venc || '9') < (b.prox_venc || '9') ? -1 : 1, nombre: (a, b) => a.nombre.localeCompare(b.nombre), reciente: (a, b) => (b.ultimo_mov || '') > (a.ultimo_mov || '') ? 1 : -1 }[ordenCli];
      l = l.sort(cmp);
      vaciar(lista);
      if (!l.length) lista.append(el('div', { class: 'vacio' }, el('span', { class: 'ico' }, '👥'), S.clientes.length ? 'No hay clientes con este filtro.' : 'Aún no tienes clientes. Toca ＋ para agregar el primero.'));
      for (const c of l.slice(0, 300)) lista.append(filaCliente(c));
      if (l.length > 300) lista.append(el('div', { class: 'vacio' }, 'Mostrando 300 de ' + l.length + '. Usa el buscador.'));
    };
    busc.oninput = () => { buscaCli = busc.value; pintarLista(); };
    orden.onchange = () => { ordenCli = orden.value; pintarLista(); };
    pintar(
      el('div', { class: 'fila entre mb' }, el('h2', { style: 'margin:0' }, 'Clientes'),
        lim ? el('span', { class: 'tag ' + (activos >= lim ? 'rojo' : activos >= lim * 0.8 ? 'naranjo' : '') }, activos + ' de ' + lim + ' (Normal)') : el('span', { class: 'tag premium' }, 'Ilimitados')),
      busc,
      el('div', { class: 'chips mt' }, FILTROS.filter((f) => f[0] !== 'fuera' || S.st.uso.fuera_de_plan).map(([v, t]) => el('button', { class: 'chip' + (filtroCli === v ? ' activo' : ''), type: 'button', onclick: () => { filtroCli = v; vClientes(); } }, t))),
      el('div', { class: 'fila entre mb' }, el('span', { class: 'sutil' }, 'Ordenar por'), orden),
      lista,
      el('button', { class: 'fab', type: 'button', 'aria-label': 'Nuevo cliente', onclick: () => formCliente() }, '＋'));
    pintarLista();
  }

  function filaCliente(c) {
    const hoy = hoyISO();
    let sub = c.apodo ? c.apodo + ' · ' : '';
    if (c.estado === 'archivado') sub += 'Archivado';
    else if (c.fuera_de_plan) sub += '🔒 Fuera del plan (solo cobro)';
    else if (c.bloqueado) sub += '🚫 Solo cobro';
    else if (c.saldo > 0 && c.atrasado) sub += 'Atrasado desde ' + fechaCorta(c.prox_venc);
    else if (c.saldo > 0 && c.prox_venc) sub += 'Vence ' + (c.prox_venc === hoy ? 'hoy' : fechaCorta(c.prox_venc));
    else if (c.saldo < 0) sub += 'Saldo a favor';
    else sub += 'Al día';
    return el('a', { class: 'item', href: '#cliente/' + c.id },
      avatar(c.nombre),
      el('div', { class: 'crece' }, el('div', { class: 'nom' }, c.nombre, prem() && c.puntaje !== 'nuevo' ? ' ' : '', prem() ? puntajeTag(c.puntaje, true) : null),
        el('div', { class: 'sub ' + (c.saldo > 0 && c.atrasado ? 'rojo' : '') }, sub)),
      el('div', { class: 'monto ' + (c.saldo > 0 ? 'rojo' : 'verde') }, c.saldo > 0 ? pesos(c.saldo) : c.saldo < 0 ? '+' + pesos(-c.saldo) : '✓'));
  }
  function puntajeTag(p, mini) {
    const m = { bueno: ['verde', '👍 Buen pagador'], regular: ['naranjo', '⚠️ Regular'], riesgoso: ['rojo', '🚩 Riesgoso'], nuevo: ['', '🆕 Nuevo'] }[p] || ['', p];
    if (mini && p === 'nuevo') return null;
    return el('span', { class: 'tag ' + m[0] }, mini ? m[1].split(' ')[0] : m[1]);
  }

  // ---------- Formulario de cliente ----------
  async function formCliente(c) {
    const nuevo = !c;
    const f = {
      nombre: el('input', { maxlength: 60, autocomplete: 'off' }), apodo: el('input', { maxlength: 30, placeholder: 'Ej: la vecina del 5' }),
      telefono: el('input', { type: 'tel', inputmode: 'tel', placeholder: '+56 9 1234 5678' }), rut: el('input', { placeholder: '12.345.678-5' }),
      nota: el('textarea', { maxlength: 200, placeholder: 'Solo la ves tú (el cliente no la ve)' }), limite: el('input', { type: 'number', inputmode: 'numeric', min: 0, max: 5000000 }),
      pin: el('input', { inputmode: 'numeric', maxlength: 4, placeholder: 'Últimos 4 del teléfono' }), saldo: el('input', { type: 'number', inputmode: 'numeric', min: 0, placeholder: '0' }),
      autoriza: el('input', { type: 'checkbox', id: 'autoriza', checked: local.get('lc-autoriza', false) }),
    };
    if (c) { f.nombre.value = c.nombre; f.apodo.value = c.apodo || ''; f.telefono.value = V.telBonito(c.telefono); f.rut.value = c.rut ? V.rutBonito(c.rut) : ''; f.nota.value = c.nota || ''; f.limite.value = c.limite || ''; }
    const err = el('div', { class: 'error' });
    const campo = (t, i, a) => el('div', { class: 'campo' }, el('label', null, t), i, a ? el('div', { class: 'ayuda' }, a) : null);
    const cont = el('div', null,
      campo('Nombre *', f.nombre), campo('Apodo o referencia', f.apodo), campo('Teléfono (WhatsApp)', f.telefono, 'Necesario para cobrarle y enviarle su link.'),
      el('details', null, el('summary', { class: 'sutil', style: 'margin-bottom:10px;cursor:pointer' }, 'Más datos (RUT, nota, límite' + (nuevo ? ', PIN, saldo anterior' : '') + ')'),
        campo('RUT', f.rut), campo('Nota interna', f.nota),
        prem() && esDueno() ? campo('Límite de fiado para este cliente', f.limite, 'Vacío = usa el límite general.') : null,
        nuevo ? campo('PIN del link (4 números)', f.pin, 'Si lo dejas vacío, son los últimos 4 dígitos de su teléfono.') : null,
        nuevo ? campo('Saldo que ya te debe (del cuaderno)', f.saldo) : null),
      nuevo ? el('label', { class: 'check', for: 'autoriza' }, f.autoriza, el('span', null, 'El cliente me autorizó a registrar sus datos para llevar su cuenta.')) : null,
      err);
    const ok = await dialogo(nuevo ? 'Nuevo cliente' : 'Editar cliente', cont, [{ texto: 'Cancelar', valor: null }, { texto: 'Guardar', clase: 'primario', valor: true, antes: async () => {
      err.textContent = '';
      try {
        const nombre = f.nombre.value.trim().replace(/\s+/g, ' ');
        if (nombre.length < 2) throw new Error('El nombre debe tener entre 2 y 60 letras');
        const tel = V.telefono(f.telefono.value); const rut = V.rut(f.rut.value);
        const lim = f.limite.value ? Math.round(Number(f.limite.value)) : null;
        if (lim != null && (lim < 0 || lim > 5000000)) throw new Error('El límite debe ser entre $0 y $5.000.000');
        if (nuevo) {
          if (f.pin.value && !/^\d{4}$/.test(f.pin.value)) throw new Error('El PIN debe tener 4 números');
          const saldo = f.saldo.value ? Math.round(Number(f.saldo.value)) : 0;
          if (saldo < 0 || saldo > 9999999) throw new Error('El saldo inicial debe ser entre $0 y $9.999.999');
          if (!f.autoriza.checked) throw new Error('Marca que el cliente te autorizó');
          local.set('lc-autoriza', true);
          const params = { p_nombre: nombre, p_apodo: f.apodo.value, p_telefono: tel, p_rut: rut, p_nota: f.nota.value, p_limite: lim, p_pin: f.pin.value || null, p_saldo_inicial: saldo, p_forzar: false, p_autorizado: true };
          let r = await conCarga(() => rpc('crear_cliente', params));
          if (r.duplicado) {
            const otra = await confirmar('¿Es otra persona?', 'Ya tienes a ' + r.duplicado.nombre + (r.duplicado.telefono ? ' (' + r.duplicado.telefono + ')' : '') + '. ¿Quieres crear otro cliente igual? Te sugerimos agregarle un apodo.', 'Sí, es otra persona');
            if (!otra) return false;
            r = await conCarga(() => rpc('crear_cliente', { ...params, p_forzar: true }));
          }
          await cargarClientes();
          toast('Cliente creado ✓' + (r.sin_pin ? ' · Define su PIN antes de enviarle el link' : ''));
          location.hash = 'cliente/' + r.id;
        } else {
          await conCarga(() => rpc('editar_cliente', { p_id: c.id, p_nombre: nombre, p_apodo: f.apodo.value, p_telefono: tel, p_rut: rut, p_nota: f.nota.value, p_limite: lim }));
          await cargarClientes(); toast('Guardado ✓'); router(true);
        }
        return true;
      } catch (e) { if (e.pista === 'PLAN') { error(e); return true; } err.textContent = LC.traducir(e).message; return false; }
    } }]);
    return ok;
  }

  async function pasarCuaderno() {
    const filas = el('div', { class: 'col' });
    const agregar = () => filas.append(el('div', { class: 'grid3', style: 'grid-template-columns:2fr 1.5fr 1fr' },
      el('input', { placeholder: 'Nombre', maxlength: 60 }), el('input', { placeholder: 'Teléfono', type: 'tel', inputmode: 'tel' }), el('input', { placeholder: 'Debe $', type: 'number', inputmode: 'numeric', min: 0 })));
    for (let i = 0; i < 5; i++) agregar();
    const aut = el('input', { type: 'checkbox', id: 'autc' });
    const res = el('div', { class: 'sutil' });
    await dialogo('Pasar mi cuaderno', el('div', null, el('p', { class: 'sutil' }, 'Escribe tus clientes y lo que te deben hoy. El PIN de cada uno serán los últimos 4 dígitos de su teléfono.'),
      filas, el('button', { class: 'btn texto', type: 'button', onclick: agregar }, '+ Agregar fila'),
      el('label', { class: 'check mt', for: 'autc' }, aut, 'Mis clientes me autorizaron a registrar sus datos.'), res),
    [{ texto: 'Cancelar', valor: null }, { texto: 'Guardar todos', clase: 'primario', valor: true, antes: async () => {
      if (!aut.checked) { res.textContent = 'Marca la casilla de autorización'; return false; }
      const datos = [...filas.children].map((r) => [...r.children].map((i) => i.value.trim())).filter((r) => r[0]);
      if (!datos.length) { res.textContent = 'Escribe al menos un nombre'; return false; }
      let ok = 0; const malos = [];
      await conCarga(async () => {
        for (const [n, t, s] of datos) {
          try {
            const r = await rpc('crear_cliente', { p_nombre: n, p_apodo: null, p_telefono: V.telefono(t), p_rut: null, p_nota: null, p_limite: null, p_pin: null, p_saldo_inicial: s ? Math.round(Number(s)) : 0, p_forzar: false, p_autorizado: true });
            if (r.duplicado) malos.push(n + ': ya existe'); else ok++;
          } catch (e) { malos.push(n + ': ' + LC.traducir(e).message); if (e.pista === 'PLAN') break; }
        }
      });
      local.set('lc-autoriza', true);
      await cargarClientes();
      toast(ok + ' clientes guardados ✓');
      if (malos.length) { res.textContent = 'No se guardaron: ' + malos.join(' · '); return false; }
      router(); return true;
    } }]);
  }

  // ================= FICHA DEL CLIENTE =================
  async function vCliente(id, pestana) {
    let c = cliente(id);
    if (!c) { await cargarClientes().catch(() => {}); c = cliente(id); }
    if (!c) { pintar(el('div', { class: 'vacio' }, 'Cliente no encontrado.', el('br'), el('a', { href: '#clientes' }, 'Volver'))); return; }
    pestana = pestana || 'movimientos';
    const lim = (prem() && c.limite) || S.neg.limite_general || null;
    const usado = lim ? Math.min(100, Math.round(Math.max(c.saldo, 0) * 100 / lim)) : 0;
    const estadoTxt = c.estado === 'archivado' ? el('span', { class: 'tag' }, 'Archivado') : c.fuera_de_plan ? el('span', { class: 'tag naranjo' }, '🔒 Fuera del plan') : c.bloqueado ? el('span', { class: 'tag rojo' }, '🚫 Solo cobro') : null;
    const cuerpo = el('div');
    pintar(
      el('div', { class: 'fila mb' }, el('a', { class: 'btn-icono', href: '#clientes', 'aria-label': 'Volver', style: 'text-decoration:none' }, '←'),
        avatar(c.nombre), el('div', { class: 'crece' }, el('h2', { style: 'margin:0' }, c.nombre), el('div', { class: 'sutil' }, [c.apodo, V.telBonito(c.telefono)].filter(Boolean).join(' · ') || 'Sin teléfono')),
        estadoTxt),
      el('div', { class: 'tarjeta centro' },
        el('div', { class: 'sutil' }, c.saldo > 0 ? 'Debe' : c.saldo < 0 ? 'Saldo a favor del cliente' : 'Estado'),
        el('div', { class: 'saldo-gigante ' + (c.saldo > 0 ? 'rojo' : 'verde') }, c.saldo > 0 ? pesos(c.saldo) : c.saldo < 0 ? pesos(-c.saldo) : 'Al día ✓'),
        c.saldo > 0 && c.prox_venc ? el('div', { class: c.atrasado ? 'rojo' : 'sutil' }, (c.atrasado ? 'Atrasado desde ' : 'Próximo vencimiento: ') + fechaCorta(c.prox_venc) + ' (' + relativo(c.prox_venc) + ')') : null,
        lim ? el('div', { class: 'mt' }, el('div', { class: 'barra ' + (usado >= 100 ? 'lleno' : usado >= 80 ? 'alerta' : '') }, el('i', { style: 'width:' + usado + '%' })), el('div', { class: 'sutil mt' }, 'Límite de fiado: ' + pesos(lim) + ' (' + usado + '% usado)')) : null,
        prem() ? el('div', { class: 'mt' }, puntajeTag(c.puntaje)) : null),
      el('div', { class: 'acciones mb' },
        el('a', { class: 'btn rojo', href: '#anotar/' + c.id + '/fiado' }, el('span', { class: 'ico' }, '＋'), 'Fiado'),
        el('a', { class: 'btn verde', href: '#anotar/' + c.id + '/abono' }, el('span', { class: 'ico' }, '－'), 'Abono'),
        el('button', { class: 'btn wsp', type: 'button', onclick: () => cobrar(c.id) }, el('span', { class: 'ico' }, '💬'), 'Cobrar'),
        el('button', { class: 'btn', type: 'button', onclick: () => compartirLink(c.id) }, el('span', { class: 'ico' }, '🔗'), 'Link')),
      el('div', { class: 'chips' }, [['movimientos', 'Movimientos'], ['cuotas', 'Cuotas'], ['datos', 'Datos']].map(([v, t]) =>
        el('a', { class: 'chip' + (pestana === v ? ' activo' : ''), href: '#cliente/' + c.id + '/' + v, style: 'text-decoration:none' }, t))),
      cuerpo);
    if (pestana === 'cuotas') return pCuotas(c, cuerpo);
    if (pestana === 'datos') return pDatos(c, cuerpo);
    return pMovimientos(c, cuerpo);
  }

  async function pMovimientos(c, cuerpo) {
    cuerpo.append(el('div', { class: 'vacio' }, el('div', { class: 'spinner', style: 'margin:auto' })));
    const { data, error: e } = await sb.from('movimientos').select('*').eq('cliente', c.id).order('fecha', { ascending: false }).limit(300);
    if (e) throw LC.traducir(e);
    const pend = cola().filter((m) => m.cliente === c.id);
    vaciar(cuerpo);
    if (!data.length && !pend.length) { cuerpo.append(el('div', { class: 'lista' }, el('div', { class: 'vacio' }, el('span', { class: 'ico' }, '📒'), 'Sin movimientos todavía.'))); return; }
    const chat = el('div', { class: 'chat' });
    for (const m of pend) chat.append(el('div', { class: 'burbuja ' + (m.tipo === 'cargo' ? 'cargo' : 'abono') }, el('div', { class: 'm' }, pesos(m.monto)), el('div', { class: 'd' }, m.descripcion || (m.tipo === 'cargo' ? 'Fiado' : 'Abono')), el('div', { class: 'meta' }, '⏳ Por subir' + (m.error ? ' · ❌ ' + m.error : ''))));
    let dia = '';
    for (const m of data) {
      const d = fechaLarga(m.fecha);
      if (d !== dia) { chat.append(el('div', { class: 'dia' }, d)); dia = d; }
      const tipo = m.tipo === 'cargo' || (m.tipo === 'ajuste' && m.signo === 1) ? 'cargo' : m.tipo === 'abono' ? 'abono' : 'ajuste';
      const etiqueta = m.tipo === 'cargo' ? (m.venta ? 'Venta en cuotas' : 'Fiado') : m.tipo === 'abono' ? 'Abono' + (m.medio ? ' · ' + m.medio : '') : 'Ajuste ' + (m.signo === 1 ? '(suma)' : '(resta)');
      const conf = m.tipo === 'cargo' ? (m.confirmacion === 'reconocido' ? ' · ✓ confirmado' : m.confirmacion === 'reclamado' ? ' · ⚠️ reclamado' : '') : '';
      const b = el('div', { class: 'burbuja ' + tipo + (m.anulado_at ? ' anulado' : ''), role: 'button', tabindex: 0, onclick: () => menuMovimiento(m, c) },
        el('div', { class: 'm' }, (m.signo === 1 ? '+' : '−') + pesos(m.monto)),
        el('div', { class: 'd' }, m.descripcion || etiqueta),
        el('div', { class: 'meta' }, (m.descripcion ? etiqueta + ' · ' : '') + hora(m.fecha) + (m.vence && m.tipo === 'cargo' && !m.venta ? ' · vence ' + fechaCorta(m.vence) : '') + conf),
        m.anulado_at ? el('div', { class: 'meta rojo' }, 'Anulado: ' + (m.motivo_anulacion || '')) : null,
        m.confirmacion === 'reclamado' && !m.anulado_at ? el('div', { class: 'meta rojo' }, 'Reclamo: ' + (m.reclamo_motivo || '') + (m.respuesta ? ' · Respuesta: ' + m.respuesta : '')) : null);
      chat.append(b);
    }
    if (!prem()) chat.append(el('p', { class: 'sutil centro' }, 'En el plan Normal ves los últimos 6 meses. El saldo siempre es exacto.'));
    cuerpo.append(chat);
  }

  async function menuMovimiento(m, c) {
    if (m.anulado_at) return;
    const yo = m.creado_por === S.uid && (Date.now() - new Date(m.creado_at)) < 10 * 60 * 1000;
    const puedeAnular = (esDueno() || yo);
    const botones = [{ texto: 'Cerrar', valor: null }];
    if (m.confirmacion === 'reclamado' && !m.respuesta && esDueno()) botones.push({ texto: 'Responder reclamo', clase: 'primario', valor: 'reclamo' });
    if (puedeAnular) botones.push({ texto: m.venta ? 'Anular venta' : 'Anular', clase: 'peligro', valor: 'anular' });
    const info = el('div', null,
      el('p', null, el('strong', null, (m.signo === 1 ? '+' : '−') + pesos(m.monto)), ' · ', m.descripcion || m.tipo),
      el('p', { class: 'sutil' }, 'Fecha: ' + fechaHora(m.fecha) + (m.vence && m.tipo === 'cargo' ? ' · Vence: ' + fechaCorta(m.vence) : '')),
      m.tipo === 'cargo' ? el('p', { class: 'sutil' }, m.confirmacion === 'reconocido' ? '✓ El cliente confirmó este cargo.' : m.confirmacion === 'reclamado' ? '⚠️ Reclamo del cliente: ' + (m.reclamo_motivo || '') : 'El cliente aún no lo confirma.') : null,
      !puedeAnular && !esDueno() ? el('p', { class: 'sutil' }, 'Como ayudante solo puedes anular lo tuyo en los primeros 10 minutos.') : null);
    const r = await dialogo('Movimiento', info, botones);
    if (r === 'anular') {
      const mot = await pedirTexto(m.venta ? 'Anular venta en cuotas' : 'Anular movimiento', 'Motivo', { min: 5, max: 100, placeholder: 'Ej: me equivoqué de cliente', boton: 'Anular', clase: 'rojo' });
      if (!mot) return;
      try {
        await conCarga(() => m.venta ? rpc('anular_venta_cuotas', { p_venta: m.venta, p_motivo: mot }) : rpc('anular_movimiento', { p_id: m.id, p_motivo: mot }));
        await cargarClientes(); toast('Anulado ✓'); router(true);
      } catch (e) { error(e); }
    } else if (r === 'reclamo') {
      const mantener = el('select', null, el('option', { value: '1' }, 'Mantener el cargo (es correcto)'), el('option', { value: '0' }, 'Anular el cargo (el cliente tiene razón)'));
      const txt = el('textarea', { maxlength: 150, placeholder: 'Respuesta que verá el cliente' });
      const ok = await dialogo('Responder reclamo', el('div', null, el('p', { class: 'sutil' }, 'Reclamo: ' + (m.reclamo_motivo || '')), el('div', { class: 'campo' }, mantener), el('div', { class: 'campo' }, txt)),
        [{ texto: 'Cancelar', valor: null }, { texto: 'Responder', clase: 'primario', valor: true }]);
      if (!ok) return;
      try { await conCarga(() => rpc('responder_reclamo', { p_mov: m.id, p_mantener: mantener.value === '1', p_comentario: txt.value })); await cargarClientes(); await refrescarEstado(); toast('Respuesta enviada ✓'); router(true); } catch (e) { error(e); }
    }
  }

  // ---------- Cuotas ----------
  async function pCuotas(c, cuerpo) {
    const { data: ventas, error: e } = await sb.from('ventas_cuotas').select('*, cuotas(*)').eq('cliente', c.id).order('creado', { ascending: false });
    if (e) throw LC.traducir(e);
    const hoy = hoyISO();
    cuerpo.append(el('button', { class: 'btn primario ancho mb', type: 'button', onclick: () => formCuotas(c) }, '＋ Nueva venta en cuotas'));
    if (!ventas.length) { cuerpo.append(el('div', { class: 'lista' }, el('div', { class: 'vacio' }, el('span', { class: 'ico' }, '📆'), 'Sin ventas en cuotas.'))); return; }
    for (const v of ventas) {
      const cs = (v.cuotas || []).sort((a, b) => a.numero - b.numero);
      cuerpo.append(el('div', { class: 'tarjeta' + (v.estado === 'anulada' ? ' anulado' : ''), style: v.estado === 'anulada' ? 'opacity:.55' : '' },
        el('div', { class: 'fila entre' }, el('strong', null, v.descripcion), el('span', { class: 'tag ' + (v.estado === 'pagada' ? 'verde' : v.estado === 'anulada' ? '' : 'marca') }, v.estado)),
        el('div', { class: 'sutil' }, pesos(v.total) + (v.pie ? ' · pie ' + pesos(v.pie) : '') + ' · ' + v.n + ' cuotas ' + v.frecuencia + 's'),
        el('div', { class: 'lista mt' }, cs.map((q) => {
          const pagada = q.pagado >= q.monto, atr = !pagada && q.vence < hoy, pronto = !pagada && !atr && q.vence <= sumarDias(hoy, 3);
          return el('div', { class: 'item', style: 'cursor:default' }, el('div', { class: 'crece' }, el('div', { class: 'nom' }, 'Cuota ' + q.numero + ' · ' + pesos(q.monto)),
            el('div', { class: 'sub' }, 'Vence ' + fechaCorta(q.vence) + (q.pagado && !pagada ? ' · pagado ' + pesos(q.pagado) : ''))),
          el('span', { class: 'tag ' + (pagada ? 'verde' : atr ? 'rojo' : pronto ? 'naranjo' : '') }, pagada ? 'Pagada' : atr ? 'Atrasada' : pronto ? 'Por vencer' : 'Pendiente'));
        })),
        v.estado !== 'anulada' && (esDueno() || v.creado_por === S.uid) ? el('button', { class: 'btn peligro chico mt', type: 'button', onclick: async () => {
          const mot = await pedirTexto('Anular venta en cuotas', 'Motivo', { min: 5, max: 100, boton: 'Anular', clase: 'rojo', ayuda: 'Si ya hubo abonos, quedan a favor del cliente o pagan otras deudas.' });
          if (!mot) return;
          try { await conCarga(() => rpc('anular_venta_cuotas', { p_venta: v.id, p_motivo: mot })); await cargarClientes(); toast('Venta anulada'); router(true); } catch (er) { error(er); }
        } }, 'Anular venta') : null));
    }
  }

  function calendario(total, pie, n, frec, primera) {
    const fin = total - pie, base = Math.floor(fin / n), out = [];
    for (let i = 1; i <= n; i++) {
      let f;
      if (frec === 'semanal') f = sumarDias(primera, 7 * (i - 1));
      else if (frec === 'quincenal') f = sumarDias(primera, 14 * (i - 1));
      else {
        const [y, m, d] = primera.split('-').map(Number); const mm = m - 1 + (i - 1); const yy = y + Math.floor(mm / 12); const mes = ((mm % 12) + 12) % 12;
        const ult = new Date(Date.UTC(yy, mes + 1, 0)).getUTCDate();
        f = yy + '-' + String(mes + 1).padStart(2, '0') + '-' + String(Math.min(d, ult)).padStart(2, '0');
      }
      out.push({ n: i, monto: i === n ? fin - base * (n - 1) : base, vence: f });
    }
    return out;
  }

  async function formCuotas(c) {
    if (c.bloqueado || c.fuera_de_plan || c.estado !== 'activo') { toast('Este cliente no admite más deuda (solo cobro o archivado).', { error: true }); return; }
    const desc = el('input', { maxlength: 80, placeholder: 'Ej: Zapatillas Nike' });
    const total = el('input', { type: 'number', inputmode: 'numeric', min: 1000, placeholder: '60000' });
    const pie = el('input', { type: 'number', inputmode: 'numeric', min: 0, placeholder: '0' });
    const n = el('select', null, Array.from({ length: 23 }, (_, i) => el('option', { value: i + 2, selected: i + 2 === 3 }, (i + 2) + ' cuotas')));
    const frec = el('select', null, el('option', { value: 'mensual' }, 'Mensual'), el('option', { value: 'quincenal' }, 'Quincenal'), el('option', { value: 'semanal' }, 'Semanal'));
    const primera = el('input', { type: 'date', min: hoyISO(), max: sumarDias(hoyISO(), 60), value: sumarDias(hoyISO(), 30) });
    const prev = el('div', { class: 'lista' }); const err = el('div', { class: 'error' });
    const ver = () => {
      vaciar(prev); err.textContent = '';
      const t = Math.round(Number(total.value)), p = Math.round(Number(pie.value || 0));
      if (!t || t < 1000) return; if (p >= t) { err.textContent = 'El pie debe ser menor que el total'; return; }
      calendario(t, p, Number(n.value), frec.value, primera.value || hoyISO()).forEach((q) => prev.append(el('div', { class: 'item', style: 'cursor:default' }, el('span', { class: 'crece' }, 'Cuota ' + q.n + ' · ' + fechaCorta(q.vence)), el('strong', null, pesos(q.monto)))));
    };
    [total, pie, n, frec, primera].forEach((x) => x.addEventListener('input', ver));
    const campo = (t, i) => el('div', { class: 'campo' }, el('label', null, t), i);
    const id = uuid();
    const r = await dialogo('Venta en cuotas · ' + c.nombre, el('div', null, campo('¿Qué vendiste?', desc), el('div', { class: 'grid2' }, campo('Total', total), campo('Pie (opcional)', pie)),
      el('div', { class: 'grid2' }, campo('Cuotas', n), campo('Frecuencia', frec)), campo('Primera cuota', primera), el('label', null, 'Calendario'), prev, err),
    [{ texto: 'Cancelar', valor: null }, { texto: 'Crear', clase: 'primario', valor: true, antes: async () => {
      const params = { p_id: id, p_cliente: c.id, p_descripcion: desc.value, p_total: Math.round(Number(total.value)), p_pie: Math.round(Number(pie.value || 0)), p_n: Number(n.value), p_frecuencia: frec.value, p_primera: primera.value, p_forzar_limite: false };
      try {
        let res = await conCarga(() => rpc('crear_venta_cuotas', params));
        if (res.limite) {
          if (!esDueno()) { err.textContent = 'Supera el límite de fiado de este cliente.'; return false; }
          if (!await confirmar('Supera el límite', 'Con esta venta el cliente pasa su límite de ' + pesos(res.limite) + '. ¿Crear igual?', 'Crear igual')) return false;
          res = await conCarga(() => rpc('crear_venta_cuotas', { ...params, p_forzar_limite: true }));
        }
        return true;
      } catch (e) { if (e.pista === 'PLAN') { error(e); return true; } err.textContent = e.message; return false; }
    } }]);
    if (!r) return;
    await cargarClientes(); toast('Venta en cuotas creada ✓');
    if (c.telefono && await confirmar('¿Enviar el detalle?', '¿Quieres mandarle el calendario de cuotas por WhatsApp?', 'Enviar')) {
      const cal = calendario(Math.round(Number(total.value)), Math.round(Number(pie.value || 0)), Number(n.value), frec.value, primera.value).map((q) => '• Cuota ' + q.n + ': ' + pesos(q.monto) + ' el ' + fechaCorta(q.vence)).join('\n');
      abrir(wa(c.telefono, 'Hola ' + primerNombre(c.nombre) + ', te dejo el detalle de tu compra en ' + S.neg.nombre + ' (' + desc.value + '):\n' + cal + '\n\nPuedes ver tu cuenta aquí: ' + linkDe(c)));
    }
    router(true);
  }

  // ---------- Datos del cliente ----------
  async function pDatos(c, cuerpo) {
    const { data: recs } = await sb.from('recordatorios').select('canal,tono,at').eq('cliente', c.id).order('at', { ascending: false }).limit(10);
    const acc = (t, fn, clase) => el('button', { class: 'item', type: 'button', onclick: fn }, el('span', { class: 'crece ' + (clase || '') }, t), el('span', { class: 'sutil' }, '›'));
    const est = async (accion, msg) => { try { await conCarga(() => rpc('estado_cliente', { p_id: c.id, p_accion: accion })); await cargarClientes(); await refrescarEstado(); toast(msg); router(true); } catch (e) { error(e); } };
    cuerpo.append(
      el('div', { class: 'tarjeta' },
        dato('Teléfono', V.telBonito(c.telefono) || '—'), dato('RUT', c.rut ? V.rutBonito(c.rut) : '—'), dato('Nota interna', c.nota || '—'),
        dato('Límite de fiado', c.limite ? pesos(c.limite) : S.neg.limite_general ? pesos(S.neg.limite_general) + ' (general)' : 'Sin límite'),
        dato('Cliente desde', fechaCorta(c.creado))),
      el('div', { class: 'lista' },
        acc('✏️ Editar datos', () => formCliente(c)),
        acc('🔗 Link y PIN', () => compartirLink(c.id)),
        c.fuera_de_plan ? acc('🔓 Incluir en el plan (si hay cupo)', () => est('incluir', 'Cliente incluido ✓')) : null,
        c.estado === 'activo' && !c.fuera_de_plan ? (c.bloqueado ? acc('✅ Permitir fiar de nuevo', () => est('desbloquear', 'Listo ✓')) : acc('🚫 Solo cobro (no fiarle más)', () => est('bloquear', 'Ahora es solo cobro'))) : null,
        c.estado === 'archivado' ? acc('♻️ Reactivar', () => est('reactivar', 'Cliente reactivado ✓')) : acc('🗄️ Archivar (con saldo $0)', () => est('archivar', 'Cliente archivado ✓')),
        prem() ? acc('📄 Estado de cuenta (PDF)', () => estadoCuentaPDF(c)) : acc('📄 Estado de cuenta (PDF) ⭐', () => alPlan('El estado de cuenta en PDF es Premium.')),
        esDueno() ? acc('🗑️ Borrar cliente', async () => {
          const conf = await pedirTexto('Borrar cliente', 'Escribe "' + c.nombre + '" para confirmar', { boton: 'Borrar', clase: 'rojo', ayuda: 'Solo con saldo $0. Se borran sus datos personales; los movimientos quedan anónimos para que tus totales cuadren.' });
          if (!conf) return;
          try { await conCarga(() => rpc('borrar_cliente', { p_id: c.id, p_confirmacion: conf })); await cargarClientes(); toast('Cliente borrado'); location.hash = 'clientes'; } catch (e) { error(e); }
        }, 'rojo') : null),
      el('h3', null, 'Recordatorios enviados'),
      el('div', { class: 'lista' }, (recs || []).length ? recs.map((r) => el('div', { class: 'item', style: 'cursor:default' }, el('span', { class: 'crece' }, (r.canal === 'push' ? '🔔 Aviso' : '💬 WhatsApp') + ' · ' + r.tono), el('span', { class: 'sutil' }, fechaHora(r.at))))
        : el('div', { class: 'vacio' }, 'Ninguno todavía.')),
      el('p', { class: 'sutil' }, 'La ley permite máximo 2 recordatorios por semana, separados por 2 días, de lunes a sábado entre 08:00 y 20:00.'));
  }
  const dato = (k, v) => el('div', { class: 'copiar-fila' }, el('div', { class: 'crece' }, el('div', { class: 'k' }, k), el('div', { class: 'v' }, v)));

  // ---------- Link del cliente ----------
  const linkDe = (c) => RAIZ + 'c/#' + c.link_codigo;
  const primerNombre = (n) => String(n || '').split(' ')[0];
  async function compartirLink(id) {
    const c = cliente(id); if (!c) return;
    let info;
    try { info = await conCarga(() => rpc('link_cliente', { p_id: id, p_regenerar: false, p_pin: null })); } catch (e) { return error(e); }
    const url = RAIZ + 'c/#' + info.codigo;
    const pinTxt = S.neg.pin_activo ? (info.tiene_pin ? 'Su PIN: últimos 4 dígitos de su teléfono (o el que definiste).' : '⚠️ Este cliente aún no tiene PIN. Defínelo abajo.') : 'El PIN está desactivado en Ajustes.';
    const r = await dialogo('Link de ' + c.nombre, el('div', null,
      el('p', { class: 'sutil' }, 'Con este link tu cliente ve su saldo, sus cuotas y tus datos para transferir, y sube el comprobante.'),
      el('div', { class: 'tarjeta plana', style: 'word-break:break-all' }, url),
      el('p', { class: 'sutil' }, pinTxt),
      info.bloqueado ? el('p', { class: 'rojo' }, 'El link está bloqueado por intentos fallidos. Genera uno nuevo.') : null,
      el('div', { class: 'col' },
        el('button', { class: 'btn wsp', type: 'button', disabled: !c.telefono || info.bloqueado, onclick: () => abrir(wa(c.telefono, 'Hola ' + primerNombre(c.nombre) + ', aquí puedes ver tu cuenta en ' + S.neg.nombre + ' cuando quieras: ' + url + (S.neg.pin_activo ? '\nTu PIN son los últimos 4 dígitos de tu teléfono.' : ''))) }, '💬 Enviar por WhatsApp'),
        el('button', { class: 'btn', type: 'button', onclick: () => copiar(url, 'Link copiado ✓') }, '📋 Copiar link'))),
    [{ texto: 'Cerrar', valor: null }, { texto: 'Cambiar PIN', valor: 'pin' }, { texto: 'Nuevo link', valor: 'nuevo' }]);
    if (r === 'pin') {
      const pin = await pedirTexto('PIN de ' + c.nombre, 'Nuevo PIN (4 números)', { inputmode: 'numeric', max: 4, validar: (v) => /^\d{4}$/.test(v) ? null : 'Deben ser 4 números' });
      if (!pin) return;
      try { await conCarga(() => rpc('link_cliente', { p_id: id, p_regenerar: false, p_pin: pin })); toast('PIN cambiado ✓. Avísale a tu cliente.'); } catch (e) { error(e); }
    } else if (r === 'nuevo') {
      if (!await confirmar('¿Generar un link nuevo?', 'El link anterior dejará de funcionar al instante. Úsalo si el link se compartió con otra persona o se bloqueó.', 'Generar')) return;
      try { await conCarga(() => rpc('link_cliente', { p_id: id, p_regenerar: true, p_pin: null })); await cargarClientes(); toast('Link nuevo listo ✓'); compartirLink(id); } catch (e) { error(e); }
    }
  }

  // ---------- Cobrar ----------
  const PLANTILLAS = {
    amable: '¡Hola {nombre}! 😊 Te escribo de {negocio}. Tu saldo pendiente es de {saldo}. Puedes ver el detalle y pagar por transferencia aquí: {link}{pin} ¡Gracias!',
    neutral: 'Hola {nombre}, te recordamos que en {negocio} tienes un saldo de {saldo}{fecha}. Detalle y datos para pagar: {link}',
    firme: 'Hola {nombre}. Tu cuenta en {negocio} tiene {saldo} pendiente{fecha}. Te pedimos ponerte al día o escribirnos para acordar una fecha. Detalle: {link}',
  };
  function armarMensaje(tono, c) {
    const base = tono === 'propio' ? (S.neg.plantilla_propia || PLANTILLAS.amable) : PLANTILLAS[tono];
    return base.replace(/\{nombre\}/g, primerNombre(c.nombre)).replace(/\{negocio\}/g, S.neg.nombre).replace(/\{saldo\}/g, pesos(c.saldo))
      .replace(/\{link\}/g, linkDe(c)).replace(/\{pin\}/g, S.neg.pin_activo ? ' (tu PIN son los últimos 4 dígitos de tu teléfono).' : '')
      .replace(/\{fecha\}/g, c.prox_venc && c.atrasado ? ', vencido desde el ' + fechaCorta(c.prox_venc) : c.prox_venc ? ', con vencimiento el ' + fechaCorta(c.prox_venc) : '');
  }
  async function cobrar(id) {
    const c = cliente(id); if (!c) return;
    if (c.saldo <= 0) { toast('Este cliente no tiene deuda ✓'); return; }
    let p;
    try { p = await conCarga(() => rpc('puede_cobrar', { p_cliente: id })); } catch (e) { return error(e); }
    if (!p.ok) {
      const prox = new Date(p.proxima);
      await dialogo('Todavía no se puede cobrar', el('div', null, el('p', null, p.motivo),
        el('p', null, el('strong', null, 'Podrás enviarlo el ' + fechaLarga(p.proxima) + ' desde las ' + prox.toLocaleTimeString('es-CL', { hour: '2-digit', minute: '2-digit', hourCycle: 'h23', timeZone: 'America/Santiago' }) + ' hrs.')),
        el('p', { class: 'sutil' }, 'Esto lo pide la ley de cobranza (Ley 19.496): de lunes a sábado de 08:00 a 20:00, sin feriados, máximo 2 por semana.')));
      return;
    }
    let tono = 'amable';
    const prev = el('div', { class: 'tarjeta plana', style: 'white-space:pre-wrap' });
    const tonos = el('div', { class: 'segmento' });
    const pintarT = () => { vaciar(tonos); [['amable', 'Amable'], ['neutral', 'Neutral'], ['firme', 'Firme'], ['propio', 'Propio']].forEach(([v, t]) => {
      const bloqueado = v !== 'amable' && !prem(); if (v === 'propio' && prem() && !S.neg.plantilla_propia) return;
      tonos.append(el('button', { type: 'button', class: tono === v ? 'activo' : '', onclick: () => { if (bloqueado) return alPlan('Los tonos neutral, firme y tu mensaje propio son Premium.'); tono = v; pintarT(); } }, t + (bloqueado ? ' ⭐' : '')));
    }); prev.textContent = armarMensaje(tono, c); };
    pintarT();
    const botones = [{ texto: 'Cancelar', valor: null }];
    if (p.push) botones.push({ texto: '🔔 Aviso', valor: 'push' });
    botones.push({ texto: '💬 WhatsApp', clase: 'wsp', valor: 'wsp' });
    const r = await dialogo('Cobrar a ' + c.nombre, el('div', null, tonos, el('div', { class: 'mt' }, prev),
      !c.telefono ? el('p', { class: 'rojo' }, 'Este cliente no tiene teléfono. Agrégalo en sus datos.') : null,
      el('p', { class: 'sutil' }, 'Se registra como recordatorio de cobro (máximo 2 por semana).')), botones);
    if (!r) return;
    const texto = armarMensaje(tono, c);
    try {
      const res = await conCarga(() => rpc('registrar_recordatorio', { p_cliente: id, p_canal: r === 'push' ? 'push' : 'whatsapp', p_tono: tono, p_texto: texto }));
      if (!res.ok) { toast(res.motivo + ' Próximo: ' + fechaLarga(res.proxima), { error: true, ms: 6000 }); return; }
      if (r === 'push') toast('Aviso enviado ✓'); else abrir(wa(c.telefono, texto));
    } catch (e) { error(e); }
  }

  // ================= ANOTAR =================
  async function vAnotar(id, tipoIni) {
    if (!id) return elegirCliente();
    const c = cliente(id);
    if (!c) { location.hash = 'anotar'; return; }
    let tipo = tipoIni === 'abono' ? 'abono' : 'fiado';
    if (tipoIni !== 'fiado' && (c.bloqueado || c.fuera_de_plan || c.estado !== 'activo') && c.saldo > 0) tipo = 'abono';
    let monto = '', desc = '', medio = 'efectivo', fecha = '', vence = '';
    const pantalla = el('div', { class: 'pantalla-monto' });
    const seg = el('div', { class: 'segmento' });
    const descIn = el('input', { maxlength: 80, placeholder: 'Detalle (opcional): pan, leche…' });
    descIn.oninput = () => { desc = descIn.value; };
    const extra = el('div');
    const pintarTodo = () => {
      vaciar(seg).append(
        el('button', { type: 'button', class: 'fiado' + (tipo === 'fiado' ? ' activo' : ''), onclick: () => { tipo = 'fiado'; pintarTodo(); } }, '＋ Fiado'),
        el('button', { type: 'button', class: 'abono' + (tipo === 'abono' ? ' activo' : ''), onclick: () => { tipo = 'abono'; pintarTodo(); } }, '－ Abono'));
      pantalla.className = 'pantalla-monto ' + tipo;
      pantalla.textContent = monto ? pesos(Number(monto)) : '$0';
      vaciar(extra);
      if (tipo === 'abono') {
        extra.append(el('div', { class: 'chips' }, [['efectivo', '💵 Efectivo'], ['transferencia', '🏦 Transferencia'], ['otro', 'Otro']].map(([v, t]) =>
          el('button', { type: 'button', class: 'chip' + (medio === v ? ' activo' : ''), onclick: () => { medio = v; pintarTodo(); } }, t))));
        if (c.saldo > 0) extra.append(el('button', { class: 'btn chico', type: 'button', onclick: () => { monto = String(c.saldo); pintarTodo(); } }, 'Paga todo: ' + pesos(c.saldo)));
      } else if (S.productos.length) {
        extra.append(el('div', { class: 'rapidos' }, S.productos.map((p) => el('button', { class: 'chip', type: 'button', onclick: () => {
          monto = String((Number(monto) || 0) + p.precio); desc = desc ? desc + ', ' + p.nombre : p.nombre; descIn.value = desc; pintarTodo();
        } }, p.nombre + ' ' + pesos(p.precio)))));
      }
    };
    const tecla = (k) => {
      if (k === '⌫') monto = monto.slice(0, -1);
      else if (k === 'C') monto = '';
      else if (k.startsWith('+')) monto = String((Number(monto) || 0) + Number(k.slice(1)));
      else if ((monto + k).length <= 7) monto = (monto === '0' ? '' : monto) + k;
      if (Number(monto) > 9999999) monto = '9999999';
      pintarTodo();
      if (navigator.vibrate) navigator.vibrate(8);
    };
    const opciones = el('details', { class: 'mt' }, el('summary', { class: 'sutil', style: 'cursor:pointer' }, 'Fecha y vencimiento'),
      el('div', { class: 'grid2 mt' },
        el('div', { class: 'campo' }, el('label', null, 'Fecha'), el('input', { type: 'date', max: hoyISO(), min: sumarDias(hoyISO(), esDueno() ? -365 : -3), oninput: (e) => { fecha = e.target.value; } })),
        el('div', { class: 'campo' }, el('label', null, 'Vence (fiado)'), el('input', { type: 'date', min: hoyISO(), oninput: (e) => { vence = e.target.value; } }))),
      el('div', { class: 'ayuda' }, 'Por defecto: hoy, y vence según tus Ajustes (' + ({ 0: 'el mismo día', 7: '7 días', 15: '15 días', 30: '30 días', fin: 'fin de mes' }[S.neg.venc_defecto]) + ').'));
    const guardar = el('button', { class: 'btn primario ancho mt', type: 'button', onclick: async () => {
      const m = V.monto(monto);
      if (!m) { toast('Escribe un monto', { error: true }); return; }
      guardar.disabled = true;
      try { await guardarMovimiento(c, tipo, m, desc, medio, fecha, vence); } finally { guardar.disabled = false; }
    } }, 'Guardar');
    pintar(
      el('div', { class: 'fila mb' }, el('a', { class: 'btn-icono', href: '#cliente/' + c.id, style: 'text-decoration:none', 'aria-label': 'Volver' }, '←'), avatar(c.nombre),
        el('div', { class: 'crece' }, el('strong', null, c.nombre), el('div', { class: 'sutil' }, 'Debe ' + pesos(Math.max(c.saldo, 0)))),
        el('button', { class: 'btn chico', type: 'button', onclick: () => { location.hash = 'anotar'; } }, 'Cambiar')),
      seg, pantalla, extra,
      el('div', { class: 'teclado mt' }, ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'C', '0', '⌫'].map((k) => el('button', { type: 'button', onclick: () => tecla(k), 'aria-label': k === '⌫' ? 'Borrar' : k === 'C' ? 'Limpiar' : k }, k))),
      el('div', { class: 'rapidos' }, ['+500', '+1000', '+5000', '+10000'].map((k) => el('button', { class: 'chip', type: 'button', onclick: () => tecla(k) }, '+' + pesos(Number(k.slice(1)))))),
      el('div', { class: 'mt' }, descIn),
      opciones,
      el('button', { class: 'btn ancho mt', type: 'button', onclick: () => formCuotas(c) }, '📆 Es una venta en cuotas'),
      guardar);
    pintarTodo();
  }

  async function guardarMovimiento(c, tipo, monto, desc, medio, fecha, vence) {
    const mov = { id: uuid(), cliente: c.id, tipo: tipo === 'fiado' ? 'cargo' : 'abono', monto, descripcion: desc || null, medio: tipo === 'abono' ? medio : null,
      fecha: fecha ? new Date(fecha + 'T' + new Date().toTimeString().slice(0, 8)).toISOString() : new Date().toISOString(), vence: tipo === 'fiado' && vence ? vence : null };
    if (mov.tipo === 'cargo' && (c.bloqueado || c.fuera_de_plan || c.estado !== 'activo')) {
      if (c.fuera_de_plan) return alPlan('Este cliente quedó fuera del plan Normal (solo cobro). Hazte Premium o archiva clientes saldados.');
      toast('Este cliente es "solo cobro": no se le puede anotar más deuda.', { error: true }); return;
    }
    if (!navigator.onLine) return encolar(mov, c);
    const params = { p_id: mov.id, p_cliente: c.id, p_tipo: mov.tipo, p_monto: monto, p_descripcion: mov.descripcion, p_medio: mov.medio, p_fecha: mov.fecha, p_vence: mov.vence, p_signo: null, p_forzar_limite: false, p_confirmar_dup: false };
    try {
      let r = await conCarga(() => rpc('registrar_movimiento', params));
      if (r.duplicado) {
        if (!await confirmar('¿Anotar de nuevo?', 'Hace menos de un minuto anotaste ' + pesos(monto) + ' a ' + c.nombre + '. ¿Es otro movimiento?', 'Sí, anotar')) return;
        r = await conCarga(() => rpc('registrar_movimiento', { ...params, p_confirmar_dup: true }));
      }
      if (r.limite) {
        if (!await confirmar('Supera el límite de fiado', c.nombre + ' debe ' + pesos(r.saldo) + ' y su límite es ' + pesos(r.limite) + '. ¿Anotar igual?', 'Anotar igual', 'rojo')) return;
        r = await conCarga(() => rpc('registrar_movimiento', { ...params, p_forzar_limite: true, p_confirmar_dup: true }));
      }
      if (!r.ok) return;
      if (navigator.vibrate) navigator.vibrate([20, 40, 20]);
      await cargarClientes().catch(() => {});
      location.hash = 'cliente/' + c.id;
      toast((mov.tipo === 'cargo' ? 'Fiado ' : 'Abono ') + pesos(monto) + ' ✓ · Saldo ' + pesos(r.saldo), { accion: { texto: 'Deshacer', fn: async () => {
        try { await rpc('anular_movimiento', { p_id: mov.id, p_motivo: 'Deshecho al instante' }); await cargarClientes(); toast('Deshecho'); router(true); } catch (e) { error(e); }
      } } });
      refrescarEstado().catch(() => {});
    } catch (e) {
      if (e.pista === 'RED') return encolar(mov, c);
      error(e);
    }
  }
  function encolar(mov, c) {
    guardarCola([...cola(), mov]);
    const i = S.clientes.findIndex((x) => x.id === c.id);
    if (i >= 0) { S.clientes[i] = { ...c, saldo: c.saldo + (mov.tipo === 'cargo' ? mov.monto : -mov.monto) }; local.set('lc-clientes-' + S.uid, S.clientes); }
    toast('Guardado sin internet ⏳ Se subirá solo.');
    location.hash = 'cliente/' + c.id;
  }

  function elegirCliente() {
    const busc = el('input', { type: 'search', placeholder: '🔎 Buscar cliente', 'aria-label': 'Buscar cliente' });
    const lista = el('div', { class: 'lista' });
    const pintarL = () => {
      const q = norm(busc.value);
      let l = S.clientes.filter((c) => c.estado === 'activo' || c.saldo > 0);
      if (q) l = l.filter((c) => norm(c.nombre).includes(q) || norm(c.apodo).includes(q));
      else l = l.sort((a, b) => (b.ultimo_mov || '') > (a.ultimo_mov || '') ? 1 : -1);
      vaciar(lista);
      lista.append(el('button', { class: 'item', type: 'button', onclick: () => formCliente() }, el('div', { class: 'avatar', style: 'background:var(--marca)' }, '＋'), el('div', { class: 'crece nom' }, 'Nuevo cliente')));
      l.slice(0, 50).forEach((c) => lista.append(el('a', { class: 'item', href: '#anotar/' + c.id }, avatar(c.nombre), el('div', { class: 'crece' }, el('div', { class: 'nom' }, c.nombre), el('div', { class: 'sub' }, c.apodo || (c.saldo > 0 ? 'Debe ' + pesos(c.saldo) : 'Al día'))),
        el('div', { class: 'monto ' + (c.saldo > 0 ? 'rojo' : 'verde') }, c.saldo > 0 ? pesos(c.saldo) : '✓'))));
    };
    busc.oninput = pintarL;
    pintar(el('h2', null, '¿A quién le anotas?'), busc, el('div', { class: 'mt' }, lista));
    pintarL();
    if (S.clientes.length > 8) setTimeout(() => busc.focus(), 50);
  }

  // ================= MÁS =================
  function vMas() {
    const p = S.st.pendientes || {};
    const it = (h, ico, t, badge, solo) => solo === false ? null : el('a', { class: 'item', href: h }, el('span', { style: 'font-size:1.3em' }, ico), el('span', { class: 'crece' }, t), badge ? el('span', { class: 'tag rojo' }, badge) : null, el('span', { class: 'sutil' }, '›'));
    pintar(
      el('h2', null, 'Más'),
      el('div', { class: 'lista' },
        it('#comprobantes', '🧾', 'Comprobantes', p.comprobantes),
        it('#reportes', '📊', 'Reportes', null, esDueno()),
        it('#productos', '🏷️', 'Productos frecuentes', null, esDueno()),
        it('#ayudantes', '🧑‍🤝‍🧑', 'Ayudantes', null, esDueno()),
        it('#ajustes', '⚙️', 'Ajustes del negocio', null, esDueno()),
        it('#plan', '⭐', 'Mi plan · ' + (prem() ? (S.st.plan.en_prueba ? 'Prueba Premium' : 'Premium') : 'Normal'), null, esDueno()),
        it('#avisos', '🔔', 'Avisos', p.avisos),
        cola().length ? it('#pendientes', '⏳', 'Por subir', cola().length) : null),
      el('div', { class: 'lista' },
        it('#cuenta', '👤', 'Mi cuenta'),
        it('#ayuda', '❓', 'Ayuda'),
        S.st.es_admin ? it('../admin/', '🛡️', 'Administración') : null));
  }

  // ================= COMPROBANTES =================
  async function vComprobantes(arg) {
    const todos = arg === 'todos';
    let q = sb.from('comprobantes').select('id,cliente,monto,fecha,comentario,foto_path,estado,motivo,creado,revisado_at').order('creado', { ascending: false }).limit(100);
    if (!todos) q = q.eq('estado', 'pendiente');
    const { data, error: e } = await q;
    if (e) throw LC.traducir(e);
    const lista = el('div', { class: 'col' });
    if (!data.length) lista.append(el('div', { class: 'lista' }, el('div', { class: 'vacio' }, el('span', { class: 'ico' }, '🧾'), todos ? 'Sin comprobantes.' : 'No hay comprobantes por revisar.')));
    for (const k of data) {
      const c = cliente(k.cliente) || { nombre: 'Cliente' };
      const foto = el('div');
      if (k.foto_path) {
        sb.storage.from('comprobantes').createSignedUrl(k.foto_path, 600).then(({ data: u }) => {
          if (u && u.signedUrl) foto.append(el('img', { class: 'foto-comp mt', src: u.signedUrl, alt: 'Comprobante', loading: 'lazy', onclick: () => abrir(u.signedUrl) }));
        });
      }
      lista.append(el('div', { class: 'tarjeta' },
        el('div', { class: 'fila entre' }, el('strong', null, c.nombre), el('span', { class: 'tag ' + (k.estado === 'aprobado' ? 'verde' : k.estado === 'rechazado' ? 'rojo' : 'naranjo') }, k.estado)),
        el('div', { class: 'saldo-gigante', style: 'font-size:1.6em' }, pesos(k.monto)),
        el('div', { class: 'sutil' }, 'Transferencia del ' + fechaCorta(k.fecha) + ' · enviado ' + fechaHora(k.creado)),
        k.comentario ? el('p', { class: 'mt' }, '“' + k.comentario + '”') : null,
        k.motivo ? el('p', { class: 'rojo' }, 'Rechazado: ' + k.motivo) : null,
        k.foto_path ? foto : el('p', { class: 'sutil' }, 'Sin foto. Revisa tu cuenta bancaria antes de aprobar.'),
        k.estado === 'pendiente' ? el('div', { class: 'grid2 mt' },
          el('button', { class: 'btn peligro', type: 'button', onclick: () => revisar(k, false) }, 'Rechazar'),
          el('button', { class: 'btn verde', type: 'button', onclick: () => revisar(k, true) }, 'Aprobar')) : null));
    }
    pintar(el('div', { class: 'fila entre mb' }, el('h2', { style: 'margin:0' }, 'Comprobantes'),
      el('a', { class: 'btn chico', href: todos ? '#comprobantes' : '#comprobantes/todos' }, todos ? 'Solo pendientes' : 'Ver todos')),
    el('p', { class: 'sutil' }, 'Antes de aprobar, revisa que la plata haya llegado a tu cuenta.'), lista);
  }
  async function revisar(k, aprobar) {
    try {
      if (aprobar) {
        const m = await pedirTexto('Aprobar comprobante', 'Monto recibido', { valor: String(k.monto), inputmode: 'numeric', tipo: 'number', boton: 'Aprobar', clase: 'verde',
          ayuda: 'Corrígelo si llegó un monto distinto.', validar: (v) => V.monto(v) ? null : 'Monto inválido' });
        if (!m) return;
        await conCarga(() => rpc('revisar_comprobante', { p_id: k.id, p_aprobar: true, p_monto: V.monto(m), p_motivo: null }));
        toast('Aprobado ✓ Se registró el abono.');
      } else {
        const mot = el('select', null, ['No llegó la transferencia', 'El monto no coincide', 'La foto no se lee', 'Comprobante repetido', 'Otro'].map((t) => el('option', null, t)));
        const det = el('input', { maxlength: 60, placeholder: 'Detalle (opcional)' });
        const ok = await dialogo('Rechazar comprobante', el('div', null, el('div', { class: 'campo' }, el('label', null, 'Motivo (lo verá el cliente)'), mot), det),
          [{ texto: 'Cancelar', valor: null }, { texto: 'Rechazar', clase: 'rojo', valor: true }]);
        if (!ok) return;
        await conCarga(() => rpc('revisar_comprobante', { p_id: k.id, p_aprobar: false, p_monto: null, p_motivo: mot.value + (det.value ? ': ' + det.value : '') }));
        toast('Comprobante rechazado');
      }
      await Promise.all([cargarClientes(), refrescarEstado()]); router(true);
    } catch (e) { error(e); }
  }

  // ================= REPORTES =================
  let rango = 'mes';
  async function vReportes() {
    if (soloDueno()) return;
    const hoy = hoyISO(), [y, m] = hoy.split('-').map(Number);
    const ini = (yy, mm) => yy + '-' + String(mm).padStart(2, '0') + '-01';
    const finMes = (yy, mm) => new Date(Date.UTC(yy, mm, 0)).toISOString().slice(0, 10);
    const R = { mes: [ini(y, m), hoy, 'Este mes'], pasado: [ini(m === 1 ? y - 1 : y, m === 1 ? 12 : m - 1), finMes(m === 1 ? y - 1 : y, m === 1 ? 12 : m - 1), 'Mes pasado'],
      tres: [sumarDias(hoy, -90), hoy, '3 meses'], anio: [ini(y, 1), hoy, 'Este año'] };
    const [d, h] = R[rango];
    const r = await conCarga(() => rpc('reporte', { p_desde: d, p_hasta: h }));
    const max = Math.max(1, ...(r.por_dia || []).map((x) => Math.max(x.fiado || 0, x.cobrado || 0)));
    pintar(
      el('h2', null, 'Reportes'),
      el('div', { class: 'chips' }, Object.entries(R).map(([k, v]) => el('button', { class: 'chip' + (rango === k ? ' activo' : ''), type: 'button', onclick: () => {
        if (k !== 'mes' && !prem()) return alPlan('Los reportes de meses anteriores son Premium.');
        rango = k; vReportes();
      } }, v[2] + (k !== 'mes' && !prem() ? ' ⭐' : '')))),
      r.limitado ? el('div', { class: 'banda aviso' }, 'En el plan Normal ves solo el mes actual.') : null,
      el('div', { class: 'grid2 mb' },
        el('div', { class: 'kpi' }, el('div', { class: 't' }, 'Fiado'), el('div', { class: 'v rojo' }, pesos(r.fiado))),
        el('div', { class: 'kpi' }, el('div', { class: 't' }, 'Cobrado'), el('div', { class: 'v verde' }, pesos(r.cobrado))),
        el('div', { class: 'kpi' }, el('div', { class: 't' }, 'Atrasados hoy'), el('div', { class: 'v rojo' }, pesos(r.atrasados.monto)), el('div', { class: 't' }, r.atrasados.n + ' clientes')),
        el('div', { class: 'kpi' }, el('div', { class: 't' }, 'Cobrado por medio'), el('div', { class: 'sutil' }, Object.entries(r.por_medio || {}).map(([k, v]) => k + ': ' + pesos(v)).join(' · ') || '—'))),
      prem() && r.por_dia && r.por_dia.length ? el('div', { class: 'tarjeta' }, el('h3', null, 'Fiado vs cobrado por día'),
        el('div', { class: 'grafico', role: 'img', 'aria-label': 'Gráfico de fiado y cobrado por día' }, r.por_dia.map((x) => el('div', { title: fechaCorta(x.dia) + ': fiado ' + pesos(x.fiado || 0) + ', cobrado ' + pesos(x.cobrado || 0) },
          el('i', { class: 'f', style: 'height:' + Math.round((x.fiado || 0) * 100 / max) + 'px' }), el('i', { class: 'c', style: 'height:' + Math.round((x.cobrado || 0) * 100 / max) + 'px' })))),
        el('div', { class: 'sutil' }, '🟥 Fiado · 🟩 Cobrado')) : null,
      el('div', { class: 'dos-col' },
        el('div', null, el('h3', null, 'Mayores deudores'), el('div', { class: 'lista' }, r.mayores_deudores.length ? r.mayores_deudores.map((x) => el('div', { class: 'item', style: 'cursor:default' }, avatar(x.nombre), el('span', { class: 'crece nom' }, x.nombre), el('span', { class: 'monto rojo' }, pesos(x.saldo)))) : el('div', { class: 'vacio' }, 'Nadie te debe 🎉'))),
        el('div', null, el('h3', null, 'Mejores pagadores'), prem() ? el('div', { class: 'lista' }, (r.mejores_pagadores || []).length ? r.mejores_pagadores.map((x) => el('div', { class: 'item', style: 'cursor:default' }, avatar(x.nombre), el('span', { class: 'crece nom' }, x.nombre), el('span', { class: 'monto verde' }, pesos(x.pagado)))) : el('div', { class: 'vacio' }, 'Sin pagos en este período.'))
          : el('button', { class: 'btn ancho', type: 'button', onclick: () => alPlan('Los mejores pagadores y el gráfico diario son Premium.') }, '⭐ Ver con Premium'))),
      el('h3', { class: 'mt' }, 'Exportar'),
      el('div', { class: 'grid2' }, el('button', { class: 'btn', type: 'button', onclick: () => exportar('csv') }, '📄 CSV (todo)'),
        el('button', { class: 'btn', type: 'button', onclick: () => prem() ? exportar('excel') : alPlan('Exportar a Excel ordenado es Premium. El CSV es gratis.') }, '📗 Excel' + (prem() ? '' : ' ⭐'))));
  }

  async function exportar(tipo) {
    try {
      const d = await conCarga(() => rpc('exportar_datos'));
      const tipoTxt = (m) => m.tipo === 'cargo' ? 'Fiado' : m.tipo === 'abono' ? 'Abono' : 'Ajuste';
      const colsM = [{ t: 'Fecha', v: (m) => fechaHora(m.fecha) }, { t: 'Cliente', v: (m) => m.cliente }, { t: 'Tipo', v: tipoTxt }, { t: 'Monto', v: (m) => m.monto * m.signo },
        { t: 'Detalle', v: (m) => m.descripcion || '' }, { t: 'Medio', v: (m) => m.medio || '' }, { t: 'Vence', v: (m) => m.vence || '' }, { t: 'Confirmación', v: (m) => m.confirmacion || '' },
        { t: 'Anulado', v: (m) => m.anulado ? 'Sí: ' + (m.motivo_anulacion || '') : '' }];
      const colsC = [{ t: 'Nombre', v: (c) => c.nombre }, { t: 'Apodo', v: (c) => c.apodo || '' }, { t: 'Teléfono', v: (c) => c.telefono || '' }, { t: 'RUT', v: (c) => c.rut || '' },
        { t: 'Saldo', v: (c) => c.saldo }, { t: 'Próximo vencimiento', v: (c) => c.prox_venc || '' }, { t: 'Estado', v: (c) => c.estado }, { t: 'Nota', v: (c) => c.nota || '' }];
      const colsQ = [{ t: 'Cliente', v: (q) => q.cliente }, { t: 'Venta', v: (q) => q.venta }, { t: 'Cuota', v: (q) => q.numero }, { t: 'Monto', v: (q) => q.monto }, { t: 'Vence', v: (q) => q.vence }, { t: 'Pagado', v: (q) => q.pagado }, { t: 'Estado venta', v: (q) => q.estado_venta }];
      const base = 'libreta-' + norm(S.neg.nombre).replace(/[^a-z0-9]+/g, '-') + '-' + hoyISO();
      if (tipo === 'excel') LC.descargar(base + '.xls', LC.excel([{ nombre: 'Clientes', filas: d.clientes, columnas: colsC }, { nombre: 'Movimientos', filas: d.movimientos, columnas: colsM }, { nombre: 'Cuotas', filas: d.cuotas, columnas: colsQ }]));
      else { LC.descargar(base + '-movimientos.csv', LC.csv(d.movimientos, colsM)); setTimeout(() => LC.descargar(base + '-clientes.csv', LC.csv(d.clientes, colsC)), 600); }
      toast('Descarga lista ✓');
    } catch (e) { error(e); }
  }

  async function estadoCuentaPDF(c) {
    const { data: movs } = await sb.from('movimientos').select('*').eq('cliente', c.id).is('anulado_at', null).order('fecha');
    const w = window.open('', '_blank');
    if (!w) { toast('Permite las ventanas emergentes para generar el PDF', { error: true }); return; }
    const d = w.document;
    d.title = 'Estado de cuenta · ' + c.nombre;
    const st = d.createElement('style');
    st.textContent = 'body{font-family:system-ui,sans-serif;color:#111;margin:32px;font-size:13px}h1{font-size:20px;margin:0}table{width:100%;border-collapse:collapse;margin-top:16px}th,td{text-align:left;padding:6px;border-bottom:1px solid #ddd}td.n,th.n{text-align:right}.tot{font-size:22px;font-weight:800;margin-top:12px}.s{color:#555}';
    d.head.append(st);
    const E = (tag, txt, cls) => { const x = d.createElement(tag); if (txt != null) x.textContent = txt; if (cls) x.className = cls; return x; };
    let acum = 0;
    const tabla = E('table'); const thead = E('tr'); ['Fecha', 'Detalle', 'Cargo', 'Abono', 'Saldo'].forEach((t, i) => thead.append(E('th', t, i > 1 ? 'n' : null))); tabla.append(thead);
    for (const m of movs || []) {
      acum += m.monto * m.signo;
      const tr = E('tr');
      tr.append(E('td', fechaCorta(m.fecha)), E('td', m.descripcion || (m.tipo === 'cargo' ? 'Fiado' : m.tipo === 'abono' ? 'Abono' : 'Ajuste')),
        E('td', m.signo === 1 ? pesos(m.monto) : '', 'n'), E('td', m.signo === -1 ? pesos(m.monto) : '', 'n'), E('td', pesos(acum), 'n'));
      tabla.append(tr);
    }
    const b = S.neg.banco || {};
    d.body.append(E('h1', S.neg.nombre), E('div', 'Estado de cuenta al ' + fechaLarga(hoyISO()), 's'), E('h2', c.nombre),
      E('div', 'Saldo: ' + pesos(c.saldo), 'tot'), tabla,
      b.numero ? E('p', 'Para pagar: ' + [b.banco, b.tipo, 'N° ' + b.numero, b.rut ? 'RUT ' + V.rutBonito(b.rut) : '', b.titular, b.email].filter(Boolean).join(' · '), 's') : E('p', ''),
      E('p', 'Generado con Libreta de Cobros', 's'));
    setTimeout(() => w.print(), 300);
  }

  // ================= PRODUCTOS =================
  async function vProductos() {
    if (soloDueno()) return;
    await cargarProductos();
    const lim = S.st.limites.productos;
    const editar = async (p) => {
      const nom = el('input', { maxlength: 30, value: p ? p.nombre : '' }), pre = el('input', { type: 'number', inputmode: 'numeric', min: 1, value: p ? p.precio : '' });
      const ok = await dialogo(p ? 'Editar producto' : 'Nuevo producto', el('div', null, el('div', { class: 'campo' }, el('label', null, 'Nombre'), nom), el('div', { class: 'campo' }, el('label', null, 'Precio'), pre)),
        [{ texto: 'Cancelar', valor: null }, { texto: 'Guardar', clase: 'primario', valor: true }]);
      if (!ok) return;
      try { await conCarga(() => rpc('guardar_producto', { p_id: p ? p.id : null, p_nombre: nom.value, p_precio: V.monto(pre.value) })); vProductos(); } catch (e) { error(e); }
    };
    const mover = async (i, d) => { const ids = S.productos.map((p) => p.id); const j = i + d; if (j < 0 || j >= ids.length) return; [ids[i], ids[j]] = [ids[j], ids[i]]; try { await rpc('ordenar_productos', { p_ids: ids }); vProductos(); } catch (e) { error(e); } };
    pintar(el('div', { class: 'fila entre mb' }, el('h2', { style: 'margin:0' }, 'Productos frecuentes'), el('span', { class: 'tag' }, S.productos.length + ' de ' + lim)),
      el('p', { class: 'sutil' }, 'Aparecen como botones al anotar un fiado: tocas "Pan $1.500" y listo.'),
      el('div', { class: 'lista' }, S.productos.length ? S.productos.map((p, i) => el('div', { class: 'item', style: 'cursor:default' },
        el('div', { class: 'crece' }, el('div', { class: 'nom' }, p.nombre), el('div', { class: 'sub' }, pesos(p.precio))),
        el('button', { class: 'btn-icono', type: 'button', 'aria-label': 'Subir', onclick: () => mover(i, -1) }, '↑'),
        el('button', { class: 'btn-icono', type: 'button', 'aria-label': 'Editar', onclick: () => editar(p) }, '✏️'),
        el('button', { class: 'btn-icono', type: 'button', 'aria-label': 'Borrar', onclick: async () => { if (await confirmar('Borrar producto', '¿Borrar ' + p.nombre + '?', 'Borrar', 'rojo')) { await rpc('borrar_producto', { p_id: p.id }).catch(error); vProductos(); } } }, '🗑️')))
        : el('div', { class: 'vacio' }, 'Sin productos todavía.')),
      el('button', { class: 'btn primario ancho', type: 'button', onclick: () => editar(null) }, '＋ Agregar producto'));
  }

  // ================= AYUDANTES =================
  async function vAyudantes() {
    if (soloDueno()) return;
    if (!prem()) { pintar(el('h2', null, 'Ayudantes'), el('div', { class: 'tarjeta centro' }, el('p', null, 'Con Premium puedes sumar hasta 3 ayudantes que anotan y cobran desde su propio celular, sin ver tus reportes ni ajustes.'), el('button', { class: 'btn primario', type: 'button', onclick: () => alPlan('Los ayudantes son Premium.') }, '⭐ Hazte Premium'))); return; }
    const lista = await conCarga(() => rpc('ayudantes'));
    pintar(el('h2', null, 'Ayudantes'),
      el('p', { class: 'sutil' }, 'Pueden anotar fiados y abonos, ver clientes y cobrar. No ven reportes ni ajustes, no pasan límites de fiado y solo anulan lo suyo en 10 minutos.'),
      el('div', { class: 'lista' }, lista.length ? lista.map((a) => el('div', { class: 'item', style: 'cursor:default' }, avatar(a.nombre), el('div', { class: 'crece' }, el('div', { class: 'nom' }, a.nombre), el('div', { class: 'sub' }, a.email)),
        el('button', { class: 'btn peligro chico', type: 'button', onclick: async () => { if (await confirmar('Quitar ayudante', '¿Quitar a ' + a.nombre + '? Perderá el acceso al instante.', 'Quitar', 'rojo')) { try { await rpc('quitar_ayudante', { p_usuario: a.usuario }); vAyudantes(); } catch (e) { error(e); } } } }, 'Quitar')))
        : el('div', { class: 'vacio' }, 'Aún no tienes ayudantes.')),
      el('button', { class: 'btn primario ancho', type: 'button', disabled: lista.length >= S.st.limites.ayudantes, onclick: async () => {
        try {
          const cod = await conCarga(() => rpc('invitar_ayudante'));
          const url = RAIZ + '#invitacion=' + cod;
          await dialogo('Invitación lista', el('div', null, el('p', null, 'Envíale este link a tu ayudante. Sirve una sola vez y vence en 48 horas.'), el('div', { class: 'tarjeta plana', style: 'word-break:break-all' }, url),
            el('div', { class: 'col' }, el('button', { class: 'btn wsp', type: 'button', onclick: () => abrir('https://wa.me/?text=' + encodeURIComponent('Te invito a ayudarme en mi libreta de ' + S.neg.nombre + ': ' + url)) }, '💬 Enviar por WhatsApp'),
              el('button', { class: 'btn', type: 'button', onclick: () => copiar(url) }, '📋 Copiar link'))));
        } catch (e) { error(e); }
      } }, '＋ Invitar ayudante (' + lista.length + ' de ' + S.st.limites.ayudantes + ')'));
  }

  // ================= AJUSTES =================
  const BANCOS = ['BancoEstado', 'Banco de Chile', 'Santander', 'BCI', 'Scotiabank', 'Itaú', 'Banco Falabella', 'Banco Ripley', 'Security', 'BICE', 'Consorcio', 'Internacional', 'Coopeuch', 'Mercado Pago', 'Tenpo', 'MACH', 'Prepago Los Héroes', 'Otro'];
  const COLORES_MARCA = ['#059669', '#2563eb', '#7c3aed', '#db2777', '#ea580c', '#0d9488', '#4f46e5', '#334155'];
  async function vAjustes() {
    if (soloDueno()) return;
    const n = S.neg, b = n.banco || {};
    const f = {
      nombre: el('input', { maxlength: 50, value: n.nombre }), rubro: el('select', null, [['almacen', 'Almacén'], ['feria', 'Feria'], ['catalogo', 'Catálogo'], ['emprendimiento', 'Emprendimiento'], ['servicios', 'Servicios'], ['educacion', 'Educación'], ['club', 'Club'], ['personal', 'Personal'], ['otro', 'Otro']].map(([v, t]) => el('option', { value: v, selected: v === n.rubro }, t))),
      whatsapp: el('input', { type: 'tel', inputmode: 'tel', value: V.telBonito(n.whatsapp), placeholder: '+56 9 1234 5678' }),
      banco: el('select', null, el('option', { value: '' }, 'Elige tu banco'), BANCOS.map((x) => el('option', { selected: x === b.banco }, x))),
      tipo: el('select', null, el('option', { value: '' }, 'Tipo de cuenta'), ['Cuenta Corriente', 'Cuenta Vista / RUT', 'Cuenta de Ahorro'].map((x) => el('option', { selected: x === b.tipo }, x))),
      numero: el('input', { inputmode: 'numeric', value: b.numero || '', maxlength: 20 }), rut: el('input', { value: b.rut ? V.rutBonito(b.rut) : '', placeholder: '12.345.678-5' }),
      titular: el('input', { maxlength: 60, value: b.titular || '' }), email: el('input', { type: 'email', value: b.email || '', inputmode: 'email' }),
      venc: el('select', null, [['0', 'El mismo día'], ['7', '7 días'], ['15', '15 días'], ['30', '30 días'], ['fin', 'Fin de mes']].map(([v, t]) => el('option', { value: v, selected: v === n.venc_defecto }, t))),
      limite: el('input', { type: 'number', inputmode: 'numeric', min: 0, max: 5000000, value: n.limite_general || '' }),
      pin: el('input', { type: 'checkbox', id: 'pinAct', checked: n.pin_activo }), favor: el('input', { type: 'checkbox', id: 'favor', checked: n.saldo_a_favor }),
      plantilla: el('textarea', { maxlength: 500, placeholder: 'Hola {nombre}, tu saldo en {negocio} es {saldo}. Detalle: {link}' }),
    };
    f.plantilla.value = n.plantilla_propia || '';
    let color = n.color || COLORES_MARCA[0], logo = n.logo_url || '';
    const colores = el('div', { class: 'fila envolver' });
    const pintarColores = () => { vaciar(colores); COLORES_MARCA.forEach((x) => colores.append(el('button', { type: 'button', 'aria-label': 'Color ' + x, onclick: () => { color = x; pintarColores(); }, style: 'width:40px;height:40px;border-radius:50%;border:3px solid ' + (x === color ? 'var(--texto)' : 'transparent') + ';background:' + x + ';cursor:pointer' }))); };
    pintarColores();
    const logoImg = el('div', { class: 'logo-mini', style: 'width:60px;height:60px' }); const pintarLogo = () => { vaciar(logoImg).append(logo ? el('img', { src: logo, alt: 'Logo' }) : iniciales(n.nombre)); }; pintarLogo();
    const logoIn = el('input', { type: 'file', accept: 'image/*', class: 'oculto' });
    logoIn.onchange = async () => {
      try {
        const blob = await LC.achicarImagen(logoIn.files[0], 256, 90 * 1024);
        const ruta = n.id + '/logo-' + Date.now() + (blob.type === 'image/webp' ? '.webp' : '.jpg');
        const { error: e } = await conCarga(() => sb.storage.from('logos').upload(ruta, blob, { contentType: blob.type, upsert: true }));
        if (e) throw e;
        logo = sb.storage.from('logos').getPublicUrl(ruta).data.publicUrl; pintarLogo(); toast('Logo listo. Toca Guardar.');
      } catch (e) { error(e); }
    };
    const err = el('div', { class: 'error' });
    const campo = (t, i, a) => el('div', { class: 'campo' }, el('label', null, t), i, a ? el('div', { class: 'ayuda' }, a) : null);
    const premiumBloque = prem() ? el('div', { class: 'tarjeta' }, el('h2', null, '⭐ Apariencia y mensaje propio'),
      el('div', { class: 'fila' }, logoImg, el('button', { class: 'btn chico', type: 'button', onclick: () => logoIn.click() }, 'Cambiar logo'), logo ? el('button', { class: 'btn texto chico', type: 'button', onclick: () => { logo = ''; pintarLogo(); } }, 'Quitar') : null, logoIn),
      el('label', { class: 'mt' }, 'Color'), colores,
      campo('Tu mensaje de cobro', f.plantilla, 'Usa {nombre}, {negocio}, {saldo}, {fecha} y {link}. No se aceptan amenazas (lo prohíbe la ley).'))
      : el('div', { class: 'tarjeta' }, el('h2', null, '⭐ Logo, color y mensaje propio'), el('p', { class: 'sutil' }, 'Con Premium tu link de cliente lleva tu logo y tus colores, y puedes escribir tu propio mensaje de cobro.'), el('button', { class: 'btn', type: 'button', onclick: () => alPlan('La apariencia personalizada es Premium.') }, 'Ver Premium'));
    pintar(el('h2', null, 'Ajustes del negocio'),
      el('div', { class: 'dos-col' },
        el('div', null,
          el('div', { class: 'tarjeta' }, el('h2', null, 'Tu negocio'), campo('Nombre', f.nombre), campo('Rubro', f.rubro), campo('WhatsApp del negocio', f.whatsapp, 'Tus clientes te escriben aquí desde su link.')),
          el('div', { class: 'tarjeta' }, el('h2', null, 'Datos para que te transfieran'), el('p', { class: 'sutil' }, 'Tus clientes los ven en su link con un botón para copiar.'),
            campo('Banco', f.banco), campo('Tipo de cuenta', f.tipo), campo('Número de cuenta', f.numero), campo('RUT del titular', f.rut), campo('Nombre del titular', f.titular), campo('Correo para avisar la transferencia', f.email))),
        el('div', null,
          el('div', { class: 'tarjeta' }, el('h2', null, 'Reglas de fiado'), campo('Vencimiento por defecto', f.venc), campo('Límite de fiado general', f.limite, '0 o vacío = sin límite. Te avisa al pasarlo; los ayudantes no pueden pasarlo.'),
            el('label', { class: 'check', for: 'pinAct' }, f.pin, el('span', null, 'Pedir PIN en el link del cliente ', el('span', { class: 'sutil' }, '(recomendado por privacidad)'))),
            el('label', { class: 'check', for: 'favor' }, f.favor, el('span', null, 'Permitir saldo a favor (abonos mayores a la deuda)'))),
          premiumBloque)),
      err,
      el('button', { class: 'btn primario ancho', type: 'button', onclick: async () => {
        err.textContent = '';
        try {
          if (!f.pin.checked && n.pin_activo && !await confirmar('¿Quitar el PIN?', 'Cualquiera que tenga el link podrá ver la cuenta de tu cliente. ¿Seguro?', 'Quitar PIN', 'rojo')) return;
          const datos = { nombre: f.nombre.value, rubro: f.rubro.value, whatsapp: V.telefono(f.whatsapp.value),
            banco: { banco: f.banco.value || null, tipo: f.tipo.value || null, numero: f.numero.value.replace(/\D/g, '') || null, rut: V.rut(f.rut.value), titular: f.titular.value || null, email: f.email.value.trim() || null },
            venc_defecto: f.venc.value, limite_general: f.limite.value ? Math.round(Number(f.limite.value)) : 0, pin_activo: f.pin.checked, saldo_a_favor: f.favor.checked,
            logo_url: logo || null, color: prem() ? color : null, plantilla_propia: f.plantilla.value || null };
          if (datos.banco.email && !V.email(datos.banco.email)) throw new Error('Correo de transferencia inválido');
          if (prem() && datos.plantilla_propia && V.prohibida(datos.plantilla_propia)) throw new Error('El mensaje no puede contener "' + V.prohibida(datos.plantilla_propia) + '"');
          await conCarga(() => rpc('guardar_negocio', { p: datos }));
          await refrescarEstado(); toast('Guardado ✓');
        } catch (e) { err.textContent = LC.traducir(e).message; }
      } }, 'Guardar'),
      el('div', { class: 'tarjeta mt' }, el('h2', null, 'Tus datos'), el('p', { class: 'sutil' }, 'Descarga todo lo que tienes en la libreta (es tu derecho, en cualquier plan).'),
        el('button', { class: 'btn ancho', type: 'button', onclick: () => exportar('csv') }, '📄 Exportar todo (CSV)')));
  }

  // ================= PLAN =================
  async function vPlan() {
    if (soloDueno()) return;
    await refrescarEstado().catch(() => {});
    const st = S.st, pl = st.plan, cfg = st.config, u = st.uso, l = st.limites, ln = cfg.lim_normal;
    const barra = (t, usado, max) => { const pct = max ? Math.min(100, Math.round(usado * 100 / max)) : 0; return el('div', { class: 'mb' }, el('div', { class: 'fila entre' }, el('span', null, t), el('strong', null, max ? usado + ' / ' + max : usado + ' · ilimitado')), max ? el('div', { class: 'barra ' + (pct >= 100 ? 'lleno' : pct >= 80 ? 'alerta' : '') }, el('i', { style: 'width:' + pct + '%' })) : null); };
    const tr = cfg.transferencia || {};
    pintar(el('h2', null, 'Mi plan'),
      el('div', { class: 'tarjeta ' + (pl.premium ? 'hero' : '') },
        el('div', { class: 't' }, 'Plan actual'), el('div', { class: 'grande', style: 'font-size:1.8em' }, pl.premium ? (pl.en_prueba ? 'Premium (prueba)' : 'Premium ⭐') : 'Normal'),
        pl.hasta && pl.premium ? el('div', { class: 't' }, (pl.en_gracia ? 'Venció el ' : 'Hasta el ') + fechaLarga(pl.hasta)) : null,
        pl.pago_pendiente ? el('div', { class: 'tag naranjo mt' }, '⏳ Pago en revisión') : null),
      el('div', { class: 'tarjeta' }, el('h2', null, 'Uso este mes'),
        barra('Clientes activos', u.clientes, l.clientes), barra('Movimientos', u.movimientos, l.movimientos), barra('Ventas en cuotas activas', u.cuotas, l.cuotas),
        barra('Comprobantes recibidos', u.comprobantes, l.comprobantes), barra('Productos frecuentes', u.productos, l.productos)),
      el('div', { class: 'tarjeta' }, el('h2', null, pl.premium ? 'Renovar Premium' : 'Hazte Premium'),
        el('p', null, el('strong', { style: 'font-size:1.4em' }, pesos(cfg.precio_mensual)), ' al mes · o ', el('strong', null, pesos(cfg.precio_anual)), ' al año (2 meses gratis)'),
        el('ul', { class: 'sutil' }, el('li', null, 'Sin límite de clientes (Normal: ' + ln.clientes + '), movimientos (' + ln.movimientos + ') ni cuotas (' + ln.cuotas + ')'),
          el('li', null, 'Avisos automáticos a tus clientes y resumen diario al celular'), el('li', null, 'Puntaje de buen pagador y límite por cliente'),
          el('li', null, 'Reportes históricos, Excel y estado de cuenta en PDF'), el('li', null, 'Hasta 3 ayudantes, tu logo y tus colores')),
        el('div', { class: 'col' },
          cfg.link_pago ? el('button', { class: 'btn primario', type: 'button', onclick: () => abrir(cfg.link_pago) }, '💳 Pagar en línea') : null,
          tr.numero ? el('details', null, el('summary', { class: 'btn ancho' }, '🏦 Pagar por transferencia'),
            el('div', { class: 'tarjeta plana mt' }, [['Banco', tr.banco], ['Tipo', tr.tipo], ['Número', tr.numero], ['RUT', tr.rut], ['Nombre', tr.titular], ['Correo', tr.email]].filter((x) => x[1]).map(([k, v]) => el('div', { class: 'copiar-fila' }, el('div', { class: 'crece' }, el('div', { class: 'k' }, k), el('div', { class: 'v' }, v)), el('button', { class: 'btn chico', type: 'button', onclick: () => copiar(String(v)) }, 'Copiar'))))) : null,
          el('button', { class: 'btn', type: 'button', disabled: pl.pago_pendiente, onclick: yaPague }, '✅ Ya pagué'),
          el('button', { class: 'btn texto', type: 'button', onclick: usarKey }, '🔑 Tengo una key'),
          cfg.contacto_whatsapp ? el('button', { class: 'btn texto', type: 'button', onclick: () => abrir(wa(cfg.contacto_whatsapp, 'Hola, tengo una consulta sobre Premium de Libreta de Cobros (' + S.neg.nombre + ').')) }, '💬 Consultar por WhatsApp') : null)),
      el('p', { class: 'sutil' }, 'Si no renuevas, tu libreta pasa a Normal: no se borra nada y siempre puedes registrar abonos y cobrar.'));
  }
  async function yaPague() {
    const meses = el('select', null, el('option', { value: 1 }, 'Mensual · ' + pesos(S.st.config.precio_mensual)), el('option', { value: 12 }, 'Anual · ' + pesos(S.st.config.precio_anual)));
    const foto = el('input', { type: 'file', accept: 'image/*' }); const nota = el('input', { maxlength: 200, placeholder: 'Ej: transferí desde la cuenta de mi esposa' });
    const ok = await dialogo('Avisar pago', el('div', null, el('div', { class: 'campo' }, el('label', null, 'Plan'), meses), el('div', { class: 'campo' }, el('label', null, 'Comprobante (opcional)'), foto), el('div', { class: 'campo' }, el('label', null, 'Nota'), nota)),
      [{ texto: 'Cancelar', valor: null }, { texto: 'Enviar', clase: 'primario', valor: true }]);
    if (!ok) return;
    try {
      let ruta = null;
      if (foto.files[0]) {
        const blob = await LC.achicarImagen(foto.files[0], 1280, 300 * 1024);
        ruta = S.neg.id + '/' + uuid() + (blob.type === 'image/webp' ? '.webp' : '.jpg');
        const { error: e } = await conCarga(() => sb.storage.from('pagos').upload(ruta, blob, { contentType: blob.type }));
        if (e) throw e;
      }
      await conCarga(() => rpc('solicitar_pago', { p_meses: Number(meses.value), p_path: ruta, p_nota: nota.value }));
      toast('¡Gracias! Te avisaremos apenas se apruebe.'); vPlan();
    } catch (e) { error(e); }
  }
  async function usarKey() {
    const k = await pedirTexto('Usar key', 'Tu key', { placeholder: 'LC-XXXX-XXXX-XXXX', max: 20 });
    if (!k) return;
    try { const r = await conCarga(() => rpc('usar_key', { p_codigo: k })); toast('¡Premium activo hasta el ' + fechaLarga(r.hasta) + '! 🎉'); await cargarClientes(); vPlan(); } catch (e) { error(e); }
  }

  // ================= AVISOS =================
  async function vAvisos() {
    const { data } = await sb.from('notificaciones').select('*').order('creado', { ascending: false }).limit(60);
    rpc('marcar_leidas').then(() => refrescarEstado()).catch(() => {});
    pintar(el('h2', null, 'Avisos'), el('div', { class: 'lista' }, (data || []).length ? data.map((n) => el('a', { class: 'item', href: (n.url || '').replace(/^app\//, '') || '#inicio' },
      el('span', null, n.leido ? '•' : '🔵'), el('div', { class: 'crece' }, el('div', { class: 'nom', style: 'white-space:normal' }, n.titulo), n.cuerpo ? el('div', { class: 'sub', style: 'white-space:normal' }, n.cuerpo) : null),
      el('span', { class: 'sutil' }, fechaCorta(n.creado)))) : el('div', { class: 'vacio' }, el('span', { class: 'ico' }, '🔔'), 'Sin avisos.')));
  }

  // ================= PENDIENTES (cola) =================
  function vPendientes() {
    const c = cola();
    pintar(el('h2', null, 'Por subir'), el('p', { class: 'sutil' }, 'Movimientos anotados sin internet. Se suben solos al volver la conexión.'),
      el('div', { class: 'lista' }, c.length ? c.map((m) => el('div', { class: 'item', style: 'cursor:default' }, el('div', { class: 'crece' },
        el('div', { class: 'nom' }, (cliente(m.cliente) || {}).nombre || 'Cliente', ' · ', (m.tipo === 'cargo' ? '+' : '−') + pesos(m.monto)),
        el('div', { class: 'sub ' + (m.error ? 'rojo' : '') }, m.error || fechaHora(m.fecha))),
        m.limite && esDueno() ? el('button', { class: 'btn chico', type: 'button', onclick: () => { guardarCola(cola().map((x) => x.id === m.id ? { ...x, error: null, limite: false, forzar: true } : x)); sincronizar(); vPendientes(); } }, 'Anotar igual') : null,
        m.error && !m.limite ? el('button', { class: 'btn chico', type: 'button', onclick: () => { guardarCola(cola().map((x) => x.id === m.id ? { ...x, error: null } : x)); sincronizar(); vPendientes(); } }, 'Reintentar') : null,
        el('button', { class: 'btn-icono', type: 'button', 'aria-label': 'Descartar', onclick: async () => { if (await confirmar('Descartar', '¿Descartar este movimiento? No se anotará.', 'Descartar', 'rojo')) { guardarCola(cola().filter((x) => x.id !== m.id)); vPendientes(); } } }, '🗑️')))
        : el('div', { class: 'vacio' }, '✓ Todo está subido.')),
      c.length ? el('button', { class: 'btn primario ancho', type: 'button', onclick: sincronizar }, 'Subir ahora') : null);
  }

  // ================= MI CUENTA =================
  async function vCuenta() {
    const sub = await LC.pushActual().catch(() => null);
    const tema = local.get('lc-tema', 'auto');
    const tieneBloqueo = !!local.get('lc-bloqueo-' + S.uid, null);
    pintar(el('h2', null, 'Mi cuenta'),
      el('div', { class: 'tarjeta' }, dato('Correo', S.email), dato('Rol', esDueno() ? 'Dueño' : 'Ayudante'), dato('Libreta', S.neg.nombre)),
      el('div', { class: 'lista' },
        el('button', { class: 'item', type: 'button', onclick: async () => {
          try {
            if (sub) { await rpc('borrar_push', { p_endpoint: sub.endpoint }); await sub.unsubscribe(); toast('Notificaciones desactivadas'); }
            else { const s = await LC.suscribirPush(S.st.config.vapid_public); await rpc('guardar_push', { p_endpoint: s.endpoint, p_p256dh: s.keys.p256dh, p_auth: s.keys.auth }); toast('Notificaciones activadas ✓'); }
            vCuenta();
          } catch (e) { error(e); }
        } }, el('span', { class: 'crece' }, '🔔 Notificaciones en este celular'), el('span', { class: 'tag ' + (sub ? 'verde' : '') }, sub ? 'Activas' : 'Apagadas')),
        el('button', { class: 'item', type: 'button', onclick: cambiarClave }, el('span', { class: 'crece' }, '🔑 Cambiar contraseña'), el('span', { class: 'sutil' }, '›')),
        el('button', { class: 'item', type: 'button', onclick: async () => {
          if (tieneBloqueo) { local.del('lc-bloqueo-' + S.uid); toast('Bloqueo con PIN quitado'); return vCuenta(); }
          const p = await pedirTexto('PIN para abrir la app', 'PIN de 4 números (solo en este celular)', { inputmode: 'numeric', max: 4, validar: (v) => /^\d{4}$/.test(v) ? null : 'Deben ser 4 números' });
          if (!p) return; local.set('lc-bloqueo-' + S.uid, await sha(p)); toast('Bloqueo activado ✓'); vCuenta();
        } }, el('span', { class: 'crece' }, '🔒 Bloquear la app con PIN'), el('span', { class: 'tag ' + (tieneBloqueo ? 'verde' : '') }, tieneBloqueo ? 'Activo' : 'No')),
        el('button', { class: 'item', type: 'button', onclick: () => { const g = !document.documentElement.classList.contains('grande'); document.documentElement.classList.toggle('grande', g); local.set('lc-letra-grande', g); vCuenta(); } },
          el('span', { class: 'crece' }, '🔠 Letra más grande'), el('span', { class: 'tag' }, document.documentElement.classList.contains('grande') ? 'Sí' : 'No')),
        el('button', { class: 'item', type: 'button', onclick: () => { const sig = { auto: 'light', light: 'dark', dark: 'auto' }[tema]; local.set('lc-tema', sig); aplicarTema(); vCuenta(); } },
          el('span', { class: 'crece' }, '🌓 Tema'), el('span', { class: 'tag' }, { auto: 'Automático', light: 'Claro', dark: 'Oscuro' }[tema])),
        !LC.instalada() ? el('button', { class: 'item', type: 'button', onclick: () => LC.instalar() }, el('span', { class: 'crece' }, '📲 Instalar la app'), el('span', { class: 'sutil' }, '›')) : null),
      el('div', { class: 'lista' },
        el('button', { class: 'item', type: 'button', onclick: salir }, el('span', { class: 'crece' }, '🚪 Cerrar sesión')),
        el('button', { class: 'item', type: 'button', onclick: borrarCuenta }, el('span', { class: 'crece rojo' }, esDueno() ? '🗑️ Borrar mi cuenta y libreta' : '🗑️ Borrar mi cuenta de ayudante'))));
  }
  async function cambiarClave() {
    const a = el('input', { type: 'password', autocomplete: 'new-password' }), b = el('input', { type: 'password', autocomplete: 'new-password' }), err = el('div', { class: 'error' });
    await dialogo('Cambiar contraseña', el('div', null, el('div', { class: 'campo' }, el('label', null, 'Nueva'), a), el('div', { class: 'campo' }, el('label', null, 'Repítela'), b), err),
      [{ texto: 'Cancelar', valor: null }, { texto: 'Guardar', clase: 'primario', valor: true, antes: async () => {
        const m = V.clave(a.value, S.email); if (m) { err.textContent = m; return false; }
        if (a.value !== b.value) { err.textContent = 'No coinciden'; return false; }
        const { error: e } = await sb.auth.updateUser({ password: a.value }); if (e) { err.textContent = LC.traducir(e).message; return false; }
        toast('Contraseña cambiada ✓'); return true;
      } }]);
  }
  async function salir() {
    if (cola().length && !await confirmar('Hay movimientos sin subir', 'Si cierras sesión ahora se perderán ' + cola().length + ' movimientos. Conéctate a internet para subirlos primero.', 'Cerrar igual', 'rojo')) return;
    const s = await LC.pushActual().catch(() => null);
    if (s) await rpc('borrar_push', { p_endpoint: s.endpoint }).catch(() => {});
    ['lc-cola-', 'lc-clientes-', 'lc-estado-', 'lc-tablero-', 'lc-bloqueo-'].forEach((k) => local.del(k + S.uid));
    await sb.auth.signOut().catch(() => {});
    location.replace('../');
  }
  async function borrarCuenta() {
    if (esDueno()) {
      const conf = await pedirTexto('Borrar mi cuenta', 'Escribe "' + S.neg.nombre + '" para confirmar', { boton: 'Borrar', clase: 'rojo', ayuda: 'Tu libreta se borrará para siempre en 30 días. Antes de eso puedes recuperarla ingresando de nuevo. Te recomendamos exportar tus datos primero.' });
      if (!conf) return;
      try { await conCarga(() => rpc('borrar_mi_cuenta', { p_confirmacion: conf })); await sb.auth.signOut(); location.replace('../'); } catch (e) { error(e); }
    } else {
      if (!await confirmar('Borrar mi cuenta', 'Dejarás de ser ayudante y tu cuenta se borrará ahora.', 'Borrar', 'rojo')) return;
      try { await conCarga(() => rpc('borrar_mi_cuenta', { p_confirmacion: '' })); await sb.auth.signOut(); location.replace('../'); } catch (e) { error(e); }
    }
  }
  function aplicarTema() { const t = local.get('lc-tema', 'auto'); if (t === 'auto') document.documentElement.removeAttribute('data-theme'); else document.documentElement.setAttribute('data-theme', t); }
  aplicarTema();

  // ================= AYUDA =================
  function vAyuda() {
    const cfg = (S.st && S.st.config) || {};
    const p = (q, r) => el('details', { class: 'tarjeta' }, el('summary', { style: 'font-weight:700;cursor:pointer' }, q), el('p', { class: 'mt sutil' }, r));
    pintar(el('h2', null, 'Ayuda'),
      p('¿Cómo anoto un fiado?', 'Toca ＋ Anotar, elige el cliente, escribe el monto con el teclado (o toca un producto frecuente) y Guardar. Si te equivocas, toca "Deshacer" en los próximos segundos.'),
      p('¿Cómo ve su cuenta mi cliente?', 'En su ficha toca 🔗 Link y envíaselo por WhatsApp. Entra con un PIN de 4 números (los últimos de su teléfono). Ahí ve su saldo, sus cuotas y tus datos para transferir, y te sube el comprobante.'),
      p('¿Por qué no me deja cobrar ahora?', 'La ley chilena de cobranza (Ley 19.496) permite cobrar de lunes a sábado entre 08:00 y 20:00, sin feriados, máximo 2 veces por semana y con 2 días entre cada mensaje. La app lo controla por ti.'),
      p('¿Qué pasa si no tengo internet?', 'Puedes anotar fiados y abonos igual. Quedan "por subir" y se envían solos cuando vuelve la conexión, sin duplicarse.'),
      p('¿Puedo corregir un error?', 'Nada se borra: toca el movimiento y elige "Anular" con un motivo. Queda tachado y se recalcula el saldo. Así nadie puede cambiar una deuda sin dejar rastro.'),
      p('¿Qué es "solo cobro"?', 'Un cliente al que ya no le fías: puedes registrar sus abonos y cobrarle, pero no anotarle más deuda.'),
      p('¿Cómo instalo la app?', 'Android/computador: menú del navegador → Instalar app. iPhone: botón Compartir → Agregar a inicio.'),
      el('div', { class: 'col' },
        cfg.contacto_whatsapp ? el('button', { class: 'btn wsp', type: 'button', onclick: () => abrir(wa(cfg.contacto_whatsapp, 'Hola, necesito ayuda con Libreta de Cobros.')) }, '💬 Escribir a soporte') : null,
        el('a', { class: 'btn', href: '../legal/#terminos' }, 'Términos y privacidad')),
      el('p', { class: 'sutil centro mt' }, 'Versión ' + LC.VERSION));
  }

  arrancar().catch(error);
})();
