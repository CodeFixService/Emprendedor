# 6. Técnico

## Principios
- **Sin frameworks y sin compilar**: HTML, CSS y JavaScript moderno (módulos ES). Lo único externo es el cliente de Supabase,
  copiado dentro de `vendor/`, sin depender de CDN.
- **Liviana**: la meta es que la app del negocio pese menos de 150 KB sin contar Supabase, y la página del cliente menos de 60 KB.
- Funciona en Chrome, Edge, Safari y Firefox de los últimos 2 años, Android 8+ e iOS 16.4+ (push).

## Independencia total de CodeFix Apps
| Cosa | CodeFix Apps | Libreta de Cobros |
|---|---|---|
| Repositorio | `CodeFixService/Aplicaciones` | **`CodeFixService/Emprendedor`** |
| URL | `…github.io/Aplicaciones/` | `…github.io/Emprendedor/` |
| Supabase | proyecto actual | **proyecto nuevo** (el 2º gratis de tu cuenta) |
| Service worker, manifest, íconos, versión | los suyos | los suyos propios |
| Datos guardados en el celular | claves `cfx-…` | claves `lc-…` (no se pisan) |

**No se toca nada del repo `Aplicaciones`.** Cada app tiene su propia dirección y su propio service worker, así que no se pueden interferir.
Las dos se instalan **por separado** en el celular o el computador, con dos íconos distintos.
Para un dominio propio después, basta con apuntarlo a este repo y cambiar las URLs en Supabase.

## Archivos
```
(raíz del repo)
  index.html            portada, crear cuenta, ingresar, recuperar contraseña e invitaciones de ayudante
  app/index.html        app del negocio (rutas con #)
  c/index.html          link del cliente (página aparte y liviana) + c/manifest.webmanifest
  admin/index.html      superadmin
  legal/index.html      términos, privacidad, aviso al cliente y uso aceptable
  js/
    config.js           URL y clave pública del Supabase propio, correo admin y marca
    core.js             herramientas comunes: llamadas al servidor, validaciones (RUT, teléfono, montos),
                        avisos, diálogos, imágenes, push, instalación, CSV/Excel
    inicio.js           portada y cuentas
    app.js              todo el negocio: inicio, clientes, anotar, cuotas, cobrar, comprobantes, reportes,
                        productos, ayudantes, ajustes, plan, avisos, cuenta, ayuda y cola sin internet
    portal.js           link del cliente
    admin.js            panel del administrador
  css/app.css           estilos con variables (modo claro/oscuro, letra grande)
  vendor/supabase.js    cliente oficial de Supabase (copiado, sin CDN)
  icons/                íconos de la app
  manifest.webmanifest · sw.js · version.json · robots.txt · .nojekyll
  .github/workflows/ping.yml   mantiene activo el Supabase gratis
  supabase/
    instalar.sql        tablas, reglas, funciones, tareas y feriados (todo en uno, se puede correr de nuevo)
    instalar-corto.sql  versión corta para pegar (descarga e instala la larga)
    functions/enviar/index.ts   push, fotos de comprobantes y limpieza
    pruebas/            simulación de Supabase + 70 pruebas de reglas y abusos (solo para desarrollo)
  docs/                 esta documentación
```

## Sin internet (clave en ferias y almacenes con mala señal)
- La app abre sin internet: el service worker guarda los archivos.
- La lista de clientes, sus saldos y el tablero quedan guardados en el celular (almacenamiento local) y se ven sin conexión.
- **Anotar sin internet**: el movimiento queda en una **cola** con su id único y el saldo se muestra "estimado".
  Al volver la conexión se envía en orden. Si el servidor lo rechaza (por ejemplo, porque el plan llegó al tope o el cliente quedó en solo cobro),
  queda marcado en rojo para que la persona decida.
- Lo que **necesita** internet: crear clientes, aprobar comprobantes, cuotas, cobrar (para revisar las reglas legales) y todo lo del admin.
  El botón lo dice: "Necesitas internet para esto".
- El link del cliente necesita internet (los datos siempre vienen del servidor).

## Tiempo real
- Supabase Realtime en `movimientos` y `notificaciones` del negocio: si el ayudante anota algo o llega un comprobante, el dueño lo ve al instante.
- Cuando la app vuelve a primer plano, se refresca sola.

## Actualizaciones
Mismo sistema que CodeFix: `version.json`, aviso de "Hay una versión nueva" y botón **Actualizar**. Si el admin sube la
"versión mínima" en Ajustes, la app obliga a actualizar (por ejemplo, después de un cambio en la base de datos).

## Mantener vivo el Supabase gratis
El plan gratis **se pausa después de 7 días sin uso**. Un GitHub Action (`.github/workflows/ping.yml`) llama a `ping()`
cada 3 días. Ojo: GitHub apaga las tareas programadas si el repo pasa 60 días sin cambios. El inicio del admin lo avisa.

## Calidad comprobada antes de entregar
- Todos los archivos JavaScript pasan `node --check` y la función del servidor pasa `deno check`.
- `supabase/pruebas/pruebas.sql`: 70 pruebas de reglas y abusos sobre Postgres real (aislamiento entre negocios, límites del plan,
  PIN con bloqueo, cuotas, cobranza legal, ayudantes, admin, escritura directa prohibida). Todas pasan.
- Recorridos completos en Chrome (celular y escritorio) contra la base de datos: crear cuenta, ajustes, clientes, fiado, abono,
  doble toque, cuotas, cobro legal, link del cliente con PIN, confirmar y reclamar cargos, comprobante con foto, aprobarlo,
  sin internet y sincronizar, ayudante, límite del plan Normal, "Ya pagué" y aprobación del admin. Sin errores.
- La función "enviar" se probó corriendo: diagnóstico, cola, limpieza y subida de fotos (token de un solo uso, rechaza no-imágenes).
