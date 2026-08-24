-- Serialize reversals without granting UPDATE on the immutable event ledger.

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

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'leaderboard_tip_event:' || p_event_id::text,
      0
    )
  );

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
