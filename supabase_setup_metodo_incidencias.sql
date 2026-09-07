-- Añade método de identificación e incidencia a los pacientes.
-- Ejecutar UNA sola vez en Supabase > SQL Editor.

alter table public.pacientes
  add column if not exists metodo text,
  add column if not exists incidencia text default 'Sin incidencia';

-- RPC auxiliar: guarda estos dos datos mientras el paciente sigue en máquina.
-- La finalización real continúa haciéndola la función finalizar_paciente existente,
-- así no cambiamos la lógica que ya tienes funcionando.
create or replace function public.guardar_datos_paciente(
  p_id bigint,
  p_metodo text,
  p_incidencia text
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
      incidencia = p_incidencia
  where id = p_id
    and estado = 'maquina';

  get diagnostics v_actualizados = row_count;
  return v_actualizados = 1;
end;
$$;

grant execute on function public.guardar_datos_paciente(bigint, text, text) to anon, authenticated;
