drop policy "admin all" on recipes;

create policy "staff+admin read" on recipes for select
  using (my_role() in ('admin','staff'));
create policy "admin insert" on recipes for insert
  with check (my_role() = 'admin');
create policy "admin update" on recipes for update
  using (my_role() = 'admin');
create policy "admin delete" on recipes for delete
  using (my_role() = 'admin');
