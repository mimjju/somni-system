alter table employees add column if not exists avatar text not null default '🐣';
alter table employees add column if not exists points integer not null default 0;

drop function if exists list_employees_public();

create or replace function list_employees_public()
returns table(id uuid, name text, avatar text, points integer)
language sql
security definer
stable
as $$
  select id, name, avatar, points from employees where my_role() in ('admin','staff')
$$;

grant execute on function list_employees_public() to authenticated;

create or replace function add_employee_points(p_employee_id uuid, p_amount integer)
returns void
language sql
security definer
as $$
  update employees set points = points + p_amount where id = p_employee_id
$$;

grant execute on function add_employee_points(uuid, integer) to authenticated;
