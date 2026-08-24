-- Keep the trigger helper outside the schemas exposed by the Data API.

create or replace function private.set_leaderboard_tip_event_actor()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_user_email text := coalesce((select auth.jwt() ->> 'email'), '');
begin
  if v_user_id is null then
    raise exception '必須登入才能新增排行榜紀錄'
      using errcode = '42501';
  end if;

  new.created_by := v_user_id;
  new.created_by_email := v_user_email;
  return new;
end;
$function$;

revoke all on function private.set_leaderboard_tip_event_actor()
from public, anon, authenticated;

drop trigger if exists set_leaderboard_tip_event_actor
on public.leaderboard_tip_events;

create trigger set_leaderboard_tip_event_actor_before_insert
before insert on public.leaderboard_tip_events
for each row
execute function private.set_leaderboard_tip_event_actor();

drop function if exists public.set_leaderboard_tip_event_actor();
