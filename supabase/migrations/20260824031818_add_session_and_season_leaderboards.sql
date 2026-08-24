create table public.leaderboard_seasons (
  id bigint generated always as identity primary key,
  season_number integer not null unique check (season_number > 0),
  label text not null check (char_length(btrim(label)) between 1 and 60),
  status text not null default 'draft' check (status in ('draft', 'open', 'closed')),
  is_visible boolean not null default false,
  created_at timestamptz not null default now(),
  opened_at timestamptz,
  closed_at timestamptz,
  created_by uuid,
  opened_by uuid,
  closed_by uuid
);

create unique index leaderboard_seasons_one_open_idx
  on public.leaderboard_seasons ((1))
  where status = 'open';

create table public.leaderboard_sessions (
  id bigint generated always as identity primary key,
  season_id bigint not null references public.leaderboard_seasons(id) on delete restrict,
  session_number smallint not null check (session_number between 1 and 3),
  label text not null check (char_length(btrim(label)) between 1 and 60),
  business_date date,
  status text not null default 'draft' check (status in ('draft', 'open', 'closed')),
  created_at timestamptz not null default now(),
  opened_at timestamptz,
  closed_at timestamptz,
  created_by uuid,
  opened_by uuid,
  closed_by uuid,
  unique (season_id, session_number)
);

create unique index leaderboard_sessions_one_open_idx
  on public.leaderboard_sessions ((1))
  where status = 'open';

create index leaderboard_sessions_season_idx
  on public.leaderboard_sessions (season_id, session_number);

create table public.leaderboard_session_scores (
  session_id bigint not null references public.leaderboard_sessions(id) on delete restrict,
  host_name text not null references public.host_leaderboard(host_name)
    on update cascade on delete restrict,
  tip_count bigint not null default 0 check (tip_count >= 0),
  total_amount bigint not null default 0 check (total_amount >= 0),
  updated_at timestamptz not null default now(),
  primary key (session_id, host_name)
);

create index leaderboard_session_scores_rank_idx
  on public.leaderboard_session_scores
  (session_id, total_amount desc, tip_count desc, host_name);

create index leaderboard_session_scores_host_idx
  on public.leaderboard_session_scores (host_name);

create table public.leaderboard_tip_events (
  id bigint generated always as identity primary key,
  session_id bigint not null references public.leaderboard_sessions(id) on delete restrict,
  host_name text not null references public.host_leaderboard(host_name)
    on update cascade on delete restrict,
  amount_delta bigint not null check (amount_delta <> 0),
  tip_delta smallint not null check (tip_delta in (-1, 1)),
  note text check (note is null or char_length(note) <= 160),
  created_by uuid not null,
  created_by_email text not null,
  created_at timestamptz not null default now(),
  idempotency_key uuid not null unique,
  reversal_of_event_id bigint unique
    references public.leaderboard_tip_events(id) on delete restrict,
  constraint leaderboard_tip_events_semantics_check check (
    (reversal_of_event_id is null and amount_delta > 0 and tip_delta = 1)
    or
    (reversal_of_event_id is not null and amount_delta < 0 and tip_delta = -1)
  )
);

create index leaderboard_tip_events_session_created_idx
  on public.leaderboard_tip_events (session_id, created_at desc);

create index leaderboard_tip_events_host_created_idx
  on public.leaderboard_tip_events (host_name, created_at desc);

create view public.leaderboard_season_scores
with (security_invoker = true)
as
select
  s.season_id,
  sc.host_name,
  sum(sc.tip_count)::bigint as tip_count,
  sum(sc.total_amount)::bigint as total_amount,
  max(sc.updated_at) as updated_at
from public.leaderboard_sessions s
join public.leaderboard_session_scores sc on sc.session_id = s.id
group by s.season_id, sc.host_name;

alter table public.leaderboard_seasons enable row level security;
alter table public.leaderboard_sessions enable row level security;
alter table public.leaderboard_session_scores enable row level security;
alter table public.leaderboard_tip_events enable row level security;

create policy "visible seasons public read"
on public.leaderboard_seasons
for select to anon, authenticated
using (is_visible = true and status in ('open', 'closed'));

create policy "seasons admin read"
on public.leaderboard_seasons
for select to authenticated
using ((select private.is_admin()));

create policy "seasons admin insert"
on public.leaderboard_seasons
for insert to authenticated
with check ((select private.is_admin()));

create policy "seasons admin update"
on public.leaderboard_seasons
for update to authenticated
using ((select private.is_admin()))
with check ((select private.is_admin()));

create policy "visible sessions public read"
on public.leaderboard_sessions
for select to anon, authenticated
using (
  status in ('open', 'closed')
  and exists (
    select 1
    from public.leaderboard_seasons season
    where season.id = leaderboard_sessions.season_id
      and season.is_visible = true
      and season.status in ('open', 'closed')
  )
);

create policy "sessions admin read"
on public.leaderboard_sessions
for select to authenticated
using ((select private.is_admin()));

create policy "sessions admin insert"
on public.leaderboard_sessions
for insert to authenticated
with check ((select private.is_admin()));

create policy "sessions admin update"
on public.leaderboard_sessions
for update to authenticated
using ((select private.is_admin()))
with check ((select private.is_admin()));

create policy "visible session scores public read"
on public.leaderboard_session_scores
for select to anon, authenticated
using (
  exists (
    select 1
    from public.leaderboard_sessions session
    join public.leaderboard_seasons season on season.id = session.season_id
    where session.id = leaderboard_session_scores.session_id
      and session.status in ('open', 'closed')
      and season.is_visible = true
      and season.status in ('open', 'closed')
  )
);

create policy "session scores admin read"
on public.leaderboard_session_scores
for select to authenticated
using ((select private.is_admin()));

create policy "session scores admin insert"
on public.leaderboard_session_scores
for insert to authenticated
with check ((select private.is_admin()));

create policy "session scores admin update"
on public.leaderboard_session_scores
for update to authenticated
using ((select private.is_admin()))
with check ((select private.is_admin()));

create policy "tip events admin read"
on public.leaderboard_tip_events
for select to authenticated
using ((select private.is_admin()));

create policy "tip events admin insert"
on public.leaderboard_tip_events
for insert to authenticated
with check (
  (select private.is_admin())
  and created_by = (select auth.uid())
  and created_by_email = coalesce((select auth.jwt() ->> 'email'), '')
);

revoke all on
  public.leaderboard_seasons,
  public.leaderboard_sessions,
  public.leaderboard_session_scores,
  public.leaderboard_tip_events,
  public.leaderboard_season_scores
from anon, authenticated;

grant select on
  public.leaderboard_seasons,
  public.leaderboard_sessions,
  public.leaderboard_session_scores,
  public.leaderboard_season_scores
to anon, authenticated;

grant insert, update on
  public.leaderboard_seasons,
  public.leaderboard_sessions,
  public.leaderboard_session_scores
to authenticated;

grant select, insert on public.leaderboard_tip_events to authenticated;

grant usage, select on sequence
  public.leaderboard_seasons_id_seq,
  public.leaderboard_sessions_id_seq,
  public.leaderboard_tip_events_id_seq
to authenticated;

create or replace function public.create_leaderboard_season(p_label text)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_label text := btrim(coalesce(p_label, ''));
  v_season_id bigint;
  v_season_number integer;
  v_sessions jsonb;
begin
  if auth.uid() is null or not private.is_admin() then
    raise exception '僅限管理員操作' using errcode = '42501';
  end if;

  if char_length(v_label) not between 1 and 60 then
    raise exception '季度名稱需為 1 至 60 個字';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leaderboard_lifecycle', 0)
  );

  if exists (
    select 1 from public.leaderboard_seasons where status in ('draft', 'open')
  ) then
    raise exception '請先完成目前季度的三次營業';
  end if;

  select coalesce(max(season_number), 0) + 1
  into v_season_number
  from public.leaderboard_seasons;

  insert into public.leaderboard_seasons (
    season_number, label, status, is_visible, created_by
  ) values (
    v_season_number, v_label, 'draft', false, auth.uid()
  ) returning id into v_season_id;

  insert into public.leaderboard_sessions (
    season_id, session_number, label, status, created_by
  )
  select
    v_season_id,
    n,
    '第 ' || n || ' 次營業',
    'draft',
    auth.uid()
  from generate_series(1, 3) n;

  select jsonb_agg(
    jsonb_build_object(
      'id', id,
      'session_number', session_number,
      'label', label,
      'business_date', business_date,
      'status', status
    ) order by session_number
  )
  into v_sessions
  from public.leaderboard_sessions
  where season_id = v_season_id;

  return jsonb_build_object(
    'success', true,
    'season_id', v_season_id,
    'season_number', v_season_number,
    'label', v_label,
    'status', 'draft',
    'sessions', v_sessions
  );
end;
$function$;

create or replace function public.open_leaderboard_session(
  p_session_id bigint,
  p_business_date date,
  p_label text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_session public.leaderboard_sessions%rowtype;
  v_season public.leaderboard_seasons%rowtype;
  v_label text := nullif(btrim(coalesce(p_label, '')), '');
begin
  if auth.uid() is null or not private.is_admin() then
    raise exception '僅限管理員操作' using errcode = '42501';
  end if;

  if p_business_date is null then
    raise exception '請填寫營業日期';
  end if;

  if v_label is not null and char_length(v_label) > 60 then
    raise exception '場次名稱不可超過 60 個字';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leaderboard_lifecycle', 0)
  );

  select * into v_session
  from public.leaderboard_sessions
  where id = p_session_id
  for update;

  if not found then raise exception '找不到營業場次'; end if;

  select * into v_season
  from public.leaderboard_seasons
  where id = v_session.season_id
  for update;

  if v_session.status <> 'draft' then
    raise exception '此場次目前不是待開啟狀態';
  end if;
  if v_season.status = 'closed' then raise exception '此季度已封榜'; end if;

  if exists (
    select 1 from public.leaderboard_sessions
    where status = 'open' and id <> v_session.id
  ) then
    raise exception '目前已有其他營業場次開啟';
  end if;

  if exists (
    select 1 from public.leaderboard_sessions
    where season_id = v_session.season_id
      and session_number < v_session.session_number
      and status <> 'closed'
  ) then
    raise exception '請依序完成前一場營業';
  end if;

  if v_season.status = 'draft' then
    update public.leaderboard_seasons
    set status = 'open', is_visible = true, opened_at = now(), opened_by = auth.uid()
    where id = v_season.id;
  end if;

  update public.leaderboard_sessions
  set
    label = coalesce(v_label, label),
    business_date = p_business_date,
    status = 'open',
    opened_at = now(),
    opened_by = auth.uid()
  where id = v_session.id
  returning * into v_session;

  return jsonb_build_object(
    'success', true,
    'session_id', v_session.id,
    'season_id', v_session.season_id,
    'session_number', v_session.session_number,
    'label', v_session.label,
    'business_date', v_session.business_date,
    'status', v_session.status
  );
end;
$function$;

create or replace function public.close_leaderboard_session(p_session_id bigint)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_session public.leaderboard_sessions%rowtype;
  v_closed_count integer;
  v_season_closed boolean := false;
begin
  if auth.uid() is null or not private.is_admin() then
    raise exception '僅限管理員操作' using errcode = '42501';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leaderboard_lifecycle', 0)
  );

  select * into v_session
  from public.leaderboard_sessions
  where id = p_session_id
  for update;

  if not found then raise exception '找不到營業場次'; end if;

  perform 1
  from public.leaderboard_seasons
  where id = v_session.season_id
  for update;

  if v_session.status <> 'open' then
    raise exception '此場次目前不是營業中';
  end if;

  update public.leaderboard_sessions
  set status = 'closed', closed_at = now(), closed_by = auth.uid()
  where id = v_session.id;

  select count(*) into v_closed_count
  from public.leaderboard_sessions
  where season_id = v_session.season_id and status = 'closed';

  if v_closed_count = 3 then
    update public.leaderboard_seasons
    set status = 'closed', is_visible = true, closed_at = now(), closed_by = auth.uid()
    where id = v_session.season_id;
    v_season_closed := true;
  end if;

  return jsonb_build_object(
    'success', true,
    'session_id', v_session.id,
    'season_id', v_session.season_id,
    'session_number', v_session.session_number,
    'session_status', 'closed',
    'season_closed', v_season_closed
  );
end;
$function$;

create or replace function public.add_leaderboard_tip(
  p_session_id bigint,
  p_host_name text,
  p_amount bigint,
  p_note text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_host_name text := btrim(coalesce(p_host_name, ''));
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_session public.leaderboard_sessions%rowtype;
  v_existing public.leaderboard_tip_events%rowtype;
  v_event_id bigint;
  v_session_tip_count bigint;
  v_session_total_amount bigint;
  v_all_time_tip_count bigint;
  v_all_time_total_amount bigint;
begin
  if auth.uid() is null or not private.is_admin() then
    raise exception '僅限管理員操作' using errcode = '42501';
  end if;
  if p_idempotency_key is null then raise exception '缺少操作識別碼'; end if;
  if p_amount is null or p_amount <= 0 then raise exception '增加金額必須大於零'; end if;
  if v_host_name = '' then raise exception '請選擇店員'; end if;
  if v_note is not null and char_length(v_note) > 160 then
    raise exception '備註不可超過 160 個字';
  end if;

  select * into v_session
  from public.leaderboard_sessions
  where id = p_session_id
  for update;

  if not found then raise exception '找不到營業場次'; end if;
  if v_session.status <> 'open' then
    raise exception '只能替目前營業中的場次增加金額';
  end if;

  select * into v_existing
  from public.leaderboard_tip_events
  where idempotency_key = p_idempotency_key;

  if found then
    if v_existing.reversal_of_event_id is not null
      or v_existing.session_id <> p_session_id
      or v_existing.host_name <> v_host_name
      or v_existing.amount_delta <> p_amount then
      raise exception '此操作識別碼已用於其他操作';
    end if;

    select tip_count, total_amount
    into v_session_tip_count, v_session_total_amount
    from public.leaderboard_session_scores
    where session_id = p_session_id and host_name = v_host_name;

    select coalesce(tip_count, 0)::bigint, coalesce(total_amount, 0)
    into v_all_time_tip_count, v_all_time_total_amount
    from public.host_leaderboard
    where host_name = v_host_name;

    return jsonb_build_object(
      'success', true,
      'idempotent', true,
      'event_id', v_existing.id,
      'session_id', p_session_id,
      'host_name', v_host_name,
      'session_tip_count', coalesce(v_session_tip_count, 0),
      'session_total_amount', coalesce(v_session_total_amount, 0),
      'all_time_tip_count', coalesce(v_all_time_tip_count, 0),
      'all_time_total_amount', coalesce(v_all_time_total_amount, 0)
    );
  end if;

  perform 1 from public.host_leaderboard
  where host_name = v_host_name
  for update;
  if not found then raise exception '此店員尚未建立在排行榜名單'; end if;

  insert into public.leaderboard_tip_events (
    session_id, host_name, amount_delta, tip_delta, note,
    created_by, created_by_email, idempotency_key
  ) values (
    p_session_id, v_host_name, p_amount, 1, v_note,
    auth.uid(), coalesce(auth.jwt() ->> 'email', ''), p_idempotency_key
  ) returning id into v_event_id;

  insert into public.leaderboard_session_scores as scores (
    session_id, host_name, tip_count, total_amount, updated_at
  ) values (
    p_session_id, v_host_name, 1, p_amount, now()
  )
  on conflict (session_id, host_name)
  do update set
    tip_count = scores.tip_count + 1,
    total_amount = scores.total_amount + excluded.total_amount,
    updated_at = now()
  returning tip_count, total_amount
  into v_session_tip_count, v_session_total_amount;

  update public.host_leaderboard
  set
    tip_count = coalesce(tip_count, 0) + 1,
    total_amount = coalesce(total_amount, 0) + p_amount,
    updated_at = now()
  where host_name = v_host_name
  returning coalesce(tip_count, 0)::bigint, coalesce(total_amount, 0)
  into v_all_time_tip_count, v_all_time_total_amount;

  return jsonb_build_object(
    'success', true,
    'idempotent', false,
    'event_id', v_event_id,
    'session_id', p_session_id,
    'host_name', v_host_name,
    'session_tip_count', v_session_tip_count,
    'session_total_amount', v_session_total_amount,
    'all_time_tip_count', v_all_time_tip_count,
    'all_time_total_amount', v_all_time_total_amount
  );
end;
$function$;

create or replace function public.reverse_leaderboard_tip(
  p_event_id bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_original public.leaderboard_tip_events%rowtype;
  v_existing public.leaderboard_tip_events%rowtype;
  v_session public.leaderboard_sessions%rowtype;
  v_reversal_id bigint;
  v_session_tip_count bigint;
  v_session_total_amount bigint;
  v_all_time_tip_count bigint;
  v_all_time_total_amount bigint;
begin
  if auth.uid() is null or not private.is_admin() then
    raise exception '僅限管理員操作' using errcode = '42501';
  end if;
  if p_idempotency_key is null then raise exception '缺少操作識別碼'; end if;

  select * into v_existing
  from public.leaderboard_tip_events
  where idempotency_key = p_idempotency_key;

  if found then
    if v_existing.reversal_of_event_id <> p_event_id then
      raise exception '此操作識別碼已用於其他操作';
    end if;

    select tip_count, total_amount
    into v_session_tip_count, v_session_total_amount
    from public.leaderboard_session_scores
    where session_id = v_existing.session_id and host_name = v_existing.host_name;

    select coalesce(tip_count, 0)::bigint, coalesce(total_amount, 0)
    into v_all_time_tip_count, v_all_time_total_amount
    from public.host_leaderboard
    where host_name = v_existing.host_name;

    return jsonb_build_object(
      'success', true,
      'idempotent', true,
      'event_id', v_existing.id,
      'reversal_of_event_id', p_event_id,
      'session_id', v_existing.session_id,
      'host_name', v_existing.host_name,
      'session_tip_count', coalesce(v_session_tip_count, 0),
      'session_total_amount', coalesce(v_session_total_amount, 0),
      'all_time_tip_count', coalesce(v_all_time_tip_count, 0),
      'all_time_total_amount', coalesce(v_all_time_total_amount, 0)
    );
  end if;

  select * into v_original
  from public.leaderboard_tip_events
  where id = p_event_id;
  if not found then raise exception '找不到原始增加紀錄'; end if;

  if v_original.reversal_of_event_id is not null
    or v_original.amount_delta <= 0
    or v_original.tip_delta <> 1 then
    raise exception '只能沖銷原始增加紀錄';
  end if;

  select * into v_session
  from public.leaderboard_sessions
  where id = v_original.session_id
  for update;
  if v_session.status <> 'open' then raise exception '已封榜的營業場次不可更動'; end if;

  select * into v_original
  from public.leaderboard_tip_events
  where id = p_event_id
  for update;

  if exists (
    select 1 from public.leaderboard_tip_events where reversal_of_event_id = p_event_id
  ) then
    raise exception '此筆紀錄已經沖銷';
  end if;

  perform 1 from public.host_leaderboard
  where host_name = v_original.host_name
  for update;

  insert into public.leaderboard_tip_events (
    session_id, host_name, amount_delta, tip_delta, note,
    created_by, created_by_email, idempotency_key, reversal_of_event_id
  ) values (
    v_original.session_id,
    v_original.host_name,
    -v_original.amount_delta,
    -1,
    left('沖銷事件 #' || p_event_id::text, 160),
    auth.uid(),
    coalesce(auth.jwt() ->> 'email', ''),
    p_idempotency_key,
    p_event_id
  ) returning id into v_reversal_id;

  update public.leaderboard_session_scores
  set
    tip_count = tip_count - 1,
    total_amount = total_amount - v_original.amount_delta,
    updated_at = now()
  where session_id = v_original.session_id
    and host_name = v_original.host_name
    and tip_count >= 1
    and total_amount >= v_original.amount_delta
  returning tip_count, total_amount
  into v_session_tip_count, v_session_total_amount;
  if not found then raise exception '單次榜分數不足，無法沖銷'; end if;

  update public.host_leaderboard
  set
    tip_count = coalesce(tip_count, 0) - 1,
    total_amount = coalesce(total_amount, 0) - v_original.amount_delta,
    updated_at = now()
  where host_name = v_original.host_name
    and coalesce(tip_count, 0) >= 1
    and coalesce(total_amount, 0) >= v_original.amount_delta
  returning coalesce(tip_count, 0)::bigint, coalesce(total_amount, 0)
  into v_all_time_tip_count, v_all_time_total_amount;
  if not found then raise exception '累積榜分數不足，無法沖銷'; end if;

  return jsonb_build_object(
    'success', true,
    'idempotent', false,
    'event_id', v_reversal_id,
    'reversal_of_event_id', p_event_id,
    'session_id', v_original.session_id,
    'host_name', v_original.host_name,
    'session_tip_count', v_session_tip_count,
    'session_total_amount', v_session_total_amount,
    'all_time_tip_count', v_all_time_tip_count,
    'all_time_total_amount', v_all_time_total_amount
  );
end;
$function$;

revoke all on function public.create_leaderboard_season(text) from public, anon;
revoke all on function public.open_leaderboard_session(bigint, date, text) from public, anon;
revoke all on function public.close_leaderboard_session(bigint) from public, anon;
revoke all on function public.add_leaderboard_tip(bigint, text, bigint, text, uuid) from public, anon;
revoke all on function public.reverse_leaderboard_tip(bigint, uuid) from public, anon;

grant execute on function public.create_leaderboard_season(text) to authenticated;
grant execute on function public.open_leaderboard_session(bigint, date, text) to authenticated;
grant execute on function public.close_leaderboard_session(bigint) to authenticated;
grant execute on function public.add_leaderboard_tip(bigint, text, bigint, text, uuid) to authenticated;
grant execute on function public.reverse_leaderboard_tip(bigint, uuid) to authenticated;

with new_season as (
  insert into public.leaderboard_seasons (
    season_number, label, status, is_visible
  ) values (
    1, '第 1 季', 'draft', false
  )
  returning id
)
insert into public.leaderboard_sessions (
  season_id, session_number, label, business_date, status
)
select
  new_season.id,
  slot.session_number,
  '第 ' || slot.session_number || ' 次營業',
  null,
  'draft'
from new_season
cross join generate_series(1, 3) as slot(session_number);

alter publication supabase_realtime add table
  public.leaderboard_seasons,
  public.leaderboard_sessions,
  public.leaderboard_session_scores,
  public.leaderboard_tip_events;
