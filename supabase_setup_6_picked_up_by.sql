drop function if exists create_shipment(uuid, uuid, numeric, numeric, text, date);
drop function if exists update_shipment(uuid, uuid, uuid, numeric, numeric, text, date);
drop function if exists list_shipment_history(uuid);

alter table shipments add column if not exists picked_up_by text;

create or replace function create_shipment(
  p_cafe_id uuid,
  p_recipe_id uuid,
  p_qty numeric,
  p_entered_qty numeric,
  p_entered_unit text,
  p_date date,
  p_picked_up_by text
)
returns uuid
language plpgsql
security definer
as $$
declare
  v_unit_cost numeric;
  v_id uuid;
begin
  select compute_recipe_unit_cost(p_recipe_id) into v_unit_cost;
  insert into shipments (date, cafe_id, recipe_id, qty, entered_qty, entered_unit, unit_cost, total_cost, picked_up_by)
  values (p_date, p_cafe_id, p_recipe_id, p_qty, p_entered_qty, p_entered_unit, v_unit_cost, v_unit_cost * p_qty, p_picked_up_by)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function update_shipment(
  p_shipment_id uuid,
  p_cafe_id uuid,
  p_recipe_id uuid,
  p_qty numeric,
  p_entered_qty numeric,
  p_entered_unit text,
  p_date date,
  p_picked_up_by text
)
returns void
language plpgsql
security definer
as $$
declare
  v_unit_cost numeric;
begin
  select compute_recipe_unit_cost(p_recipe_id) into v_unit_cost;
  update shipments set
    date = p_date, recipe_id = p_recipe_id, qty = p_qty,
    entered_qty = p_entered_qty, entered_unit = p_entered_unit,
    unit_cost = v_unit_cost, total_cost = v_unit_cost * p_qty,
    picked_up_by = p_picked_up_by
  where id = p_shipment_id and cafe_id = p_cafe_id;
end;
$$;

create or replace function list_shipment_history(p_cafe_id uuid)
returns table(id uuid, date date, recipe_id uuid, product_name text, qty numeric, entered_qty numeric, entered_unit text, picked_up_by text)
language sql
security definer
stable
as $$
  select s.id, s.date, s.recipe_id, r.name as product_name, s.qty, s.entered_qty, s.entered_unit, s.picked_up_by
  from shipments s
  left join recipes r on r.id = s.recipe_id
  where s.cafe_id = p_cafe_id
  order by s.date desc
  limit 30
$$;

grant execute on function create_shipment(uuid, uuid, numeric, numeric, text, date, text) to anon;
grant execute on function update_shipment(uuid, uuid, uuid, numeric, numeric, text, date, text) to anon;
grant execute on function list_shipment_history(uuid) to anon;
