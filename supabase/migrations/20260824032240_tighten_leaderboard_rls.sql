-- Keep one SELECT policy per role and make audit identity server-controlled.

drop policy if exists "visible seasons public read"
on public.leaderboard_seasons;

drop policy if exists "seasons admin read"
on public.leaderboard_seasons;

create policy "visible seasons anon read"
on public.leaderboard_seasons
for select to anon
using (is_visible = true and status in ('open', 'closed'));

create policy "seasons authenticated read"
on public.leaderboard_seasons
for select to authenticated
using (
  (is_visible = true and status in ('open', 'closed'))
  or (select private.is_admin())
);

drop policy if exists "visible sessions public read"
on public.leaderboard_sessions;

drop policy if exists "sessions admin read"
on public.leaderboard_sessions;

create policy "visible sessions anon read"
on public.leaderboard_sessions
for select to anon
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

create policy "sessions authenticated read"
on public.leaderboard_sessions
for select to authenticated
using (
  (
    status in ('open', 'closed')
    and exists (
      select 1
      from public.leaderboard_seasons season
      where season.id = leaderboard_sessions.season_id
        and season.is_visible = true
        and season.status in ('open', 'closed')
    )
  )
  or (select private.is_admin())
);

drop policy if exists "visible session scores public read"
on public.leaderboard_session_scores;

drop policy if exists "session scores admin read"
on public.leaderboard_session_scores;

create policy "visible session scores anon read"
on public.leaderboard_session_scores
for select to anon
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

create policy "session scores authenticated read"
on public.leaderboard_session_scores
for select to authenticated
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
  or (select private.is_admin())
);

create or replace function public.set_leaderboard_tip_event_actor()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  new.created_by := (select auth.uid());
  new.created_by_email := coalesce((select auth.jwt() ->> 'email'), '');
  return new;
end;
$function$;

revoke all on function public.set_leaderboard_tip_event_actor()
from public, anon, authenticated;

drop trigger if exists set_leaderboard_tip_event_actor
on public.leaderboard_tip_events;

create trigger set_leaderboard_tip_event_actor
before insert on public.leaderboard_tip_events
for each row
execute function public.set_leaderboard_tip_event_actor();

drop policy if exists "tip events admin insert"
on public.leaderboard_tip_events;

create policy "tip events admin insert"
on public.leaderboard_tip_events
for insert to authenticated
with check ((select private.is_admin()));
