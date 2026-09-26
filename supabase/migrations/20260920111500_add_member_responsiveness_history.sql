-- Track persistent member responsiveness across recent rolling windows without
-- automatically changing membership status.
create or replace function public.hive_member_responsiveness_history()
returns table(
 hive_id uuid,
 business_id uuid,
 business_name text,
 overdue_7d bigint,
 overdue_30d bigint,
 overdue_90d bigint,
 waiting_24h_plus bigint,
 oldest_waiting_at timestamptz
)
language sql
security invoker
set search_path=''
stable
as $function$
 with visible_memberships as (
  select hm.hive_id,hm.business_id,b.name
  from public.hive_members hm
  join public.businesses b on b.id=hm.business_id
  where hm.status='active' and exists(
   select 1 from public.hive_members mine
   join public.business_users bu on bu.business_id=mine.business_id
   where mine.hive_id=hm.hive_id and bu.user_id=(select auth.uid())
  )
 ),
 stats as (
  select o.hive_id,o.receiving_business_id business_id,
   count(*) filter(where o.status='new' and o.created_at<now()-interval '24 hours' and o.created_at>=now()-interval '7 days')::bigint overdue_7d,
   count(*) filter(where o.status='new' and o.created_at<now()-interval '24 hours' and o.created_at>=now()-interval '30 days')::bigint overdue_30d,
   count(*) filter(where o.status='new' and o.created_at<now()-interval '24 hours' and o.created_at>=now()-interval '90 days')::bigint overdue_90d,
   count(*) filter(where o.status='new' and o.created_at<now()-interval '24 hours')::bigint waiting_24h_plus,
   min(o.created_at) filter(where o.status='new') oldest_waiting_at
  from public.opportunities o
  where o.created_at>=now()-interval '90 days'
  group by o.hive_id,o.receiving_business_id
 )
 select vm.hive_id,vm.business_id,vm.name,
  coalesce(s.overdue_7d,0),coalesce(s.overdue_30d,0),coalesce(s.overdue_90d,0),
  coalesce(s.waiting_24h_plus,0),s.oldest_waiting_at
 from visible_memberships vm
 left join stats s on s.hive_id=vm.hive_id and s.business_id=vm.business_id
 where coalesce(s.overdue_90d,0)>0
 order by coalesce(s.overdue_30d,0) desc,coalesce(s.overdue_90d,0) desc
$function$;

revoke all on function public.hive_member_responsiveness_history() from public,anon;
grant execute on function public.hive_member_responsiveness_history() to authenticated;
