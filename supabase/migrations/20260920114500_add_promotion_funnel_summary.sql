-- Promotion-first analytics: distinguish audience contribution, promotional
-- exposure, engagement, high-intent opportunity creation, and revenue.
create or replace function public.promotion_funnel_summary(p_days integer default 30)
returns jsonb
language sql
security invoker
set search_path=''
stable
as $function$
 with cutoff as (
  select now()-(greatest(1,least(coalesce(p_days,30),365))||' days')::interval ts
 ),
 visible_businesses as (
  select distinct bu.business_id from public.business_users bu
  where bu.user_id=(select auth.uid())
 ),
 visible_hives as (
  select distinct hm.hive_id from public.hive_members hm
  join visible_businesses vb on vb.business_id=hm.business_id
 ),
 audience as (
  select count(distinct l.customer_id)::bigint customers
  from public.leads l,cutoff c
  where l.hive_id in(select hive_id from visible_hives)
   and l.received_at>=c.ts
   and (l.marketing_email_allowed or l.marketing_sms_allowed)
 ),
 delivery as (
  select
   count(*) filter(where pd.status in('queued','sending','sent','delivered'))::bigint promotions,
   count(*) filter(where pd.status in('sent','delivered'))::bigint sent,
   count(*) filter(where pd.status='delivered')::bigint delivered
  from public.promotion_deliveries pd
  join public.leads l on l.id=pd.lead_id
  cross join cutoff c
  where l.hive_id in(select hive_id from visible_hives) and pd.created_at>=c.ts
 ),
 engagement as (
  select
   count(*) filter(where e.event_type='hive_page.visited')::bigint hive_visits,
   count(*) filter(where e.event_type='member.clicked')::bigint member_engagements,
   count(*) filter(where e.event_type='offer.clicked')::bigint offer_engagements
  from public.events e,cutoff c
  where e.hive_id in(select hive_id from visible_hives) and e.occurred_at>=c.ts
 ),
 opp as (
  select count(*)::bigint opportunities,
   count(*) filter(where o.status='won')::bigint won,
   coalesce(sum(o.closed_value) filter(where o.status='won'),0)::numeric revenue
  from public.opportunities o,cutoff c
  where o.hive_id in(select hive_id from visible_hives) and o.created_at>=c.ts
 )
 select jsonb_build_object(
  'audience_customers',coalesce(a.customers,0),
  'promotions',coalesce(d.promotions,0),
  'sent',coalesce(d.sent,0),
  'delivered',coalesce(d.delivered,0),
  'hive_visits',coalesce(e.hive_visits,0),
  'member_engagements',coalesce(e.member_engagements,0),
  'offer_engagements',coalesce(e.offer_engagements,0),
  'opportunities',coalesce(o.opportunities,0),
  'won',coalesce(o.won,0),
  'revenue',coalesce(o.revenue,0)
 )
 from audience a cross join delivery d cross join engagement e cross join opp o
$function$;

revoke all on function public.promotion_funnel_summary(integer) from public,anon;
grant execute on function public.promotion_funnel_summary(integer) to authenticated;
