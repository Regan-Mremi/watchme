-- Lets accounts marked is_admin manage movies, episodes and files from the
-- admin web page, using their normal login (no secret key in the browser).

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false);
$$;

create policy "admin manages movies" on public.movies
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy "admin manages episodes" on public.episodes
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy "admin manages episode media" on public.episode_media
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy "admin reads payments" on public.payments
  for select to authenticated using (public.is_admin());

create policy "admin reads subscriptions" on public.subscriptions
  for select to authenticated using (public.is_admin());

create policy "admin manages video and poster files" on storage.objects
  for all to authenticated
  using (bucket_id in ('videos', 'posters') and public.is_admin())
  with check (bucket_id in ('videos', 'posters') and public.is_admin());

-- To make yourself an admin, run this once in the Supabase SQL editor
-- (after you have signed up in the app or on the admin page):
--
--   update public.profiles set is_admin = true
--   where id = (select id from auth.users where email = 'YOUR_EMAIL');
