-- ============================================================
-- 주간 스케줄 + 레시피북
-- 이 파일 전체를 한 번에 복사해서 SQL Editor에 붙여넣고 Run 하세요.
-- 12번(멀티테넌트)을 이미 실행했든 안 했든 둘 다 동작해요.
-- (12번을 나중에 실행해도 12번 파일 끝에서 이 테이블들까지 함께 전환해요.)
-- ============================================================

begin;

-- ============================================================
-- 1) 레시피북: 만드는 법 / 굽기 / 보관 / 사진
-- ============================================================

alter table recipes add column if not exists steps text;
alter table recipes add column if not exists oven text;
alter table recipes add column if not exists storage_note text;
alter table recipes add column if not exists photo text; -- 축소한 jpeg data URL

-- ============================================================
-- 2) 매장(카페) 휴무 요일 (0=월 … 6=일)
-- ============================================================

alter table cafes add column if not exists closed_days smallint[] not null default '{}';

-- ============================================================
-- 3) 스케줄 테이블
-- ============================================================

-- 작업 목록 (한 번 등록해두고 매주 골라서 배정)
create table if not exists schedule_tasks (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  level text not null default 'easy' check (level in ('easy','pro')),
  minutes numeric not null default 60,
  recipe_id uuid references recipes(id) on delete set null,
  batches numeric,
  memo text,
  created_at timestamptz default now()
);

-- 직원별 기본 근무시간 (요일별, 0시간 = 휴무)
create table if not exists schedule_staff_hours (
  employee_id uuid not null references employees(id) on delete cascade,
  day smallint not null check (day between 0 and 6),
  hours numeric not null default 0,
  primary key (employee_id, day)
);

-- 특정 주에만 근무시간을 바꿀 때
create table if not exists schedule_week_hours (
  week_start date not null,
  employee_id uuid not null references employees(id) on delete cascade,
  day smallint not null check (day between 0 and 6),
  hours numeric not null default 0,
  primary key (week_start, employee_id, day)
);

-- 주간 배정 (week_start = 그 주 월요일)
create table if not exists schedule_assignments (
  id uuid primary key default gen_random_uuid(),
  week_start date not null,
  day smallint not null check (day between 0 and 6),
  employee_id uuid not null references employees(id) on delete cascade,
  task_id uuid not null references schedule_tasks(id) on delete cascade,
  batches numeric,
  done boolean not null default false,
  created_at timestamptz default now()
);
create index if not exists schedule_assignments_week_idx on schedule_assignments(week_start);

alter table schedule_tasks enable row level security;
alter table schedule_staff_hours enable row level security;
alter table schedule_week_hours enable row level security;
alter table schedule_assignments enable row level security;

grant select, insert, update, delete on schedule_tasks, schedule_staff_hours, schedule_week_hours, schedule_assignments to authenticated;

-- ============================================================
-- 4) RLS — 12번(멀티테넌트) 실행 여부에 따라 org 조건을 붙여요
--    작업목록/근무시간: 직원 읽기, 관리자 쓰기
--    배정: 직원도 "완료" 체크해야 하니 직원+관리자 모두
--    레시피 재료(recipe_items): 직원도 레시피북에서 볼 수 있게 읽기 허용
-- ============================================================

do $$
declare
  t text;
  v_multi boolean := to_regclass('public.organizations') is not null;
  v_org text := case when v_multi then 'org_id = my_org_id() and ' else '' end;
  v_somli_id uuid;
begin
  if v_multi then
    select id into v_somli_id from organizations where slug = 'somli';
    foreach t in array array['schedule_tasks','schedule_staff_hours','schedule_week_hours','schedule_assignments']
    loop
      execute format('alter table %I add column if not exists org_id uuid references organizations(id)', t);
      execute format('update %I set org_id = %L where org_id is null', t, v_somli_id);
      execute format('alter table %I alter column org_id set not null', t);
      execute format('alter table %I alter column org_id set default my_org_id()', t);
    end loop;
  end if;

  foreach t in array array['schedule_tasks','schedule_staff_hours','schedule_week_hours']
  loop
    execute format('drop policy if exists "sched read" on %I', t);
    execute format('drop policy if exists "sched admin write" on %I', t);
    execute format('create policy "sched read" on %I for select using (%s my_role() in (''admin'',''staff''))', t, v_org);
    execute format('create policy "sched admin write" on %I for all using (%s my_role() = ''admin'') with check (%s my_role() = ''admin'')', t, v_org, v_org);
  end loop;

  drop policy if exists "sched all" on schedule_assignments;
  execute format('create policy "sched all" on schedule_assignments for all using (%s my_role() in (''admin'',''staff'')) with check (%s my_role() in (''admin'',''staff''))', v_org, v_org);

  drop policy if exists "staff read" on recipe_items;
  execute format('create policy "staff read" on recipe_items for select using (%s my_role() in (''admin'',''staff''))', v_org);
end $$;

commit;
