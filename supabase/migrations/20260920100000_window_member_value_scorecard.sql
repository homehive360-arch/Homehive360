-- Add a windowed, RLS-scoped member value scorecard so the Analytics time selector
-- applies consistently to summary metrics and member ROI.
create or replace function public.member_value_scorecard(p_days integer default 30)
returns table(
  id uuid,
  name text,
  contributed bigint,
  received bigint,
  sourced bigint,
  pipeline numeric,
  revenue numeric,
  wins bigint
)
language sql
security invoker
set search_path=''
stable
as $function$
 with cutoff as (
  select now() - (greatest(1,least(coalesce(p_days,30),365)) || ' days')::interval as ts
 ),
 visible_businesses as (
  select b.id,b.name
  from public.businesses b
  where exists(
   select 1 from public.business_users bu
   where bu.business_id=b.id and bu.user_id=(select auth.uid())
  )
 ),
 lead_counts as (
  select l.source_business_id as business_id,count(*)::bigint contributed
  from public.leads l,cutoff c
  where l.received_at>=c.ts
  group by l.source_business_id
 ),
 received_counts as (
  select o.receiving_business_id as business_id,
   count(*)::bigint received,
   count(*) filter(where o.status='won')::bigint wins,
   coalesce(sum(o.estimated_value) filter(where o.status not in ('won','lost')),0)::numeric pipeline,
   coalesce(sum(o.closed_value) filter(where o.status='won'),0)::numeric revenue
  from public.opportunities o,cutoff c
  where o.created_at>=c.ts
  group by o.receiving_business_id
 ),
 sourced_counts as (
  select o.source_business_id as business_id,count(*)::bigint sourced
  from public.opportunities o,cutoff c
  where o.created_at>=c.ts
  group by o.source_business_id
 )
 select vb.id,vb.name,
  coalesce(lc.contributed,0),
  coalesce(rc.received,0),
  coalesce(sc.sourced,0),
  coalesce(rc.pipeline,0),
  coalesce(rc.revenue,0),
  coalesce(rc.wins,0)
 from visible_businesses vb
 left join lead_counts lc on lc.business_id=vb.id
 left join received_counts rc on rc.business_id=vb.id
 left join sourced_counts sc on sc.business_id=vb.id
 order by coalesce(rc.revenue,0) desc,coalesce(rc.pipeline,0) desc,vb.name
$function$;

revoke all on function public.member_value_scorecard(integer) from public,anon;
grant execute on function public.member_value_scorecard(integer) to authenticated;
