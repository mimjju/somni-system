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
  v_needed numeric;
  v_after numeric;
begin
  for it in
    select ri.ingredient_id, ri.amount, i.name, i.purchase_unit, i.stock
    from recipe_items ri
    join ingredients i on i.id = ri.ingredient_id
    where ri.recipe_id = p_recipe_id
  loop
    v_needed := it.amount * p_batches * p_sign;
    v_after := it.stock - v_needed;
    update ingredients set stock = v_after where id = it.ingredient_id;
    insert into stock_logs (ingredient_id, ingredient_name, unit, date, type, change, after, note)
    values (
      it.ingredient_id, it.name, it.purchase_unit, p_date,
      case when p_sign > 0 then '생산 차감' else '생산 취소(복구)' end,
      -v_needed, v_after, p_note
    );
  end loop;
end;
$$;

grant execute on function apply_recipe_stock_delta(uuid, numeric, date, text, numeric) to authenticated;
