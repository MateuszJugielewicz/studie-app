-- The Resend API key can live in Supabase Vault (name 'resend_api_key') instead of an Edge Function
-- secret. Only the server (service role) can read it. Store it with:
--   select vault.create_secret('re_…', 'resend_api_key');
create or replace function public.resend_api_key()
returns text language sql stable security definer set search_path = public, vault as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'resend_api_key' limit 1;
$$;
revoke execute on function public.resend_api_key() from public, anon, authenticated;
grant execute on function public.resend_api_key() to service_role;
