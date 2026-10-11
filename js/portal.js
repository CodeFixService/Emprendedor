/* Link del cliente: entra con código + PIN (sin cuenta). Ve su saldo, cuotas y datos para pagar; confirma cargos y sube comprobantes. */
(function () {
  'use strict';
  const { el, $, vaciar, rpc, error, toast, conCarga, dialogo, pesos, fechaCorta, fechaLarga, fechaHora, hoyISO, sumarDias, relativo, local, copiar, wa, abrir, V } = LC;
  const raiz = $('#portal');
  LC.registrarSW();
  const guardado = local.get('lc-portal', null);
  const codigo = (location.hash.slice(1) || (guardado && guardado.codigo) || '').replace(/[^A-Za-z0-9]/g, '');
  let sesion = guardado && guardado.codigo === codigo ? guardado.sesion : null;
  let D = null;
  LC.alSesion = () => { sesion = null; local.del('lc-portal'); pedirPin(); };

  const pintar = (...n) => { vaciar(raiz).append(...n.flat().filter((x) => x != null && x !== false)); window.scrollTo(0, 0); };
  function marcaColor(c) { if (c) { document.documentElement.style.setProperty('--marca', c); document.documentElement.style.setProperty('--marca-2', c); } }
  function cabecera(nombre, logo) {
    return el('div', { class: 'fila mb' }, el('div', { class: 'logo-mini', style: 'width:44px;height:44px' }, logo ? el('img', { src: logo, alt: '' }) : LC.iniciales(nombre)),
      el('div', { class: 'crece' }, el('div', { class: 'sutil' }, 'Tu cuenta en'), el('strong', { style: 'font-size:1.15em' }, nombre)));
  }

  async function iniciar() {
    if (!codigo) return pintar(el('div', { class: 'tarjeta centro' }, el('h1', null, 'Link incompleto'), el('p', null, 'Abre el link completo que te envió el negocio por WhatsApp.')));
    if (sesion) { try { return await cargar(); } catch (e) { if (e.pista !== 'SESION') return pintarError(e); sesion = null; } }
    pedirPin();
  }
  function pintarError(e) {
    pintar(el('div', { class: 'tarjeta centro' }, el('h1', null, 'No pudimos abrir tu cuenta'), el('p', null, LC.traducir(e).message),
      el('button', { class: 'btn primario', type: 'button', onclick: iniciar }, 'Reintentar')));
  }

  async function pedirPin() {
    let info;
    try { info = await rpc('portal_info', { p_codigo: codigo }); } catch (e) { return pintarError(e); }
    if (!info.ok) return pintar(el('div', { class: 'tarjeta centro' }, el('div', { style: 'font-size:2.5em' }, '🔗'), el('h1', null, 'Este link no es válido'),
      el('p', null, 'Puede que el negocio haya generado uno nuevo. Pídele que te lo envíe otra vez.')));
    marcaColor(info.color);
    if (info.bloqueado) return pintar(cabecera(info.negocio, info.logo_url), el('div', { class: 'tarjeta centro' }, el('h1', null, 'Link bloqueado'), el('p', null, 'Por seguridad este link se bloqueó. Pídele a ' + info.negocio + ' uno nuevo.')));
    if (!info.pin) return entrar('');
    let pin = '';
    const puntos = el('div', { class: 'pin' }, [0, 1, 2, 3].map(() => el('span')));
    const msg = el('p', { class: 'centro sutil' }, 'Ingresa tu PIN de 4 números. Si no lo sabes, son los últimos 4 dígitos de tu teléfono.');
    const repintar = () => [...puntos.children].forEach((s, i) => s.classList.toggle('lleno', i < pin.length));
    const tecla = async (k) => {
      if (k === '⌫') pin = pin.slice(0, -1); else if (pin.length < 4) pin += k;
      repintar();
      if (pin.length === 4) {
        const p = pin; pin = '';
        const r = await entrar(p);
        if (r) { msg.textContent = r; msg.className = 'centro rojo'; repintar(); }
      }
    };
    pintar(cabecera(info.negocio, info.logo_url), el('div', { class: 'tarjeta' }, el('h1', { class: 'centro' }, '🔒 Tu PIN'), msg, puntos,
      el('div', { class: 'teclado', style: 'max-width:320px;margin:0 auto' }, ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '⌫'].map((k) => k ? el('button', { type: 'button', onclick: () => tecla(k), 'aria-label': k === '⌫' ? 'Borrar' : k }, k) : el('span')))),
    el('p', { class: 'sutil centro' }, '🔐 Solo tú ves esta cuenta. ', el('a', { href: '../legal/#cliente' }, 'Privacidad')));
  }
  async function entrar(pin) {
    try {
      const r = await conCarga(() => rpc('portal_entrar', { p_codigo: codigo, p_pin: pin }));
      if (!r.ok) return r.error;
      sesion = r.sesion; local.set('lc-portal', { codigo, sesion });
      if (location.hash.slice(1) !== codigo) history.replaceState(null, '', '#' + codigo);
      await cargar();
      return null;
    } catch (e) { return LC.traducir(e).message; }
  }

  async function cargar() {
    D = await rpc('portal_ver', { p_sesion: sesion });
    marcaColor(D.negocio.color);
    document.title = 'Mi cuenta · ' + D.negocio.nombre;
    vista();
  }

  function vista() {
    const n = D.negocio, c = D.cliente;
    const porConfirmar = D.movimientos.filter((m) => m.tipo === 'cargo' && m.confirmacion === 'pendiente' && !m.anulado);
    const cuotasProx = D.cuotas.filter((v) => v.estado === 'activa').flatMap((v) => v.cuotas.filter((q) => q.pagado < q.monto).map((q) => ({ ...q, venta: v.descripcion }))).sort((a, b) => a.vence < b.vence ? -1 : 1);
    const prox = cuotasProx[0];
    pintar(
      cabecera(n.nombre, n.logo_url),
      el('div', { class: 'tarjeta centro' },
        el('div', { class: 'sutil' }, c.saldo > 0 ? 'Debes' : c.saldo < 0 ? 'Saldo a tu favor' : 'Tu cuenta'),
        el('div', { class: 'saldo-gigante ' + (c.saldo > 0 ? 'rojo' : 'verde') }, c.saldo > 0 ? pesos(c.saldo) : c.saldo < 0 ? pesos(-c.saldo) : '¡Al día! ✓'),
        c.saldo > 0 && c.prox_venc ? el('div', { class: c.atrasado ? 'rojo' : 'sutil' }, (c.atrasado ? 'Vencido desde el ' : 'Próximo vencimiento: ') + fechaLarga(c.prox_venc)) : null,
        prox ? el('div', { class: 'tag marca mt' }, 'Próxima cuota: ' + pesos(prox.monto - prox.pagado) + ' el ' + fechaCorta(prox.vence)) : null),
      c.saldo > 0 ? el('div', { class: 'col mb' },
        el('button', { class: 'btn primario', type: 'button', onclick: pagar }, '💸 Pagar por transferencia'),
        el('button', { class: 'btn', type: 'button', onclick: subirComprobante }, '📤 Ya pagué: enviar comprobante')) : null,
      n.whatsapp ? el('button', { class: 'btn wsp ancho mb', type: 'button', onclick: () => abrir(wa(n.whatsapp, 'Hola ' + n.nombre + ', soy ' + c.nombre + '. ')) }, '💬 Escribir a ' + n.nombre) : null,
      porConfirmar.length ? el('div', { class: 'tarjeta', style: 'border-color:var(--aviso)' }, el('h2', null, '¿Reconoces estos cargos?'),
        el('p', { class: 'sutil' }, 'Confírmalos para que tu cuenta quede clara. Si alguno no es tuyo, avísale al negocio.'),
        porConfirmar.map((m) => el('div', { class: 'copiar-fila' }, el('div', { class: 'crece' }, el('div', { class: 'v' }, pesos(m.monto) + ' · ' + (m.descripcion || 'Fiado')), el('div', { class: 'k' }, fechaHora(m.fecha))),
          el('button', { class: 'btn chico verde', type: 'button', onclick: () => confirmarCargo(m, true) }, 'Sí'),
          el('button', { class: 'btn chico peligro', type: 'button', onclick: () => confirmarCargo(m, false) }, 'No')))) : null,
      D.comprobantes.length ? el('div', { class: 'tarjeta' }, el('h2', null, 'Tus comprobantes'), D.comprobantes.slice(0, 5).map((k) => el('div', { class: 'copiar-fila' },
        el('div', { class: 'crece' }, el('div', { class: 'v' }, pesos(k.monto) + ' · ' + fechaCorta(k.fecha)), k.motivo ? el('div', { class: 'k rojo' }, k.motivo) : null),
        el('span', { class: 'tag ' + (k.estado === 'aprobado' ? 'verde' : k.estado === 'rechazado' ? 'rojo' : 'naranjo') }, k.estado === 'pendiente' ? 'En revisión' : k.estado)))) : null,
      D.cuotas.length ? el('div', { class: 'tarjeta' }, el('h2', null, 'Tus cuotas'), D.cuotas.map((v) => el('div', { class: 'mb' }, el('strong', null, v.descripcion), el('div', { class: 'sutil' }, pesos(v.total) + (v.pie ? ' · pie ' + pesos(v.pie) : '')),
        (v.cuotas || []).map((q) => { const pag = q.pagado >= q.monto, atr = !pag && q.vence < hoyISO();
          return el('div', { class: 'copiar-fila' }, el('div', { class: 'crece' }, el('div', { class: 'v' }, 'Cuota ' + q.numero + ' · ' + pesos(q.monto)), el('div', { class: 'k' }, 'Vence ' + fechaCorta(q.vence) + (q.pagado && !pag ? ' · pagado ' + pesos(q.pagado) : ''))),
            el('span', { class: 'tag ' + (pag ? 'verde' : atr ? 'rojo' : '') }, pag ? 'Pagada' : atr ? 'Atrasada' : 'Pendiente')); })))) : null,
      el('div', { class: 'tarjeta' }, el('h2', null, 'Movimientos'), D.movimientos.length ? D.movimientos.map((m) => el('div', { class: 'copiar-fila', style: m.anulado ? 'opacity:.5' : '' },
        el('div', { class: 'crece' }, el('div', { class: 'v', style: m.anulado ? 'text-decoration:line-through' : '' }, (m.signo === 1 ? 'Cargo ' : 'Pago ') + pesos(m.monto)),
          el('div', { class: 'k' }, fechaHora(m.fecha) + ' · ' + (m.descripcion || (m.tipo === 'abono' ? 'Abono' : 'Fiado'))),
          m.anulado ? el('div', { class: 'k' }, 'Anulado' + (m.motivo_anulacion ? ': ' + m.motivo_anulacion : '')) : null,
          m.confirmacion === 'reclamado' ? el('div', { class: 'k rojo' }, 'Tu reclamo: ' + (m.reclamo_motivo || '') + (m.respuesta ? ' · Respuesta: ' + m.respuesta : ' · Esperando respuesta')) : null),
        el('strong', { class: m.signo === 1 ? 'rojo' : 'verde' }, (m.signo === 1 ? '+' : '−') + pesos(m.monto)))) : el('p', { class: 'sutil' }, 'Sin movimientos.')),
      el('div', { class: 'lista' },
        el('button', { class: 'item', type: 'button', onclick: avisarme }, el('span', { class: 'crece' }, '🔔 Avisarme de mis pagos y cuotas'), el('span', { class: 'sutil' }, '›')),
        !LC.instalada() ? el('button', { class: 'item', type: 'button', onclick: () => LC.instalar() }, el('span', { class: 'crece' }, '📲 Guardar en mi celular'), el('span', { class: 'sutil' }, '›')) : null,
        el('button', { class: 'item', type: 'button', onclick: salir }, el('span', { class: 'crece' }, '🚪 Salir'))),
      el('p', { class: 'sutil centro' }, '🔐 Tus datos los guarda ', n.nombre, ' para llevar tu cuenta. ', el('a', { href: '../legal/#cliente' }, 'Privacidad y tus derechos')),
      n.marca ? el('div', { class: 'tarjeta centro', style: 'margin-top:20px' }, el('div', { class: 'sutil' }, 'Hecho con'), el('strong', null, 'Libreta de Cobros'),
        el('p', { class: 'sutil' }, '¿Tienes negocio? Anota tus fiados y cobra fácil.'), el('a', { class: 'btn chico primario', href: '../#crear' }, 'Crea tu libreta gratis')) : null);
  }

  async function pagar() {
    const b = D.negocio.banco || {};
    if (!b.numero) {
      await dialogo('Datos para transferir', el('p', null, D.negocio.nombre + ' aún no registra sus datos bancarios. Escríbele para pedírselos.'));
      return;
    }
    const filas = [['Banco', b.banco], ['Tipo de cuenta', b.tipo], ['Número', b.numero], ['RUT', b.rut ? V.rutBonito(b.rut) : null], ['Nombre', b.titular], ['Correo', b.email], ['Monto', pesos(D.cliente.saldo)]].filter((x) => x[1]);
    const todo = filas.map(([k, v]) => k + ': ' + v).join('\n');
    const r = await dialogo('Datos para transferir', el('div', null, filas.map(([k, v]) => el('div', { class: 'copiar-fila' }, el('div', { class: 'crece' }, el('div', { class: 'k' }, k), el('div', { class: 'v' }, v)),
      el('button', { class: 'btn chico', type: 'button', onclick: () => copiar(k === 'Monto' ? String(D.cliente.saldo) : k === 'RUT' ? b.rut : String(v)) }, 'Copiar'))),
      el('button', { class: 'btn ancho mt', type: 'button', onclick: () => copiar(todo, 'Datos copiados ✓ Pégalos en tu app del banco') }, '📋 Copiar todo'),
      el('p', { class: 'sutil mt' }, 'Después de transferir, toca "Ya pagué" y envía el comprobante.')),
    [{ texto: 'Cerrar', valor: null }, { texto: 'Ya pagué', clase: 'primario', valor: 1 }]);
    if (r) subirComprobante();
  }

  async function subirComprobante() {
    const monto = el('input', { type: 'number', inputmode: 'numeric', min: 1, value: D.cliente.saldo > 0 ? D.cliente.saldo : '' });
    const fecha = el('input', { type: 'date', max: hoyISO(), min: sumarDias(hoyISO(), -30), value: hoyISO() });
    const foto = el('input', { type: 'file', accept: 'image/*' });
    const com = el('input', { maxlength: 100, placeholder: 'Opcional' });
    const err = el('div', { class: 'error' });
    const campo = (t, i, a) => el('div', { class: 'campo' }, el('label', null, t), i, a ? el('div', { class: 'ayuda' }, a) : null);
    await dialogo('Enviar comprobante', el('div', null, campo('Monto que transferiste', monto), campo('Fecha de la transferencia', fecha),
      campo('Foto o captura del comprobante', foto, 'Recomendado: así el negocio lo aprueba más rápido.'), campo('Comentario', com), err),
    [{ texto: 'Cancelar', valor: null }, { texto: 'Enviar', clase: 'primario', valor: true, antes: async () => {
      err.textContent = '';
      const m = V.monto(monto.value);
      if (!m) { err.textContent = 'Escribe el monto'; return false; }
      try {
        let blob = null;
        if (foto.files[0]) blob = await LC.achicarImagen(foto.files[0], 1280, 300 * 1024);
        const r = await conCarga(() => rpc('portal_comprobante', { p_sesion: sesion, p_monto: m, p_fecha: fecha.value, p_comentario: com.value, p_con_foto: !!blob }));
        if (blob && r.foto_token) {
          const data = await LC.blobADataURL(blob);
          const f = await conCarga(() => LC.funcion({ accion: 'foto', id: r.id, token: r.foto_token, data })).catch((e) => ({ ok: false, error: e.message }));
          if (!f.ok) toast('El comprobante se envió, pero la foto no: ' + (f.error || 'error') + '. Mándasela por WhatsApp.', { error: true, ms: 7000 });
        }
        toast('¡Enviado! ' + D.negocio.nombre + ' lo revisará pronto.');
        return true;
      } catch (e) { err.textContent = LC.traducir(e).message; return false; }
    } }]);
    cargar().catch(error);
  }

  async function confirmarCargo(m, reconoce) {
    let motivo = null;
    if (!reconoce) {
      motivo = await LC.pedirTexto('No reconozco este cargo', 'Cuéntale al negocio qué pasó', { min: 5, max: 150, multilinea: true, placeholder: 'Ej: ese día no compré nada', boton: 'Enviar reclamo' });
      if (!motivo) return;
    }
    try { await conCarga(() => rpc('portal_confirmar', { p_sesion: sesion, p_mov: m.id, p_reconoce: reconoce, p_motivo: motivo })); toast(reconoce ? 'Gracias por confirmar ✓' : 'Reclamo enviado. El negocio te responderá.'); await cargar(); } catch (e) { error(e); }
  }

  async function avisarme() {
    try {
      const s = await LC.suscribirPush(D.vapid_public);
      await conCarga(() => rpc('portal_push', { p_sesion: sesion, p_endpoint: s.endpoint, p_p256dh: s.keys.p256dh, p_auth: s.keys.auth }));
      toast('Listo ✓ Te avisaremos de tus pagos y cuotas.');
    } catch (e) { error(e); }
  }

  async function salir() {
    await rpc('portal_salir', { p_sesion: sesion }).catch(() => {});
    local.del('lc-portal'); sesion = null; pedirPin();
  }

  window.addEventListener('hashchange', () => location.reload());
  document.addEventListener('visibilitychange', () => { if (!document.hidden && sesion && D) cargar().catch(() => {}); });
  iniciar();
})();
