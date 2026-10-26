-- Libreta de Cobros · instalación corta (para pegar desde el celular).
-- Descarga y ejecuta supabase/instalar.sql de la versión publicada. Se puede correr de nuevo para actualizar.
create extension if not exists http with schema extensions;
do $$ begin
  execute (select content from extensions.http_get('https://raw.githubusercontent.com/CodeFixService/Emprendedor/a5e82d17bbd36d80a44e1187e4c6874fff4f712b/supabase/instalar.sql'));
end $$;
select 'Libreta instalada v' || valor as resultado from privado.config where clave = 'version_bd';
