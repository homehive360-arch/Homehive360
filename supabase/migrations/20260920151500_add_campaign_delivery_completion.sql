-- Delivery-state rollup keeps audience queueing separate from provider delivery
-- and campaign measurement completion.
create or replace function public.hive_campaign_delivery_status(p_campaign_id uuid)
returns jsonb
language sql security invoker set search_path='' stable
as $function$
 with d as(
  select count(*)::bigint total,
   count(*) filter(where status='queued')::bigint queued,
   count(*) filter(where status='sending')::bigint sending,
   count(*) filter(where status='sent')::bigint sent,
   count(*) filter(where status='delivered')::bigint delivered,
   count(*) filter(where status in('failed','bounced'))::bigint failed
  from public.promotion_deliveries where campaign_id=p_campaign_id
 ),r as(select status queue_status,audience_processed,deliveries_queued,deliveries_skipped,deliveries_failed from public.hive_campaign_runs where campaign_id=p_campaign_id)
 select jsonb_build_object(
  'queue_status',coalesce(r.queue_status,'not_started'),
  'audience_processed',coalesce(r.audience_processed,0),
  'eligibility_skipped',coalesce(r.deliveries_skipped,0),
  'queue_failures',coalesce(r.deliveries_failed,0),
  'delivery_total',d.total,'queued',d.queued,'sending',d.sending,'sent',d.sent,'delivered',d.delivered,'failed',d.failed,
  'delivery_complete',(coalesce(r.queue_status,'')='queue_complete' and d.queued=0 and d.sending=0)
 ) from d left join r on true
$function$;
revoke all on function public.hive_campaign_delivery_status(uuid) from public,anon;
grant execute on function public.hive_campaign_delivery_status(uuid) to authenticated;

create or replace function public.complete_hive_campaign(p_campaign_id uuid)
returns public.hive_campaigns
language plpgsql security definer set search_path=''
as $function$
declare v public.hive_campaigns;v_state jsonb;
begin
 select * into v from public.hive_campaigns where id=p_campaign_id;
 if v.id is null then raise exception 'Campaign not found'; end if;
 if not exists(select 1 from public.hive_members hm join public.business_users bu on bu.business_id=hm.business_id
  where hm.hive_id=v.hive_id and bu.user_id=(select auth.uid()) and bu.role in('owner','admin'))
 then raise exception 'Not authorized to manage this Hive'; end if;
 v_state:=public.hive_campaign_delivery_status(p_campaign_id);
 if coalesce((v_state->>'delivery_complete')::boolean,false)=false
 then raise exception 'Campaign delivery is not complete'; end if;
 update public.hive_campaigns set status='completed',updated_at=now() where id=p_campaign_id returning * into v;
 return v;
end
$function$;
revoke all on function public.complete_hive_campaign(uuid) from public,anon;
grant execute on function public.complete_hive_campaign(uuid) to authenticated;
