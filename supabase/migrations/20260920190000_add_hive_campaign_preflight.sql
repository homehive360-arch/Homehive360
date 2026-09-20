-- Preflight a Hive's first/next monthly campaign. This keeps launch readiness,
-- Spotlight rotation and incremental network reach in one operator-facing view.
create or replace function public.hive_campaign_preflight(p_hive_id uuid)
returns jsonb language plpgsql security invoker set search_path=''
as $function$
declare
 v_ready jsonb;v_spotlight uuid;v_owned bigint:=0;v_incremental bigint:=0;v_total bigint:=0;
begin
 v_ready:=public.hive_launch_readiness(p_hive_id);
 if v_ready is null then return null; end if;
 if coalesce((v_ready->>'launch_ready')::boolean,false)=false then
  return jsonb_build_object('launch_ready',false,'readiness',v_ready);
 end if;

 -- Use the existing fair rotation engine rather than ranking businesses by
 -- performance. Spotlight is premium placement, not a winner/leaderboard.
 select n.business_id into v_spotlight from public.next_hive_spotlight_member(p_hive_id) n limit 1;
 if v_spotlight is null then
  return jsonb_build_object('launch_ready',true,'readiness',v_ready,'spotlight_business_id',null);
 end if;

 with policy as (
  select email_enabled,sms_enabled from public.hive_campaign_policy where hive_id=p_hive_id
 ), eligible as (
  select distinct on(l.customer_id) l.customer_id,l.source_business_id
  from public.leads l
  join public.hive_members hm on hm.hive_id=l.hive_id and hm.business_id=l.source_business_id and hm.status='active'
  cross join policy p
  where l.hive_id=p_hive_id and l.customer_id is not null
   and ((p.email_enabled and l.marketing_email_allowed) or (p.sms_enabled and l.marketing_sms_allowed))
  order by l.customer_id,l.received_at desc nulls last,l.created_at desc,l.id desc
 )
 select count(*) filter(where source_business_id=v_spotlight),
        count(*) filter(where source_business_id<>v_spotlight),
        count(*)
 into v_owned,v_incremental,v_total from eligible;

 return jsonb_build_object(
  'launch_ready',true,'readiness',v_ready,
  'spotlight_business_id',v_spotlight,
  'owned_audience_reach',coalesce(v_owned,0),
  'incremental_hive_reach',coalesce(v_incremental,0),
  'total_campaign_reach',coalesce(v_total,0)
 );
end
$function$;

revoke all on function public.hive_campaign_preflight(uuid) from public,anon;
grant execute on function public.hive_campaign_preflight(uuid) to authenticated;


-- Guard monthly campaign creation with the same minimum viable network rules
-- operators see in preflight. This prevents UI/API bypasses.
create or replace function public.create_launch_ready_monthly_hive_campaign(
 p_hive_id uuid,
 p_campaign_month date,
 p_spotlight_offer_id uuid default null
) returns public.hive_campaigns
language plpgsql security definer set search_path=''
as $function$
declare v_ready jsonb;v_spotlight uuid;v_campaign public.hive_campaigns;
begin
 if not exists(
  select 1 from public.hive_members hm
  join public.business_users bu on bu.business_id=hm.business_id
  where hm.hive_id=p_hive_id and hm.status='active'
   and bu.user_id=(select auth.uid()) and bu.role in('owner','admin')
 ) then raise exception 'Not authorized to create campaigns for this Hive'; end if;

 v_ready:=public.hive_launch_readiness(p_hive_id);
 if coalesce((v_ready->>'launch_ready')::boolean,false)=false then
  raise exception 'Hive is not launch ready';
 end if;

 select n.business_id into v_spotlight from public.next_hive_spotlight_member(p_hive_id) n limit 1;
 if v_spotlight is null then raise exception 'No eligible Spotlight member'; end if;

 -- Delegate month/offer ownership/status/date validation to the canonical
 -- campaign creation function so there is one source of truth for creation.
 select * into v_campaign from public.create_monthly_hive_campaign(
  p_hive_id,p_campaign_month,v_spotlight,p_spotlight_offer_id
 );
 return v_campaign;
end
$function$;

revoke all on function public.create_launch_ready_monthly_hive_campaign(uuid,date,uuid) from public,anon;
grant execute on function public.create_launch_ready_monthly_hive_campaign(uuid,date,uuid) to authenticated;


-- External authenticated callers must use the launch-readiness gate. The lower-level
-- creator remains available only to the service role for controlled internal work.
revoke all on function public.create_monthly_hive_campaign(uuid,date,uuid,uuid,text) from authenticated;
grant execute on function public.create_monthly_hive_campaign(uuid,date,uuid,uuid,text) to service_role;


-- A campaign audience is immutable once activation begins, including the valid
-- zero-recipient case. A timestamp is the freeze marker; row count is not.
alter table public.hive_campaigns add column if not exists audience_frozen_at timestamptz;

create or replace function public.mark_hive_campaign_audience_frozen(p_campaign_id uuid)
returns timestamptz language plpgsql security definer set search_path=''
as $function$
declare v_frozen timestamptz;
begin
 update public.hive_campaigns
 set audience_frozen_at=coalesce(audience_frozen_at,now()),updated_at=now()
 where id=p_campaign_id
 returning audience_frozen_at into v_frozen;
 if v_frozen is null then raise exception 'Campaign not found'; end if;
 return v_frozen;
end
$function$;

revoke all on function public.mark_hive_campaign_audience_frozen(uuid) from public,anon,authenticated;
grant execute on function public.mark_hive_campaign_audience_frozen(uuid) to service_role;


create or replace function public.snapshot_hive_campaign_recipients(p_campaign_id uuid)
returns bigint language plpgsql security definer set search_path='' as $function$
declare v_hive uuid;v_count bigint;v_frozen timestamptz;
begin
 select hive_id,audience_frozen_at into v_hive,v_frozen
 from public.hive_campaigns where id=p_campaign_id for update;
 if v_hive is null then raise exception 'Campaign not found';end if;
 if v_frozen is not null then
  select count(*) into v_count from public.hive_campaign_recipients where campaign_id=p_campaign_id;
  return v_count;
 end if;
 insert into public.hive_campaign_recipients(campaign_id,lead_id,source_business_id,customer_id,email_eligible,sms_eligible)
 select p_campaign_id,x.lead_id,x.source_business_id,x.customer_id,x.email_eligible,x.sms_eligible from (
  select distinct on(l.customer_id) l.id lead_id,l.source_business_id,l.customer_id,
   p.email_enabled and bool_or(l.marketing_email_allowed) over(partition by l.customer_id) email_eligible,
   p.sms_enabled and bool_or(l.marketing_sms_allowed) over(partition by l.customer_id) sms_eligible
  from public.leads l join public.hive_members hm on hm.hive_id=l.hive_id and hm.business_id=l.source_business_id and hm.status='active'
  join public.hive_campaign_policy p on p.hive_id=l.hive_id
  where l.hive_id=v_hive and l.customer_id is not null
   and ((p.email_enabled and l.marketing_email_allowed) or (p.sms_enabled and l.marketing_sms_allowed))
  order by l.customer_id,l.received_at desc nulls last,l.created_at desc,l.id desc
 ) x;
 get diagnostics v_count=row_count;
 update public.hive_campaigns set audience_frozen_at=now(),updated_at=now() where id=p_campaign_id;
 return v_count;
end $function$;

revoke all on function public.snapshot_hive_campaign_recipients(uuid) from public,anon,authenticated;
grant execute on function public.snapshot_hive_campaign_recipients(uuid) to service_role;


-- Keep aggregate reach reporting aligned with the immutable recipient snapshot.
-- Once frozen, reach is derived from the actual campaign recipients rather than
-- mutable lead records or pre-launch projections.
create or replace function public.hive_campaign_reach(p_campaign_id uuid)
returns jsonb language sql security invoker set search_path='' stable as $function$
 with c as(
  select spotlight_business_id,audience_frozen_at from public.hive_campaigns where id=p_campaign_id
 ), frozen as(
  select count(*)::bigint total_reach,
   count(*) filter(where r.source_business_id=(select spotlight_business_id from c))::bigint owned_reach,
   count(*) filter(where r.source_business_id<>(select spotlight_business_id from c))::bigint incremental_hive_reach,
   count(*) filter(where r.email_eligible)::bigint email_reach,
   count(*) filter(where r.sms_eligible)::bigint sms_reach
  from public.hive_campaign_recipients r where r.campaign_id=p_campaign_id
 ), projected as(
  select coalesce(sum(a.eligible_customers),0)::bigint total_reach,
   coalesce(sum(a.eligible_customers) filter(where a.source_business_id=(select spotlight_business_id from c)),0)::bigint owned_reach,
   coalesce(sum(a.eligible_customers) filter(where a.source_business_id<>(select spotlight_business_id from c)),0)::bigint incremental_hive_reach,
   coalesce(sum(a.email_eligible),0)::bigint email_reach,
   coalesce(sum(a.sms_eligible),0)::bigint sms_reach
  from public.hive_campaign_audiences a where a.campaign_id=p_campaign_id
 ), chosen as(
  select * from frozen where (select audience_frozen_at from c) is not null
  union all
  select * from projected where (select audience_frozen_at from c) is null
 )
 select jsonb_build_object('owned_reach',owned_reach,'incremental_hive_reach',incremental_hive_reach,
  'total_reach',total_reach,'email_reach',email_reach,'sms_reach',sms_reach,
  'audience_frozen',(select audience_frozen_at is not null from c)) from chosen
$function$;

revoke all on function public.hive_campaign_reach(uuid) from public,anon;
grant execute on function public.hive_campaign_reach(uuid) to authenticated;


-- Normalize funnel reporting to the actual promotion_delivery_status domain.
-- Provider bounce detail can be added later as a separate delivery-event field;
-- it is not a valid delivery status today.
create or replace function public.hive_campaign_funnel(p_campaign_id uuid)
returns jsonb language sql security invoker set search_path='' stable as $function$
 with d as(
  select pd.id,pd.status,pd.lead_id from public.promotion_deliveries pd where pd.campaign_id=p_campaign_id
 ),e as(
  select count(*) filter(where ev.event_type='hive_page.visited')::bigint hive_visits,
   count(*) filter(where ev.event_type='member.clicked')::bigint member_engagements,
   count(*) filter(where ev.event_type='offer.clicked')::bigint offer_intent
  from public.events ev where exists(select 1 from d where d.id=ev.promotion_delivery_id)
 ),o as(
  select count(*)::bigint opportunities,count(*) filter(where status='won')::bigint wins,
   coalesce(sum(closed_value) filter(where status='won'),0)::numeric attributed_revenue
  from public.opportunities where campaign_id=p_campaign_id
 ),del as(
  select count(*)::bigint delivery_total,count(*) filter(where status='queued')::bigint queued,
   count(*) filter(where status='sending')::bigint sending,count(*) filter(where status='sent')::bigint sent,
   count(*) filter(where status='delivered')::bigint delivered,count(*) filter(where status='failed')::bigint failed
  from d
 ),r as(
  select audience_processed,deliveries_skipped,deliveries_failed,status queue_status
  from public.hive_campaign_runs where campaign_id=p_campaign_id
 )
 select jsonb_build_object('audience_processed',coalesce(r.audience_processed,0),'eligibility_skipped',coalesce(r.deliveries_skipped,0),
  'queue_failures',coalesce(r.deliveries_failed,0),'queue_status',coalesce(r.queue_status,'not_started'),
  'delivery_total',del.delivery_total,'queued',del.queued,'sending',del.sending,'sent',del.sent,'delivered',del.delivered,'failed',del.failed,
  'hive_visits',coalesce(e.hive_visits,0),'member_engagements',coalesce(e.member_engagements,0),'offer_intent',coalesce(e.offer_intent,0),
  'opportunities',o.opportunities,'wins',o.wins,'attributed_revenue',o.attributed_revenue)
 from del cross join e cross join o left join r on true
$function$;

revoke all on function public.hive_campaign_funnel(uuid) from public,anon;
grant execute on function public.hive_campaign_funnel(uuid) to authenticated;


-- An active campaign must have an immutable audience snapshot before deliveries
-- can be queued. This closes the gap between lifecycle state and dispatch state.
create or replace function public.assert_hive_campaign_dispatch_ready(p_campaign_id uuid)
returns void language plpgsql security definer set search_path='' as $function$
declare v_status text;v_frozen timestamptz;
begin
 select status,audience_frozen_at into v_status,v_frozen from public.hive_campaigns where id=p_campaign_id;
 if v_status is null then raise exception 'Campaign not found'; end if;
 if v_status<>'active' then raise exception 'Campaign must be active before dispatch'; end if;
 if v_frozen is null then raise exception 'Campaign audience must be frozen before dispatch'; end if;
end $function$;

revoke all on function public.assert_hive_campaign_dispatch_ready(uuid) from public,anon,authenticated;
grant execute on function public.assert_hive_campaign_dispatch_ready(uuid) to service_role;


-- Final campaign queue guard: deliveries must come from the immutable snapshot,
-- not merely from a currently-valid lead record.
create or replace function public.queue_hive_campaign_delivery(
 p_campaign_id uuid,p_lead_id uuid,p_channel text
) returns public.promotion_deliveries
language plpgsql security definer set search_path='' as $function$
declare v_campaign public.hive_campaigns;v_recipient public.hive_campaign_recipients;v_delivery public.promotion_deliveries;v_eligible jsonb;
begin
 perform public.assert_hive_campaign_dispatch_ready(p_campaign_id);
 select * into v_campaign from public.hive_campaigns where id=p_campaign_id;
 if p_channel not in('email','sms') then raise exception 'Unsupported channel'; end if;
 select * into v_recipient from public.hive_campaign_recipients
 where campaign_id=p_campaign_id and lead_id=p_lead_id;
 if v_recipient.id is null then raise exception 'Audience record is not part of the frozen campaign audience'; end if;
 if p_channel='email' and not v_recipient.email_eligible then raise exception 'Frozen audience record is not email eligible'; end if;
 if p_channel='sms' and not v_recipient.sms_eligible then raise exception 'Frozen audience record is not SMS eligible'; end if;
 v_eligible:=public.campaign_delivery_eligibility(p_campaign_id,p_lead_id,p_channel);
 if coalesce((v_eligible->>'eligible')::boolean,false)=false then
  raise exception 'Campaign delivery is not eligible: %',coalesce(v_eligible->>'reason','unknown');
 end if;
 select * into v_delivery from public.promotion_deliveries
 where campaign_id=p_campaign_id and lead_id=p_lead_id and channel=p_channel order by created_at desc limit 1;
 if v_delivery.id is not null then return v_delivery; end if;
 insert into public.promotion_deliveries(lead_id,source_business_id,target_business_id,channel,status,campaign_id)
 values(p_lead_id,v_recipient.source_business_id,v_campaign.spotlight_business_id,p_channel,'queued',p_campaign_id)
 returning * into v_delivery;
 return v_delivery;
exception when unique_violation then
 select * into v_delivery from public.promotion_deliveries
 where campaign_id=p_campaign_id and lead_id=p_lead_id and channel=p_channel order by created_at desc limit 1;
 return v_delivery;
end $function$;

revoke all on function public.queue_hive_campaign_delivery(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.queue_hive_campaign_delivery(uuid,uuid,text) to service_role;


-- Delivery eligibility must honor the immutable campaign recipient snapshot.
-- Live lead consent may become stricter after activation (opt-out), but it may
-- never broaden a frozen campaign audience or enable a channel not frozen in it.
create or replace function public.campaign_delivery_eligibility(
 p_campaign_id uuid,p_lead_id uuid,p_channel text
) returns jsonb language plpgsql security definer set search_path='' stable as $function$
declare v_campaign public.hive_campaigns;v_lead public.leads;v_recipient public.hive_campaign_recipients;v_last timestamptz;
begin
 select * into v_campaign from public.hive_campaigns where id=p_campaign_id;
 if v_campaign.id is null then return jsonb_build_object('eligible',false,'reason','campaign_not_found'); end if;
 if v_campaign.audience_frozen_at is null then return jsonb_build_object('eligible',false,'reason','audience_not_frozen'); end if;
 select * into v_recipient from public.hive_campaign_recipients where campaign_id=p_campaign_id and lead_id=p_lead_id;
 if v_recipient.id is null then return jsonb_build_object('eligible',false,'reason','not_in_frozen_audience'); end if;
 select * into v_lead from public.leads where id=p_lead_id;
 if v_lead.id is null then return jsonb_build_object('eligible',false,'reason','audience_record_not_found'); end if;
 if p_channel not in('email','sms') then return jsonb_build_object('eligible',false,'reason','unsupported_channel'); end if;
 if p_channel='email' and (not v_recipient.email_eligible or not v_lead.marketing_email_allowed)
 then return jsonb_build_object('eligible',false,'reason','email_not_enabled_or_consented'); end if;
 if p_channel='sms' and (not v_recipient.sms_eligible or not v_lead.marketing_sms_allowed)
 then return jsonb_build_object('eligible',false,'reason','sms_not_enabled_or_consented'); end if;
 select max(pd.created_at) into v_last from public.promotion_deliveries pd join public.leads l on l.id=pd.lead_id
 where l.customer_id=v_recipient.customer_id and pd.campaign_id is not null and pd.channel=p_channel and pd.status in('queued','sending','sent','delivered');
 if v_last is not null and v_last>now()-(v_campaign.min_contact_gap_days||' days')::interval
 then return jsonb_build_object('eligible',false,'reason','campaign_contact_cooldown','channel',p_channel,'last_contact_at',v_last); end if;
 return jsonb_build_object('eligible',true,'reason','eligible');
end $function$;

revoke all on function public.campaign_delivery_eligibility(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.campaign_delivery_eligibility(uuid,uuid,text) to service_role;


-- Existing members may predate authoritative category seats. Surface that gap
-- explicitly instead of guessing a primary category from a multi-service profile.
create or replace function public.hive_seat_assignment_readiness(p_hive_id uuid)
returns jsonb language sql security invoker set search_path='' stable as $function$
 with authorized as(
  select exists(select 1 from public.hive_members hm join public.business_users bu on bu.business_id=hm.business_id
   where hm.hive_id=p_hive_id and hm.status='active' and bu.user_id=(select auth.uid())) ok
 ), active as(
  select hm.business_id,b.name business_name,hs.category
  from public.hive_members hm join public.businesses b on b.id=hm.business_id
  left join public.hive_member_seats hs on hs.hive_id=hm.hive_id and hs.business_id=hm.business_id and hs.status='active'
  where hm.hive_id=p_hive_id and hm.status='active'
 )
 select case when (select ok from authorized) then jsonb_build_object(
  'active_members',count(*),'assigned_seats',count(*) filter(where category is not null),
  'missing_seats',count(*) filter(where category is null),
  'members_missing_seats',coalesce(jsonb_agg(jsonb_build_object('business_id',business_id,'business_name',business_name)
   order by business_name) filter(where category is null),'[]'::jsonb)
 ) else null end from active
$function$;

revoke all on function public.hive_seat_assignment_readiness(uuid) from public,anon;
grant execute on function public.hive_seat_assignment_readiness(uuid) to authenticated;
