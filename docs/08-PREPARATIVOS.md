# 8. Preparativos (tu paso a paso)

Marca cada casilla al terminar. **La parte A se puede hacer ahora**, antes del código. La parte B se hace cuando el código esté en el repo.

## A. Antes de programar (unos 10 minutos)

### A1. Crear el proyecto Supabase nuevo
- [ ] Entra a https://supabase.com/dashboard → **New project**.
- [ ] Organización: la misma de siempre. El plan gratis permite **2 proyectos**: el de CodeFix y este.
- [ ] Nombre: `libreta-cobros` (o el nombre final de la app).
- [ ] Contraseña de la base de datos: genera una y **guárdala tú**, no la mandes por el chat.
- [ ] Región: **South America (São Paulo)** → **Create new project**. Espera 1–2 minutos.

### A2. Configurar el inicio de sesión
- [ ] **Authentication → Sign In / Providers → Email**: deja **Enable email** encendido. **Confirm email**: apágalo por ahora (Save).
- [ ] **Authentication → URL Configuration**:
  - Site URL: `https://codefixservice.github.io/Emprendedor/` → Save.
  - Redirect URLs → Add URL: `https://codefixservice.github.io/Emprendedor/**` → Save URLs.

### A3. Correo para "olvidé mi contraseña" (obligatorio)
El correo de fábrica de Supabase **solo envía a los miembros de tu equipo** (máximo 2 por hora). Para los clientes hay que usar Gmail.
- [ ] Crea una contraseña de aplicación en https://myaccount.google.com/apppasswords (requiere la verificación en 2 pasos activada).
- [ ] Supabase → **Authentication → Emails → SMTP Settings** → **Enable custom SMTP**:
  host `smtp.gmail.com`, puerto `465`, usuario tu Gmail, contraseña las 16 letras, remitente tu Gmail, nombre `Libreta de Cobros` → Save.

### A4. Mandarme las 2 claves públicas
- [ ] **Project Settings → Data API**: copia la **Project URL** (`https://xxxx.supabase.co`).
- [ ] **Project Settings → API Keys → Legacy API Keys**: copia **anon public** (empieza con `eyJ`).
- [ ] Mándame las dos por el chat.
- ⚠️ **Nunca** mandes la `service_role` ni la `secret key`, ni la contraseña de la base de datos.

### A5. Decisiones
- [x] Se usan las propuestas de `09-PLAN.md` (nombre, precio, límites y color). Todo se cambia después desde Administración → Ajustes.

## B. Instalar y publicar (unos 20 minutos) — el código ya está listo
Todo en https://supabase.com/dashboard → organización **Emprendedor** → proyecto **libreta-cobros**.

**B1. Base de datos**
1. [ ] **SQL Editor → + New query** → pega `supabase/instalar-corto.sql` → **Run**.
   Si aparece un aviso de operación destructiva, toca **Run this query** (es normal).
   ✅ Debe terminar con `Libreta instalada v1`.

**B2. Tu usuario administrador**
2. [ ] **Authentication → Users → Add user → Create new user**: correo `juanjosuecastilloloyola@gmail.com`,
   una contraseña **distinta** a la de CodeFix, con **Auto Confirm User** marcado → **Create user**.
3. [ ] **SQL Editor → + New query** → pega `select privado.fijar_admin();` → **Run**.
   ✅ Debe decir `Administrador fijado ✓`. (Esto evita que otra persona se haga admin registrándose con tu correo.)

**B3. Función de avisos y fotos**
4. [ ] **Edge Functions → Deploy a new function → Via Editor** → borra el ejemplo → pega `supabase/functions/enviar/index.ts`
   → nombre `enviar` → **Deploy function**.
5. [ ] En la función: **Details/Settings** → apaga **Verify JWT** (o "Enforce JWT verification") → **Save**.

**B4. Publicar la app**
6. [ ] Unir la rama del código a `main` (te dejo el Pull Request listo; tú tocas **Merge**).
7. [ ] GitHub → repo **Emprendedor** → **Settings → Pages** → Source: **Deploy from a branch** → rama `main`, carpeta `/ (root)` → **Save**.
   ✅ En 1–2 minutos abre `https://codefixservice.github.io/Emprendedor/`.

**B5. Configurar desde tu panel**
8. [ ] Abre `https://codefixservice.github.io/Emprendedor/#ingresar` → ingresa con el correo del paso 2 → te lleva a **Administración**.
9. [ ] **Ajustes → Generar claves push** (una sola vez).
10. [ ] En **Ajustes**: tu WhatsApp de soporte, link de pago (si tienes) y tus datos de transferencia → **Guardar ajustes**.
11. [ ] **Ajustes → Probar servidor**: debe decir `✅ Función "enviar" v1.0.0`.
12. [ ] **Resumen**: no debe aparecer el aviso rojo de "tareas automáticas". Si aparece: **Database → Extensions** → activa **pg_cron** y **pg_net** → repite el paso 1.

**B6. Prueba completa con tu celular** (con otro correo, como si fueras un cliente tuyo)
13. [ ] Crear una libreta de prueba (otro correo) → instalar la app (📲 Instalar).
14. [ ] Anotar un fiado y un abono → ver que el saldo cambia.
15. [ ] Enviar el link del cliente a tu WhatsApp → abrirlo → PIN → ver el saldo → enviar un comprobante con foto.
16. [ ] En la libreta: **Más → Comprobantes** → aprobar.
17. [ ] **Más → Mi cuenta → Notificaciones** → activar → desde el link del cliente envía otro comprobante → debe llegar el aviso.
18. [ ] Probar **Cobrar** (lunes a sábado de 08:00 a 20:00; fuera de ese horario la app te dice cuándo se puede).

**B7. Mantener activa la base de datos**
19. [ ] GitHub → **Actions → "Mantener activa la base de datos" → Run workflow** → debe quedar en verde ✅.

## C. Antes de vender
- [ ] Hacer privado el repo y publicar en Cloudflare Pages (gratis), o comprar el dominio. Al cambiar la URL, actualiza las URLs de A2.
- [ ] Revisar los textos legales con un abogado (ver `07-LEGAL.md`).
- [ ] Cuando la base de datos pase el 70 % (el admin lo muestra), pasar a Supabase Pro (US$25 al mes) y encender "Confirm email".
