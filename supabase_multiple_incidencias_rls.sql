-- ACTUALIZACIÓN PARA SUPABASE / RLS
-- Múltiples incidencias + cambio de máquina seguro.
-- Ejecutar una sola vez en Supabase > SQL Editor > New query > Run.
-- No borra los datos existentes.

-- La columna public.pacientes.incidencia sigue siendo TEXT.
-- Si se seleccionan varias incidencias se guardan separadas por " | ".

create or replace function public.guardar_datos_paciente_multiple(
  p_id bigint,
  p_metodo text,
  p_incidencias text[],
  p_comentario text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actualizados integer;
  v_incidencia text;
  v_incidencias_limpias text[];
begin
  if p_metodo not in ('DNI', 'Tarjeta sanitaria') then
    raise exception 'Método no válido';
  end if;

  -- Quita nulos, vacíos y duplicados manteniendo únicamente opciones permitidas.
  select coalesce(array_agg(distinct x), '{}'::text[])
    into v_incidencias_limpias
  from unnest(coalesce(p_incidencias, '{}'::text[])) as t(x)
  where nullif(trim(x), '') is not null;

  if exists (
    select 1
    from unnest(v_incidencias_limpias) as t(x)
    where x not in (
      'Finalmente falla',
      'Prueba a meter la tarjeta varias veces',
      'Prueba varios métodos',
      'Se cambia de máquina',
      'Pide ayuda',
      'Se equivoca al meter el DNI',
      'Falla la lectura de tarjeta',
      'Tarda en encontrar la tarjeta',
      'La máquina tarda en procesar la petición'
    )
  ) then
    raise exception 'Una o más incidencias no son válidas';
  end if;

  if cardinality(v_incidencias_limpias) = 0 then
    v_incidencia := 'Sin incidencia';
  else
    v_incidencia := array_to_string(v_incidencias_limpias, ' | ');
  end if;

  update public.pacientes
  set metodo = p_metodo,
      incidencia = v_incidencia,
      comentario = nullif(trim(coalesce(p_comentario, '')), '')
  where id = p_id
    and estado = 'maquina';

  get diagnostics v_actualizados = row_count;
  return v_actualizados = 1;
end;
$$;

grant execute on function public.guardar_datos_paciente_multiple(bigint, text, text[], text)
  to anon, authenticated;


-- Cambio de máquina mediante RPC SECURITY DEFINER.
-- Así el navegador NO necesita permiso UPDATE directo sobre pacientes.
create or replace function public.cambiar_paciente_maquina(
  p_id bigint,
  p_maquina_actual text,
  p_maquina_nueva text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cola text;
  v_actualizados integer;
begin
  if p_maquina_actual = p_maquina_nueva then
    raise exception 'La máquina de destino es la misma máquina actual';
  end if;

  select cola
    into v_cola
  from public.pacientes
  where id = p_id
    and estado = 'maquina'
    and maquina = p_maquina_actual
  for update;

  if not found then
    raise exception 'El paciente ya no está en la máquina %', p_maquina_actual;
  end if;

  if v_cola = 'Izquierda' and p_maquina_nueva not in ('I1','I2','I3') then
    raise exception 'Un paciente de la izquierda solo puede cambiar a I1, I2 o I3';
  elsif v_cola = 'Derecha' and p_maquina_nueva not in ('D1','D2','D3','D4') then
    raise exception 'Un paciente de la derecha solo puede cambiar a D1, D2, D3 o D4';
  elsif v_cola not in ('Izquierda','Derecha') then
    raise exception 'Cola del paciente no válida';
  end if;

  perform 1
  from public.pacientes
  where estado = 'maquina'
    and maquina = p_maquina_nueva
  for update;

  if found then
    raise exception 'La máquina % ya está ocupada', p_maquina_nueva;
  end if;

  update public.pacientes
  set maquina = p_maquina_nueva
  where id = p_id
    and estado = 'maquina'
    and maquina = p_maquina_actual;

  get diagnostics v_actualizados = row_count;
  if v_actualizados <> 1 then
    raise exception 'No se pudo realizar el cambio de máquina';
  end if;

  return true;
end;
$$;

grant execute on function public.cambiar_paciente_maquina(bigint, text, text)
  to anon, authenticated;

-- No hace falta abrir una policy UPDATE de RLS sobre public.pacientes.
-- Las escrituras anteriores se realizan dentro de funciones SECURITY DEFINER.
