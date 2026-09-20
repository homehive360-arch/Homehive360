-- Full monthly campaign funnel, including delivery, engagement, opportunity,
-- wins and revenue. Event attribution follows promotion delivery tracking.
-- Ensure the event attribution key exists before compiling the funnel function.
alter table public.events add column if not exists promotion_delivery_id uuid references public.promotion_deliveries(id) on delete set null;
create index if not exists events_promotion_delivery_idx on public.events(promotion_delivery_id,occurred_at desc);

create or replace function public.hive_campaign_funnel(p_campaign_id uuid)
returns jsonb
language sql security invoker set search_path='' stable
as $function$
 with d as(
  select pd.id,pd.status,pd.lead_id
  from public.promotion_deliveries pd where pd.campaign_id=p_campaign_id
 ),e as(
  select
   count(*) filter(where ev.event_type='hive_page.visited')::bigint hive_visits,
   count(*) filter(where ev.event_type='member.clicked')::bigint member_engagements,
   count(*) filter(where ev.event_type='offer.clicked')::bigint offer_intent
  from public.events ev
  where exists(select 1 from d where d.id=ev.promotion_delivery_id)
 ),o as(
  select count(*)::bigint opportunities,
   count(*) filter(where status='won')::bigint wins,
   coalesce(sum(closed_value) filter(where status='won'),0)::numeric attributed_revenue
  from public.opportunities where campaign_id=p_campaign_id
 ),del as(
  select count(*)::bigint delivery_total,
   count(*) filter(where status='queued')::bigint queued,
   count(*) filter(where status='sending')::bigint sending,
   count(*) filter(where status='sent')::bigint sent,
   count(*) filter(where status='delivered')::bigint delivered,
   count(*) filter(where status='failed')::bigint failed
  from d
 ),r as(
  select audience_processed,deliveries_skipped,deliveries_failed,status queue_status
  from public.hive_campaign_runs where campaign_id=p_campaign_id
 )
 select jsonb_build_object(
  'audience_processed',coalesce(r.audience_processed,0),
  'eligibility_skipped',coalesce(r.deliveries_skipped,0),
  'queue_failures',coalesce(r.deliveries_failed,0),
  'queue_status',coalesce(r.queue_status,'not_started'),
  'delivery_total',del.delivery_total,'queued',del.queued,'sending',del.sending,'sent',del.sent,'delivered',del.delivered,'failed',del.failed,
  'hive_visits',coalesce(e.hive_visits,0),'member_engagements',coalesce(e.member_engagements,0),'offer_intent',coalesce(e.offer_intent,0),
  'opportunities',o.opportunities,'wins',o.wins,'attributed_revenue',o.attributed_revenue
 ) from del cross join e cross join o left join r on true
$function$;
revoke all on function public.hive_campaign_funnel(uuid) from public,anon;
grant execute on function public.hive_campaign_funnel(uuid) to authenticated;
