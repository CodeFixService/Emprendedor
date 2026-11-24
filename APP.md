# APP.md

(Mapa completo pendiente: G42j.)

- G95 (1.21.82 · bd 56): la billetera parte FREE (crear_negocio sin prueba) · 🎁 Probar Pro (núcleo) → cfx_pro_prueba_app = prueba_hasta (estado 'prueba') · privado.pruebas_usadas → cfx_pruebas_usadas · 🐞 cfx_negocio_dueno_app (el dueño ya puede probar/comprar módulos) · landing: "Partes gratis". Prueba: SaaS/pruebas/g95.js.
- G99 a (1.21.86 · bd 60 · enviar 1.4.1): ⚡ aviso instantáneo de Mercado Pago (núcleo): cfx_mp_aviso_url_app = privado.config url_proyecto + /functions/v1/enviar · enviar atiende ?cfx_mp=. Prueba: SaaS/pruebas/g99.js.

- G104 (1.21.90 · bd 64): 🧩 3 módulos más → 📤 cuentas_pagar (tabla cuentas_pagar · cpp_lista/guardar/borrar/pagar/pronto; pagar = gasto "Proveedores" en caja; banda en Inicio) · 💵 cierre_caja (cierres_caja · privado.efectivo_dia · cierre_ver/cierre_guardar; ayudante con diferencia → aviso al dueño) · 🔔 aviso_vence (cron lc-vence 3×/día → privado.avisar_vencimientos: push al cliente con push_subs, cuenta como recordatorio tono "auto" y respeta cobro_permitido; resumen al dueño). Rutas #pagar #cierre #avisovence. 🐞 atraso de "Cobrar" salía 1 día menos antes del mediodía → hoyISO(). Prueba: SaaS/pruebas/g104a.js.

## 🧠 Del núcleo: falta aplicar aquí
- G42e (núcleo 2.78): utilidades Bootstrap 5.3.8 ya usan los colores CodeFix (--bs-* → --cfx-*). Al revisar esta app: si quiere Bootstrap, enlazar vendor/bootstrap-utilities.min.css ANTES de su CSS (nunca el Bootstrap completo: choca con .btn/.card/.modal/.row/.toast).
- G48 (núcleo 2.77): revisar en el celular ✋ mover secciones desde el título y 🎨 Color y modo → Colores a tu gusto (fondo, texto, íconos y +); si la app pinta íconos o fondo con colores fijos, pasarlos a var(--cfx-icono)/var(--cfx-fondo).
- G37 (núcleo 2.76): 🧾 comprobante.js + 🖨️ impresora.js son del núcleo (OPCIONAL). Aplicar: sumar "emprendedor" a OPCIONAL en sincronizar.py + <script> + FILES de sw.js; definir window.CFX_COMPROBANTE_DATOS = async (c) => ({ logo, firma }) y abrir CFX_COMPROBANTE.abrir({...}) en abono o venta. 🧾 Boleta SII: hoy solo Despega (SQL boleta_*); si esta app la necesita, pasarla primero a nucleo/sql/boleta.sql. · 🔑 Entrar con QR: la función ya atiende qr_entrar (enviar 1.3.0); falta en la app: <script qr.js> + #lQR en el ingreso (como CM/Barbería) + ?qr=.
- G42 (núcleo 2.75, ya activo solo): ⬆️ subir, 🪟 ventanas del núcleo (✕+Cerrar / ← Volver), 📌 títulos fijos y ✋ ordenar en CFX_AJUSTES/CFX_MENU. Falta aquí: ✋ marcar otras listas propias con data-cfx-orden si sirve; 🪟 revisar ventanas propias (dialog) que no usan la hoja del núcleo; 🔐 usar CFX_TAPAR en avisos de enlace/validación y CFX_URL en links que pone el negocio (boleta, pago).
- G43: revisar la tarjeta "🚀 Termina de armar tu negocio" (núcleo) en app/ (o marcar data-cfx-guia); afinar guiaPasos (whatsapp, cobro, logo → campo exacto en Ajustes); quitar avisos propios de instalar/notificaciones si se repiten.

- 🧩 G112 b · Packs 🌱 Básico · ⭐ Normal (clave `crecer`, destacado) · 💎 Completo, iguales en las 6; precios y módulos: SaaS/LANZAMIENTO.md (Módulos, paso 3). Solo cambian si siguen de fábrica.
- 🎬 G112 d · Estudio de contenido = 🧩 módulo 'estudio' (núcleo estudio.sql/estudio.js; ayuda.js lo carga al abrir: CFX_ESTUDIO.montar(zona, { rpc, probar, nombre })). Datos en cfx_estudio (solo el dueño por funciones). Entra en ⭐ Normal (si sigue de fábrica) y 💎 Completo. Dónde: Más → 🎬 Estudio (/app/#estudio, vEstudio).
- G113 (núcleo 3.21): ☰ Más en páginas que se deslizan de lado (pestañas + ⇅ ordenar/renombrar por persona), ≥ 900 px opciones en grilla pareja, 🗂️ CFX_CAJA y CFX_DIALOGO { lista } disponibles para elegir entre muchas opciones / mostrar listas.
- 📊 G118 (1.21.105): Clientes → 📊 Cargar muchos clientes (núcleo CFX_RESPALDO.planilla, soloCrear: los que existen no se tocan; pide autorización; crear_cliente por fila).
- G140 (núcleo 3.36): Mi perfil → 🎨 Personalizar (ex Color y modo): temas listos, barra de abajo (tipo/tamaño/nombres), ↩️ de fábrica; se guarda en public.cfx_personal (nucleo/sql/personal.sql). Prueba: SaaS/pruebas/g140.js.
- 📱 G141 (núcleo 3.37): 🔗 Mis redes (CodeFixVitrina.redes + nucleo/sql/redes.sql, gancho cfx_redes_llave_app en instalar/schema) y 🎬 Estudio por link + 📸 pantallazo + 📊 gráficos + 💡 ideas sin base (nucleo/est-links.js). Pruebas: SaaS/pruebas/g141.js, g141b.js.
- 🛡️ G144 (núcleo 3.40): sin fila "Panel de administración" ni limpieza/respaldo dentro de la app (todo en CM → Apps) · .cfx-num/.cfx-redondo (círculo perfecto) · 🎤/⬜ = íconos de línea · 💬 WhatsApp del registro → Mis redes (cfx_redes_con_wa; gancho cfx_whatsapp_app donde aplica; uno solo, el botón antiguo se oculta con redes.unWa) · .assetsignore: notas, SQL y pruebas NO se publican.
- 🙂 G148 (1.21.123, núcleo 3.43): perfiles sin ícono → foto o la letra del nombre (el ícono guardado se conserva, no se muestra).

## 🐞 G156 (1.21.132)
- Anotar: ＋ Nueva categoría → gestionarCategorias({ tipo, alCambiar }) la deja elegida sin recargar · medios de pago `.medios-ico` (ícono arriba, texto abajo) · Caja: botón 💵 Cierre de caja (#cierre) del mes actual. Prueba: SaaS/pruebas/g156.js.
