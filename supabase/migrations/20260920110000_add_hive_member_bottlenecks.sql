-- Identify member-level referral bottlenecks inside each visible Hive.
create or replace function public.hive_member_bottlenecks(p_days integer default 30)
returns table(
 hive_id uuid,
 business_id uuid,
 business_name text,
 awaiting bigint,
 overdue bigint,
 oldest_waiting_at timestamptz
)
language sql
security invoker
set search_path=''
stable
as $function$
 with cutoff as (
  select now()-(greatest(1,least(coalesce(p_days,30),365))||' days')::interval ts
 ),
 visible_memberships as (
  select hm.hive_id,hm.business_id,b.name
  from public.hive_members hm
  join public.businesses b on b.id=hm.business_id
  where hm.status='active' and exists(
   select 1 from public.hive_members mine
   join public.business_users bu on bu.business_id=mine.business_id
   where mine.hive_id=hm.hive_id and bu.user_id=(select auth.uid())
  )
 ),
 waiting as (
  select o.hive_id,o.receiving_business_id business_id,
   count(*)::bigint awaiting,
   count(*) filter(where o.created_at<now()-interval '24 hours')::bigint overdue,
   min(o.created_at) oldest_waiting_at
  from public.opportunities o,cutoff c
  where o.status='new' and o.created_at>=c.ts
  group by o.hive_id,o.receiving_business_id
 )
 select vm.hive_id,vm.business_id,vm.name,
  coalesce(w.awaiting,0),coalesce(w.overdue,0),w.oldest_waiting_at
 from visible_memberships vm
 left join waiting w on w.hive_id=vm.hive_id and w.business_id=vm.business_id
 where coalesce(w.awaiting,0)>0
 order by coalesce(w.overdue,0) desc,w.oldest_waiting_at asc
$function$;

revoke all on function public.hive_member_bottlenecks(integer) from public,anon;
grant execute on function public.hive_member_bottlenecks(integer) to authenticated;
