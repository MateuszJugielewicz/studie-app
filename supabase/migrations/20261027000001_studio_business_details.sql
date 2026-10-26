-- A studio's business registration number (CVR in Denmark, VAT/tax number elsewhere), added in the
-- application. Optional, and private: only the studio's owner and the EasySesh team can see it, so it
-- lives outside public.studios (which artists and guests can read).

create table if not exists public.studio_business_details (
  studio_id uuid primary key references public.studios (id) on delete cascade,
  cvr text not null default '' check (char_length(cvr) <= 40),
  updated_at timestamptz not null default now()
);

alter table public.studio_business_details enable row level security;

create policy "studio_business_details: owner or admin reads" on public.studio_business_details for select
  using (public.is_admin() or exists (select 1 from public.studios s where s.id = studio_id and s.owner_id = auth.uid()));
create policy "studio_business_details: owner adds" on public.studio_business_details for insert
  with check (exists (select 1 from public.studios s where s.id = studio_id and s.owner_id = auth.uid()));
create policy "studio_business_details: owner updates" on public.studio_business_details for update
  using (exists (select 1 from public.studios s where s.id = studio_id and s.owner_id = auth.uid()))
  with check (exists (select 1 from public.studios s where s.id = studio_id and s.owner_id = auth.uid()));

revoke all on public.studio_business_details from anon;
grant select, insert, update on public.studio_business_details to authenticated;
