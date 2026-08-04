create table suppliers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  memo text,
  created_at timestamptz default now()
);

alter table suppliers enable row level security;

create policy "staff+admin all" on suppliers for all
  using (my_role() in ('admin','staff')) with check (my_role() in ('admin','staff'));

grant select, insert, update, delete on suppliers to authenticated;

alter table ingredients add column if not exists supplier_id uuid references suppliers(id) on delete set null;
