-- ============================================================
-- 홈페이지에서 관리자/직원 비밀번호 바꾸기
-- 이 파일 전체를 한 번에 복사해서 SQL Editor에 붙여넣고 Run 하세요. 여러 번 실행해도 괜찮아요.
-- 관리자 계정으로 로그인했을 때만 바꿀 수 있고, 두 비밀번호가 같아지지 않게 막아요.
-- (두 비밀번호가 같으면 로그인 화면에서 누구나 관리자로 들어가요)
-- ============================================================

create extension if not exists pgcrypto with schema extensions;

create or replace function set_account_password(p_target text, p_password text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_email text;
  v_other text;
begin
  if my_role() is distinct from 'admin' then
    raise exception '관리자만 비밀번호를 바꿀 수 있어요.';
  end if;
  if p_target = 'admin' then
    v_email := 'admin@somri.local'; v_other := 'staff@somri.local';
  elsif p_target = 'staff' then
    v_email := 'staff@somri.local'; v_other := 'admin@somri.local';
  else
    raise exception '대상이 올바르지 않아요.';
  end if;
  if length(coalesce(p_password, '')) < 6 then
    raise exception '비밀번호는 6자 이상이어야 해요.';
  end if;
  if exists (
    select 1 from auth.users
    where email = v_other and encrypted_password = extensions.crypt(p_password, encrypted_password)
  ) then
    raise exception '관리자 비밀번호와 직원 비밀번호는 서로 달라야 해요.';
  end if;

  update auth.users
  set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')),
      updated_at = now()
  where email = v_email;
end;
$$;

revoke all on function set_account_password(text, text) from public, anon;
grant execute on function set_account_password(text, text) to authenticated;
