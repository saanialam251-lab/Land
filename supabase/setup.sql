-- ======================================================================
--  Measure Reality - accounts + per-account history (Supabase)
--  Paste ALL of this into: Supabase dashboard -> SQL Editor -> New query -> Run
--  Safe to run more than once (also safe if you already ran the older version).
-- ======================================================================

-- 1) Users ---------------------------------------------------------------
create table if not exists public.app_users (
  id            uuid primary key default gen_random_uuid(),
  full_name     text        not null,            -- exactly what the user typed
  first_name    text        not null,            -- lower-case FIRST word, used for login
  phone         text        not null,            -- as typed
  phone_key     text        not null unique,     -- last 10 digits, used for login
  email         text        not null,
  created_at    timestamptz not null default now(),
  last_login_at timestamptz
);
create unique index if not exists app_users_email_unique on public.app_users (lower(email));

-- 2) Login sessions (one row per phone that is logged in) -----------------
create table if not exists public.app_sessions (
  token      uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.app_users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists app_sessions_user_idx on public.app_sessions (user_id);

-- 3) Saved measurements, one history per account --------------------------
create table if not exists public.measurements (
  user_id    uuid not null references public.app_users(id) on delete cascade,
  client_id  text not null,                      -- id created by the app
  data       jsonb not null,                     -- the measurement itself
  created_at timestamptz not null default now(),
  primary key (user_id, client_id)
);
create index if not exists measurements_user_time_idx on public.measurements (user_id, created_at desc);

-- 4) Lock every table: the public key can NOT read or write them directly --
alter table public.app_users    enable row level security;
alter table public.app_sessions enable row level security;
alter table public.measurements enable row level security;
revoke all on public.app_users    from anon, authenticated;
revoke all on public.app_sessions from anon, authenticated;
revoke all on public.measurements from anon, authenticated;
-- (no policies on purpose: only the functions below can touch the tables)

-- 5) Helper: which user owns this session token? (internal, not callable) --
create or replace function public.session_user_id(p_token text)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v uuid;
begin
  begin
    select user_id into v
    from public.app_sessions
    where token = p_token::uuid
      and created_at > now() - interval '180 days';
  exception when others then
    return null;
  end;
  return v;
end;
$$;
revoke all on function public.session_user_id(text) from public, anon, authenticated;

-- 6) Create account --------------------------------------------------------
create or replace function public.create_account(p_name text, p_phone text, p_email text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name   text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  v_first  text := lower(split_part(btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g')), ' ', 1));
  v_digits text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  v_key    text := right(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), 10);
  v_email  text := lower(btrim(coalesce(p_email, '')));
begin
  if length(v_first) < 2 then
    return jsonb_build_object('ok', false, 'error', 'invalid_name');
  end if;
  if length(v_digits) < 7 or length(v_digits) > 15 then
    return jsonb_build_object('ok', false, 'error', 'invalid_phone');
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    return jsonb_build_object('ok', false, 'error', 'invalid_email');
  end if;

  if exists (select 1 from public.app_users where phone_key = v_key) then
    return jsonb_build_object('ok', false, 'error', 'phone_exists');
  end if;
  if exists (select 1 from public.app_users where lower(email) = v_email) then
    return jsonb_build_object('ok', false, 'error', 'email_exists');
  end if;

  insert into public.app_users (full_name, first_name, phone, phone_key, email)
  values (v_name, v_first, btrim(p_phone), v_key, v_email);

  return jsonb_build_object('ok', true);
exception
  when unique_violation then
    return jsonb_build_object('ok', false, 'error', 'phone_exists');
end;
$$;

-- 7) Login: FIRST name (any capitals) + phone number -> returns a session token
create or replace function public.login_user(p_name text, p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_first text := lower(split_part(btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g')), ' ', 1));
  v_key   text := right(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), 10);
  v_token uuid;
  u       public.app_users%rowtype;
begin
  if v_first = '' or v_key = '' then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  select * into u
  from public.app_users
  where first_name = v_first and phone_key = v_key;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  update public.app_users set last_login_at = now() where id = u.id;
  delete from public.app_sessions where user_id = u.id and created_at < now() - interval '180 days';
  insert into public.app_sessions (user_id) values (u.id) returning token into v_token;

  return jsonb_build_object(
    'ok', true,
    'user', jsonb_build_object(
      'id', u.id,
      'name', u.full_name,
      'phone', u.phone,
      'email', u.email,
      'token', v_token
    )
  );
end;
$$;

-- 8) Logout (ends this phone's session only) -------------------------------
create or replace function public.logout_user(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    delete from public.app_sessions where token = p_token::uuid;
  exception when others then
    null;
  end;
  return jsonb_build_object('ok', true);
end;
$$;

-- 9) History: save / list / delete (only for the logged-in account) --------
create or replace function public.save_measurement(p_token text, p_id text, p_data jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := public.session_user_id(p_token);
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'bad_session');
  end if;
  if p_id is null or length(p_id) = 0 or length(p_id) > 100
     or p_data is null or pg_column_size(p_data) > 20000 then
    return jsonb_build_object('ok', false, 'error', 'invalid_data');
  end if;

  insert into public.measurements (user_id, client_id, data)
  values (v_uid, p_id, p_data)
  on conflict (user_id, client_id) do update set data = excluded.data;

  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.list_measurements(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := public.session_user_id(p_token);
  v_list jsonb;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'bad_session');
  end if;

  select coalesce(jsonb_agg(s.data order by s.created_at desc), '[]'::jsonb)
    into v_list
  from (
    select data, created_at
    from public.measurements
    where user_id = v_uid
    order by created_at desc
    limit 2000
  ) s;

  return jsonb_build_object('ok', true, 'items', v_list);
end;
$$;

create or replace function public.delete_measurement(p_token text, p_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := public.session_user_id(p_token);
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'bad_session');
  end if;
  delete from public.measurements where user_id = v_uid and client_id = p_id;
  return jsonb_build_object('ok', true);
end;
$$;

-- 10) Who may call what ----------------------------------------------------
revoke all on function public.create_account(text, text, text)  from public;
revoke all on function public.login_user(text, text)             from public;
revoke all on function public.logout_user(text)                  from public;
revoke all on function public.save_measurement(text, text, jsonb) from public;
revoke all on function public.list_measurements(text)            from public;
revoke all on function public.delete_measurement(text, text)     from public;

grant execute on function public.create_account(text, text, text)  to anon, authenticated;
grant execute on function public.login_user(text, text)             to anon, authenticated;
grant execute on function public.logout_user(text)                  to anon, authenticated;
grant execute on function public.save_measurement(text, text, jsonb) to anon, authenticated;
grant execute on function public.list_measurements(text)            to anon, authenticated;
grant execute on function public.delete_measurement(text, text)     to anon, authenticated;

-- 11) Make the API see the new functions right away
notify pgrst, 'reload schema';
