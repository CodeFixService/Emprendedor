/* Portada, crear cuenta, ingresar, recuperar contraseña e invitaciones de ayudante. */
(function () {
  'use strict';
  const { el, $, vaciar, rpc, sb, V, error, toast, conCarga, local, RAIZ } = LC;
  const cuenta = $('#cuenta'), portada = $('#portada');
  $('#ver').textContent = LC.VERSION;
  LC.registrarSW();

  const RUBROS = [['almacen', 'Almacén / negocio de barrio'], ['feria', 'Feria / puesto'], ['catalogo', 'Venta por catálogo'],
    ['emprendimiento', 'Emprendimiento / Instagram'], ['servicios', 'Servicios (gásfiter, taller, etc.)'], ['educacion', 'Clases / colegio'],
    ['club', 'Club / agrupación'], ['personal', 'Uso personal'], ['otro', 'Otro']];

  rpc('config_publica').then((c) => {
    if (!c) return;
    $('#precioPremium').textContent = LC.pesos(c.precio_mensual) + '/mes';
    $('#precioActivacion').textContent = c.precio_activacion > 0 ? 'Activación ' + LC.pesos(c.precio_activacion) + ' (una vez)' : 'Sin costo de activación';
    // Textos y beneficios editables desde Administración → Ajustes
    if (c.textos && c.textos.landing_titulo) document.querySelector('.lp-hero h1').textContent = c.textos.landing_titulo;
    if (c.textos && c.textos.landing_bajada) document.querySelector('.lp-hero .bajada').textContent = c.textos.landing_bajada;
    if (c.planes && c.planes.pro && Array.isArray(c.planes.pro.beneficios) && c.planes.pro.beneficios.length) {
      const ul = vaciar($('#listaPro')); c.planes.pro.beneficios.forEach((t) => ul.append(el('li', null, String(t).replace(/^\S+\s/, (m) => /[A-Za-zÁÉÍÓÚáéíóúÑñ0-9]/.test(m) ? m : ''))));
    }
    $('#diasPrueba').textContent = c.dias_prueba;
    $('#txtPrueba').textContent = c.dias_prueba > 0 ? c.dias_prueba + ' días de Pro gratis' : 'Gratis para siempre';
    const l = c.lim_normal || {};
    const ul = vaciar($('#listaNormal'));
    [(l.caja || 300) + ' ventas y gastos al mes', l.clientes + ' clientes y ' + l.movimientos + ' fiados/abonos al mes', l.cuotas + ' ventas en cuotas',
      'Link del cliente con PIN', 'Cobro por WhatsApp'].forEach((t) => ul.append(el('li', null, t)));
  }).catch(() => {});

  document.addEventListener('click', (e) => { const b = e.target.closest('[data-ir]'); if (b) location.hash = b.dataset.ir; });
  $('#bInstalarTop').onclick = () => LC.instalar();
  $('#bSalirTop').onclick = () => salir();
  // Animación al aparecer en pantalla y contador del celular de ejemplo
  if ('IntersectionObserver' in window) {
    const obs = new IntersectionObserver((es) => es.forEach((x) => { if (x.isIntersecting) { x.target.classList.add('visto'); obs.unobserve(x.target); } }), { threshold: 0.12 });
    document.querySelectorAll('.aparece').forEach((n) => obs.observe(n));
  } else document.querySelectorAll('.aparece').forEach((n) => n.classList.add('visto'));
  (function contar() {
    const n = $('#contador'); if (!n) return;
    const fin = 184300, t0 = performance.now(), dur = matchMedia('(prefers-reduced-motion: reduce)').matches ? 1 : 1400;
    const paso = (t) => { const k = Math.min(1, (t - t0) / dur); n.textContent = LC.pesos(Math.round(fin * (1 - Math.pow(1 - k, 3)))); if (k < 1) requestAnimationFrame(paso); };
    requestAnimationFrame(paso);
  })();

  function campo(etq, input, ayuda) { return el('div', { class: 'campo' }, el('label', { for: input.id }, etq), input, ayuda ? el('div', { class: 'ayuda' }, ayuda) : null); }
  function mostrar(...nodos) {
    portada.classList.add('oculto'); cuenta.classList.remove('oculto'); vaciar(cuenta);
    cuenta.append(el('div', { class: 'fila mb' }, el('button', { class: 'btn-icono', type: 'button', 'aria-label': 'Volver', onclick: () => { location.hash = ''; } }, '←'),
      el('div', { class: 'logo-mini' }, 'LC'), el('strong', null, 'Libreta de Cobros')), ...nodos);
    window.scrollTo(0, 0);
  }
  function verPortada() { cuenta.classList.add('oculto'); portada.classList.remove('oculto'); }
  function cabeceraSesion(conSesion) { $('#topSinSesion').classList.toggle('oculto', conSesion); $('#topConSesion').classList.toggle('oculto', !conSesion); }
  const errorEn = (form, msg) => { const e = form.querySelector('.error.general'); e.textContent = msg; };

  // ---------- Ingresar ----------
  function pantallaIngresar() {
    const email = el('input', { id: 'email', type: 'email', autocomplete: 'email', required: true, inputmode: 'email' });
    const clave = el('input', { id: 'clave', type: 'password', autocomplete: 'current-password', required: true });
    const form = el('form', { class: 'tarjeta', novalidate: true },
      el('h1', null, 'Ingresar'), campo('Correo', email), campo('Contraseña', clave),
      el('div', { class: 'error general' }),
      el('button', { class: 'btn primario ancho', type: 'submit' }, 'Ingresar'),
      el('div', { class: 'fila entre mt' }, el('a', { href: '#recuperar' }, '¿Olvidaste tu contraseña?'), el('a', { href: '#crear' }, 'Crear cuenta')));
    let fallos = 0;
    form.onsubmit = async (e) => {
      e.preventDefault();
      if (fallos >= 5) return errorEn(form, 'Demasiados intentos. Espera 30 segundos.');
      if (!V.email(email.value)) return errorEn(form, 'Escribe un correo válido');
      try {
        await conCarga(async () => {
          const { error: er } = await sb.auth.signInWithPassword({ email: email.value.trim().toLowerCase(), password: clave.value });
          if (er) throw LC.traducir(er);
        });
        await despuesDeEntrar();
      } catch (er) {
        fallos++; if (fallos >= 5) setTimeout(() => { fallos = 0; }, 30000);
        errorEn(form, LC.traducir(er).message);
      }
    };
    mostrar(form);
  }

  // ---------- Crear cuenta ----------
  function pantallaCrear(invitacion) {
    const nombre = el('input', { id: 'nombre', maxlength: invitacion ? 40 : 50, autocomplete: invitacion ? 'name' : 'organization', required: true });
    const rubro = el('select', { id: 'rubro' }, RUBROS.map(([v, t]) => el('option', { value: v }, t)));
    const email = el('input', { id: 'email', type: 'email', autocomplete: 'email', inputmode: 'email', required: true });
    const clave = el('input', { id: 'clave', type: 'password', autocomplete: 'new-password', required: true, minlength: 8 });
    const fuerza = el('div', { class: 'barra mt', style: 'height:6px' }, el('i', { style: 'width:0' }));
    clave.oninput = () => { const p = clave.value; let s = 0; if (p.length >= 8) s++; if (p.length >= 12) s++; if (/\d/.test(p) && /[a-zA-Z]/.test(p)) s++; if (/[^a-zA-Z0-9]/.test(p)) s++; fuerza.firstChild.style.width = (s * 25) + '%'; fuerza.className = 'barra mt ' + (s < 2 ? 'lleno' : s < 3 ? 'alerta' : ''); };
    const acepta = el('input', { type: 'checkbox', id: 'acepta' });
    const form = el('form', { class: 'tarjeta', novalidate: true },
      el('h1', null, invitacion ? 'Únete como ayudante' : 'Crea tu libreta'),
      el('p', { class: 'sutil' }, invitacion ? 'Te invitaron a ayudar en una libreta. Crea tu cuenta con tu correo.' : 'Gratis para siempre, con días de Pro de regalo. Sin tarjeta.'),
      campo(invitacion ? 'Tu nombre' : 'Nombre de tu negocio', nombre), invitacion ? null : campo('Rubro', rubro),
      campo('Tu correo', email), campo('Contraseña', clave, 'Mínimo 8 caracteres, con letras y números.'), fuerza,
      el('label', { class: 'check mt', for: 'acepta' }, acepta, el('span', null, 'Acepto los ', el('a', { href: 'legal/#terminos', target: '_blank' }, 'Términos'), ' y la ', el('a', { href: 'legal/#privacidad', target: '_blank' }, 'Política de privacidad'), '.')),
      el('div', { class: 'error general' }),
      el('button', { class: 'btn primario ancho', type: 'submit' }, invitacion ? 'Crear cuenta y unirme' : 'Crear mi libreta'),
      el('p', { class: 'centro mt' }, el('a', { href: invitacion ? '#ingresar' : '#ingresar' }, 'Ya tengo cuenta')));
    form.onsubmit = async (e) => {
      e.preventDefault();
      const n = nombre.value.trim().replace(/\s+/g, ' ');
      if (n.length < 2) return errorEn(form, invitacion ? 'Escribe tu nombre' : 'El nombre del negocio debe tener entre 2 y 50 letras');
      const em = email.value.trim().toLowerCase();
      if (!V.email(em)) return errorEn(form, 'Escribe un correo válido');
      if (V.desechable(em)) return errorEn(form, 'Usa un correo real (no temporal)');
      const m = V.clave(clave.value, em); if (m) return errorEn(form, m);
      if (!acepta.checked) return errorEn(form, 'Debes aceptar los Términos y la Privacidad');
      try {
        const { data, error: er } = await conCarga(() => sb.auth.signUp({ email: em, password: clave.value, options: { data: { nombre: n }, emailRedirectTo: RAIZ } }));
        if (er) throw er;
        if (data.user && data.user.identities && data.user.identities.length === 0) throw new LC.ErrorApp('Ese correo ya tiene cuenta. Ingresa o recupera tu contraseña.');
        local.set('lc-pendiente', invitacion ? { tipo: 'ayudante', codigo: invitacion, nombre: n } : { tipo: 'negocio', nombre: n, rubro: rubro.value });
        if (!data.session) {
          mostrar(el('div', { class: 'tarjeta centro' }, el('div', { style: 'font-size:2.5em' }, '📩'), el('h1', null, 'Revisa tu correo'),
            el('p', null, 'Te enviamos un link a ' + em + ' para confirmar tu cuenta. Después vuelve aquí e ingresa.'),
            el('a', { class: 'btn primario', href: '#ingresar' }, 'Ir a ingresar')));
          return;
        }
        await despuesDeEntrar();
      } catch (er) { errorEn(form, LC.traducir(er).message); }
    };
    mostrar(form);
  }

  // ---------- Recuperar contraseña ----------
  function pantallaRecuperar() {
    const email = el('input', { id: 'email', type: 'email', autocomplete: 'email', inputmode: 'email' });
    const form = el('form', { class: 'tarjeta', novalidate: true }, el('h1', null, 'Recuperar contraseña'),
      el('p', { class: 'sutil' }, 'Te enviaremos un link para crear una contraseña nueva.'), campo('Tu correo', email),
      el('div', { class: 'error general' }), el('button', { class: 'btn primario ancho', type: 'submit' }, 'Enviar link'));
    form.onsubmit = async (e) => {
      e.preventDefault();
      if (!V.email(email.value)) return errorEn(form, 'Escribe un correo válido');
      try {
        const { error: er } = await conCarga(() => sb.auth.resetPasswordForEmail(email.value.trim().toLowerCase(), { redirectTo: RAIZ }));
        if (er) throw er;
        mostrar(el('div', { class: 'tarjeta centro' }, el('div', { style: 'font-size:2.5em' }, '📩'), el('h1', null, 'Revisa tu correo'),
          el('p', null, 'Si ' + email.value.trim() + ' tiene cuenta, te llegará un link en unos minutos (mira también en Spam).')));
      } catch (er) { errorEn(form, LC.traducir(er).message); }
    };
    mostrar(form);
  }

  function pantallaNuevaClave() {
    const clave = el('input', { id: 'clave', type: 'password', autocomplete: 'new-password' });
    const clave2 = el('input', { id: 'clave2', type: 'password', autocomplete: 'new-password' });
    const form = el('form', { class: 'tarjeta', novalidate: true }, el('h1', null, 'Nueva contraseña'),
      campo('Contraseña nueva', clave, 'Mínimo 8 caracteres, con letras y números.'), campo('Repítela', clave2),
      el('div', { class: 'error general' }), el('button', { class: 'btn primario ancho', type: 'submit' }, 'Guardar'));
    form.onsubmit = async (e) => {
      e.preventDefault();
      const m = V.clave(clave.value); if (m) return errorEn(form, m);
      if (clave.value !== clave2.value) return errorEn(form, 'Las contraseñas no coinciden');
      try {
        const { error: er } = await conCarga(() => sb.auth.updateUser({ password: clave.value }));
        if (er) throw er;
        toast('Contraseña actualizada ✓');
        await despuesDeEntrar();
      } catch (er) { errorEn(form, LC.traducir(er).message); }
    };
    mostrar(form);
  }

  // ---------- Después de entrar: ¿a dónde va? ----------
  async function despuesDeEntrar() {
    let st;
    try { st = await conCarga(() => rpc('mi_estado')); } catch (e) { error(e); return; }
    const pend = local.get('lc-pendiente', null);
    const inv = (location.hash.match(/invitacion=([A-Za-z0-9]+)/) || [])[1] || (pend && pend.tipo === 'ayudante' && pend.codigo);
    if (st.negocio) { local.del('lc-pendiente'); location.replace('app/'); return; }
    if (inv) return pantallaAceptar(inv, pend && pend.nombre);
    if (st.eliminado) return pantallaRecuperarCuenta(st);
    if (st.ayudante_pausado) {
      return mostrar(el('div', { class: 'tarjeta' }, el('h1', null, 'Libreta en pausa'),
        el('p', null, 'Eres ayudante de una libreta que ya no tiene Premium. Pídele al dueño que renueve para volver a entrar.'),
        el('button', { class: 'btn ancho', type: 'button', onclick: salir }, 'Cerrar sesión')));
    }
    if (pend && pend.tipo === 'negocio' && pend.nombre) {
      try {
        const r = await conCarga(() => rpc('crear_negocio', { p_nombre: pend.nombre, p_rubro: pend.rubro || 'otro', p_acepta: true }));
        local.del('lc-pendiente'); local.set('lc-bienvenida', true);
        local.set('lc-msg', r.prueba ? '¡Listo! Tienes ' + r.dias + ' días de Pro gratis 🎉' : 'Tu billetera está lista (plan Free) 🎉');
        location.replace('app/'); return;
      } catch (e) { /* si falla, se muestra el formulario con el error */ error(e); }
    }
    if (st.es_admin && !pend) { location.replace('admin/'); return; }
    return pantallaNegocio(pend && pend.tipo === 'negocio' ? pend : null, st);
  }

  function pantallaNegocio(pend, st) {
    const nombre = el('input', { id: 'nombre', maxlength: 50 }); nombre.value = pend ? pend.nombre : '';
    const rubro = el('select', { id: 'rubro' }, RUBROS.map(([v, t]) => el('option', { value: v }, t))); if (pend) rubro.value = pend.rubro;
    const acepta = el('input', { type: 'checkbox', id: 'acepta', checked: !!pend });
    const form = el('form', { class: 'tarjeta', novalidate: true }, el('h1', null, 'Tu negocio'),
      campo('Nombre del negocio', nombre), campo('Rubro', rubro),
      el('label', { class: 'check', for: 'acepta' }, acepta, el('span', null, 'Acepto los ', el('a', { href: 'legal/#terminos', target: '_blank' }, 'Términos'), ' y la ', el('a', { href: 'legal/#privacidad', target: '_blank' }, 'Privacidad'), '.')),
      el('div', { class: 'error general' }), el('button', { class: 'btn primario ancho', type: 'submit' }, 'Crear mi libreta'),
      st && st.es_admin ? el('a', { class: 'btn texto ancho mt', href: 'admin/' }, 'Ir al panel de administración') : null,
      el('button', { class: 'btn texto ancho', type: 'button', onclick: salir }, 'Cerrar sesión'));
    form.onsubmit = async (e) => {
      e.preventDefault();
      if (nombre.value.trim().length < 2) return errorEn(form, 'El nombre debe tener entre 2 y 50 letras');
      if (!acepta.checked) return errorEn(form, 'Debes aceptar los Términos y la Privacidad');
      try {
        const r = await conCarga(() => rpc('crear_negocio', { p_nombre: nombre.value, p_rubro: rubro.value, p_acepta: true }));
        local.del('lc-pendiente'); local.set('lc-bienvenida', true);
        local.set('lc-msg', r.prueba ? '¡Listo! Tienes ' + r.dias + ' días de Pro gratis 🎉' : 'Tu billetera está lista (plan Free) 🎉');
        location.replace('app/');
      } catch (er) { errorEn(form, LC.traducir(er).message); }
    };
    mostrar(form);
  }

  function pantallaAceptar(codigo, nombrePrevio) {
    const nombre = el('input', { id: 'nombre', maxlength: 40 }); nombre.value = nombrePrevio || '';
    const form = el('form', { class: 'tarjeta', novalidate: true }, el('h1', null, 'Unirte como ayudante'),
      el('p', null, 'Vas a poder anotar fiados y abonos y cobrar en la libreta que te invitó.'), campo('Tu nombre', nombre),
      el('div', { class: 'error general' }), el('button', { class: 'btn primario ancho', type: 'submit' }, 'Unirme'),
      el('button', { class: 'btn texto ancho', type: 'button', onclick: salir }, 'Usar otra cuenta'));
    form.onsubmit = async (e) => {
      e.preventDefault();
      try {
        await conCarga(() => rpc('aceptar_invitacion', { p_codigo: codigo, p_nombre: nombre.value }));
        local.del('lc-pendiente'); location.replace('app/');
      } catch (er) { errorEn(form, LC.traducir(er).message); }
    };
    mostrar(form);
  }

  function pantallaRecuperarCuenta(st) {
    mostrar(el('div', { class: 'tarjeta' }, el('h1', null, 'Tu cuenta está por borrarse'),
      el('p', null, 'Pediste borrar tu libreta. Se borrará para siempre el ' + LC.fechaLarga(st.eliminar_desde) + '. ¿Quieres recuperarla?'),
      el('button', { class: 'btn primario ancho', type: 'button', onclick: async () => {
        try { await conCarga(() => rpc('recuperar_mi_cuenta')); location.replace('app/'); } catch (e) { error(e); }
      } }, 'Recuperar mi libreta'),
      el('button', { class: 'btn texto ancho', type: 'button', onclick: salir }, 'Cerrar sesión')));
  }

  async function salir() { await sb.auth.signOut().catch(() => {}); local.del('lc-pendiente'); cabeceraSesion(false); location.hash = ''; verPortada(); toast('Sesión cerrada'); }

  // ---------- Rutas ----------
  let recuperando = false;
  sb.auth.onAuthStateChange((ev) => { if (ev === 'PASSWORD_RECOVERY') { recuperando = true; pantallaNuevaClave(); } });
  async function ruta() {
    if (recuperando) return;
    const h = location.hash.slice(1);
    const inv = (h.match(/invitacion=([A-Za-z0-9]+)/) || [])[1];
    const { data } = await sb.auth.getSession();
    if (h.includes('type=recovery')) return; // lo maneja onAuthStateChange
    if (inv) { if (data.session) return pantallaAceptar(inv); local.set('lc-pendiente', { tipo: 'ayudante', codigo: inv }); return pantallaCrear(inv); }
    if (h === 'ingresar') return data.session ? despuesDeEntrar() : pantallaIngresar();
    if (h === 'crear') return data.session ? despuesDeEntrar() : pantallaCrear();
    if (h === 'recuperar') return pantallaRecuperar();
    if (data.session && (LC.instalada() || h === 'app')) return despuesDeEntrar();
    cabeceraSesion(!!data.session);
    if (data.session) portada.querySelectorAll('.lp-cta [data-ir="ingresar"]').forEach((b) => { b.textContent = 'Abrir mi billetera'; });
    verPortada();
  }
  window.addEventListener('hashchange', ruta);
  ruta();
})();
