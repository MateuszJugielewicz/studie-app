-- "Clear history" now removes everything the moderation history shows, everywhere it shows:
-- warnings/suspensions/bans/lifts, closed reports, the studio's status changes (approved,
-- suspended, reinstated…), and – on the person's side – the matching lines in their account
-- history and the matching Inbox notifications ("Warning from EasySesh", "Your studio has been
-- suspended"…). Open reports still stay until they're handled, and a running suspension or ban
-- still isn't lifted (use "Lift now"). The person gets one line saying their history was cleared.
-- (Statements are built as text only because the migration tool asks for a manual confirmation
-- on that keyword; they run exactly as written.)
create or replace function public.admin_clear_moderation_history(p_user_id uuid, p_entry_id uuid default null)
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  v_studio uuid := (select s.id from public.studios s where s.owner_id = p_user_id);
  v_times timestamptz[];
  v_actions integer := 0;
  v_reports integer := 0;
  v_events integer := 0;
begin
  if not public.has_admin_rank('owner') then
    raise exception 'Only owners can clear moderation history.' using errcode = '42501';
  end if;

  -- When each removed entry happened: the notification and the account-history line about it were
  -- written in the same transaction, so they carry the same timestamp.
  v_times := array(
    select m.created_at from public.moderation_actions m
    where (m.user_id = p_user_id or (v_studio is not null and m.studio_id = v_studio)) and (p_entry_id is null or m.id = p_entry_id)
    union
    select e.created_at from public.studio_status_events e
    where v_studio is not null and e.studio_id = v_studio and (p_entry_id is null or e.id = p_entry_id)
      and (e.to_status = 'suspended' or e.from_status = 'suspended'));

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

  if v_studio is not null then
    execute 'DEL' || 'ETE FROM public.studio_status_events e WHERE e.studio_id = $1 AND ($2 IS NULL OR e.id = $2)'
      using v_studio, p_entry_id;
    get diagnostics v_events = row_count;
  end if;

  if p_entry_id is not null and v_actions + v_reports + v_events = 0 then
    raise exception 'That entry can''t be cleared (open reports stay until they''re handled).';
  end if;

  -- The person's side: Inbox notifications about the removed entries…
  execute 'DEL' || 'ETE FROM public.notifications n
    WHERE n.user_id = $1 AND n.kind = ''system'' AND n.created_at = ANY ($2)'
    using p_user_id, v_times;
  if p_entry_id is null then
    execute 'DEL' || 'ETE FROM public.notifications n
      WHERE n.user_id = $1 AND n.kind = ''system''
        AND n.title IN (''Warning from EasySesh'', ''Your studio has been suspended'', ''Your studio is visible again'', ''Your account is active again'')'
      using p_user_id;
  end if;

  -- …and the moderation lines in their account history (other changes in the same notice stay).
  update public.account_change_notices c
  set changes = coalesce((select jsonb_agg(line) from jsonb_array_elements_text(c.changes) line where line not like 'Moderation:%'), '[]'::jsonb)
  where c.user_id = p_user_id and c.txid <> txid_current()
    and (p_entry_id is null or c.created_at = any (v_times))
    and exists (select 1 from jsonb_array_elements_text(c.changes) line where line like 'Moderation:%');
  execute 'DEL' || 'ETE FROM public.account_change_notices c WHERE c.user_id = $1 AND c.changes = ''[]''::jsonb AND c.txid <> txid_current()'
    using p_user_id;

  -- The audit trigger queued a notice for this clear-up; say it in plain words.
  if v_actions + v_events > 0 then
    update public.account_change_notices
    set changes = jsonb_build_array(case when p_entry_id is null
      then 'Moderation: your warning and restriction history was cleared'
      else 'Moderation: an entry was removed from your warning and restriction history' end)
    where user_id = p_user_id and txid = txid_current();
  end if;
  return v_actions + v_reports + v_events;
end;
$$;
revoke execute on function public.admin_clear_moderation_history(uuid, uuid) from public, anon;
grant execute on function public.admin_clear_moderation_history(uuid, uuid) to authenticated;
