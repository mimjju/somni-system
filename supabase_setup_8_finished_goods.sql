create table finished_goods_batches (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid references recipes(id) on delete set null,
  product_name text not null,
  produced_date date not null,
  initial_qty numeric not null,
  remaining_qty numeric not null,
  unit_cost numeric not null,
  work_log_id uuid references work_logs(id) on delete set null,
  created_at timestamptz default now()
);

alter table finished_goods_batches enable row level security;

create policy "staff+admin all" on finished_goods_batches for all
  using (my_role() in ('admin','staff')) with check (my_role() in ('admin','staff'));

grant select, insert, update, delete on finished_goods_batches to authenticated;

-- Recreate create_shipment so it also FIFO-deducts finished_goods_batches
drop function if exists create_shipment(uuid, uuid, numeric, numeric, text, date, text);

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
  v_remaining numeric := p_qty;
  batch record;
  v_deduct numeric;
begin
  select compute_recipe_unit_cost(p_recipe_id) into v_unit_cost;
  insert into shipments (date, cafe_id, recipe_id, qty, entered_qty, entered_unit, unit_cost, total_cost, picked_up_by)
  values (p_date, p_cafe_id, p_recipe_id, p_qty, p_entered_qty, p_entered_unit, v_unit_cost, v_unit_cost * p_qty, p_picked_up_by)
  returning id into v_id;

  for batch in
    select id, remaining_qty from finished_goods_batches
    where recipe_id = p_recipe_id and remaining_qty > 0
    order by produced_date asc, created_at asc
  loop
    exit when v_remaining <= 0;
    v_deduct := least(batch.remaining_qty, v_remaining);
    update finished_goods_batches set remaining_qty = remaining_qty - v_deduct where id = batch.id;
    v_remaining := v_remaining - v_deduct;
  end loop;

  return v_id;
end;
$$;

grant execute on function create_shipment(uuid, uuid, numeric, numeric, text, date, text) to anon;
