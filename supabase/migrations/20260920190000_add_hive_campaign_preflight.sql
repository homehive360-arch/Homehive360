-- Tighten Spotlight rotation after authoritative member seats exist.
create or replace function public.next_hive_spotlight_member(p_hive_id uuid)
returns table(business_id uuid,business_name text,last_spotlight_month date)
language sql security invoker set search_path='' stable as $function$
 select b.id,b.name,max(c.campaign_month)
 from public.hive_members hm join public.businesses b on b.id=hm.business_id
 join public.hive_member_seats hs on hs.hive_id=hm.hive_id and hs.business_id=hm.business_id and hs.status='active'
 left join public.hive_campaigns c on c.hive_id=hm.hive_id and c.spotlight_business_id=hm.business_id and c.status<>'cancelled'
 where hm.hive_id=p_hive_id and hm.status='active'
 group by b.id,b.name order by max(c.campaign_month) asc nulls first,b.name limit 1
$function$;
revoke all on function public.next_hive_spotlight_member(uuid) from public,anon;
grant execute on function public.next_hive_spotlight_member(uuid) to authenticated;

-- Privacy-safe cross-member recipient key. Customer rows remain member-owned; this
-- key is used only to prevent duplicate monthly sends when the same person exists
-- in more than one member CRM. No raw email/phone is exposed across businesses.
create or replace function public.hive_recipient_identity_key(p_customer_id uuid)
returns text language sql security definer set search_path='' stable as $function$
 select case
  when nullif(lower(trim(c.email)),'') is not null then encode(extensions.digest('email:'||lower(trim(c.email)),'sha256'),'hex')
  when nullif(regexp_replace(coalesce(c.phone,''),'\\D','','g'),'') is not null then extensions.encode(extensions.digest('phone:'||regexp_replace(c.phone,'\\D','','g'),'sha256'),'hex')
  else extensions.encode(extensions.digest('customer:'||c.id::text,'sha256'),'hex')
 end from public.customers c where c.id=p_customer_id
$function$;
revoke all on function public.hive_recipient_identity_key(uuid) from public,anon,authenticated;
grant execute on function public.hive_recipient_identity_key(uuid) to service_role;

-- Preserve member audience contribution independently from send deduplication.
-- A shared homeowner can therefore count as a relationship for multiple members
-- while the campaign still chooses a single delivery anchor for that person.
create table if not exists public.hive_campaign_audience_contributions(
 id uuid primary key default gen_random_uuid(),
 campaign_id uuid not null references public.hive_campaigns(id) on delete cascade,
 source_business_id uuid not null references public.businesses(id),
 customer_id uuid not null references public.customers(id) on delete cascade,
 recipient_key text not null,
 email_eligible boolean not null default false,
 sms_eligible boolean not null default false,
 created_at timestamptz not null default now(),
 unique(campaign_id,source_business_id,customer_id)
);
create index if not exists hive_campaign_contributions_recipient_idx on public.hive_campaign_audience_contributions(campaign_id,recipient_key);
alter table public.hive_campaign_audience_contributions enable row level security;
-- Private ledger: customer IDs and recipient hashes are never exposed to Hive members.\nrevoke all on table public.hive_campaign_audience_contributions from public,anon,authenticated;\ngrant select,insert,update,delete on table public.hive_campaign_audience_contributions to service_role;\n\n
-- Refresh the private contribution ledger without changing member-owned customer rows.
create or replace function public.refresh_hive_campaign_audience_contributions(p_campaign_id uuid)
returns bigint language plpgsql security definer set search_path='' as $function$
declare v_hive uuid;v_email boolean;v_sms boolean;v_count bigint;
begin
 select hive_id,email_enabled,sms_enabled into v_hive,v_email,v_sms from public.hive_campaigns where id=p_campaign_id;
 if v_hive is null then raise exception 'Campaign not found'; end if;
 if not exists(select 1 from public.hive_members hm join public.business_users bu on bu.business_id=hm.business_id where hm.hive_id=v_hive and hm.status='active' and bu.user_id=(select auth.uid()) and bu.role in('owner','admin')) then raise exception 'Not authorized to manage this Hive'; end if;
 delete from public.hive_campaign_audience_contributions where campaign_id=p_campaign_id;
 insert into public.hive_campaign_audience_contributions(campaign_id,source_business_id,customer_id,recipient_key,email_eligible,sms_eligible)
 select p_campaign_id,x.source_business_id,x.customer_id,public.hive_recipient_identity_key(x.customer_id),x.email_eligible,x.sms_eligible
 from(
  select distinct on(l.source_business_id,l.customer_id) l.source_business_id,l.customer_id,
   v_email and bool_or(l.marketing_email_allowed) over(partition by l.source_business_id,l.customer_id) email_eligible,
   v_sms and bool_or(l.marketing_sms_allowed) over(partition by l.source_business_id,l.customer_id) sms_eligible
  from public.leads l join public.hive_members hm on hm.hive_id=l.hive_id and hm.business_id=l.source_business_id and hm.status='active'
  where l.hive_id=v_hive and l.customer_id is not null and ((v_email and l.marketing_email_allowed) or (v_sms and l.marketing_sms_allowed))
  order by l.source_business_id,l.customer_id,l.received_at desc nulls last,l.created_at desc,l.id desc
 ) x;
 get diagnostics v_count=row_count; return v_count;
end $function$;
revoke all on function public.refresh_hive_campaign_audience_contributions(uuid) from public,anon;
grant execute on function public.refresh_hive_campaign_audience_contributions(uuid) to authenticated;

create or replace function public.hive_campaign_contribution_summary(p_campaign_id uuid)
returns jsonb language plpgsql security definer set search_path='' stable as $function$
declare v_hive uuid;v_result jsonb;
begin
 select hive_id into v_hive from public.hive_campaigns where id=p_campaign_id;
 if v_hive is null then raise exception 'Campaign not found'; end if;
 if not exists(select 1 from public.hive_members hm join public.business_users bu on bu.business_id=hm.business_id where hm.hive_id=v_hive and hm.status='active' and bu.user_id=(select auth.uid())) then raise exception 'Not authorized to view this Hive'; end if;
 with a as(select source_business_id,count(*)::bigint contributed_relationships,count(*) filter(where email_eligible)::bigint email_eligible_relationships,count(*) filter(where sms_eligible)::bigint sms_eligible_relationships from public.hive_campaign_audience_contributions where campaign_id=p_campaign_id group by source_business_id),u as(select count(distinct recipient_key)::bigint unique_recipients from public.hive_campaign_audience_contributions where campaign_id=p_campaign_id)
 select jsonb_build_object('unique_recipients',coalesce((select unique_recipients from u),0),'member_contributions',coalesce(jsonb_agg(jsonb_build_object('source_business_id',a.source_business_id,'contributed_relationships',a.contributed_relationships,'email_eligible_relationships',a.email_eligible_relationships,'sms_eligible_relationships',a.sms_eligible_relationships) order by a.source_business_id),'[]'::jsonb)) into v_result from a;
 return v_result;
end $function$;
revoke all on function public.hive_campaign_contribution_summary(uuid) from public,anon;
grant execute on function public.hive_campaign_contribution_summary(uuid) to authenticated;

-- Final projected-audience refresh: assign each unique person to one deterministic
-- delivery source for reach accounting while preserving every member relationship
-- separately in hive_campaign_audience_contributions.
create or replace function public.refresh_hive_campaign_audiences(p_campaign_id uuid)
returns void language plpgsql security definer set search_path='' as $function$
declare v_hive uuid;v_email boolean;v_sms boolean;
begin
 select hive_id,email_enabled,sms_enabled into v_hive,v_email,v_sms from public.hive_campaigns where id=p_campaign_id;
 if v_hive is null then raise exception 'Campaign not found'; end if;
 if not exists(select 1 from public.hive_members hm join public.business_users bu on bu.business_id=hm.business_id where hm.hive_id=v_hive and hm.status='active' and bu.user_id=(select auth.uid()) and bu.role in('owner','admin')) then raise exception 'Not authorized to manage this Hive'; end if;
 perform public.refresh_hive_campaign_audience_contributions(p_campaign_id);
 insert into public.hive_campaign_audiences(campaign_id,source_business_id,eligible_customers,email_eligible,sms_eligible)
 with candidates as(
  select l.source_business_id,l.customer_id,public.hive_recipient_identity_key(l.customer_id) recipient_key,l.received_at,l.created_at,l.id,
   bool_or(v_email and l.marketing_email_allowed) over(partition by public.hive_recipient_identity_key(l.customer_id)) email_ok,
   bool_or(v_sms and l.marketing_sms_allowed) over(partition by public.hive_recipient_identity_key(l.customer_id)) sms_ok
  from public.leads l join public.hive_members hm on hm.hive_id=l.hive_id and hm.business_id=l.source_business_id and hm.status='active'
  where l.hive_id=v_hive and l.customer_id is not null and ((v_email and l.marketing_email_allowed) or (v_sms and l.marketing_sms_allowed))
 ), unique_people as(
  select distinct on(recipient_key) recipient_key,source_business_id,email_ok,sms_ok from candidates
  order by recipient_key,received_at desc nulls last,created_at desc,id desc
 )
 select p_campaign_id,hm.business_id,count(u.recipient_key),count(u.recipient_key) filter(where u.email_ok),count(u.recipient_key) filter(where u.sms_ok)
 from public.hive_members hm left join unique_people u on u.source_business_id=hm.business_id
 where hm.hive_id=v_hive and hm.status='active' group by hm.business_id
 on conflict(campaign_id,source_business_id) do update set eligible_customers=excluded.eligible_customers,email_eligible=excluded.email_eligible,sms_eligible=excluded.sms_eligible;
end $function$;
revoke all on function public.refresh_hive_campaign_audiences(uuid) from public,anon;
grant execute on function public.refresh_hive_campaign_audiences(uuid) to authenticated;

-- Final launch-readiness override: use privacy-safe unique people rather than
-- summing member-owned customer rows. Member relationships remain intact; this
-- gate measures the audience the network can actually contact without duplicates.
create or replace function public.hive_launch_readiness(p_hive_id uuid)
returns jsonb language sql security invoker set search_path='' stable as $function$
 with authorized as(
  select exists(select 1 from public.hive_members hm join public.business_users bu on bu.business_id=hm.business_id where hm.hive_id=p_hive_id and hm.status='active' and bu.user_id=(select auth.uid()) and bu.role in('owner','admin')) ok
 ),cfg as(select min_launch_members,min_launch_audience from public.hives where id=p_hive_id),
 members as(select count(*)::int active_members from public.hive_members hm where hm.hive_id=p_hive_id and hm.status='active'),
 seats as(select count(distinct hs.category)::int occupied_categories,count(distinct hs.business_id)::int members_with_seats from public.hive_member_seats hs join public.hive_members hm on hm.hive_id=hs.hive_id and hm.business_id=hs.business_id and hm.status='active' where hs.hive_id=p_hive_id and hs.status='active'),
 eligible as(select distinct public.hive_recipient_identity_key(l.customer_id) recipient_key from public.leads l join public.hive_members hm on hm.hive_id=l.hive_id and hm.business_id=l.source_business_id and hm.status='active' where l.hive_id=p_hive_id and l.customer_id is not null and l.marketing_email_allowed),
 aud as(select count(*)::int eligible_audience from eligible)
 select case when (select ok from authorized) then jsonb_build_object('active_members',m.active_members,'occupied_categories',s.occupied_categories,'members_with_seats',s.members_with_seats,'missing_seats',greatest(m.active_members-s.members_with_seats,0),'eligible_audience',a.eligible_audience,'min_launch_members',cfg.min_launch_members,'min_launch_audience',cfg.min_launch_audience,'member_gate_met',m.active_members>=cfg.min_launch_members,'seat_gate_met',s.members_with_seats=m.active_members and s.occupied_categories=m.active_members,'audience_gate_met',a.eligible_audience>=cfg.min_launch_audience,'launch_ready',m.active_members>=cfg.min_launch_members and s.members_with_seats=m.active_members and s.occupied_categories=m.active_members and a.eligible_audience>=cfg.min_launch_audience) else null end
 from cfg cross join members m cross join seats s cross join aud a
$function$;
revoke all on function public.hive_launch_readiness(uuid) from public,anon;
grant execute on function public.hive_launch_readiness(uuid) to authenticated;

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
  select true email_enabled,false sms_enabled
 ), relationships as (
  select distinct on(l.source_business_id,l.customer_id) l.source_business_id,l.customer_id,
   public.hive_recipient_identity_key(l.customer_id) recipient_key,l.received_at,l.created_at,l.id
  from public.leads l join public.hive_members hm on hm.hive_id=l.hive_id and hm.business_id=l.source_business_id and hm.status='active'
  cross join policy p
  where l.hive_id=p_hive_id and l.customer_id is not null
   and ((p.email_enabled and l.marketing_email_allowed) or (p.sms_enabled and l.marketing_sms_allowed))
  order by l.source_business_id,l.customer_id,l.received_at desc nulls last,l.created_at desc,l.id desc
 ), unique_people as(
  select recipient_key,bool_or(source_business_id=v_spotlight) spotlight_owned
  from relationships group by recipient_key
 )
 select count(*) filter(where spotlight_owned),count(*) filter(where not spotlight_owned),count(*)
 into v_owned,v_incremental,v_total from unique_people;

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
-- Serialize campaign creation per Hive so two operators cannot both pass
-- Spotlight validation concurrently and consume the same rotation slot.
-- The lock stays inline in the creator: exposing a separate lock RPC would be
-- misleading because an RPC transaction ends as soon as that call returns.
create or replace function public.create_launch_ready_monthly_hive_campaign(
 p_hive_id uuid,
 p_campaign_month date,
 p_spotlight_offer_id uuid default null,
 p_expected_spotlight_business_id uuid default null
) returns public.hive_campaigns
language plpgsql security definer set search_path=''
as $function$
declare v_ready jsonb;v_spotlight uuid;v_campaign public.hive_campaigns;
begin
 -- Transaction-scoped lock makes fair Spotlight selection + campaign insert atomic per Hive.
 perform pg_advisory_xact_lock(hashtextextended('hh360:campaign:'||p_hive_id::text,0));
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
 if p_expected_spotlight_business_id is not null and v_spotlight<>p_expected_spotlight_business_id then
  raise exception 'Spotlight changed since campaign planning; refresh before creating campaign';
 end if;

 -- Delegate month/offer ownership/status/date validation to the canonical
 -- campaign creation function so there is one source of truth for creation.
 select * into v_campaign from public.create_monthly_hive_campaign(
  p_hive_id,p_campaign_month,v_spotlight,p_spotlight_offer_id
 );
 return v_campaign;
end
$function$;

revoke all on function public.create_launch_ready_monthly_hive_campaign(uuid,date,uuid,uuid) from public,anon;
grant execute on function public.create_launch_ready_monthly_hive_campaign(uuid,date,uuid,uuid) to authenticated;


-- External authenticated callers must use the launch-readiness gate. The lower-level
-- creator remains available only to the service role for controlled internal work.
revoke all on function public.create_monthly_hive_campaign(uuid,date,uuid,uuid,text) from authenticated;
grant execute on function public.create_monthly_hive_campaign(uuid,date,uuid,uuid,text) to service_role;


-- A campaign audience is immutable once activation begins, including the valid
-- zero-recipient case. A timestamp is the freeze marker; row count is not.
alter table public.hive_campaigns add column if not exists audience_frozen_at timestamptz;
alter table public.hive_campaign_recipients add column if not exists recipient_key text;
create unique index if not exists hive_campaign_recipients_unique_person_idx on public.hive_campaign_recipients(campaign_id,recipient_key) where recipient_key is not null;

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
declare v_hive uuid;v_count bigint;v_frozen timestamptz;v_email boolean;v_sms boolean;
begin
 select hive_id,audience_frozen_at,email_enabled,sms_enabled into v_hive,v_frozen,v_email,v_sms
 from public.hive_campaigns where id=p_campaign_id for update;
 if v_hive is null then raise exception 'Campaign not found';end if;
 if v_frozen is not null then
  select count(*) into v_count from public.hive_campaign_recipients where campaign_id=p_campaign_id;
  return v_count;
 end if;
 insert into public.hive_campaign_recipients(campaign_id,lead_id,source_business_id,customer_id,email_eligible,sms_eligible,recipient_key)
 with candidates as(
  select l.id lead_id,l.source_business_id,l.customer_id,l.received_at,l.created_at,
   public.hive_recipient_identity_key(l.customer_id) recipient_key,
   (v_email and l.marketing_email_allowed) row_email_eligible,
   (v_sms and l.marketing_sms_allowed) row_sms_eligible
  from public.leads l join public.hive_members hm on hm.hive_id=l.hive_id and hm.business_id=l.source_business_id and hm.status='active'
  where l.hive_id=v_hive and l.customer_id is not null and ((v_email and l.marketing_email_allowed) or (v_sms and l.marketing_sms_allowed))
 ), aggregate_eligibility as(
  select recipient_key,bool_or(row_email_eligible) email_eligible,bool_or(row_sms_eligible) sms_eligible from candidates group by recipient_key
 ), anchors as(
  select distinct on(c.recipient_key) c.lead_id,c.source_business_id,c.customer_id,c.recipient_key,a.email_eligible,a.sms_eligible
  from candidates c join aggregate_eligibility a using(recipient_key)
  where (a.email_eligible and c.row_email_eligible) or (not a.email_eligible and a.sms_eligible and c.row_sms_eligible)
  order by c.recipient_key,c.received_at desc nulls last,c.created_at desc,c.lead_id desc
 )
 select p_campaign_id,lead_id,source_business_id,customer_id,email_eligible,sms_eligible,recipient_key from anchors;
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


-- RLS-scoped analytics summary. Keep the existing response shape while limiting
-- every metric to Hives visible to the signed-in user's businesses.
create or replace function public.analytics_summary(p_days integer default 30)
returns jsonb language sql security invoker set search_path='' stable as $function$
 with cutoff as(select now()-(greatest(1,least(coalesce(p_days,30),365))||' days')::interval ts),
 visible_businesses as(select distinct bu.business_id from public.business_users bu where bu.user_id=(select auth.uid())),
 visible_hives as(select distinct hm.hive_id from public.hive_members hm join visible_businesses vb on vb.business_id=hm.business_id),
 lead_stats as(select count(*)::bigint leads from public.leads l,cutoff c where l.hive_id in(select hive_id from visible_hives) and l.received_at>=c.ts),
 opp_stats as(select count(*)::bigint opportunities,coalesce(sum(estimated_value) filter(where status not in('won','lost')),0)::numeric pipeline,coalesce(sum(closed_value) filter(where status='won'),0)::numeric revenue,count(*) filter(where status='won')::bigint won from public.opportunities o,cutoff c where o.hive_id in(select hive_id from visible_hives) and o.created_at>=c.ts),
 delivery_stats as(select count(*) filter(where pd.status='queued')::bigint queued,count(*) filter(where pd.status in('sent','delivered'))::bigint sent,count(*) filter(where pd.status='delivered')::bigint delivered from public.promotion_deliveries pd join public.hive_campaigns hc on hc.id=pd.campaign_id,cutoff c where hc.hive_id in(select hive_id from visible_hives) and pd.created_at>=c.ts),
 event_stats as(select count(*) filter(where e.event_type='opportunity.accepted')::bigint accepted,count(*) filter(where e.event_type in('member.clicked','offer.clicked') and e.promotion_delivery_id is not null)::bigint attributed_clicks,count(*) filter(where e.event_type in('member.clicked','offer.clicked') and e.promotion_delivery_id is null)::bigint organic_clicks from public.events e,cutoff c where e.hive_id in(select hive_id from visible_hives) and e.occurred_at>=c.ts)
 select jsonb_build_object('leads',coalesce(l.leads,0),'opportunities',coalesce(o.opportunities,0),'pipeline',coalesce(o.pipeline,0),'revenue',coalesce(o.revenue,0),'won',coalesce(o.won,0),'queued',coalesce(d.queued,0),'sent',coalesce(d.sent,0),'delivered',coalesce(d.delivered,0),'accepted',coalesce(e.accepted,0),'attributed_clicks',coalesce(e.attributed_clicks,0),'organic_clicks',coalesce(e.organic_clicks,0)) from lead_stats l cross join opp_stats o cross join delivery_stats d cross join event_stats e
$function$;
revoke all on function public.analytics_summary(integer) from public,anon;
grant execute on function public.analytics_summary(integer) to authenticated;

-- Promotion funnel aligned to campaign audience semantics. Audience is unique
-- campaign recipients in the reporting window, not newly ingested lead rows.
create or replace function public.promotion_funnel_summary(p_days integer default 30)
returns jsonb language sql security invoker set search_path='' stable as $function$
 with cutoff as(select now()-(greatest(1,least(coalesce(p_days,30),365))||' days')::interval ts),
 visible_businesses as(select distinct bu.business_id from public.business_users bu where bu.user_id=(select auth.uid())),
 visible_hives as(select distinct hm.hive_id from public.hive_members hm join visible_businesses vb on vb.business_id=hm.business_id),
 audience as(select count(distinct r.recipient_key)::bigint customers from public.hive_campaign_recipients r join public.hive_campaigns hc on hc.id=r.campaign_id,cutoff c where hc.hive_id in(select hive_id from visible_hives) and hc.audience_frozen_at>=c.ts),
 delivery as(select count(*) filter(where pd.status in('queued','sending','sent','delivered'))::bigint promotions,count(*) filter(where pd.status in('sent','delivered'))::bigint sent,count(*) filter(where pd.status='delivered')::bigint delivered from public.promotion_deliveries pd join public.hive_campaigns hc on hc.id=pd.campaign_id,cutoff c where hc.hive_id in(select hive_id from visible_hives) and pd.created_at>=c.ts),
 engagement as(select count(*) filter(where e.event_type='hive_page.visited')::bigint hive_visits,count(*) filter(where e.event_type='member.clicked')::bigint member_engagements,count(*) filter(where e.event_type='offer.clicked')::bigint offer_engagements from public.events e,cutoff c where e.hive_id in(select hive_id from visible_hives) and e.occurred_at>=c.ts and e.promotion_delivery_id is not null),
 opp as(select count(*)::bigint opportunities,count(*) filter(where o.status='won')::bigint won,coalesce(sum(o.closed_value) filter(where o.status='won'),0)::numeric revenue from public.opportunities o,cutoff c where o.hive_id in(select hive_id from visible_hives) and o.created_at>=c.ts and o.campaign_id is not null)
 select jsonb_build_object('audience_customers',coalesce(a.customers,0),'promotions',coalesce(d.promotions,0),'sent',coalesce(d.sent,0),'delivered',coalesce(d.delivered,0),'hive_visits',coalesce(e.hive_visits,0),'member_engagements',coalesce(e.member_engagements,0),'offer_engagements',coalesce(e.offer_engagements,0),'opportunities',coalesce(o.opportunities,0),'won',coalesce(o.won,0),'revenue',coalesce(o.revenue,0)) from audience a cross join delivery d cross join engagement e cross join opp o
$function$;
revoke all on function public.promotion_funnel_summary(integer) from public,anon;
grant execute on function public.promotion_funnel_summary(integer) to authenticated;

-- Member value scorecard aligned to the campaign network model. Contribution is
-- campaign audience relationships, not raw lead ingestion volume.
create or replace function public.member_value_scorecard(p_days integer default 30)
returns table(id uuid,name text,contributed bigint,received bigint,sourced bigint,pipeline numeric,revenue numeric,wins bigint)
language sql security invoker set search_path='' stable as $function$
 with cutoff as(select now()-(greatest(1,least(coalesce(p_days,30),365))||' days')::interval ts),
 visible as(select b.id,b.name from public.businesses b where exists(select 1 from public.business_users bu where bu.business_id=b.id and bu.user_id=(select auth.uid()))),
 contribution as(select ac.source_business_id id,count(*)::bigint contributed from public.hive_campaign_audience_contributions ac join public.hive_campaigns hc on hc.id=ac.campaign_id,cutoff c where hc.created_at>=c.ts group by ac.source_business_id),
 received as(select o.receiving_business_id id,count(*)::bigint received,count(*) filter(where o.status='won')::bigint wins,coalesce(sum(o.estimated_value) filter(where o.status not in('won','lost')),0)::numeric pipeline,coalesce(sum(o.closed_value) filter(where o.status='won'),0)::numeric revenue from public.opportunities o,cutoff c where o.created_at>=c.ts group by o.receiving_business_id),
 sourced as(select o.source_business_id id,count(*)::bigint sourced from public.opportunities o,cutoff c where o.created_at>=c.ts group by o.source_business_id)
 select v.id,v.name,coalesce(a.contributed,0),coalesce(r.received,0),coalesce(s.sourced,0),coalesce(r.pipeline,0),coalesce(r.revenue,0),coalesce(r.wins,0) from visible v left join contribution a on a.id=v.id left join received r on r.id=v.id left join sourced s on s.id=v.id order by v.name
$function$;
revoke all on function public.member_value_scorecard(integer) from public,anon;
grant execute on function public.member_value_scorecard(integer) to authenticated;

-- Whole-Hive member exchange reporting. Exposure is campaign reach while the member
-- was an active participant, not clicks. Clicks remain engagement metrics.
create or replace function public.member_promotion_exchange(p_days integer default 30)
returns table(business_id uuid,business_name text,audience_contributed bigint,promotions_contributed bigint,exposure_received bigint,member_engagements bigint,offer_intent bigint,opportunities_received bigint,wins bigint,attributed_revenue numeric)
language sql security invoker set search_path='' stable as $function$
 with cutoff as(select now()-(greatest(1,least(coalesce(p_days,30),365))||' days')::interval ts),
 visible as(select distinct b.id,b.name from public.businesses b join public.business_users bu on bu.business_id=b.id where bu.user_id=(select auth.uid())),
 audience as(select ac.source_business_id id,count(*)::bigint n from public.hive_campaign_audience_contributions ac join public.hive_campaigns hc on hc.id=ac.campaign_id,cutoff c where hc.created_at>=c.ts group by ac.source_business_id),
 contributed as(select pd.source_business_id id,count(*)::bigint n from public.promotion_deliveries pd,cutoff c where pd.created_at>=c.ts group by pd.source_business_id),
 exposure as(select hm.business_id id,count(pd.id)::bigint n from public.promotion_deliveries pd join public.hive_campaigns hc on hc.id=pd.campaign_id join public.hive_members hm on hm.hive_id=hc.hive_id and hm.status='active' and hm.business_id<>pd.source_business_id,cutoff c where pd.created_at>=c.ts and pd.status in('sent','delivered') group by hm.business_id),
 engagement as(select (e.properties->>'target_business_id')::uuid id,count(*) filter(where e.event_type='member.clicked')::bigint member_clicks,count(*) filter(where e.event_type='offer.clicked')::bigint offer_clicks from public.events e,cutoff c where e.occurred_at>=c.ts and e.properties ? 'delivery_id' and e.properties ? 'target_business_id' group by (e.properties->>'target_business_id')::uuid),
 received as(select o.receiving_business_id id,count(*)::bigint opportunities,count(*) filter(where o.status='won')::bigint wins,coalesce(sum(o.closed_value) filter(where o.status='won'),0)::numeric revenue from public.opportunities o,cutoff c where o.created_at>=c.ts group by o.receiving_business_id)
 select v.id,v.name,coalesce(a.n,0),coalesce(cn.n,0),coalesce(x.n,0),coalesce(e.member_clicks,0),coalesce(e.offer_clicks,0),coalesce(r.opportunities,0),coalesce(r.wins,0),coalesce(r.revenue,0) from visible v left join audience a on a.id=v.id left join contributed cn on cn.id=v.id left join exposure x on x.id=v.id left join engagement e on e.id=v.id left join received r on r.id=v.id order by v.name
$function$;
revoke all on function public.member_promotion_exchange(integer) from public,anon;
grant execute on function public.member_promotion_exchange(integer) to authenticated;

-- Final performance semantics: delivery_total is all campaign delivery rows;
-- queued is only work that has not yet been claimed. Keep legacy keys while
-- removing the misleading count(*) => queued behavior from the earlier migration.
create or replace function public.hive_campaign_performance(p_campaign_id uuid)
returns jsonb language sql security invoker set search_path='' stable as $function$
 with d as(
  select count(*)::bigint delivery_total,
   count(*) filter(where status='queued')::bigint queued,
   count(*) filter(where status='sending')::bigint sending,
   count(*) filter(where status in('sent','delivered'))::bigint sent,
   count(*) filter(where status='delivered')::bigint delivered,
   count(*) filter(where status='failed')::bigint failed,
   count(distinct source_business_id)::bigint contributing_members
  from public.promotion_deliveries where campaign_id=p_campaign_id
 ),o as(
  select count(*)::bigint opportunities,count(*) filter(where status='won')::bigint wins,
   coalesce(sum(closed_value) filter(where status='won'),0)::numeric revenue
  from public.opportunities where campaign_id=p_campaign_id
 )
 select jsonb_build_object('contributing_members',coalesce(d.contributing_members,0),'delivery_total',coalesce(d.delivery_total,0),'queued',coalesce(d.queued,0),'sending',coalesce(d.sending,0),'sent',coalesce(d.sent,0),'delivered',coalesce(d.delivered,0),'failed',coalesce(d.failed,0),'opportunities',coalesce(o.opportunities,0),'wins',coalesce(o.wins,0),'attributed_revenue',coalesce(o.revenue,0)) from d cross join o
$function$;
revoke all on function public.hive_campaign_performance(uuid) from public,anon;
grant execute on function public.hive_campaign_performance(uuid) to authenticated;

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
 -- The frozen lead is only an execution anchor. If CRM sync has reassigned that
 -- lead to another customer/source/Hive, fail closed rather than send to drifted identity.
 if not exists(
  select 1 from public.leads l
  where l.id=p_lead_id and l.hive_id=v_campaign.hive_id
   and l.customer_id=v_recipient.customer_id and l.source_business_id=v_recipient.source_business_id
 ) then raise exception 'Frozen audience identity no longer matches the live audience record'; end if;
 if p_channel='email' and not v_recipient.email_eligible then raise exception 'Frozen audience record is not email eligible'; end if;
 if p_channel='sms' and not v_recipient.sms_eligible then raise exception 'Frozen audience record is not SMS eligible'; end if;
 v_eligible:=public.campaign_delivery_eligibility(p_campaign_id,p_lead_id,p_channel);
 if coalesce((v_eligible->>'eligible')::boolean,false)=false then
  raise exception 'Campaign delivery is not eligible: %',coalesce(v_eligible->>'reason','unknown');
 end if;
 select * into v_delivery from public.promotion_deliveries
 where campaign_id=p_campaign_id and lead_id=p_lead_id and channel=p_channel order by created_at desc limit 1;
 if v_delivery.id is not null then return v_delivery; end if;
 -- Campaign delivery represents exposure to the whole Hive, not a delivery to
 -- the Spotlight member. The actual receiving business is established by the
 -- customer's tracked member/offer click and stored on that event/opportunity.
 insert into public.promotion_deliveries(lead_id,source_business_id,target_business_id,channel,status,campaign_id)
 values(p_lead_id,v_recipient.source_business_id,null,p_channel,'queued',p_campaign_id)
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


-- Final attribution guard: a campaign may only be attached to an opportunity
-- when the supplied lead/source/customer tuple exists in that campaign's frozen
-- audience. This prevents callers from attaching a valid campaign id to an
-- unrelated promotion engagement.
create or replace function public.create_promotion_engagement_opportunity(
 p_lead_id uuid,p_hive_id uuid,p_source_business_id uuid,p_receiving_business_id uuid,p_offer_id uuid default null,p_campaign_id uuid default null
) returns uuid language plpgsql security definer set search_path='' as $function$
declare v_id uuid;v_customer_id uuid;
begin
 if p_source_business_id=p_receiving_business_id then raise exception 'Self-attribution is not allowed'; end if;
 select l.customer_id into v_customer_id from public.leads l where l.id=p_lead_id and l.hive_id=p_hive_id and l.source_business_id=p_source_business_id;
 if v_customer_id is null then raise exception 'Lead attribution context is invalid'; end if;
 if not exists(select 1 from public.hive_members hm where hm.hive_id=p_hive_id and hm.business_id=p_source_business_id and hm.status='active') or not exists(select 1 from public.hive_members hm where hm.hive_id=p_hive_id and hm.business_id=p_receiving_business_id and hm.status='active') then raise exception 'Businesses must be active members of the Hive'; end if;
 if p_offer_id is not null and not exists(select 1 from public.offers o where o.id=p_offer_id and o.business_id=p_receiving_business_id and o.status='active' and (o.hive_id is null or o.hive_id=p_hive_id) and (o.starts_at is null or o.starts_at<=now()) and (o.ends_at is null or o.ends_at>=now())) then raise exception 'Offer is not eligible'; end if;
 if p_campaign_id is not null then
  if not exists(select 1 from public.hive_campaigns c where c.id=p_campaign_id and c.hive_id=p_hive_id and c.status in('active','completed')) then raise exception 'Campaign attribution context is invalid'; end if;
  if not exists(
   select 1 from public.hive_campaign_recipients r
   join public.promotion_deliveries d on d.campaign_id=r.campaign_id and d.lead_id=r.lead_id
    and d.customer_id=r.customer_id and d.source_business_id=r.source_business_id
   where r.campaign_id=p_campaign_id and r.lead_id=p_lead_id and r.customer_id=v_customer_id
    and r.source_business_id=p_source_business_id and d.status in('sent','delivered')
  ) then raise exception 'Campaign attribution requires a dispatched frozen-audience delivery'; end if;
 end if;
 -- Serialize idempotency on the exact attribution identity. Without this lock,
 -- two simultaneous clicks can both observe no opportunity and insert duplicates.
 perform pg_advisory_xact_lock(hashtextextended('hh360:opp:'||p_lead_id::text||':'||p_receiving_business_id::text||':'||coalesce(p_campaign_id::text,'organic'),0));
 select id into v_id from public.opportunities
 where lead_id=p_lead_id and receiving_business_id=p_receiving_business_id
  and campaign_id is not distinct from p_campaign_id
 order by created_at limit 1;
 if v_id is not null then
  update public.opportunities set offer_id=coalesce(offer_id,p_offer_id),updated_at=now() where id=v_id;
  return v_id;
 end if;
 insert into public.opportunities(lead_id,hive_id,source_business_id,receiving_business_id,customer_id,offer_id,campaign_id,status)
 values(p_lead_id,p_hive_id,p_source_business_id,p_receiving_business_id,v_customer_id,p_offer_id,p_campaign_id,'new') returning id into v_id;
 return v_id;
end $function$;
revoke all on function public.create_promotion_engagement_opportunity(uuid,uuid,uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.create_promotion_engagement_opportunity(uuid,uuid,uuid,uuid,uuid,uuid) to service_role;
