-- ACTUALIZACIÓN: cambio de máquina + nuevas incidencias
-- Ejecutar una vez en Supabase > SQL Editor > New query > Run.
-- No borra datos existentes.

-- 1) Actualiza la RPC que guarda método, incidencia y comentario
--    para aceptar las nuevas opciones de incidencia.
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

  -- "Sin incidencia" se mantiene como valor interno cuando no se pulsa
  -- ninguna de las opciones de incidencia.
  if p_incidencia not in (
    'Sin incidencia',
    'Finalmente falla',
    'Prueba a meter la tarjeta varias veces',
    'Prueba varios métodos',
    'Se cambia de máquina',
    'Pide ayuda',
    'Se equivoca al meter el DNI',
    'Falla la lectura de tarjeta',
    'Tarda en encontrar la tarjeta',
    'La máquina tarda en procesar la petición'
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

grant execute on function public.guardar_datos_paciente(bigint, text, text, text)
  to anon, authenticated;


-- 2) RPC para cambiar un paciente de máquina.
--    SECURITY DEFINER evita el error "permission denied for table pacientes".
--    Solo permite moverse entre máquinas del mismo lado y únicamente si
--    la máquina de destino está libre.
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

  -- Bloquea la fila del paciente mientras se realiza el cambio.
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

  -- El destino tiene que pertenecer al mismo lado que la cola del paciente.
  if v_cola = 'Izquierda' and p_maquina_nueva not in ('I1','I2','I3') then
    raise exception 'Un paciente de la izquierda solo puede cambiar a I1, I2 o I3';
  elsif v_cola = 'Derecha' and p_maquina_nueva not in ('D1','D2','D3','D4') then
    raise exception 'Un paciente de la derecha solo puede cambiar a D1, D2, D3 o D4';
  elsif v_cola not in ('Izquierda','Derecha') then
    raise exception 'Cola del paciente no válida';
  end if;

  -- Bloquea cualquier paciente que pueda estar ya en la máquina de destino.
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
