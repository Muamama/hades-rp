-- Taiwan time: booking opens Nov 2 at noon; service takes place Nov 7.
create table public.booking_releases (
  id text primary key,
  opens_at timestamptz not null,
  ready boolean not null default false,
  addon_name text not null,
  addon_price integer not null check (addon_price > 0),
  addon_limit integer not null check (addon_limit >= 0),
  hosts text[] not null
);
alter table public.booking_releases enable row level security;
revoke all on public.booking_releases from anon, authenticated;
grant select on public.booking_releases to anon, authenticated;
grant update on public.booking_releases to authenticated;
create policy booking_release_read on public.booking_releases for select to anon, authenticated using (true);
create policy booking_release_admin on public.booking_releases for update to authenticated
  using (private.is_admin()) with check (private.is_admin());

insert into public.booking_releases values (
  '2026-11-02', '2026-11-02T12:00:00+08:00', true,
  '香檳的黏膩相擁', 100000, 2,
  array['著魔','龍冽','安怛','Jazper','蛇魂','埃伊諾','牛奶']
);
alter table public.schedule_list add column release_id text references public.booking_releases(id)
  default '2026-11-02';
insert into public.schedule_list(name,date,status,img,sort_order,release_id)
select h.name, '2026-11-07 ' || t.slot, 'wait', h.img, (t.position-1)*7+h.position, '2026-11-02'
from (values
  ('著魔','images/著魔-popup.jpg',1),('龍冽','images/龍冽.jpg',2),
  ('安怛','images/安怛.jpg',3),('Jazper','images/Jazper.jpg',4),
  ('蛇魂','images/蛇魂.jpg',5),('埃伊諾','images/埃伊諾.jpg',6),('牛奶','images/牛奶-popup.jpg',7)
) h(name,img,position)
cross join (values ('22:25–22:55',1),('23:25–23:55',2)) t(slot,position);
alter table public.reservations
  add column release_id text references public.booking_releases(id),
  add column champagne_quantity integer not null default 0 check (champagne_quantity between 0 and 1),
  add column champagne_unit_price integer not null default 0,
  add column request_key uuid unique;
alter table public.reservations add constraint champagne_price_check check (
  (champagne_quantity = 0 and champagne_unit_price = 0) or
  (champagne_quantity = 1 and champagne_unit_price = 100000 and release_id is not null)
);
create index reservations_release_champagne_idx on public.reservations(release_id)
  where champagne_quantity > 0 and status <> 'cancelled';

-- The public booking API intentionally supports guests. The definer is scoped to
-- a fixed release, the allowed hosts, server opening time and locked inventory.
-- No customer data is returned by the state API or the booking response.
create or replace function private.booking_release_state()
returns jsonb language sql security definer set search_path = '' as $$
  select jsonb_build_object(
    'release_id', b.id, 'opens_at', b.opens_at, 'ready', b.ready,
    'server_now', clock_timestamp(),
    'is_open', b.ready and clock_timestamp() >= b.opens_at,
    'hosts', b.hosts, 'addon_name', b.addon_name,
    'addon_price', b.addon_price, 'addon_limit', b.addon_limit,
    'addon_remaining', greatest(0, b.addon_limit - (
      select coalesce(sum(r.champagne_quantity),0) from public.reservations r
      where r.release_id=b.id and r.status <> 'cancelled'
    )),
    'slots', coalesce((select jsonb_agg(jsonb_build_object(
      'id',s.id,'name',s.name,'date',s.date,
      'available',s.status='wait' and not exists (
        select 1 from public.reservations r where r.schedule_id=s.id and r.status <> 'cancelled'
      )
    ) order by s.sort_order,s.id) from public.schedule_list s
      where s.release_id=b.id and s.name=any(b.hosts) and s.status <> 'off'), '[]'::jsonb)
  ) from public.booking_releases b where b.id='2026-11-02';
$$;
revoke all on function private.booking_release_state() from public;
grant usage on schema private to anon,authenticated;
grant execute on function private.booking_release_state() to anon,authenticated;
create function public.get_booking_release_state() returns jsonb
language sql security invoker set search_path = '' as $$
  select private.booking_release_state();
$$;
revoke all on function public.get_booking_release_state() from public;
grant execute on function public.get_booking_release_state() to anon,authenticated;

create or replace function private.reserve_release_slot(
  p_schedule_id bigint, p_customer_name text, p_customer_contact text,
  p_customer_note text, p_champagne boolean, p_request_key uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  b public.booking_releases%rowtype;
  s public.schedule_list%rowtype;
  r public.reservations%rowtype;
  v_name text := btrim(coalesce(p_customer_name,''));
  v_contact text := btrim(coalesce(p_customer_contact,''));
  v_note text := nullif(btrim(coalesce(p_customer_note,'')),'');
  v_quantity integer := 0;
  v_remaining integer;
begin
  if p_request_key is null or p_schedule_id is null then
    return jsonb_build_object('success',false,'message','請選擇指名對象後重新送出。');
  end if;
  if length(v_name) not between 1 and 60 or length(v_contact) not between 1 and 120
     or coalesce(length(v_note),0)>500 then
    return jsonb_build_object('success',false,'message','請填寫姓名與聯絡方式；姓名限 60 字、聯絡方式限 120 字、備註限 500 字。');
  end if;
  -- The same row serializes bookings across different hosts and the two add-ons.
  select * into b from public.booking_releases where id='2026-11-02' for update;
  if not found then
    return jsonb_build_object('success',false,'message','本次預約尚未準備完成。');
  end if;
  select * into r from public.reservations where request_key=p_request_key;
  if found then
    if r.schedule_id <> p_schedule_id or r.customer_name <> v_name or r.customer_contact <> v_contact
       or r.customer_note is distinct from v_note then
      return jsonb_build_object('success',false,'message','重送內容不一致，請重新整理後再試。');
    end if;
    return jsonb_build_object('success',r.status <> 'cancelled','reservation_id',r.id,
      'addon_requested',coalesce(p_champagne,false),'addon_reserved',r.champagne_quantity=1,
      'addon_price',r.champagne_unit_price,'message','此筆預約已送達。');
  end if;
  if not b.ready or clock_timestamp()<b.opens_at then
    return jsonb_build_object('success',false,'code','not_open','message','預約將於 11 月 2 日中午 12:00（台灣時間）開放。');
  end if;
  select * into s from public.schedule_list where id=p_schedule_id for update;
  if not found or s.release_id is distinct from b.id or not (s.name=any(b.hosts))
     or s.status <> 'wait' then
    return jsonb_build_object('success',false,'message','此指名目前無法預約，請選擇其他對象。');
  end if;
  if exists(select 1 from public.reservations where schedule_id=s.id and status <> 'cancelled') then
    return jsonb_build_object('success',false,'message','此指名已被搶先預約，請選擇其他對象。');
  end if;
  select b.addon_limit-coalesce(sum(champagne_quantity),0) into v_remaining
    from public.reservations where release_id=b.id and status <> 'cancelled';
  if coalesce(p_champagne,false) and v_remaining>0 then v_quantity:=1; end if;
  insert into public.reservations(schedule_id,host_name,schedule_date,customer_name,customer_contact,
    customer_note,status,release_id,champagne_quantity,champagne_unit_price,request_key)
  values(s.id,s.name,s.date,v_name,v_contact,v_note,'confirmed',b.id,v_quantity,
    case when v_quantity=1 then b.addon_price else 0 end,p_request_key) returning * into r;
  return jsonb_build_object('success',true,'reservation_id',r.id,
    'addon_requested',coalesce(p_champagne,false),'addon_reserved',v_quantity=1,
    'addon_price',r.champagne_unit_price,'message','指名預約成功。');
end;
$$;
revoke all on function private.reserve_release_slot(bigint,text,text,text,boolean,uuid) from public;
grant execute on function private.reserve_release_slot(bigint,text,text,text,boolean,uuid) to anon,authenticated;
create function public.reserve_release_slot(
  p_schedule_id bigint,p_customer_name text,p_customer_contact text,
  p_customer_note text,p_champagne boolean,p_request_key uuid
) returns jsonb language sql security invoker set search_path = '' as $$
  select private.reserve_release_slot(p_schedule_id,p_customer_name,p_customer_contact,
    p_customer_note,p_champagne,p_request_key);
$$;
revoke all on function public.reserve_release_slot(bigint,text,text,text,boolean,uuid) from public;
grant execute on function public.reserve_release_slot(bigint,text,text,text,boolean,uuid) to anon,authenticated;


-- Keep old browser tabs on the server opening gate as well.
create or replace function public.create_reservation(
  p_schedule_id bigint,p_customer_name text,p_customer_contact text,p_customer_note text default null
) returns jsonb language sql security invoker set search_path = '' as $$
  select public.reserve_release_slot(p_schedule_id,p_customer_name,p_customer_contact,
    p_customer_note,false,pg_catalog.gen_random_uuid());
$$;
revoke all on function public.create_reservation(bigint,text,text,text) from public;
grant execute on function public.create_reservation(bigint,text,text,text) to anon,authenticated;

-- Admin edits/reactivation must obey the same stock limit as guest bookings.
create or replace function private.guard_champagne_stock()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_limit integer; v_used integer;
begin
  if new.champagne_quantity=0 or new.status='cancelled' then return new; end if;
  select addon_limit into v_limit from public.booking_releases where id=new.release_id for update;
  if not found then raise exception '找不到加購活動'; end if;
  if not exists(select 1 from public.schedule_list s join public.booking_releases b on b.id=s.release_id
    where s.id=new.schedule_id and b.id=new.release_id and s.name=any(b.hosts)) then
    raise exception '加購必須附屬於本次有效指名';
  end if;
  select coalesce(sum(champagne_quantity),0) into v_used from public.reservations
    where release_id=new.release_id and status<>'cancelled' and id is distinct from new.id;
  if v_used+new.champagne_quantity>v_limit then raise exception '香檳加購已售完'; end if;
  return new;
end;
$$;
revoke all on function private.guard_champagne_stock() from public,anon,authenticated;
create trigger guard_champagne_stock before insert or update on public.reservations
  for each row execute function private.guard_champagne_stock();

notify pgrst,'reload schema';
