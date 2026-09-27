-- 久序 / 王殿 Supabase 完整初始化与增量修复脚本
-- 在 Supabase SQL Editor 中整段执行。适用于新项目，也可重复执行已有部署。
-- 注意：此脚本保留 todos 中的数据，不会删除表或记录。

-- -----------------------------------------------------------------------------
-- Notes
-- -----------------------------------------------------------------------------
create table if not exists public.notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null default '',
  content text not null default '',
  pinned boolean not null default false,
  tags text[] not null default '{}',
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.notes add column if not exists pinned boolean not null default false;
alter table public.notes add column if not exists tags text[] not null default '{}';
alter table public.notes add column if not exists deleted_at timestamptz;
create index if not exists notes_user_idx on public.notes (user_id);
create index if not exists notes_updated_idx on public.notes (updated_at desc);
create index if not exists notes_tags_idx on public.notes using gin (tags);
create index if not exists notes_deleted_idx on public.notes (user_id, deleted_at);
alter table public.notes enable row level security;
drop policy if exists users_select_own_notes on public.notes;
drop policy if exists users_insert_own_notes on public.notes;
drop policy if exists users_update_own_notes on public.notes;
drop policy if exists users_delete_own_notes on public.notes;
create policy users_select_own_notes on public.notes for select using (auth.uid() = user_id);
create policy users_insert_own_notes on public.notes for insert with check (auth.uid() = user_id);
create policy users_update_own_notes on public.notes for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy users_delete_own_notes on public.notes for delete using (auth.uid() = user_id);

create or replace function public.handle_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;
drop trigger if exists notes_updated_at on public.notes;
create trigger notes_updated_at before update on public.notes
for each row execute function public.handle_updated_at();

-- -----------------------------------------------------------------------------
-- Check-ins
-- -----------------------------------------------------------------------------
create table if not exists public.checkins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  days int not null default 0,
  last_checkin date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.checkins enable row level security;
drop policy if exists users_select_own_checkins on public.checkins;
create policy users_select_own_checkins on public.checkins for select using (auth.uid() = user_id);

create or replace function public.checkin()
returns table (days int, last_checkin date)
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  today date := (now() at time zone 'Asia/Shanghai')::date;
  cur_days int;
  cur_last date;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select c.days, c.last_checkin into cur_days, cur_last
    from public.checkins c where c.user_id = uid for update;
  if cur_days is null then
    cur_days := 1; cur_last := today;
    insert into public.checkins (user_id, days, last_checkin) values (uid, cur_days, cur_last);
  elsif cur_last is distinct from today then
    cur_days := cur_days + 1; cur_last := today;
    update public.checkins set days = cur_days, last_checkin = cur_last, updated_at = now()
      where user_id = uid;
  end if;
  return query select cur_days, cur_last;
end;
$$;
grant execute on function public.checkin() to authenticated, anon;

-- -----------------------------------------------------------------------------
-- Profiles, chat and avatars
-- -----------------------------------------------------------------------------
create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  nickname text,
  avatar_url text,
  title text default '乞丐',
  chat_days int default 0,
  updated_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
drop policy if exists profiles_select_all on public.profiles;
drop policy if exists profiles_insert_own on public.profiles;
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_select_all on public.profiles for select using (true);
create policy profiles_insert_own on public.profiles for insert with check (auth.uid() = user_id);
create policy profiles_update_own on public.profiles for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (user_id, nickname)
  values (new.id, split_part(coalesce(new.email, '新用户'), '@', 1))
  on conflict (user_id) do nothing;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  nickname text, avatar_url text, title text,
  content text not null,
  created_at timestamptz not null default now()
);
create index if not exists messages_created_at_idx on public.messages (created_at desc);
alter table public.messages enable row level security;
drop policy if exists messages_select_all on public.messages;
drop policy if exists messages_insert_own on public.messages;
drop policy if exists messages_delete_own on public.messages;
create policy messages_select_all on public.messages for select using (true);
create policy messages_insert_own on public.messages for insert with check (auth.uid() = user_id);
create policy messages_delete_own on public.messages for delete using (auth.uid() = user_id);

insert into storage.buckets (id, name, public) values ('avatars', 'avatars', true)
on conflict (id) do nothing;
drop policy if exists avatars_read_all on storage.objects;
drop policy if exists avatars_write_own on storage.objects;
drop policy if exists avatars_update_own on storage.objects;
create policy avatars_read_all on storage.objects for select using (bucket_id = 'avatars');
create policy avatars_write_own on storage.objects for insert with check (
  bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]
);
create policy avatars_update_own on storage.objects for update using (
  bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]
) with check (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);

-- -----------------------------------------------------------------------------
-- Todos and habits. Existing todos are preserved; id remains text for todo-* ids.
-- -----------------------------------------------------------------------------
create table if not exists public.todos (
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  done boolean not null default false,
  remind_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.todos enable row level security;
drop policy if exists todos_all_own on public.todos;
create policy todos_all_own on public.todos for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create table if not exists public.habits (
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  icon text default 'check_circle',
  color bigint default 4284966897,
  created_at timestamptz not null default now()
);
alter table public.habits enable row level security;
drop policy if exists habits_all_own on public.habits;
create policy habits_all_own on public.habits for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create table if not exists public.habit_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  habit_id text not null,
  day date not null,
  unique (user_id, habit_id, day)
);
alter table public.habit_logs enable row level security;
drop policy if exists habit_logs_all_own on public.habit_logs;
create policy habit_logs_all_own on public.habit_logs for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- -----------------------------------------------------------------------------
-- Community and official welcome post
-- -----------------------------------------------------------------------------
create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  content text not null,
  created_at timestamptz not null default now()
);
alter table public.posts alter column user_id drop not null;
create index if not exists posts_created_at_idx on public.posts (created_at desc);
alter table public.posts enable row level security;
drop policy if exists posts_select_all on public.posts;
drop policy if exists posts_insert_own on public.posts;
drop policy if exists posts_update_own on public.posts;
drop policy if exists posts_delete_own on public.posts;
create policy posts_select_all on public.posts for select using (true);
create policy posts_insert_own on public.posts for insert with check (auth.uid() = user_id);
create policy posts_update_own on public.posts for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy posts_delete_own on public.posts for delete using (auth.uid() = user_id);

create table if not exists public.post_likes (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (post_id, user_id)
);
alter table public.post_likes enable row level security;
drop policy if exists likes_select_all on public.post_likes;
drop policy if exists likes_insert_own on public.post_likes;
drop policy if exists likes_delete_own on public.post_likes;
create policy likes_select_all on public.post_likes for select using (true);
create policy likes_insert_own on public.post_likes for insert with check (auth.uid() = user_id);
create policy likes_delete_own on public.post_likes for delete using (auth.uid() = user_id);

create table if not exists public.post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  content text not null,
  created_at timestamptz not null default now()
);
create index if not exists post_comments_post_idx on public.post_comments (post_id, created_at);
alter table public.post_comments enable row level security;
drop policy if exists comments_select_all on public.post_comments;
drop policy if exists comments_insert_own on public.post_comments;
drop policy if exists comments_delete_own on public.post_comments;
create policy comments_select_all on public.post_comments for select using (true);
create policy comments_insert_own on public.post_comments for insert with check (auth.uid() = user_id);
create policy comments_delete_own on public.post_comments for delete using (auth.uid() = user_id);

insert into public.posts (user_id, content)
select null, '这里是久序官方，欢迎使用社区功能，在这里可以分享有趣的知识或者有用的感悟'
where not exists (select 1 from public.posts where user_id is null);

-- Add realtime tables only when absent from the publication.
do $$
declare t text;
begin
  foreach t in array array['notes','checkins','messages','todos','habits','posts'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end;
$$;

create or replace function public.delete_my_account_data()
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not authenticated'; end if;
  delete from public.messages where user_id = uid;
  delete from public.notes where user_id = uid;
  delete from public.checkins where user_id = uid;
  delete from public.todos where user_id = uid;
  delete from public.habit_logs where user_id = uid;
  delete from public.habits where user_id = uid;
  delete from public.post_comments where user_id = uid;
  delete from public.post_likes where user_id = uid;
  delete from public.posts where user_id = uid;
  delete from public.profiles where user_id = uid;
end;
$$;
grant execute on function public.delete_my_account_data() to authenticated;
