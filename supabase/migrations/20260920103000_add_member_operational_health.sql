-- Add RLS-scoped operational responsiveness metrics for each managed member.
create or replace function public.member_operational_health(p_days integer default 30)
returns table(
 id uuid,
 name text,
 received bigint,
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
 visible_businesses as (
  select b.id,b.name from public.businesses b
  where exists(select 1 from public.business_users bu where bu.business_id=b.id and bu.user_id=(select auth.uid()))
 ),
 activity as (
  select o.receiving_business_id business_id,
   count(*)::bigint received,
   count(*) filter(where o.status='new')::bigint awaiting,
   count(*) filter(where o.status='new' and o.created_at<now()-interval '24 hours')::bigint overdue,
   count(*) filter(where o.status in ('accepted','contacted','qualified','won','lost'))::bigint progressed,
   count(*) filter(where o.status='won')::bigint won
  from public.opportunities o,cutoff c
  where o.created_at>=c.ts
  group by o.receiving_business_id
 )
 select vb.id,vb.name,coalesce(a.received,0),coalesce(a.awaiting,0),coalesce(a.overdue,0),coalesce(a.progressed,0),coalesce(a.won,0)
 from visible_businesses vb left join activity a on a.business_id=vb.id
 order by coalesce(a.overdue,0) desc,coalesce(a.awaiting,0) desc,vb.name
$function$;

revoke all on function public.member_operational_health(integer) from public,anon;
grant execute on function public.member_operational_health(integer) to authenticated;
