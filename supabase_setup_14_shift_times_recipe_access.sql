-- ============================================================
-- 스케줄 시간대(몇 시~몇 시) + 직원 레시피 공개 설정
-- 이 파일 전체를 한 번에 복사해서 SQL Editor에 붙여넣고 Run 하세요.
-- 13번을 먼저 실행한 다음에 실행해야 해요. 여러 번 실행해도 괜찮아요.
-- ============================================================

begin;

-- 근무시간: 시작/끝 (자정부터 몇 분째인지, 예: 09:00 = 540). 둘 다 비어 있으면 휴무
alter table schedule_staff_hours add column if not exists start_min integer;
alter table schedule_staff_hours add column if not exists end_min integer;
alter table schedule_week_hours add column if not exists start_min integer;
alter table schedule_week_hours add column if not exists end_min integer;

-- 작업 시작 시각 (비어 있으면 근무 시작부터 순서대로 배치)
alter table schedule_assignments add column if not exists start_min integer;

-- 레시피를 직원에게 보여줄지 (관리자가 홈페이지에서 켜고 끔)
alter table recipes add column if not exists staff_visible boolean not null default false;

-- 직원은 "공개"로 켜둔 레시피의 재료(배합)만 읽을 수 있어요
do $$
declare
  v_org text := case when to_regclass('public.organizations') is not null then 'recipe_items.org_id = my_org_id() and ' else '' end;
begin
  drop policy if exists "staff read" on recipe_items;
  execute format(
    'create policy "staff read" on recipe_items for select using (%s my_role() in (''admin'',''staff'') and (my_role() = ''admin'' or exists (select 1 from recipes r where r.id = recipe_items.recipe_id and r.staff_visible)))',
    v_org
  );
end $$;

commit;
