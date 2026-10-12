-- Libreta de Cobros · instalación corta (para pegar desde el celular).
-- Descarga y ejecuta supabase/instalar.sql de la versión publicada. Se puede correr de nuevo para actualizar.
create extension if not exists http with schema extensions;
do $$ begin
  execute (select content from extensions.http_get('https://raw.githubusercontent.com/CodeFixService/Emprendedor/5a979c2aa24b4c2f028780ba7480f8dddacfcd73/supabase/instalar.sql'));
end $$;
select 'Libreta instalada v' || valor as resultado from privado.config where clave = 'version_bd';
