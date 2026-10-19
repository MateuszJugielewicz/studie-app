-- Automatic flags: messages, bios, studio texts and reviews that mention minors, paying outside
-- EasySesh, or illegal things are reported to the team (Moderation → Reports) for a person to check.
-- Nothing is blocked or hidden automatically. The word lists are in content_flag_rules, which admins
-- can change in the admin panel (Auto-flags).

alter table public.reports alter column reporter_id drop not null;  -- null = reported automatically

create table if not exists public.content_flag_rules (
  id uuid primary key default gen_random_uuid(),
  category text not null check (category in ('minors', 'off_platform_payment', 'illegal', 'contact_details', 'other')),
  -- Case-insensitive POSIX regular expression (\m and \M are word boundaries).
  pattern text not null check (char_length(pattern) between 2 and 500),
  note text not null default '',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.content_flag_rules enable row level security;
create policy "content_flag_rules: staff read" on public.content_flag_rules for select using (public.is_admin());
create policy "content_flag_rules: admins write" on public.content_flag_rules for insert with check (public.has_admin_rank('admin'));
create policy "content_flag_rules: admins update" on public.content_flag_rules for update using (public.has_admin_rank('admin')) with check (public.has_admin_rank('admin'));
create policy "content_flag_rules: admins remove" on public.content_flag_rules for delete using (public.has_admin_rank('admin'));

-- A broken pattern would break every save, so patterns are checked when they're written.
create or replace function public.validate_flag_rule()
returns trigger
language plpgsql set search_path = public
as $$
begin
  perform 'x' ~* new.pattern;
  return new;
exception when invalid_regular_expression then
  raise exception 'That pattern isn''t a valid regular expression.';
end;
$$;
create trigger validate_flag_rule before insert or update on public.content_flag_rules
  for each row execute function public.validate_flag_rule();

insert into public.content_flag_rules (category, pattern, note)
select v.category, v.pattern, v.note
from (values
  ('minors', '\m(kid|kids|child|children|minor|minors|underage|under-age|teen|teens|teenager|schoolgirl|schoolboy|preteen)\M', 'Children / minors'),
  ('minors', '\m(1[0-7]|[5-9]) ?(yo|y/o|yrs? old|years? old|year-old)\M', 'Age under 18'),
  ('minors', '(ανήλικ|παιδάκι|\mbørn\M|\mkinder\M|\mdziec|\menfants?\M|\mniños?\M|\mbambin|\mbarn\M|\mkinderen\M)', 'Children (other languages)'),
  ('off_platform_payment', '\m(paypal|revolut|venmo|zelle|cash ?app|western union|moneygram|wise transfer|mobilepay|swish|blik|viva wallet)\M', 'Payment apps'),
  ('off_platform_payment', '\m(iban|bank transfer|wire transfer|bank account|crypto|bitcoin|btc|usdt|ethereum)\M', 'Bank / crypto payments'),
  ('off_platform_payment', '(pay (me |us |you )?(directly|outside|off[- ]?(the )?(app|platform))|outside (of )?(the )?(app|platform|easysesh)|skip (the )?(app|fees?|platform|easysesh)|avoid (the )?(fees?|commission)|without (the )?(app|easysesh)|book (me )?directly)', 'Paying or booking outside EasySesh'),
  ('illegal', '\m(cocaine|coke|heroin|meth|mdma|molly|ecstasy|lsd|ketamine|fentanyl|xanax|oxy|weed|cannabis|marijuana|hash)\M', 'Drugs'),
  ('illegal', '\m(gun|guns|pistol|firearm|firearms|ammo|weapon|weapons|stolen|counterfeit|fake (id|passport)|launder(ing)?|escort|prostitut\w*|sex work\w*|nudes)\M', 'Weapons, stolen goods, sex work'),
  ('contact_details', '(\+?\d[\d \-]{8,}\d|[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}|whats ?app|telegram|signal me|dm me on|instagram\.com/|t\.me/)', 'Phone numbers, emails and chat apps (in messages only)')
) as v(category, pattern, note)
where not exists (select 1 from public.content_flag_rules);

-- The first matching rule per category, as "category: matched text".
create or replace function public.scan_content(p_text text, p_include_contact boolean default false)
returns table (category text, matched text)
language sql stable security definer set search_path = public
as $$
  select distinct on (r.category) r.category, (regexp_match(p_text, r.pattern, 'i'))[1]
  from public.content_flag_rules r
  where r.is_active and coalesce(p_text, '') <> '' and p_text ~* r.pattern
    and (p_include_contact or r.category <> 'contact_details')
  order by r.category, r.created_at;
$$;
revoke execute on function public.scan_content(text, boolean) from public, anon, authenticated;

create or replace function public.flag_content()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_old jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) end;
  v_new jsonb := to_jsonb(new);
  v_fields text[];
  v_field text;
  v_text text;
  v_target public.report_target;
  v_target_id uuid;
  v_author uuid;
  v_hit record;
begin
  case tg_table_name
    when 'messages' then v_fields := array['body']; v_target := 'message'; v_target_id := new.id; v_author := (v_new ->> 'sender_id')::uuid;
    when 'artist_profiles' then v_fields := array['artist_name', 'bio']; v_target := 'user'; v_target_id := new.id; v_author := new.id;
    when 'studios' then v_fields := array['name', 'tagline', 'description', 'rules']; v_target := 'studio'; v_target_id := new.id; v_author := (v_new ->> 'owner_id')::uuid;
    when 'reviews' then v_fields := array['text', 'studio_reply']; v_target := 'review'; v_target_id := new.id; v_author := null;
    when 'artist_reviews' then v_fields := array['text']; v_target := 'user'; v_target_id := (v_new ->> 'artist_id')::uuid; v_author := null;
    else return null;
  end case;
  -- System messages and the team's own edits aren't checked.
  if tg_table_name = 'messages' and (v_author is null or coalesce(v_new ->> 'kind', 'text') <> 'text') then return null; end if;
  if v_author is not null and exists (select 1 from public.profiles p where p.id = v_author and p.role = 'admin') then return null; end if;

  foreach v_field in array v_fields loop
    continue when not (v_new ? v_field);
    v_text := v_new ->> v_field;
    continue when coalesce(v_text, '') = '' or (v_old is not null and v_old ->> v_field is not distinct from v_text);
    for v_hit in select * from public.scan_content(v_text, tg_table_name = 'messages') loop
      -- One open automatic report per thing and category is enough.
      continue when exists (
        select 1 from public.reports r
        where r.reporter_id is null and r.status = 'open' and r.target_type = v_target and r.target_id = v_target_id
          and r.details like 'Automatic flag: ' || v_hit.category || '%');
      insert into public.reports (reporter_id, target_type, target_id, reason, details)
      values (null, v_target, v_target_id,
              case when v_hit.category = 'off_platform_payment' then 'fraud'::public.report_reason else 'inappropriate'::public.report_reason end,
              'Automatic flag: ' || v_hit.category || ' – matched "' || coalesce(v_hit.matched, '?') || '" in ' || replace(tg_table_name, '_', ' ') || ' ' || replace(v_field, '_', ' ')
                || E'.\n\n"' || left(v_text, 500) || '"');
    end loop;
  end loop;
  return null;
end;
$$;
revoke execute on function public.flag_content() from public, anon, authenticated;

do $$
declare
  t text;
begin
  foreach t in array array['messages', 'artist_profiles', 'studios', 'reviews', 'artist_reviews'] loop
    if to_regclass('public.' || t) is null then continue; end if;
    if not exists (select 1 from pg_trigger where tgname = 'zz_flag_content' and tgrelid = ('public.' || t)::regclass) then
      execute format('create trigger zz_flag_content after insert or update on public.%I for each row execute function public.flag_content()', t);
    end if;
  end loop;
  if not exists (select 1 from pg_trigger where tgname = 'zz_staff_write_audit' and tgrelid = 'public.content_flag_rules'::regclass) then
    create trigger zz_staff_write_audit after insert or update or delete on public.content_flag_rules for each row execute function public.staff_write_audit();
  end if;
end $$;
