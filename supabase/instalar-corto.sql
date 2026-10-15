-- Libreta de Cobros · instalación corta (para pegar desde el celular).
-- Descarga y ejecuta supabase/instalar.sql de la versión publicada. Se puede correr de nuevo para actualizar.
create extension if not exists http with schema extensions;
do $$ begin
  execute (select content from extensions.http_get('https://raw.githubusercontent.com/CodeFixService/Emprendedor/eda6dd2e73f59e61874347d0d14e018604feaeb7/supabase/instalar.sql'));
end $$;
select 'Libreta instalada v' || valor as resultado from privado.config where clave = 'version_bd';
