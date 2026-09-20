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

 with eligible as (
  select distinct on(l.customer_id) l.customer_id,l.source_business_id
  from public.leads l
  join public.hive_members hm on hm.hive_id=l.hive_id and hm.business_id=l.source_business_id and hm.status='active'
  where l.hive_id=p_hive_id and l.customer_id is not null
   and (l.marketing_email_allowed or l.marketing_sms_allowed)
  order by l.customer_id,l.received_at desc,l.created_at desc,l.id desc
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
   bool_or(l.marketing_email_allowed) over(partition by l.customer_id) email_eligible,
   bool_or(l.marketing_sms_allowed) over(partition by l.customer_id) sms_eligible
  from public.leads l join public.hive_members hm on hm.hive_id=l.hive_id and hm.business_id=l.source_business_id and hm.status='active'
  where l.hive_id=v_hive and l.customer_id is not null and (l.marketing_email_allowed or l.marketing_sms_allowed)
  order by l.customer_id,l.received_at desc nulls last,l.created_at desc,l.id desc
 ) x;
 get diagnostics v_count=row_count;
 update public.hive_campaigns set audience_frozen_at=now(),updated_at=now() where id=p_campaign_id;
 return v_count;
end $function$;

revoke all on function public.snapshot_hive_campaign_recipients(uuid) from public,anon,authenticated;
grant execute on function public.snapshot_hive_campaign_recipients(uuid) to service_role;
