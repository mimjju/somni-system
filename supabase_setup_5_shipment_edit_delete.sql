drop function if exists list_shipment_history(uuid);

create or replace function list_shipment_history(p_cafe_id uuid)
returns table(id uuid, date date, recipe_id uuid, product_name text, qty numeric, entered_qty numeric, entered_unit text)
language sql
security definer
stable
as $$
  select s.id, s.date, s.recipe_id, r.name as product_name, s.qty, s.entered_qty, s.entered_unit
  from shipments s
  left join recipes r on r.id = s.recipe_id
  where s.cafe_id = p_cafe_id
  order by s.date desc
  limit 30
$$;

create or replace function update_shipment(
  p_shipment_id uuid,
  p_cafe_id uuid,
  p_recipe_id uuid,
  p_qty numeric,
  p_entered_qty numeric,
  p_entered_unit text,
  p_date date
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
    unit_cost = v_unit_cost, total_cost = v_unit_cost * p_qty
  where id = p_shipment_id and cafe_id = p_cafe_id;
end;
$$;

create or replace function delete_shipment(p_shipment_id uuid, p_cafe_id uuid)
returns void
language sql
security definer
as $$
  delete from shipments where id = p_shipment_id and cafe_id = p_cafe_id;
$$;

grant execute on function list_shipment_history(uuid) to anon;
grant execute on function update_shipment(uuid, uuid, uuid, numeric, numeric, text, date) to anon;
grant execute on function delete_shipment(uuid, uuid) to anon;
