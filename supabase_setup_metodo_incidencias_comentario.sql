-- Añade método, incidencia y comentario a los pacientes.
-- Ejecuta este script UNA vez en Supabase > SQL Editor.
-- Es seguro si ya ejecutaste el SQL anterior: usa IF NOT EXISTS y reemplaza la RPC.

alter table public.pacientes
  add column if not exists metodo text,
  add column if not exists incidencia text default 'Sin incidencia',
  add column if not exists comentario text;

drop function if exists public.guardar_datos_paciente(bigint, text, text);

create or replace function public.guardar_datos_paciente(
  p_id bigint,
  p_metodo text,
  p_incidencia text,
  p_comentario text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actualizados integer;
begin
  if p_metodo not in ('DNI', 'Tarjeta sanitaria') then
    raise exception 'Método no válido';
  end if;

  if p_incidencia not in (
    'Sin incidencia',
    'Sin papel',
    'No entrega papel',
    'Sin Wi-Fi',
    'Fallo lectura tarjeta sanitaria',
    'Fallo lectura DNI',
    'Otra'
  ) then
    raise exception 'Incidencia no válida';
  end if;

  update public.pacientes
  set metodo = p_metodo,
      incidencia = p_incidencia,
      comentario = nullif(trim(coalesce(p_comentario, '')), '')
  where id = p_id
    and estado = 'maquina';

  get diagnostics v_actualizados = row_count;
  return v_actualizados = 1;
end;
$$;

grant execute on function public.guardar_datos_paciente(bigint, text, text, text) to anon, authenticated;
