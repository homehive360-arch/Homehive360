-- Launch readiness is a minimum viable network gate, not a requirement to fill
-- every possible home-service category before a Hive can create value.
alter table public.hives add column if not exists min_launch_members integer not null default 3
 check(min_launch_members >= 2);
alter table public.hives add column if not exists min_launch_audience integer not null default 500
 check(min_launch_audience >= 0);

create or replace function public.hive_launch_readiness(p_hive_id uuid)
returns jsonb language sql security invoker set search_path='' stable
as $function$
 with authorized as(
  select exists(
   select 1 from public.hive_members hm
   join public.business_users bu on bu.business_id=hm.business_id
   where hm.hive_id=p_hive_id and hm.status='active'
    and bu.user_id=(select auth.uid()) and bu.role in('owner','admin')
  ) ok
 ),cfg as(
  select min_launch_members,min_launch_audience from public.hives where id=p_hive_id
 ),members as(
  select count(*)::int active_members,
   count(distinct hs.category)::int occupied_categories
  from public.hive_members hm
  join public.hive_member_seats hs on hs.hive_id=hm.hive_id and hs.business_id=hm.business_id and hs.status='active'
  where hm.hive_id=p_hive_id and hm.status='active'
 ),aud as(
  select count(distinct l.customer_id)::int eligible_audience
  from public.leads l
  join public.hive_members hm on hm.hive_id=l.hive_id and hm.business_id=l.source_business_id and hm.status='active'
  where l.hive_id=p_hive_id and (l.marketing_email_allowed or l.marketing_sms_allowed)
 )
 select case when (select ok from authorized) then jsonb_build_object(
  'active_members',m.active_members,
  'occupied_categories',m.occupied_categories,
  'eligible_audience',a.eligible_audience,
  'min_launch_members',cfg.min_launch_members,
  'min_launch_audience',cfg.min_launch_audience,
  'member_gate_met',m.active_members>=cfg.min_launch_members,
  'audience_gate_met',a.eligible_audience>=cfg.min_launch_audience,
  'launch_ready',m.active_members>=cfg.min_launch_members
    and m.occupied_categories>=cfg.min_launch_members
    and a.eligible_audience>=cfg.min_launch_audience
 ) else null end
 from cfg cross join members m cross join aud a
$function$;

revoke all on function public.hive_launch_readiness(uuid) from public,anon;
grant execute on function public.hive_launch_readiness(uuid) to authenticated;
