-- ============================================================
-- 작업 난이도 "전문가" 추가 + 직원별 스케줄 색
-- 이 파일 전체를 한 번에 복사해서 SQL Editor에 붙여넣고 Run 하세요. 여러 번 실행해도 괜찮아요.
-- ============================================================

begin;

-- 난이도: 쉬움(easy) / 숙련(pro) / 전문가(expert)
alter table schedule_tasks drop constraint if exists schedule_tasks_level_check;
alter table schedule_tasks add constraint schedule_tasks_level_check check (level in ('easy','pro','expert'));

-- 직원별 스케줄 색
create table if not exists schedule_staff_colors (
  employee_id uuid primary key references employees(id) on delete cascade,
  color text not null
);
alter table schedule_staff_colors enable row level security;
grant select, insert, update, delete on schedule_staff_colors to authenticated;

do $$
declare
  v_multi boolean := to_regclass('public.organizations') is not null;
  v_org text := case when v_multi then 'org_id = my_org_id() and ' else '' end;
begin
  if v_multi then
    alter table schedule_staff_colors add column if not exists org_id uuid references organizations(id);
    update schedule_staff_colors set org_id = (select id from organizations where slug = 'somli') where org_id is null;
    alter table schedule_staff_colors alter column org_id set not null;
    alter table schedule_staff_colors alter column org_id set default my_org_id();
  end if;

  drop policy if exists "sched read" on schedule_staff_colors;
  drop policy if exists "sched admin write" on schedule_staff_colors;
  execute format('create policy "sched read" on schedule_staff_colors for select using (%s my_role() in (''admin'',''staff''))', v_org);
  execute format('create policy "sched admin write" on schedule_staff_colors for all using (%s my_role() = ''admin'') with check (%s my_role() = ''admin'')', v_org, v_org);
end $$;

commit;
