-- Preserve the verified all-time leaderboard as the historical third session.
-- Sessions one and two intentionally stay as drafts for later admin backfill.

do $migration$
declare
  v_snapshot jsonb := '[
    {"host_name":"Jazper","tip_count":10,"total_amount":500000},
    {"host_name":"刻耳柏洛斯","tip_count":26,"total_amount":7480000},
    {"host_name":"厄耳特洛斯","tip_count":6,"total_amount":300000},
    {"host_name":"埃伊諾","tip_count":26,"total_amount":2350000},
    {"host_name":"孲絮","tip_count":0,"total_amount":0},
    {"host_name":"安怛","tip_count":17,"total_amount":7800000},
    {"host_name":"曹爺","tip_count":37,"total_amount":7150000},
    {"host_name":"桑賈亞","tip_count":10,"total_amount":1020000},
    {"host_name":"梅爾莫斯","tip_count":12,"total_amount":1780000},
    {"host_name":"法拉歐","tip_count":22,"total_amount":1100000},
    {"host_name":"洛德勒斯","tip_count":8,"total_amount":1100000},
    {"host_name":"牛奶","tip_count":29,"total_amount":2380000},
    {"host_name":"甲醛","tip_count":0,"total_amount":0},
    {"host_name":"萊特","tip_count":0,"total_amount":0},
    {"host_name":"著魔","tip_count":23,"total_amount":1150000},
    {"host_name":"蛇魂","tip_count":17,"total_amount":860000},
    {"host_name":"閻羅","tip_count":0,"total_amount":0},
    {"host_name":"龍冽","tip_count":10,"total_amount":3950000}
  ]'::jsonb;

  v_season_id bigint;
  v_session_1_id bigint;
  v_session_2_id bigint;
  v_session_3_id bigint;
  v_object_count integer;
  v_diff_count integer;
  v_snapshot_count integer;
  v_snapshot_tips bigint;
  v_snapshot_amount bigint;
  v_snapshot_present boolean;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leaderboard_lifecycle', 0)
  );

  select count(*), min(id)
  into v_object_count, v_season_id
  from public.leaderboard_seasons
  where season_number = 1;

  if v_object_count <> 1 then
    raise exception '預期恰有一筆第 1 季，實際找到 % 筆', v_object_count;
  end if;

  select
    count(*),
    max(id) filter (where session_number = 1),
    max(id) filter (where session_number = 2),
    max(id) filter (where session_number = 3)
  into
    v_object_count,
    v_session_1_id,
    v_session_2_id,
    v_session_3_id
  from public.leaderboard_sessions
  where season_id = v_season_id;

  if v_object_count <> 3
     or v_session_1_id is null
     or v_session_2_id is null
     or v_session_3_id is null then
    raise exception '第 1 季必須恰有第 1、2、3 次營業';
  end if;

  perform 1
  from public.leaderboard_seasons
  where id = v_season_id
  for update;

  perform 1
  from public.leaderboard_sessions
  where season_id = v_season_id
  order by session_number
  for update;

  select
    count(*),
    coalesce(sum(x.tip_count), 0),
    coalesce(sum(x.total_amount), 0)
  into
    v_snapshot_count,
    v_snapshot_tips,
    v_snapshot_amount
  from jsonb_to_recordset(v_snapshot) as x(
    host_name text,
    tip_count bigint,
    total_amount bigint
  );

  if v_snapshot_count <> 18
     or v_snapshot_tips <> 253
     or v_snapshot_amount <> 38920000 then
    raise exception
      'migration 內建快照斷言失敗：hosts=%, tips=%, amount=%',
      v_snapshot_count,
      v_snapshot_tips,
      v_snapshot_amount;
  end if;

  select count(*)
  into v_diff_count
  from (
    (
      select x.host_name, x.tip_count, x.total_amount
      from jsonb_to_recordset(v_snapshot) as x(
        host_name text,
        tip_count bigint,
        total_amount bigint
      )
      except
      select score.host_name, score.tip_count, score.total_amount
      from public.leaderboard_session_scores score
      where score.session_id = v_session_3_id
    )
    union all
    (
      select score.host_name, score.tip_count, score.total_amount
      from public.leaderboard_session_scores score
      where score.session_id = v_session_3_id
      except
      select x.host_name, x.tip_count, x.total_amount
      from jsonb_to_recordset(v_snapshot) as x(
        host_name text,
        tip_count bigint,
        total_amount bigint
      )
    )
  ) difference;

  select (
    session.status = 'closed'
    and session.business_date = date '2026-08-22'
    and v_diff_count = 0
  )
  into v_snapshot_present
  from public.leaderboard_sessions session
  where session.id = v_session_3_id;

  if not v_snapshot_present then
    if not exists (
      select 1
      from public.leaderboard_seasons
      where id = v_season_id
        and status = 'draft'
        and is_visible = false
    ) then
      raise exception '第 1 季已不是可安全匯入的 draft 狀態';
    end if;

    if (
      select count(*)
      from public.leaderboard_sessions
      where season_id = v_season_id
        and status = 'draft'
        and business_date is null
    ) <> 3 then
      raise exception '首次匯入前，三次營業必須全部為未填日期的 draft';
    end if;

    if exists (
      select 1
      from public.leaderboard_session_scores
      where session_id in (v_session_1_id, v_session_2_id, v_session_3_id)
    ) then
      raise exception '首次匯入前，第 1 季不可已有單次榜分數';
    end if;

    if exists (
      select 1
      from public.leaderboard_tip_events
      where session_id in (v_session_1_id, v_session_2_id, v_session_3_id)
    ) then
      raise exception '首次匯入前，第 1 季不可已有操作事件';
    end if;

    perform 1
    from public.host_leaderboard
    order by host_name
    for share;

    select count(*)
    into v_diff_count
    from (
      (
        select x.host_name, x.tip_count, x.total_amount
        from jsonb_to_recordset(v_snapshot) as x(
          host_name text,
          tip_count bigint,
          total_amount bigint
        )
        except
        select
          host.host_name,
          coalesce(host.tip_count, 0)::bigint,
          coalesce(host.total_amount, 0)::bigint
        from public.host_leaderboard host
      )
      union all
      (
        select
          host.host_name,
          coalesce(host.tip_count, 0)::bigint,
          coalesce(host.total_amount, 0)::bigint
        from public.host_leaderboard host
        except
        select x.host_name, x.tip_count, x.total_amount
        from jsonb_to_recordset(v_snapshot) as x(
          host_name text,
          tip_count bigint,
          total_amount bigint
        )
      )
    ) difference;

    if v_diff_count <> 0 then
      raise exception
        '現有總榜已與準備好的 2026-08-22 快照不同，請重新產生 migration';
    end if;

    insert into public.leaderboard_session_scores (
      session_id,
      host_name,
      tip_count,
      total_amount,
      updated_at
    )
    select
      v_session_3_id,
      x.host_name,
      x.tip_count,
      x.total_amount,
      now()
    from jsonb_to_recordset(v_snapshot) as x(
      host_name text,
      tip_count bigint,
      total_amount bigint
    );

    update public.leaderboard_sessions
    set
      status = 'closed',
      business_date = date '2026-08-22',
      opened_at = coalesce(opened_at, now()),
      closed_at = coalesce(closed_at, now())
    where id = v_session_3_id;
  end if;

  update public.leaderboard_seasons
  set
    status = case when status = 'draft' then 'open' else status end,
    is_visible = true,
    opened_at = coalesce(opened_at, now())
  where id = v_season_id
    and status in ('draft', 'open', 'closed');

  if not exists (
    select 1
    from public.leaderboard_seasons
    where id = v_season_id
      and status in ('open', 'closed')
      and is_visible = true
  ) then
    raise exception '第 1 季公開狀態斷言失敗';
  end if;

  if not exists (
    select 1
    from public.leaderboard_sessions
    where id = v_session_3_id
      and status = 'closed'
      and business_date = date '2026-08-22'
  ) then
    raise exception '第 3 次營業日期或封榜狀態斷言失敗';
  end if;

  select count(*)
  into v_diff_count
  from (
    (
      select x.host_name, x.tip_count, x.total_amount
      from jsonb_to_recordset(v_snapshot) as x(
        host_name text,
        tip_count bigint,
        total_amount bigint
      )
      except
      select score.host_name, score.tip_count, score.total_amount
      from public.leaderboard_session_scores score
      where score.session_id = v_session_3_id
    )
    union all
    (
      select score.host_name, score.tip_count, score.total_amount
      from public.leaderboard_session_scores score
      where score.session_id = v_session_3_id
      except
      select x.host_name, x.tip_count, x.total_amount
      from jsonb_to_recordset(v_snapshot) as x(
        host_name text,
        tip_count bigint,
        total_amount bigint
      )
    )
  ) difference;

  if v_diff_count <> 0 then
    raise exception '第 3 次營業快照內容斷言失敗';
  end if;

  if exists (
    select 1
    from public.leaderboard_tip_events
    where session_id = v_session_3_id
  ) then
    raise exception '歷史匯入不得偽造逐筆 tip event';
  end if;
end;
$migration$;
