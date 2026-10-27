-- Studios got Europe/Athens by default, so Danish studios' opening hours were read one hour off.
-- The time zone now follows the address country (when a studio is created or its country changes);
-- an unknown or empty country keeps the current zone, and new studios start on Copenhagen time.

create or replace function public.country_timezone(p_country text)
returns text language sql immutable as $$
  select case lower(btrim(coalesce(p_country, '')))
    when 'danmark' then 'Europe/Copenhagen' when 'denmark' then 'Europe/Copenhagen' when 'dk' then 'Europe/Copenhagen'
    when 'sverige' then 'Europe/Stockholm' when 'sweden' then 'Europe/Stockholm' when 'se' then 'Europe/Stockholm'
    when 'norge' then 'Europe/Oslo' when 'norway' then 'Europe/Oslo' when 'no' then 'Europe/Oslo'
    when 'deutschland' then 'Europe/Berlin' when 'germany' then 'Europe/Berlin' when 'de' then 'Europe/Berlin'
    when 'nederland' then 'Europe/Amsterdam' when 'netherlands' then 'Europe/Amsterdam' when 'nl' then 'Europe/Amsterdam'
    when 'polska' then 'Europe/Warsaw' when 'poland' then 'Europe/Warsaw' when 'pl' then 'Europe/Warsaw'
    when 'france' then 'Europe/Paris' when 'fr' then 'Europe/Paris'
    when 'españa' then 'Europe/Madrid' when 'spain' then 'Europe/Madrid' when 'es' then 'Europe/Madrid'
    when 'italia' then 'Europe/Rome' when 'italy' then 'Europe/Rome' when 'it' then 'Europe/Rome'
    when 'ελλάδα' then 'Europe/Athens' when 'greece' then 'Europe/Athens' when 'gr' then 'Europe/Athens'
    when 'united kingdom' then 'Europe/London' when 'uk' then 'Europe/London' when 'gb' then 'Europe/London'
    when 'suomi' then 'Europe/Helsinki' when 'finland' then 'Europe/Helsinki' when 'fi' then 'Europe/Helsinki'
    else null end;
$$;

create or replace function public.studio_timezone_from_country()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' or (new.address ->> 'country') is distinct from (old.address ->> 'country') then
    new.timezone := coalesce(public.country_timezone(new.address ->> 'country'), new.timezone);
  end if;
  return new;
end;
$$;

drop trigger if exists studios_timezone_from_country on public.studios;
create trigger studios_timezone_from_country before insert or update of address on public.studios
  for each row execute function public.studio_timezone_from_country();

alter table public.studios alter column timezone set default 'Europe/Copenhagen';

-- The three current studios are all in Denmark.
update public.studios set timezone = 'Europe/Copenhagen'
where id in ('9443e8a8-557e-4c7d-a943-9581970e44b1', '04522505-8d99-443c-898f-a02fe9410b07', 'f50b1823-9621-4848-b37b-83266d1f45ba');
