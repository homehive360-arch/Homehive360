-- Member-level network exchange: what each member contributes to the Hive
-- and what the Hive's cross-promotion engine produces for that member.
create or replace function public.member_promotion_exchange(p_days integer default 30)
returns table(
 business_id uuid,
 business_name text,
 audience_contributed bigint,
 promotions_contributed bigint,
 exposure_received bigint,
 member_engagements bigint,
 offer_intent bigint,
 opportunities_received bigint,
 wins bigint,
 attributed_revenue numeric
)
language sql
security invoker
set search_path=''
stable
as $function$
 with cutoff as (
  select now()-(greatest(1,least(coalesce(p_days,30),365))||' days')::interval ts
 ),
 visible as (
  select distinct b.id,b.name
  from public.businesses b
  join public.business_users bu on bu.business_id=b.id
  where bu.user_id=(select auth.uid())
 ),
 audience as (
  select l.source_business_id id,count(distinct l.customer_id)::bigint n
  from public.leads l,cutoff c
  where l.received_at>=c.ts and (l.marketing_email_allowed or l.marketing_sms_allowed)
  group by l.source_business_id
 ),
 contributed as (
  select pd.source_business_id id,count(*)::bigint n
  from public.promotion_deliveries pd,cutoff c
  where pd.created_at>=c.ts group by pd.source_business_id
 ),
 engagement as (
  select
   (e.properties->>'target_business_id')::uuid id,
   count(*) filter(where e.event_type='member.clicked')::bigint member_clicks,
   count(*) filter(where e.event_type='offer.clicked')::bigint offer_clicks
  from public.events e,cutoff c
  where e.occurred_at>=c.ts
   and e.properties ? 'delivery_id'
   and e.properties ? 'target_business_id'
  group by (e.properties->>'target_business_id')::uuid
 ),
 received as (
  select o.receiving_business_id id,
   count(*)::bigint opportunities,
   count(*) filter(where o.status='won')::bigint wins,
   coalesce(sum(o.closed_value) filter(where o.status='won'),0)::numeric revenue
  from public.opportunities o,cutoff c
  where o.created_at>=c.ts group by o.receiving_business_id
 )
 select v.id,v.name,
  coalesce(a.n,0),coalesce(cn.n,0),
  coalesce(e.member_clicks,0)+coalesce(e.offer_clicks,0),
  coalesce(e.member_clicks,0),coalesce(e.offer_clicks,0),
  coalesce(r.opportunities,0),coalesce(r.wins,0),coalesce(r.revenue,0)
 from visible v
 left join audience a on a.id=v.id
 left join contributed cn on cn.id=v.id
 left join engagement e on e.id=v.id
 left join received r on r.id=v.id
 order by coalesce(r.revenue,0) desc,v.name
$function$;

revoke all on function public.member_promotion_exchange(integer) from public,anon;
grant execute on function public.member_promotion_exchange(integer) to authenticated;
