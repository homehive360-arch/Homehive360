-- Aggregate actionable Hive-level health from member composition and referral responsiveness.
create or replace function public.hive_operational_health(p_days integer default 30)
returns table(
 id uuid,
 name text,
 active_members bigint,
 service_categories bigint,
 referrals bigint,
 awaiting bigint,
 overdue bigint,
 progressed bigint,
 won bigint
)
language sql
security invoker
set search_path=''
stable
as $function$
 with cutoff as (
  select now()-(greatest(1,least(coalesce(p_days,30),365))||' days')::interval ts
 ),
 visible_hives as (
  select h.id,h.name from public.hives h
  where exists(
   select 1 from public.hive_members hm
   join public.business_users bu on bu.business_id=hm.business_id
   where hm.hive_id=h.id and bu.user_id=(select auth.uid())
  )
 ),
 composition as (
  select hm.hive_id,
   count(distinct hm.business_id)::bigint active_members,
   count(distinct lower(trim(s.category))) filter(where s.is_active and nullif(trim(s.category),'') is not null)::bigint service_categories
  from public.hive_members hm
  left join public.services s on s.business_id=hm.business_id
  where hm.status='active'
  group by hm.hive_id
 ),
 activity as (
  select o.hive_id,
   count(*)::bigint referrals,
   count(*) filter(where o.status='new')::bigint awaiting,
   count(*) filter(where o.status='new' and o.created_at<now()-interval '24 hours')::bigint overdue,
   count(*) filter(where o.status in ('accepted','contacted','qualified','won','lost'))::bigint progressed,
   count(*) filter(where o.status='won')::bigint won
  from public.opportunities o,cutoff c
  where o.created_at>=c.ts
  group by o.hive_id
 )
 select vh.id,vh.name,
  coalesce(c.active_members,0),coalesce(c.service_categories,0),
  coalesce(a.referrals,0),coalesce(a.awaiting,0),coalesce(a.overdue,0),
  coalesce(a.progressed,0),coalesce(a.won,0)
 from visible_hives vh
 left join composition c on c.hive_id=vh.id
 left join activity a on a.hive_id=vh.id
 order by coalesce(a.overdue,0) desc,vh.name
$function$;

revoke all on function public.hive_operational_health(integer) from public,anon;
grant execute on function public.hive_operational_health(integer) to authenticated;
