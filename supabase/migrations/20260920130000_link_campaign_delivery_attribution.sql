-- Connect individual promotion deliveries and resulting opportunities to the
-- monthly Hive campaign that generated them.
alter table public.promotion_deliveries
 add column if not exists campaign_id uuid references public.hive_campaigns(id) on delete set null;

create index if not exists promotion_deliveries_campaign_idx
 on public.promotion_deliveries(campaign_id,source_business_id,created_at desc);

alter table public.opportunities
 add column if not exists campaign_id uuid references public.hive_campaigns(id) on delete set null;

create index if not exists opportunities_campaign_idx
 on public.opportunities(campaign_id,receiving_business_id,created_at desc);

create or replace function public.hive_campaign_performance(p_campaign_id uuid)
returns jsonb
language sql
security invoker
set search_path=''
stable
as $function$
 with c as(
  select id,spotlight_business_id from public.hive_campaigns where id=p_campaign_id
 ),
 d as(
  select count(*)::bigint queued,
   count(*) filter(where pd.status in('sent','delivered'))::bigint sent,
   count(*) filter(where pd.status='delivered')::bigint delivered,
   count(distinct pd.source_business_id)::bigint contributing_members
  from public.promotion_deliveries pd
  where pd.campaign_id=p_campaign_id
 ),
 o as(
  select count(*)::bigint opportunities,
   count(*) filter(where status='won')::bigint wins,
   coalesce(sum(closed_value) filter(where status='won'),0)::numeric revenue
  from public.opportunities where campaign_id=p_campaign_id
 )
 select jsonb_build_object(
  'contributing_members',coalesce(d.contributing_members,0),
  'queued',coalesce(d.queued,0),
  'sent',coalesce(d.sent,0),
  'delivered',coalesce(d.delivered,0),
  'opportunities',coalesce(o.opportunities,0),
  'wins',coalesce(o.wins,0),
  'attributed_revenue',coalesce(o.revenue,0)
 ) from d cross join o
$function$;

revoke all on function public.hive_campaign_performance(uuid) from public,anon;
grant execute on function public.hive_campaign_performance(uuid) to authenticated;
