-- Run as the database owner. Every test write is rolled back, including the
-- temporary opening time; no test reservations remain and the release stays closed.
begin;
do $$
declare
  slots bigint[];
  a jsonb; b jsonb; c jsonb; replay jsonb;
  key_a uuid := gen_random_uuid();
  key_b uuid := gen_random_uuid();
  key_c uuid := gen_random_uuid();
  denied boolean := false;
begin
  select array_agg(id order by sort_order,id) into slots from public.schedule_list
    where release_id='2026-11-02';
  assert array_length(slots,1)=13, 'Expected 13 slots; 蛇魂 only in second session';
  assert not (public.get_booking_release_state()->>'is_open')::boolean, 'Release must start closed';
  a:=public.reserve_release_slot(slots[1],'test','test',null,true,key_a);
  assert a->>'code'='not_open', 'Server must refuse early bookings';
  a:=public.create_reservation(slots[1],'test','test',null);
  assert a->>'code'='not_open', 'Legacy endpoint must refuse early bookings';
  update public.booking_releases set opens_at=clock_timestamp()-interval '1 minute' where id='2026-11-02';
  a:=public.reserve_release_slot(slots[1],'test','test',null,true,key_a);
  assert (a->>'success')::boolean and (a->>'addon_reserved')::boolean, 'First add-on';
  replay:=public.reserve_release_slot(slots[1],'test','test',null,true,key_a);
  assert replay->>'reservation_id'=a->>'reservation_id', 'Retry must not create a second booking';
  replay:=public.reserve_release_slot(slots[1],'changed','test',null,true,key_a);
  assert not (replay->>'success')::boolean, 'Reject changed retry payload';
  replay:=public.reserve_release_slot(slots[1],'other','test',null,true,gen_random_uuid());
  assert not (replay->>'success')::boolean, 'Same slot cannot be booked twice';
  b:=public.reserve_release_slot(slots[2],'test','test',null,true,key_b);
  assert (b->>'success')::boolean and (b->>'addon_reserved')::boolean, 'Second add-on';
  c:=public.reserve_release_slot(slots[3],'test','test',null,true,key_c);
  assert (c->>'success')::boolean and not (c->>'addon_reserved')::boolean, 'Sold-out add-on must keep successful booking';
  assert (c->>'addon_price')::integer=0, 'No charge for sold-out add-on';
  assert (public.get_booking_release_state()->>'addon_remaining')::integer=0, 'Stock cannot exceed two';
  begin
    update public.reservations set champagne_quantity=1,champagne_unit_price=100000
      where id=(c->>'reservation_id')::bigint;
  exception when raise_exception then denied:=true;
  end;
  assert denied, 'Admin writes cannot oversell';
  update public.reservations set status='completed' where id=(b->>'reservation_id')::bigint;
  assert (public.get_booking_release_state()->>'addon_remaining')::integer=0, 'Completed orders still consume stock';
  replay:=public.reserve_release_slot(slots[2],'other','test',null,false,gen_random_uuid());
  assert not (replay->>'success')::boolean, 'Completed slot is not resold';
  update public.reservations set status='cancelled' where id=(a->>'reservation_id')::bigint;
  assert (public.get_booking_release_state()->>'addon_remaining')::integer=1, 'Cancellation releases one add-on';
  replay:=public.reserve_release_slot(slots[1],'replacement','test',null,true,gen_random_uuid());
  assert (replay->>'success')::boolean and (replay->>'addon_reserved')::boolean, 'Cancelled slot and stock reusable';
  assert (public.get_booking_release_state()->>'addon_remaining')::integer=0;
  raise notice 'PASS: opening gate, legacy gate, idempotency, conflicts, stock, cancellation, completion, admin guard';
end $$;
rollback;
select 'PASS: transactional booking checks completed and rolled back' as test_result;
