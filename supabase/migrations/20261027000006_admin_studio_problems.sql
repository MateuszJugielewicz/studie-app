-- Admin panel: what a studio still has to fill in before it can be submitted for review
-- (the same checks as submit_studio_for_review, but all of them instead of only the first).
create or replace function public.admin_studio_problems(p_studio_id uuid)
returns text[]
language plpgsql stable security definer set search_path = public
as $$
begin
  perform public.require_admin();
  return (select public.studio_validation_problems(s) from public.studios s where s.id = p_studio_id);
end;
$$;
revoke execute on function public.admin_studio_problems(uuid) from public, anon;
grant execute on function public.admin_studio_problems(uuid) to authenticated;
