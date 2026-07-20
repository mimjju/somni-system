-- ============================================================
-- 솜리 베이킹실 시스템 - Supabase 스키마 + 보안정책 + RPC
-- 1단계: 이 파일 전체를 Supabase SQL Editor에 붙여넣고 Run
-- ============================================================

-- ===== 테이블 =====

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('admin','staff'))
);

create table ingredients (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  purchase_qty numeric not null,
  purchase_unit text not null,
  purchase_price numeric not null,
  stock numeric not null default 0,
  min_stock numeric
);

create table recipes (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  yield_qty numeric not null,
  pack_label text,
  pack_size numeric
);

create table recipe_items (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid references recipes(id) on delete cascade,
  ingredient_id uuid references ingredients(id) on delete set null,
  amount numeric not null
);

create table stock_logs (
  id uuid primary key default gen_random_uuid(),
  ingredient_id uuid references ingredients(id) on delete set null,
  ingredient_name text,
  unit text,
  date date not null,
  type text not null,
  change numeric not null,
  after numeric not null,
  note text,
  created_at timestamptz default now()
);

create table employees (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  hourly_wage numeric not null
);

create table cafes (
  id uuid primary key default gen_random_uuid(),
  name text not null
);

create table work_logs (
  id uuid primary key default gen_random_uuid(),
  date date not null,
  recipe_id uuid references recipes(id) on delete set null,
  batches numeric not null,
  loss numeric not null default 0,
  note text
);

create table work_log_stages (
  id uuid primary key default gen_random_uuid(),
  work_log_id uuid references work_logs(id) on delete cascade,
  stage_name text not null,
  employee_id uuid references employees(id) on delete set null,
  time_minutes numeric not null
);

create table shipments (
  id uuid primary key default gen_random_uuid(),
  date date not null,
  cafe_id uuid references cafes(id) on delete set null,
  recipe_id uuid references recipes(id) on delete set null,
  qty numeric not null,
  entered_qty numeric,
  entered_unit text,
  unit_cost numeric not null,
  total_cost numeric not null,
  created_at timestamptz default now()
);

-- ===== 역할 확인 헬퍼 함수 =====

create or replace function my_role()
returns text
language sql
security definer
stable
as $$
  select role from profiles where id = auth.uid()
$$;

-- ===== RLS 켜기 =====

alter table profiles enable row level security;
alter table ingredients enable row level security;
alter table recipes enable row level security;
alter table recipe_items enable row level security;
alter table stock_logs enable row level security;
alter table employees enable row level security;
alter table cafes enable row level security;
alter table work_logs enable row level security;
alter table work_log_stages enable row level security;
alter table shipments enable row level security;

-- ===== 정책 =====

create policy "self read" on profiles for select using (id = auth.uid());

create policy "staff+admin all" on ingredients for all
  using (my_role() in ('admin','staff')) with check (my_role() in ('admin','staff'));

create policy "staff+admin all" on stock_logs for all
  using (my_role() in ('admin','staff')) with check (my_role() in ('admin','staff'));

create policy "staff+admin all" on work_logs for all
  using (my_role() in ('admin','staff')) with check (my_role() in ('admin','staff'));

create policy "staff+admin all" on work_log_stages for all
  using (my_role() in ('admin','staff')) with check (my_role() in ('admin','staff'));

create policy "staff+admin read" on cafes for select using (my_role() in ('admin','staff'));
create policy "admin insert" on cafes for insert with check (my_role() = 'admin');
create policy "admin update" on cafes for update using (my_role() = 'admin');
create policy "admin delete" on cafes for delete using (my_role() = 'admin');

create policy "admin all" on recipes for all
  using (my_role() = 'admin') with check (my_role() = 'admin');

create policy "admin all" on recipe_items for all
  using (my_role() = 'admin') with check (my_role() = 'admin');

create policy "admin all" on employees for all
  using (my_role() = 'admin') with check (my_role() = 'admin');

create policy "admin all" on shipments for all
  using (my_role() = 'admin') with check (my_role() = 'admin');

-- ===== 권한 부여 =====

grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on
  ingredients, stock_logs, cafes, work_logs, work_log_stages,
  recipes, recipe_items, employees, shipments, profiles
  to authenticated;

-- ===== 직원용: 이름만 보이는 함수 (시급 제외) =====

create or replace function list_employees_public()
returns table(id uuid, name text)
language sql
security definer
stable
as $$
  select id, name from employees where my_role() in ('admin','staff')
$$;

grant execute on function list_employees_public() to authenticated;

-- ===== 카페 방문자용 (로그인 없음, anon) RPC =====

create or replace function list_products()
returns table(id uuid, name text, yield_qty numeric, pack_label text, pack_size numeric)
language sql
security definer
stable
as $$
  select id, name, yield_qty, pack_label, pack_size from recipes
$$;

create or replace function list_cafes_public()
returns table(id uuid, name text)
language sql
security definer
stable
as $$
  select id, name from cafes
$$;

create or replace function compute_recipe_unit_cost(p_recipe_id uuid)
returns numeric
language sql
security definer
stable
as $$
  select coalesce(sum(ri.amount * (i.purchase_price / nullif(i.purchase_qty,0))), 0) / r.yield_qty
  from recipes r
  left join recipe_items ri on ri.recipe_id = r.id
  left join ingredients i on i.id = ri.ingredient_id
  where r.id = p_recipe_id
  group by r.yield_qty
$$;

create or replace function create_shipment(
  p_cafe_id uuid,
  p_recipe_id uuid,
  p_qty numeric,
  p_entered_qty numeric,
  p_entered_unit text,
  p_date date
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
  insert into shipments (date, cafe_id, recipe_id, qty, entered_qty, entered_unit, unit_cost, total_cost)
  values (p_date, p_cafe_id, p_recipe_id, p_qty, p_entered_qty, p_entered_unit, v_unit_cost, v_unit_cost * p_qty)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function list_shipment_history(p_cafe_id uuid)
returns table(date date, product_name text, qty numeric, entered_qty numeric, entered_unit text)
language sql
security definer
stable
as $$
  select s.date, r.name as product_name, s.qty, s.entered_qty, s.entered_unit
  from shipments s
  left join recipes r on r.id = s.recipe_id
  where s.cafe_id = p_cafe_id
  order by s.date desc
  limit 30
$$;

grant execute on function list_products() to anon;
grant execute on function list_cafes_public() to anon;
grant execute on function create_shipment(uuid,uuid,numeric,numeric,text,date) to anon;
grant execute on function list_shipment_history(uuid) to anon;
