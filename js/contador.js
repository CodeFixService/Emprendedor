/* Billetera · G94 🧮 Link para el contador: solo lectura de la caja del mes (ventas, gastos, fiado y abonos) + planilla CSV.
   Sin cuenta: entra con ?t=<token> que crea el dueño (Más → 🧮 Link para el contador). No muestra nombres de clientes. */
(function () {
  'use strict';
  const { el, rpc, pesos, vaciar } = window.LC;
  const z = document.getElementById('contador');
  const t = new URLSearchParams(location.search).get('t') || '';
  const ahora = new Date(), mesHoy = ahora.getFullYear() + '-' + String(ahora.getMonth() + 1).padStart(2, '0');
  let mes = mesHoy, D = null;
  const nombreMes = (m) => new Date(m + '-15T12:00:00').toLocaleDateString('es-CL', { month: 'long', year: 'numeric' });
  const mover = (k) => { const d = new Date(mes + '-15T12:00:00'); d.setMonth(d.getMonth() + k); mes = d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0'); cargar(); };
  function csv() {
    const c = (s) => '"' + String(s == null ? '' : s).replace(/"/g, '""') + '"';
    const txt = 'fecha,tipo,categoria,descripcion,medio,monto\n' + D.filas.map((f) => [f.fecha, f.tipo, f.categoria, f.descripcion, f.medio, f.monto].map(c).join(',')).join('\n');
    const u = URL.createObjectURL(new Blob(['﻿' + txt], { type: 'text/csv;charset=utf-8' })), a = document.createElement('a');
    a.href = u; a.download = 'caja-' + D.mes + '.csv'; a.click(); setTimeout(() => URL.revokeObjectURL(u), 3000);
  }
  async function cargar() {
    try { D = await rpc('contador_ver', { p_token: t, p_mes: mes }); }
    catch (e) { vaciar(z).append(el('div', { class: 'vacio' }, '🔒 ' + ((window.LC.traducir ? window.LC.traducir(e) : e).message || 'Link no válido'))); return; }
    const ing = D.caja.filter((x) => x.tipo === 'ingreso'), gas = D.caja.filter((x) => x.tipo === 'gasto');
    const tI = ing.reduce((a, x) => a + +x.total, 0), tG = gas.reduce((a, x) => a + +x.total, 0);
    const lista = (L) => L.length ? L.map((x) => el('div', { class: 'copiar-fila' }, el('div', { class: 'crece' }, el('div', { class: 'v' }, x.categoria), el('div', { class: 'k' }, x.n + (x.n === 1 ? ' registro' : ' registros'))), el('strong', null, pesos(x.total)))) : el('p', { class: 'sutil' }, 'Sin registros');
    vaciar(z).append(
      el('h1', { style: 'margin:0 0 4px' }, '🧮 ' + D.negocio), el('p', { class: 'sutil' }, 'Caja del mes · solo lectura'),
      el('div', { class: 'fila entre mb' }, el('button', { class: 'btn chico', type: 'button', id: 'mesAnt', onclick: () => mover(-1) }, '‹'), el('strong', { id: 'mesTxt', style: 'text-transform:capitalize' }, nombreMes(D.mes)),
        el('button', { class: 'btn chico', type: 'button', id: 'mesSig', disabled: mes >= mesHoy, onclick: () => mover(1) }, '›')),
      el('div', { class: 'tarjeta centro' }, el('div', { class: 'sutil' }, 'Balance (ingresos − gastos)'), el('div', { class: 'saldo-gigante ' + (tI - tG >= 0 ? 'verde' : 'rojo'), id: 'balance' }, pesos(tI - tG)),
        el('div', { class: 'sutil' }, 'Ingresos ' + pesos(tI) + ' · Gastos ' + pesos(tG))),
      el('div', { class: 'tarjeta' }, el('h2', null, '💰 Ingresos'), lista(ing)),
      el('div', { class: 'tarjeta' }, el('h2', null, '💸 Gastos'), lista(gas)),
      el('div', { class: 'tarjeta' }, el('h2', null, '📒 Fiado'), el('p', null, 'Fiado del mes: ' + pesos(D.fiado)), el('p', null, 'Abonos recibidos: ' + pesos(D.abonos)), el('p', null, 'Total por cobrar hoy: ' + pesos(D.por_cobrar))),
      el('button', { class: 'btn primario ancho', type: 'button', id: 'bajarCsv', onclick: csv, disabled: !D.filas.length }, '⬇️ Planilla para Excel (' + D.filas.length + ')'));
  }
  cargar();
})();
