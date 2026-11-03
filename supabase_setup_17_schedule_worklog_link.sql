-- ============================================================
-- 스케줄 완료 체크 → 업무일지 자동 기록 연결
-- 이 파일 전체를 한 번에 복사해서 SQL Editor에 붙여넣고 Run 하세요. 여러 번 실행해도 괜찮아요.
-- ============================================================

-- 완료 체크로 자동 생성된 업무일지 (완료를 취소하면 이 업무일지를 지우고 재고를 되돌려요)
alter table schedule_assignments add column if not exists work_log_id uuid references work_logs(id) on delete set null;
