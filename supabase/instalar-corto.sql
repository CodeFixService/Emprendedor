-- Libreta de Cobros · instalación corta (para pegar desde el celular).
-- Siempre la última (rama main). Basta con correrla UNA vez: después la base se actualiza sola cada 10 minutos.
-- Descarga y ejecuta supabase/instalar.sql de la versión publicada. Se puede correr de nuevo para actualizar.
create extension if not exists http with schema extensions;
do $$ begin
  execute (select content from extensions.http_get('https://raw.githubusercontent.com/CodeFixService/Emprendedor/main/supabase/instalar.sql?t=' || extract(epoch from now())::bigint));
end $$;
select 'Libreta instalada v' || valor as resultado from privado.config where clave = 'version_bd';
