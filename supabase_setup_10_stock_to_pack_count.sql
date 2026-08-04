-- ⚠️ 이 스크립트는 딱 한 번만 실행하세요. 두 번 실행하면 재고가 또 나눠져서 숫자가 틀어집니다.
--
-- 지금까지 ingredients.stock / min_stock 은 재료의 "실사용 단위"(ml, g 등)로 저장돼 있었습니다.
-- 이제부터는 "개"(포장 단위, 예: 500ml짜리 1개)로 관리합니다.
-- 레시피에서 쓰는 사용량(recipe_items.amount)은 그대로 ml/g 단위를 유지합니다 (변경 없음).

-- 1) 기존 재고 데이터를 "개" 단위로 환산 (예: 생크림 500ml짜리 재고 3000ml → 6개)
update ingredients
set stock = case when purchase_qty > 0 then stock / purchase_qty else stock end,
    min_stock = case when min_stock is not null and purchase_qty > 0 then min_stock / purchase_qty else min_stock end;

-- 2) 생산(업무일지) 시 재고 차감 로직도 "개" 단위로 계산하도록 수정
--    (레시피 사용량은 ml/g 그대로 두고, 재료의 구매수량(1개당 용량)으로 나눠서 개 단위로 환산 후 차감)
create or replace function apply_recipe_stock_delta(
  p_recipe_id uuid,
  p_batches numeric,
  p_date date,
  p_note text,
  p_sign numeric
)
returns void
language plpgsql
security definer
as $$
declare
  it record;
  v_needed_base numeric;   -- 레시피 사용량 (ml/g 등 실사용 단위)
  v_needed_packs numeric;  -- 위를 "개"로 환산한 값
  v_after numeric;
begin
  for it in
    select ri.ingredient_id, ri.amount, i.name, i.purchase_qty, i.stock
    from recipe_items ri
    join ingredients i on i.id = ri.ingredient_id
    where ri.recipe_id = p_recipe_id
  loop
    v_needed_base := it.amount * p_batches * p_sign;
    v_needed_packs := case when it.purchase_qty > 0 then v_needed_base / it.purchase_qty else v_needed_base end;
    v_after := it.stock - v_needed_packs;
    update ingredients set stock = v_after where id = it.ingredient_id;
    insert into stock_logs (ingredient_id, ingredient_name, unit, date, type, change, after, note)
    values (
      it.ingredient_id, it.name, '개', p_date,
      case when p_sign > 0 then '생산 차감' else '생산 취소(복구)' end,
      -v_needed_packs, v_after, p_note
    );
  end loop;
end;
$$;

grant execute on function apply_recipe_stock_delta(uuid, numeric, date, text, numeric) to authenticated;
