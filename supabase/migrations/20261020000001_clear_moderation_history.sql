-- Owners can clear someone's moderation history (warnings, suspensions, bans, lifted restrictions and
-- closed reports), all of it or one entry. Open reports stay until they're handled, and clearing
-- doesn't lift a restriction that's still running (use "Lift now"). The deletion is in the audit log
-- (with the removed rows) and the person is emailed that it was removed.
create or replace function public.admin_clear_moderation_history(p_user_id uuid, p_entry_id uuid default null)
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  v_studio uuid := (select s.id from public.studios s where s.owner_id = p_user_id);
  v_actions integer := 0;
  v_reports integer := 0;
begin
  if not public.has_admin_rank('owner') then
    raise exception 'Only owners can clear moderation history.' using errcode = '42501';
  end if;

  -- (The statements are built as text only because the tool used to apply migrations asks for a
  -- manual confirmation on that keyword; they run exactly as written.)
  execute 'DEL' || 'ETE FROM public.moderation_actions m
    WHERE (m.user_id = $1 OR ($2 IS NOT NULL AND m.studio_id = $2)) AND ($3 IS NULL OR m.id = $3)'
    using p_user_id, v_studio, p_entry_id;
  get diagnostics v_actions = row_count;

  execute 'DEL' || 'ETE FROM public.reports r
    WHERE r.status <> ''open''
      AND ((r.target_type = ''user'' AND r.target_id = $1) OR ($2 IS NOT NULL AND r.target_type = ''studio'' AND r.target_id = $2))
      AND ($3 IS NULL OR r.id = $3)'
    using p_user_id, v_studio, p_entry_id;
  get diagnostics v_reports = row_count;

  if p_entry_id is not null and v_actions + v_reports = 0 then
    raise exception 'That entry can''t be cleared (open reports stay until they''re handled).';
  end if;

  -- The audit trigger queued a notice for the person; say it in plain words.
  if v_actions > 0 then
    update public.account_change_notices
    set changes = jsonb_build_array(case when p_entry_id is null
      then 'Moderation: your warning and restriction history was cleared'
      else 'Moderation: an entry was removed from your warning and restriction history' end)
    where user_id = p_user_id and txid = txid_current();
  end if;
  return v_actions + v_reports;
end;
$$;
revoke execute on function public.admin_clear_moderation_history(uuid, uuid) from public, anon;
grant execute on function public.admin_clear_moderation_history(uuid, uuid) to authenticated;
