-- MovieBox schema: catalog, episodes, subscriptions, payments, progress.
-- Run with: supabase db push

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------- profiles
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, new.raw_user_meta_data ->> 'full_name');
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ------------------------------------------------------------------ movies
create table public.movies (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  poster_url text,
  genre text,
  release_year int,
  free_episodes int not null default 3,   -- episodes 1..N are free
  published boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.episodes (
  id uuid primary key default gen_random_uuid(),
  movie_id uuid not null references public.movies(id) on delete cascade,
  episode_number int not null check (episode_number > 0),
  title text,
  duration_seconds int,
  thumbnail_url text,
  created_at timestamptz not null default now(),
  unique (movie_id, episode_number)
);

-- The private storage path of each video lives in its own table that clients
-- can never read. Only the get-playback edge function (service role) reads it.
create table public.episode_media (
  episode_id uuid primary key references public.episodes(id) on delete cascade,
  video_path text not null
);

-- -------------------------------------------------------- plans & payments
create table public.plans (
  id text primary key,                     -- e.g. 'monthly'
  name text not null,
  price int not null check (price > 0),    -- whole currency units (TZS)
  currency text not null default 'TZS',
  duration_days int not null check (duration_days > 0),
  active boolean not null default true
);

insert into public.plans (id, name, price, duration_days) values
  ('weekly',  'Weekly',   2000,  7),
  ('monthly', 'Monthly',  6000, 30),
  ('yearly',  'Yearly',  60000, 365);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_id text not null references public.plans(id),
  amount int not null,
  currency text not null,
  status text not null default 'pending'
    check (status in ('pending', 'succeeded', 'failed')),
  provider_ref text,
  created_at timestamptz not null default now(),
  paid_at timestamptz
);

create table public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_id text not null references public.plans(id),
  payment_id uuid unique references public.payments(id),
  starts_at timestamptz not null default now(),
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);
create index on public.subscriptions (user_id, expires_at desc);

create or replace function public.has_active_subscription(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.subscriptions
    where user_id = uid and expires_at > now()
  );
$$;

-- ---------------------------------------------------------- watch progress
create table public.watch_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  episode_id uuid not null references public.episodes(id) on delete cascade,
  position_seconds int not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, episode_id)
);

-- --------------------------------------------------------------------- RLS
alter table public.profiles       enable row level security;
alter table public.movies         enable row level security;
alter table public.episodes       enable row level security;
alter table public.episode_media  enable row level security;  -- no policies: server only
alter table public.plans          enable row level security;
alter table public.payments       enable row level security;
alter table public.subscriptions  enable row level security;
alter table public.watch_progress enable row level security;

create policy "own profile read" on public.profiles
  for select using (auth.uid() = id);
create policy "own profile update" on public.profiles
  for update using (auth.uid() = id);
-- users may change only these columns (not is_admin)
revoke update on public.profiles from authenticated;
grant update (full_name, phone) on public.profiles to authenticated;

create policy "published movies are readable" on public.movies
  for select to authenticated using (published);

create policy "episodes of published movies are readable" on public.episodes
  for select to authenticated
  using (exists (select 1 from public.movies m
                 where m.id = movie_id and m.published));

create policy "active plans are readable" on public.plans
  for select to authenticated using (active);

create policy "own payments" on public.payments
  for select using (auth.uid() = user_id);

create policy "own subscriptions" on public.subscriptions
  for select using (auth.uid() = user_id);

create policy "own progress" on public.watch_progress
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Payments and subscriptions are written only by edge functions (service role).

-- ----------------------------------------------------------------- storage
-- posters: public (shown in the catalog). videos: private, served by signed URL.
insert into storage.buckets (id, name, public)
values ('posters', 'posters', true)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('videos', 'videos', false)
on conflict (id) do nothing;
-- No storage.objects policies for 'videos' => clients cannot read or list it.
