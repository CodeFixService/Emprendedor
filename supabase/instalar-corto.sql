-- Libreta de Cobros · instalación corta (para pegar desde el celular).
-- Descarga y ejecuta supabase/instalar.sql de la versión publicada. Se puede correr de nuevo para actualizar.
create extension if not exists http with schema extensions;
do $$ begin
  execute (select content from extensions.http_get('https://raw.githubusercontent.com/CodeFixService/Emprendedor/95169687d9fffd3a36121dab7696cb6ca766e6bd/supabase/instalar.sql'));
end $$;
select 'Libreta instalada v' || valor as resultado from privado.config where clave = 'version_bd';
